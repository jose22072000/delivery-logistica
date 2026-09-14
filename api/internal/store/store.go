// El almacén: el pool de pgx sobre el `Querier` que genera sqlc.
//
// Esto es lo ÚNICO que sabe que por debajo hay un Postgres. De aquí para arriba se ve un
// `sqlc.Querier`, que es una interfaz, y por eso las pruebas del alcance corren sin base
// de datos: le pasan otro.
//
// El pool no se comparte por petición ni se abre uno por consulta: es uno solo, del
// proceso, y pgx reparte las conexiones. Abrir y cerrar conexiones por petición contra un
// Postgres que está detrás de un túnel SSH es lo que convierte una pantalla en un reloj
// de arena.
package store

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/store/sqlc"
)

type Almacen struct {
	pool *pgxpool.Pool
	q    *sqlc.Queries
}

// Abrir crea el pool y COMPRUEBA que la base contesta antes de devolver.
//
// El ping no es opcional: sin él, un servicio con la contraseña mal arranca «bien», pasa
// la comprobación de salud del desplegador y empieza a dar 500 a quien entre. Mejor no
// levantarse.
func Abrir(ctx context.Context, c *config.Config) (*Almacen, error) {
	cfg, err := pgxpool.ParseConfig(c.DatabaseURL)
	if err != nil {
		return nil, fmt.Errorf("DATABASE_URL no se puede interpretar: %w", err)
	}
	cfg.MaxConns = c.PoolMaxConns
	cfg.MinConns = c.PoolMinConns
	cfg.MaxConnIdleTime = c.PoolMaxIdleTime
	// Una conexión que lleva una hora viva detrás de un túnel SSH puede estar muerta sin
	// que ninguno de los dos lados lo sepa. Reciclarlas evita el «se quedó colgado» de la
	// primera consulta después de un rato sin usar.
	cfg.MaxConnLifetime = time.Hour

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("no se pudo crear el pool: %w", err)
	}

	ctxPing, cancelar := context.WithTimeout(ctx, 5*time.Second)
	defer cancelar()
	if err := pool.Ping(ctxPing); err != nil {
		pool.Close()
		return nil, fmt.Errorf("la base no contesta: %w", err)
	}

	return &Almacen{pool: pool, q: sqlc.New(pool)}, nil
}

// Consultas devuelve el Querier.
//
// NO SE LLAMA DESDE UN MANEJADOR. La única llamada legítima está en el arranque, para
// dárselo al paquete `alcance`, que es quien pone la sucursal en cada consulta. Un
// manejador que llegue aquí se salta la regla de seguridad del sistema.
func (a *Almacen) Consultas() sqlc.Querier { return a.q }

// EnTx corre f dentro de una transacción: si f devuelve error, no queda nada escrito.
//
// El rollback va en un defer y no al final: un pánico a mitad dejaría la transacción
// abierta, y con ella una conexión del pool y los bloqueos de las filas que tocó.
func (a *Almacen) EnTx(ctx context.Context, f func(sqlc.Querier) error) error {
	tx, err := a.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return fmt.Errorf("no se pudo abrir la transacción: %w", err)
	}
	defer func() {
		// Después de un Commit correcto este Rollback devuelve ErrTxClosed, que no es
		// un fallo: se ignora a propósito.
		_ = tx.Rollback(ctx)
	}()

	if err := f(a.q.WithTx(tx)); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// Salud es lo que contesta /health.
func (a *Almacen) Salud(ctx context.Context) error {
	ctx, cancelar := context.WithTimeout(ctx, 2*time.Second)
	defer cancelar()
	return a.pool.Ping(ctx)
}

// Cerrar espera a que terminen las consultas en vuelo.
func (a *Almacen) Cerrar() { a.pool.Close() }
