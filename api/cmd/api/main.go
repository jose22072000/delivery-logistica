// El arranque del servicio de reparto.
//
// Tres cosas y en este orden, que importa:
//
//  1. Configuración. Si falta algo, se muere AQUÍ, con un mensaje que dice qué falta.
//     Nunca un 500 a media tarde en la pantalla de alguien que está cargando un camión.
//  2. Base de datos, con ping. Un proceso vivo que no llega a Postgres está caído.
//  3. Servidor, con apagado ordenado.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/api"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/store"
)

// version la incrusta el compilador:
//
//	go build -ldflags "-X main.version=$(git describe --tags --always)" ./cmd/api
//
// No se lee de un fichero ni se pregunta a nadie: /version la consulta cada aparato al
// arrancar, y la APK decide con ella si tiene que actualizarse.
var version = "dev"

func main() {
	if err := correr(); err != nil {
		// A stderr y sin el registro estructurado: esto lo lee una persona mirando el
		// despliegue, no un agregador de logs.
		fmt.Fprintf(os.Stderr, "\nreparto-api no puede arrancar:\n%v\n\n", err)
		os.Exit(1)
	}
}

func correr() error {
	cfg, err := config.Cargar(version)
	if err != nil {
		return err
	}
	reg := registro(cfg)

	// El contexto se cancela con la primera señal. SIGTERM es lo que manda Docker al
	// parar el contenedor; SIGINT es Ctrl+C en desarrollo.
	ctx, parar := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer parar()

	almacen, err := store.Abrir(ctx, cfg)
	if err != nil {
		return err
	}
	defer almacen.Cerrar()

	reg.Info("arrancando",
		"version", cfg.Version,
		"entorno", cfg.Entorno,
		"puerto", cfg.Puerto,
		"conexiones", cfg.PoolMaxConns,
	)
	if cfg.ServiceAPIKey == "" {
		// No impide arrancar —la API de personas funciona igual— pero el espejo de
		// PEDIDO no va a poder entrar, y eso desde fuera parece que PEDIDO no manda nada.
		reg.Warn("SERVICE_API_KEY vacía: las rutas de servicio quedan cerradas (el espejo de PEDIDO no podrá entrar)")
	}
	if len(cfg.OrigenesPermitidos) == 0 {
		reg.Warn("ORIGENES_PERMITIDOS vacío: el navegador no podrá llamar a esta API desde otro dominio")
	}
	// Tampoco impide arrancar, pero tiene que verse AL DESPLEGAR y no la tarde que
	// alguien pregunte por qué el vendedor no ve que su pedido salió. Sin esto, el canal
	// hacia PEDIDO queda mudo: no se rompe nada, pero el vendedor no se entera de nada.
	if cfg.PedidoAPIURL == "" {
		reg.Warn("PEDIDO_API_URL vacía: no se le podrá contar a PEDIDO en qué punto va cada pedido " +
			"(el reparto funciona igual, pero el vendedor no verá los cambios de estado)")
	}
	if cfg.AuthSigningKey == "" {
		reg.Warn("PROCOVAR_AUTH_SIGNING_KEY vacía: no se podrá preguntar a Accesos por los almacenes " +
			"ni por las tasas, así que no se podrán cotizar domicilios")
	}
	// Tampoco impide arrancar: mientras no haya un APK colgado, no anunciar nada es lo
	// correcto. Pero tiene que verse, porque desde fuera «los aparatos no avisan de la
	// versión nueva» y «no se anunció ninguna» se parecen mucho.
	if !cfg.Publicada.HayAlguna() {
		reg.Warn("APP_ULTIMA_VERSION vacía: /api/version no anuncia ninguna versión de la aplicación, " +
			"así que ningún aparato avisará de que hay una nueva (docs/actualizaciones.md)")
	} else {
		reg.Info("versión de la aplicación publicada",
			"version", cfg.Publicada.Version,
			"compilacion", cfg.Publicada.Compilacion,
		)
	}

	servidor := &http.Server{
		Addr: cfg.Direccion(),
		Handler: api.NuevoServidor(
			cfg, reg,
			alcance.NuevaPorteria(almacen, reg),
			auth.NuevoVerificador(cfg.JWTSecret),
			almacen.Salud,
		).Rutas(),
		ReadHeaderTimeout: cfg.TiempoLectura,
		ReadTimeout:       cfg.TiempoLectura,
		WriteTimeout:      cfg.TiempoEscritura,
		ErrorLog:          slog.NewLogLogger(reg.Handler(), slog.LevelError),
	}

	fallo := make(chan error, 1)
	go func() {
		if err := servidor.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			fallo <- err
		}
	}()

	select {
	case err := <-fallo:
		return fmt.Errorf("el servidor se cayó: %w", err)
	case <-ctx.Done():
	}

	// APAGADO ORDENADO. Un corte seco tira las peticiones en vuelo: en reparto eso es un
	// logístico que le dio a guardar y no sabe si se guardó. Shutdown deja de aceptar
	// conexiones nuevas y espera a que terminen las que hay, con un plazo — pasado el
	// plazo se corta igual, porque quien nos está parando tampoco espera para siempre.
	reg.Info("parando: se espera a las peticiones en vuelo", "plazo", cfg.TiempoApagado)
	parar() // se deja de atender la señal: un segundo Ctrl+C mata de verdad

	ctxApagado, cancelar := context.WithTimeout(context.Background(), cfg.TiempoApagado)
	defer cancelar()
	if err := servidor.Shutdown(ctxApagado); err != nil {
		// Se fuerza el cierre, pero se dice: son peticiones cortadas y tienen que verse.
		_ = servidor.Close()
		return fmt.Errorf("no dio tiempo a terminar las peticiones en vuelo: %w", err)
	}
	reg.Info("parado")
	return nil
}

// registro: JSON en producción —que es lo que sabe leer el agregador— y texto en
// desarrollo, que es lo que sabe leer una persona.
func registro(cfg *config.Config) *slog.Logger {
	opciones := &slog.HandlerOptions{Level: slog.LevelInfo}
	var h slog.Handler
	if cfg.EnProduccion() {
		h = slog.NewJSONHandler(os.Stdout, opciones)
	} else {
		opciones.Level = slog.LevelDebug
		h = slog.NewTextHandler(os.Stdout, opciones)
	}
	reg := slog.New(h).With("servicio", "reparto-api")
	// También el de por defecto: lo usa cualquier sitio que escriba sin tener el suyo.
	slog.SetDefault(reg)
	return reg
}
