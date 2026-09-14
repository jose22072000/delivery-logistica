// EL ESPEJO DE PEDIDO: el proceso que trae los datos.
//
// Sin esto, la base del reparto está vacía. No hay alta de pedidos a mano en ninguna
// pantalla: los pedidos y los clientes son de PEDIDO, y este proceso los copia.
//
// Corre APARTE de la API, con su propio contenedor, y así tiene que seguir:
//
//   - Un barrido del histórico puede tardar minutos. Dentro de la API compartiría el plazo
//     de las peticiones y la tumbaría cuando más se usa, que es de día.
//   - Si el espejo se cae, la API sigue atendiendo a quien está cargando un camión — con
//     los pedidos de hasta ese momento, que es mucho mejor que una pantalla caída.
//   - Y al revés: reiniciar la API no interrumpe un barrido a medias.
//
// Uso:
//
//	espejo            da vueltas hasta que lo paren
//	espejo --once     una pasada y se va (para probar y para un cron)
//
// Lo que necesita del entorno: `DATABASE_URL`, `SERVICE_API_KEY`, `PEDIDO_API_URL` y
// `DELIVERY_URL`. El resto tiene valores por defecto medidos (ver `internal/espejo`).
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/espejo"
	"procovar/reparto-api/internal/store"
)

func main() {
	if err := correr(); err != nil {
		// A stderr y sin el registro estructurado: esto lo lee una persona mirando el
		// despliegue, no un agregador de logs.
		fmt.Fprintf(os.Stderr, "\nel espejo no puede arrancar:\n%v\n\n", err)
		os.Exit(1)
	}
}

func correr() error {
	unaVez := flag.Bool("once", false, "una sola pasada y salir")
	flag.Parse()

	opciones, err := espejo.Cargar(os.Getenv)
	if err != nil {
		return err
	}
	reg := registro()

	// El contexto se cancela con la primera señal. SIGTERM es lo que manda Docker al parar
	// el contenedor; SIGINT es Ctrl+C en desarrollo.
	ctx, parar := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer parar()

	cfg, err := configDeLaBase()
	if err != nil {
		return err
	}
	almacen, err := store.Abrir(ctx, cfg)
	if err != nil {
		return err
	}
	defer almacen.Cerrar()

	// EL ESPEJO NO TIENE PERSONA, y su alcance es «todas»: trae las ocho sucursales de una
	// pasada. Aun así se pasa por la portería y no por el `Querier` pelado — la regla del
	// sistema es que a la base se llega por `alcance`, y una excepción «porque esto es un
	// proceso de fondo» es exactamente como se acaban colando las consultas sin sucursal.
	acotado, err := alcance.NuevaPorteria(almacen, reg).Resolver(ctx,
		&auth.Usuario{ID: "servicio:espejo", Nombre: "espejo"}, "")
	if err != nil {
		return fmt.Errorf("no se pudo resolver el alcance del espejo: %w", err)
	}

	proceso := espejo.Nuevo(opciones, espejo.BaseDelReparto{Acotado: acotado}, reg)

	if *unaVez {
		return proceso.Ciclo(ctx)
	}
	return proceso.Correr(ctx)
}

// configDeLaBase arma lo justo para abrir el pool. NO pasa por `config.Cargar` a propósito:
// eso exige `JWT_SECRET`, que es para validar personas, y aquí no entra ninguna. Pedirlo
// sería no arrancar el espejo por un secreto que no va a usar.
func configDeLaBase() (*config.Config, error) {
	url := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if url == "" {
		return nil, fmt.Errorf("falta DATABASE_URL: el espejo guarda los clientes y lee su marca de agua en la base del reparto")
	}
	return &config.Config{
		DatabaseURL: url,
		// Pocas conexiones: el espejo hace una consulta cada vez y no puede quedarse con
		// las que necesita la API para atender a quien está cargando un camión.
		PoolMaxConns:    4,
		PoolMinConns:    1,
		PoolMaxIdleTime: 5 * time.Minute,
	}, nil
}

func registro() *slog.Logger {
	opciones := &slog.HandlerOptions{Level: slog.LevelInfo}
	var h slog.Handler
	if os.Getenv("ENTORNO") == "produccion" {
		h = slog.NewJSONHandler(os.Stdout, opciones)
	} else {
		opciones.Level = slog.LevelDebug
		h = slog.NewTextHandler(os.Stdout, opciones)
	}
	reg := slog.New(h).With("servicio", "espejo")
	slog.SetDefault(reg)
	return reg
}
