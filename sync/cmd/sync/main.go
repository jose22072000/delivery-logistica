// El sincronizador de reparto.
//
// Cuatro rutas y una idea: que un logístico pueda trabajar un día entero sin conexión y no
// pierda nada. El protocolo está en `docs/sincronizacion.md` y este binario no hace nada
// que no esté allí.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"procovar/reparto-sync/internal/config"
	"procovar/reparto-sync/internal/httpx"
	"procovar/reparto-sync/internal/identidad"
	"procovar/reparto-sync/internal/reparto"
	"procovar/reparto-sync/internal/sincro"
	"procovar/reparto-sync/internal/store"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(log)

	if err := arrancar(log); err != nil {
		log.Error("no arranca", "err", err)
		os.Exit(1)
	}
}

func arrancar(log *slog.Logger) error {
	cfg, err := config.Cargar()
	if err != nil {
		return err
	}

	ctx, parar := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer parar()

	base, err := store.Abrir(ctx, store.Opciones{
		URL:           cfg.BaseDeDatos,
		MaxConexiones: cfg.MaxConexiones,
	})
	if err != nil {
		return err
	}
	defer base.Cerrar()

	cliente := reparto.Nuevo(cfg.RepartoURL, cfg.RepartoClave, cfg.RepartoTiempo)

	servicio := sincro.Nuevo(sincro.Opciones{
		Datos:      base,
		Origen:     cliente,
		Aplicador:  cliente,
		TopeBajada: cfg.TopeBajada,
		Log:        log,
	})

	mux := http.NewServeMux()
	servicio.Rutas(mux)

	// Todo lo del protocolo exige sesión. La salud no, porque la mira el orquestador y
	// tiene que poder decir «está vivo» aunque auth esté caído.
	publico := http.NewServeMux()
	publico.Handle("/sync/", identidad.Exigir(identidad.DeCabeceras, mux))
	publico.HandleFunc("GET /salud", func(w http.ResponseWriter, r *http.Request) {
		if err := base.Ping(r.Context()); err != nil {
			httpx.Fallo(w, http.StatusServiceUnavailable, "La base no contesta")
			return
		}
		httpx.JSON(w, http.StatusOK, map[string]string{"estado": "bien"})
	})

	servidor := &http.Server{
		Addr:        cfg.Direccion,
		Handler:     httpx.Recuperar(log, httpx.Registro(log, publico)),
		ReadTimeout: cfg.EsperaLectura,
		// La de escritura es larga a propósito: un lote de un día entero se aplica apunte
		// por apunte contra el reparto, y cortarlo a la mitad deja trabajo sin contestar.
		WriteTimeout: cfg.EsperaEscritura,
		IdleTimeout:  2 * time.Minute,
	}

	fallo := make(chan error, 1)
	go func() {
		log.Info("sincronizador escuchando", "config", cfg.String())
		if err := servidor.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			fallo <- err
		}
	}()

	select {
	case err := <-fallo:
		return err
	case <-ctx.Done():
		// Cierre ordenado: lo que se está aplicando ahora mismo es la cola de alguien que
		// lleva ocho horas sin señal. Se le da tiempo a terminar y a contestar, que es lo
		// que le deja saber qué se aplicó y qué no.
		log.Info("parando")
		cierre, listo := context.WithTimeout(context.Background(), 30*time.Second)
		defer listo()
		return servidor.Shutdown(cierre)
	}
}
