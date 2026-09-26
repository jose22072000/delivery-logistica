// Package store es el acceso a la base del sincronizador: el pool de pgx y las
// transacciones. Las consultas son las de sqlc y no se escribe SQL fuera de
// `db/queries/sync.sql`.
package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"procovar/reparto-sync/internal/store/sqlc"
)

// Datos es lo que ve el resto del servicio: el Querier generado más la forma de meter
// varias escrituras en una transacción.
//
// Es una interfaz y no el *Base a secas para que las pruebas puedan poner un doble del
// Querier generado. Aquí eso no es comodidad: lo que hay que probar —que un lote repetido
// no se aplica dos veces, que el orden se respeta, que un `local-…` acaba en el id bueno—
// es lógica de este servicio, y no se puede quedar sin probar por no tener un Postgres
// delante.
type Datos interface {
	sqlc.Querier

	// EnTransaccion corre varias consultas como una sola. Hace falta en un sitio muy
	// concreto: el apunte rechazado y su motivo entran juntos o no entra ninguno. Un
	// apunte marcado `rechazado` sin motivo en la bandeja es exactamente el descarte en
	// silencio que todo esto viene a impedir.
	EnTransaccion(ctx context.Context, fn func(sqlc.Querier) error) error
}

type Base struct {
	*sqlc.Queries
	pool *pgxpool.Pool
}

var _ Datos = (*Base)(nil)

type Opciones struct {
	URL           string
	MaxConexiones int32
}

// PlanesAMedida obliga a Postgres a planear cada ejecución con sus valores de verdad.
//
// El porqué entero, con las medidas, está en `PlanesAMedida` de la api
// (api/internal/store/store.go): con sentencias preparadas, a la sexta vez Postgres
// puede pasar a un plan genérico que no sabe si `sqlc.narg('sucursal')` viene vacío, y
// entonces no usa el índice de la sucursal. Aquí la bandeja de apuntes filtra igual
// (`sucursal IS NULL OR a.branch_id = …`). Va en la conexión y no en la base: viaja con
// el código y no toca a nadie más del Postgres compartido.
func PlanesAMedida(cfg *pgxpool.Config) {
	if cfg.ConnConfig.RuntimeParams == nil {
		cfg.ConnConfig.RuntimeParams = map[string]string{}
	}
	cfg.ConnConfig.RuntimeParams["plan_cache_mode"] = "force_custom_plan"
}

func Abrir(ctx context.Context, o Opciones) (*Base, error) {
	cfg, err := pgxpool.ParseConfig(o.URL)
	if err != nil {
		return nil, fmt.Errorf("DATABASE_URL no se entiende: %w", err)
	}
	if o.MaxConexiones > 0 {
		cfg.MaxConns = o.MaxConexiones
	}
	// Una conexión que lleva media hora abierta contra un Postgres que se reinició es una
	// conexión muerta que se descubre en la primera subida del día.
	cfg.MaxConnLifetime = 30 * time.Minute
	cfg.MaxConnIdleTime = 5 * time.Minute
	PlanesAMedida(cfg)

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("no se pudo abrir el pool: %w", err)
	}
	// Se comprueba al arrancar, no en la primera petición: ver el porqué en `internal/config`.
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("la base no contesta: %w", err)
	}
	return &Base{Queries: sqlc.New(pool), pool: pool}, nil
}

func (b *Base) EnTransaccion(ctx context.Context, fn func(sqlc.Querier) error) error {
	tx, err := b.pool.Begin(ctx)
	if err != nil {
		return err
	}
	// Rollback tras un Commit correcto no hace nada (pgx devuelve ErrTxClosed), así que
	// este defer vale para los dos caminos y no hay ninguno que se escape sin cerrar.
	defer func() { _ = tx.Rollback(ctx) }()

	if err := fn(b.Queries.WithTx(tx)); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (b *Base) Ping(ctx context.Context) error { return b.pool.Ping(ctx) }

func (b *Base) Cerrar() { b.pool.Close() }

// SinFilas dice si el error es «no hay ninguna fila», que en varios sitios de este
// servicio no es un fallo sino la respuesta: «esta clave no la había visto nunca».
func SinFilas(err error) bool { return errors.Is(err, pgx.ErrNoRows) }
