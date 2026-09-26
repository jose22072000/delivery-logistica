package alcance_test

import (
	"context"
	"errors"
	"log/slog"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/store/sqlc"
)

// UN PEDIDO QUE LLEGA IGUAL NO SE REESCRIBE — Y SUS RENGLONES SIGUEN ENCONTRÁNDOSE.
//
// La tercera pata del 36 % de CPU del Postgres, medida en producción el 26/09/2026:
//
//	orders   5.452 filas  ·  7.170.587 actualizaciones
//
// Mil trescientas veces cada pedido, casi siempre para dejarlo exactamente igual. Las
// otras dos patas —98 millones en `customers` y 8,8 en `order_items`— se cortaron el mismo
// día con la misma guarda.
//
// PERO AQUÍ HAY UNA TRAMPA QUE NO ESTABA EN LAS OTRAS DOS, y es lo que esta prueba sujeta:
// el upsert de pedidos devuelve el `id`, y **los renglones lo necesitan**. Con el `WHERE`,
// una fila que no cambia no devuelve nada: `pgx.ErrNoRows`.
//
// Las dos formas de equivocarse aquí, y las dos son caras:
//
//   - devolver el error tal cual → el caso NORMAL se convierte en un fallo por pedido y el
//     ciclo del espejo se cae entero;
//   - seguir con el `id` en cero → los renglones se escriben colgando de un uuid que no
//     existe, o se borran los de otro pedido. Eso no da error: da una hoja de despacho
//     equivocada.
//
// La salida es buscar el pedido por su referencia, que es el índice único.

var (
	elPedido   = uuid.MustParse("11111111-1111-1111-1111-111111111111")
	laSucursal = uuid.MustParse("22222222-2222-2222-2222-222222222222")
)

type baseDePedidos struct {
	sqlc.Querier

	// Qué contesta el upsert: `nil` = no cambió nada (ErrNoRows).
	cambio bool

	buscadoPorReferencia int
	renglonesLeidosDe    []uuid.UUID
	borradosDe           []uuid.UUID
	renglonesEscritos    []sqlc.CrearRenglonDePedidoParams
}

func (b *baseDePedidos) GuardarPedidoDelEspejo(
	context.Context, sqlc.GuardarPedidoDelEspejoParams,
) (sqlc.GuardarPedidoDelEspejoRow, error) {
	if !b.cambio {
		return sqlc.GuardarPedidoDelEspejoRow{}, pgx.ErrNoRows
	}
	return sqlc.GuardarPedidoDelEspejoRow{ID: elPedido, EsNuevo: false}, nil
}

func (b *baseDePedidos) BuscarPedidoPorReferencia(
	context.Context, sqlc.BuscarPedidoPorReferenciaParams,
) (sqlc.BuscarPedidoPorReferenciaRow, error) {
	b.buscadoPorReferencia++
	return sqlc.BuscarPedidoPorReferenciaRow{ID: elPedido}, nil
}

func (b *baseDePedidos) RenglonesDePedidoParaComparar(
	_ context.Context, id uuid.UUID,
) ([]sqlc.RenglonesDePedidoParaCompararRow, error) {
	b.renglonesLeidosDe = append(b.renglonesLeidosDe, id)
	// Lo que ya hay: un renglón, el mismo que va a llegar.
	return []sqlc.RenglonesDePedidoParaCompararRow{
		{Linea: 1, Description: "MALTA GUAJIRA 330 ML", Quantity: 60},
	}, nil
}

func (b *baseDePedidos) BorrarRenglonesDePedido(_ context.Context, id uuid.UUID) error {
	b.borradosDe = append(b.borradosDe, id)
	return nil
}

func (b *baseDePedidos) CrearRenglonDePedido(
	_ context.Context, p sqlc.CrearRenglonDePedidoParams,
) (sqlc.CrearRenglonDePedidoRow, error) {
	b.renglonesEscritos = append(b.renglonesEscritos, p)
	return sqlc.CrearRenglonDePedidoRow{}, nil
}

func elMismoRenglon() []sqlc.CrearRenglonDePedidoParams {
	return []sqlc.CrearRenglonDePedidoParams{
		{Linea: 1, Description: "MALTA GUAJIRA 330 ML", Quantity: 60},
	}
}

func otroRenglon() []sqlc.CrearRenglonDePedidoParams {
	return []sqlc.CrearRenglonDePedidoParams{
		{Linea: 1, Description: "MALTA GUAJIRA 330 ML", Quantity: 24},
	}
}

func guardarCon(t *testing.T, b *baseDePedidos, renglones []sqlc.CrearRenglonDePedidoParams) (uuid.UUID, bool, error) {
	t.Helper()
	p := alcance.NuevaPorteria(fuenteDePedidos{q: b}, slog.New(slog.DiscardHandler))
	a, err := p.Resolver(context.Background(), &auth.Usuario{
		ID: "servicio:espejo", Rol: "SUPER ADMIN",
	}, "")
	if err != nil {
		t.Fatalf("resolver el alcance: %v", err)
	}
	return a.EspejoGuardarPedido(context.Background(), sqlc.GuardarPedidoDelEspejoParams{
		BranchID: pgtype.UUID{Bytes: [16]byte(laSucursal), Valid: true},
	}, renglones)
}

