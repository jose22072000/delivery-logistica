package espejo

import (
	"context"
	"errors"
	"log/slog"
	"testing"

	"github.com/jackc/pgx/v5"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/store/sqlc"
)

// UNA FILA QUE LLEGA IGUAL NO SE REESCRIBE — Y ESO NO ES UN FALLO.
//
// El número más gordo del servidor, medido el 26/09/2026 en producción:
//
//	customers   8.673 filas  ·  98.037.974 actualizaciones
//
// Cada cliente reescrito unas once mil veces con exactamente lo mismo, porque el espejo
// repasa cada minuto y siempre los últimos tres días. Es el 36 % de la CPU del Postgres
// con el servidor parado, y arrastra al resto: la búsqueda de pedidos figuraba como la
// consulta más cara —27 horas de CPU— cuando medida sola tarda 23 ms. No es lenta: compite.
//
// El arreglo es un `WHERE ... IS DISTINCT FROM ...` en el upsert. Y TRAE UNA TRAMPA que es
// justo lo que esta prueba sujeta: con ese `WHERE`, el `RETURNING` de una fila que no
// cambia **no devuelve nada**, y la consulta es `:one` — sale `pgx.ErrNoRows`.
//
// Devolverlo tal cual convierte el caso NORMAL —un repaso en el que no cambió nada, que es
// la inmensa mayoría de las vueltas— en un error por cliente, y el ciclo se cae entero. O
// sea: **la optimización habría tumbado la sincronización el primer minuto**, y en el peor
// sitio posible, porque sin espejo no entran ni clientes, ni catálogo, ni pedidos.
//
// Las dos mitades van juntas a propósito: sin la segunda, cualquiera puede «arreglar» la
// primera devolviendo siempre nil y tapando un fallo de verdad de la base.

type baseQueNoCambiaNada struct {
	sqlc.Querier
	llamadas int
}

func (b *baseQueNoCambiaNada) GuardarClienteDelEspejo(
	context.Context, sqlc.GuardarClienteDelEspejoParams,
) (sqlc.GuardarClienteDelEspejoRow, error) {
	b.llamadas++
	// Lo que contesta Postgres cuando el `WHERE` del upsert dice que no hay nada que
	// cambiar: ninguna fila, y por tanto ningún `RETURNING`.
	return sqlc.GuardarClienteDelEspejoRow{}, pgx.ErrNoRows
}

type baseQueFallaDeVerdad struct {
	sqlc.Querier
}

var errLaBaseSeCayo = errors.New("connection reset by peer")

func (b *baseQueFallaDeVerdad) GuardarClienteDelEspejo(
	context.Context, sqlc.GuardarClienteDelEspejoParams,
) (sqlc.GuardarClienteDelEspejoRow, error) {
	return sqlc.GuardarClienteDelEspejoRow{}, errLaBaseSeCayo
}

func clienteDePrueba() ClienteDeFuera {
	lat, lng := 20.02, -75.82
	return ClienteDeFuera{
		ID: "cli-1", Nombre: "Bodega La Esquina", Latitud: &lat, Longitud: &lng,
	}
}

func TestUnClienteQueNoCambioNoEsUnFallo(t *testing.T) {
	q := &baseQueNoCambiaNada{}

	err := baseDelRepartoCon(t, q).GuardarCliente(context.Background(), clienteDePrueba())

	if err != nil {
		t.Fatalf(
			"un repaso en el que no cambió nada es el caso NORMAL y aquí sale como "+
				"error: así el ciclo del espejo se cae entero y no entran ni clientes, "+
				"ni catálogo, ni pedidos. Salió: %v", err,
		)
	}
	if q.llamadas != 1 {
		t.Fatalf("no se intentó guardar: %d llamadas", q.llamadas)
	}
}

// LA OTRA MITAD. Sin esto, «no es un fallo» se cumple devolviendo siempre nil, y entonces
// una base caída se traga 8.673 clientes en silencio y el espejo dice que todo fue bien.
func TestUnFalloDeVerdadDeLaBaseSIGUESIENDOUNFALLO(t *testing.T) {
	err := baseDelRepartoCon(t, &baseQueFallaDeVerdad{}).
		GuardarCliente(context.Background(), clienteDePrueba())

	if !errors.Is(err, errLaBaseSeCayo) {
		t.Fatalf(
			"una base caída se tragó el cliente en silencio: el espejo diría que todo "+
				"fue bien con el padrón a medias. Salió: %v", err,
		)
	}
}

// baseDelRepartoCon monta una `BaseDelReparto` sobre el doble que se le dé.
//
// El alcance va de SUPER ADMIN y sin sucursal: lo que se prueba aquí es cómo se traduce lo
// que contesta Postgres, no a quién se le deja ver qué.
func baseDelRepartoCon(t *testing.T, q sqlc.Querier) BaseDelReparto {
	t.Helper()
	p := alcance.NuevaPorteria(fuenteDeLaPrueba{q: q}, slog.New(slog.DiscardHandler))
	a, err := p.Resolver(context.Background(), &auth.Usuario{
		ID: "servicio:prueba", Rol: "SUPER ADMIN",
	}, "")
	if err != nil {
		t.Fatalf("resolver el alcance: %v", err)
	}
	return BaseDelReparto{Acotado: a}
}

type fuenteDeLaPrueba struct{ q sqlc.Querier }

func (f fuenteDeLaPrueba) Consultas() sqlc.Querier { return f.q }
func (f fuenteDeLaPrueba) EnTx(ctx context.Context, fn func(sqlc.Querier) error) error {
	return fn(f.q)
}
