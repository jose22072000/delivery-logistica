package espejo

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/store/sqlc"
)

// LO QUE EL ESPEJO GUARDA POR SU CUENTA, y por qué no va todo por HTTP.
//
// Los PEDIDOS entran por `/api/quote/batch` y por ningún otro sitio: es la puerta donde se
// les resuelve el peso y la distancia, y tener una segunda puerta sería tener dos formas de
// que el mismo pedido quedara distinto.
//
// Pero hay tres cosas que no pasan por ahí:
//
//   - La MARCA DE AGUA y la POSICIÓN DEL BARRIDO, que son el estado del propio espejo y se
//     leen de los pedidos ya guardados y de los ajustes.
//   - Los CLIENTES, que no tienen ruta de entrada: en el reparto se leen, no se dan de alta.
//
// Todo eso se lee y se escribe por el MISMO camino que los manejadores —`alcance.Acotado`—
// y no con el `Querier` pelado. El espejo no tiene persona ni sucursal, así que su alcance
// es «todas», que es justo lo que le toca: trae las ocho de una pasada.

// Base es el estado del espejo en la base del reparto.
type Base interface {
	// MarcaDeAgua es lo más nuevo que ya tenemos SEGÚN PEDIDO. nil = todavía no hay nada,
	// y entonces no hay incremental que hacer: se llena con el repaso y el barrido.
	MarcaDeAgua(ctx context.Context) (*time.Time, error)
	PosicionDelBarrido(ctx context.Context) (int, error)
	FijarBarrido(ctx context.Context, dia int) error
	GuardarCliente(ctx context.Context, c ClienteDeFuera) error
	BorrarClientesQueYaNoVienen(ctx context.Context, ids []string) (int64, error)
	// QuitarPedidos borra los que PEDIDO avisó como borrados. Ver `atender_avisos.go`.
	QuitarPedidos(ctx context.Context, externalIDs []string) error
}

// BaseDelReparto es la Base de verdad, sobre el alcance.
type BaseDelReparto struct{ Acotado *alcance.Acotado }

func (b BaseDelReparto) MarcaDeAgua(ctx context.Context) (*time.Time, error) {
	marca, err := b.Acotado.EspejoMarcaDeAgua(ctx)
	if err != nil {
		return nil, err
	}
	if !marca.Valid {
		return nil, nil
	}
	t := marca.Time
	return &t, nil
}

func (b BaseDelReparto) PosicionDelBarrido(ctx context.Context) (int, error) {
	dia, err := b.Acotado.EspejoPosicionDelBarrido(ctx)
	return int(dia), err
}

func (b BaseDelReparto) FijarBarrido(ctx context.Context, dia int) error {
	return b.Acotado.EspejoFijarBarrido(ctx, int32(dia))
}

// GuardarCliente copia un cliente. Sólo los GEOLOCALIZADOS —lo comprueba quien llama— y
// siempre por el upsert: dos pasadas a la vez no pueden duplicarlo.
func (b BaseDelReparto) GuardarCliente(ctx context.Context, c ClienteDeFuera) error {
	if c.Latitud == nil || c.Longitud == nil {
		return nil
	}
	fuente := sqlc.ProcedenciaPedido
	id := strings.TrimSpace(c.ID)
	_, err := b.Acotado.EspejoGuardarCliente(ctx, sqlc.GuardarClienteDelEspejoParams{
		Source:         &fuente,
		ExternalID:     &id,
		Name:           c.Nombre,
		Phone:          textoONada(c.Telefono),
		Address:        textoONada(c.Direccion),
		Municipio:      textoONada(c.Municipio),
		Zona:           textoONada(c.Zona),
		Codigo:         textoONada(c.Codigo),
		Vendedor:       textoONada(nombreDelVendedor(c.Vendedor)),
		Lat:            *c.Latitud,
		Lng:            *c.Longitud,
		SucursalCodigo: textoONada(c.SucursalCodigo),
	})
	// SIN FILA NO ES UN FALLO: ES QUE NO HABÍA NADA QUE CAMBIAR.
	//
	// El upsert lleva desde el 26/09/2026 un `WHERE ... IS DISTINCT FROM ...` que evita
	// reescribir una fila idéntica — es lo que corta los 98 millones de actualizaciones
	// sobre 8.673 clientes—. Pero con ese `WHERE`, el `RETURNING` de una fila que no
	// cambia **no devuelve nada**, y la consulta es `:one`: sale `pgx.ErrNoRows`.
	//
	// Devolverlo tal cual convierte el caso NORMAL —un repaso en el que no cambió nada,
	// que es la inmensa mayoría de las vueltas— en un error por cliente, y el ciclo del
	// espejo se cae entero. O sea: la optimización habría tumbado la sincronización el
	// primer minuto. Aquí es donde se traduce a lo que de verdad significa.
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	return err
}

// QuitarPedidos: los que PEDIDO borró. Que no encuentre ninguno NO es un error — el stream
// entrega al menos una vez y el mismo aviso puede llegar dos veces.
func (b BaseDelReparto) QuitarPedidos(ctx context.Context, externalIDs []string) error {
	_, err := b.Acotado.QuitarPedidosDelEspejo(ctx, externalIDs)
	return err
}

func (b BaseDelReparto) BorrarClientesQueYaNoVienen(ctx context.Context, ids []string) (int64, error) {
	return b.Acotado.EspejoBorrarClientesQueYaNoVienen(ctx, ids)
}