// EL CASO NORMAL: no cambió nada. Ni error, ni id en cero, ni renglones reescritos.
func TestUnPedidoQueNoCambioNoEsUnFalloYConservaSuID(t *testing.T) {
	b := &baseDePedidos{cambio: false}

	id, nuevo, err := guardarCon(t, b, elMismoRenglon())

	if err != nil {
		t.Fatalf(
			"un repaso en el que no cambió nada es el caso NORMAL y sale como error: "+
				"así el ciclo del espejo se cae entero. Salió: %v", err,
		)
	}
	if id != elPedido {
		t.Fatalf(
			"se perdió el id del pedido: los renglones se escribirían colgando de un "+
				"uuid que no existe y la hoja de despacho saldría equivocada SIN dar "+
				"error. Salió: %v", id,
		)
	}
	if nuevo {
		t.Fatalf("un pedido que no cambió no acaba de nacer")
	}
	if b.buscadoPorReferencia != 1 {
		t.Fatalf("no se buscó el id por su referencia: %d", b.buscadoPorReferencia)
	}
	if len(b.borradosDe) != 0 || len(b.renglonesEscritos) != 0 {
		t.Fatalf(
			"los renglones se reescribieron aunque son los mismos: borrados=%d escritos=%d",
			len(b.borradosDe), len(b.renglonesEscritos),
		)
	}
}

// LA OTRA MITAD: cuando SÍ cambió, se escribe. Sin esto, «no reescribir» se cumple no
// escribiendo nunca, y el reparto se queda con la foto del primer día.
func TestUnPedidoQueSiCambioSeEscribe(t *testing.T) {
	b := &baseDePedidos{cambio: true}

	id, _, err := guardarCon(t, b, otroRenglon())

	if err != nil {
		t.Fatal(err)
	}
	if id != elPedido {
		t.Fatalf("id equivocado: %v", id)
	}
	if b.buscadoPorReferencia != 0 {
		t.Fatalf("se buscó por referencia sin hacer falta: el upsert ya dio el id")
	}
	if len(b.borradosDe) != 1 || len(b.renglonesEscritos) != 1 {
		t.Fatalf(
			"los renglones cambiaron y NO se reescribieron: el despacho prepararía lo "+
				"que el cliente ya no pidió. borrados=%d escritos=%d",
			len(b.borradosDe), len(b.renglonesEscritos),
		)
	}
	// Y el `pedido_id` lo pone este método, no quien llama.
	if b.renglonesEscritos[0].PedidoID != elPedido {
		t.Fatalf("el renglón se escribió colgando de otro pedido: %v",
			b.renglonesEscritos[0].PedidoID)
	}
}

// Y UN FALLO DE VERDAD SIGUE SIENDO UN FALLO. Sin esto, «ErrNoRows no es error» se cumple
// tragándose todos, y una base caída se come el lote entero en silencio.
func TestUnFalloDeLaBaseAlGuardarElPedidoSIGUESIENDOUNFALLO(t *testing.T) {
	b := &baseQueRevienta{}

	_, _, err := guardarCon(t, &baseDePedidos{}, elMismoRenglon())
	_ = err // el de arriba es el caso bueno; el de abajo es el que importa

	p := alcance.NuevaPorteria(fuenteDePedidos{q: b}, slog.New(slog.DiscardHandler))
	a, errA := p.Resolver(context.Background(), &auth.Usuario{
		ID: "servicio:espejo", Rol: "SUPER ADMIN",
	}, "")
	if errA != nil {
		t.Fatal(errA)
	}
	_, _, err = a.EspejoGuardarPedido(context.Background(),
		sqlc.GuardarPedidoDelEspejoParams{}, elMismoRenglon())

	if !errors.Is(err, errLaBaseSeCayo) {
		t.Fatalf("una base caída se tragó el pedido en silencio: %v", err)
	}
}

var errLaBaseSeCayo = errors.New("connection reset by peer")

type baseQueRevienta struct{ sqlc.Querier }

func (b *baseQueRevienta) GuardarPedidoDelEspejo(
	context.Context, sqlc.GuardarPedidoDelEspejoParams,
) (sqlc.GuardarPedidoDelEspejoRow, error) {
	return sqlc.GuardarPedidoDelEspejoRow{}, errLaBaseSeCayo
}

type fuenteDePedidos struct{ q sqlc.Querier }

func (f fuenteDePedidos) Consultas() sqlc.Querier { return f.q }
func (f fuenteDePedidos) EnTx(ctx context.Context, fn func(sqlc.Querier) error) error {
	return fn(f.q)
}
