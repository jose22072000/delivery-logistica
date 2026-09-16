package alcance

// LA PUERTA A LAS CONSULTAS DEL TABLERO Y DEL ESPEJO.
//
// Esto es la continuación de `consultas.go` y vale la misma regla: es ESTE fichero —no el
// manejador— quien rellena el parámetro `sucursal`, y por eso el manejador no puede
// olvidarlo. Va en fichero aparte y no dentro de `consultas.go` por una razón práctica:
// el tablero se escribe a la vez que los pedidos y las rutas, y dos manos en el mismo
// fichero es un conflicto seguro. Añadir un fichero no pisa a nadie.
//
// POR QUÉ ALGUNOS MÉTODOS LLEVAN EL PREFIJO `Tablero…` / `Espejo…`: son consultas
// COMPARTIDAS (crear una ruta, leer un pedido, listar el catálogo) que quien escriba
// `rutas.go` o `pedidos.go` va a exponer también con su nombre natural. Dos métodos con
// el mismo nombre en el mismo tipo no compilan, así que aquí van con prefijo y el día que
// estén los dos lados se unifican en uno. Es un nombre feo a cambio de que el trabajo de
// nadie se caiga al juntarlo.

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

// ---------------------------------------------------------------------------
// El tablero: columnas
// ---------------------------------------------------------------------------
//
// OJO CON EL PAR DE PARÁMETROS, que aquí son DOS y no uno. `branch_id` es el tablero que
// se está mirando y `sucursal` es el alcance. No sobra ninguno: no existe «el tablero de
// todas» —las columnas son de una sucursal y la cercanía se mide desde un almacén—, así
// que el Super Admin, que no tiene alcance, tiene que decir cuál mira. El alcance manda y
// `branch_id` estrecha: pedir el tablero de Holguín desde Santiago devuelve cero filas
// porque las dos condiciones tienen que cumplirse a la vez.

func (a *Acotado) ListarColumnasDelTablero(ctx context.Context, sucursal uuid.UUID) ([]sqlc.ListarColumnasDelTableroRow, error) {
	return a.q.ListarColumnasDelTablero(ctx, sqlc.ListarColumnasDelTableroParams{
		BranchID: sucursal, Sucursal: a.sucursalPg(),
	})
}

func (a *Acotado) ObtenerColumna(ctx context.Context, id uuid.UUID) (sqlc.BoardColumn, error) {
	return a.q.ObtenerColumna(ctx, sqlc.ObtenerColumnaParams{ID: id, Sucursal: a.sucursalPg()})
}

// CrearColumna deja constancia de quién la creó. `creado_por` NO filtra nada: aquí nada
// pertenece a una persona, y el día que aparezca un `WHERE creado_por = actor` es el
// fallo de delivery otra vez.
//
// Devuelve `BoardColumn` y no el tipo de la consulta porque la consulta pasó a tener dos
// ramas —la que inserta y la que devuelve la que ya estaba, para que subir dos veces el
// mismo id no cree dos zonas— y sqlc le da un tipo propio. Lo que sale por arriba es la
// columna, como siempre.
func (a *Acotado) CrearColumna(ctx context.Context, arg sqlc.CrearColumnaParams) (sqlc.BoardColumn, error) {
	arg.Sucursal = a.sucursalPg()
	arg.CreadoPor = a.ActorRef()
	fila, err := a.q.CrearColumna(ctx, arg)
	if err != nil {
		return sqlc.BoardColumn{}, err
	}
	return sqlc.BoardColumn{
		ID:        fila.ID,
		BranchID:  fila.BranchID,
		Nombre:    fila.Nombre,
		Posicion:  fila.Posicion,
		VehicleID: fila.VehicleID,
		CreadoPor: fila.CreadoPor,
		CreatedAt: fila.CreatedAt,
		UpdatedAt: fila.UpdatedAt,
	}, nil
}

func (a *Acotado) ActualizarColumna(ctx context.Context, arg sqlc.ActualizarColumnaParams) (sqlc.BoardColumn, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.ActualizarColumna(ctx, arg)
}

func (a *Acotado) ReordenarColumnas(ctx context.Context, sucursal uuid.UUID, ids []uuid.UUID) (int64, error) {
	return a.q.ReordenarColumnas(ctx, sqlc.ReordenarColumnasParams{
		Ids: ids, BranchID: sucursal, Sucursal: a.sucursalPg(),
	})
}

func (a *Acotado) ContarPedidosEnColumna(ctx context.Context, columna uuid.UUID) (int64, error) {
	return a.q.ContarPedidosEnColumna(ctx, sqlc.ContarPedidosEnColumnaParams{
		ColumnaID: columna, Sucursal: a.sucursalPg(),
	})
}

func (a *Acotado) VaciarColumna(ctx context.Context, columna uuid.UUID) (int64, error) {
	return a.q.VaciarColumna(ctx, sqlc.VaciarColumnaParams{
		ColumnaID: columna, Sucursal: a.sucursalPg(),
	})
}

func (a *Acotado) MoverPedidosDeColumna(ctx context.Context, origen, destino uuid.UUID) (int64, error) {
	return a.q.MoverPedidosDeColumna(ctx, sqlc.MoverPedidosDeColumnaParams{
		ColumnaOrigen: origen, ColumnaDestino: destino, Sucursal: a.sucursalPg(),
	})
}

func (a *Acotado) BorrarColumna(ctx context.Context, id uuid.UUID) (int64, error) {
	return a.q.BorrarColumna(ctx, sqlc.BorrarColumnaParams{ID: id, Sucursal: a.sucursalPg()})
}

// ---------------------------------------------------------------------------
// El tablero: tarjetas
// ---------------------------------------------------------------------------

func (a *Acotado) ListarPedidosColocados(ctx context.Context, arg sqlc.ListarPedidosColocadosParams) ([]sqlc.ListarPedidosColocadosRow, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.ListarPedidosColocados(ctx, arg)
}

func (a *Acotado) AvisosDelTablero(ctx context.Context, sucursal uuid.UUID) (sqlc.AvisosDelTableroRow, error) {
	return a.q.AvisosDelTablero(ctx, sqlc.AvisosDelTableroParams{
		BranchID: sucursal, Sucursal: a.sucursalPg(),
	})
}

func (a *Acotado) ListarPedidosSinColocar(ctx context.Context, arg sqlc.ListarPedidosSinColocarParams) ([]sqlc.ListarPedidosSinColocarRow, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.ListarPedidosSinColocar(ctx, arg)
}

func (a *Acotado) ContarPedidosSinColocar(ctx context.Context, arg sqlc.ContarPedidosSinColocarParams) (int64, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.ContarPedidosSinColocar(ctx, arg)
}

// ColocarPedido: el alcance y la constancia los pone el envoltorio. Lo demás —que el
// pedido y la columna sean de la misma sucursal, y que el pedido no vaya ya en un
// camión— lo comprueba el propio SQL en la misma sentencia que escribe, que es el único
// sitio donde esa comprobación no puede estar vieja.
func (a *Acotado) ColocarPedido(ctx context.Context, arg sqlc.ColocarPedidoParams) (sqlc.BoardPlacement, error) {
	arg.Sucursal = a.sucursalPg()
	arg.ColocadoPor = a.ActorRef()
	return a.q.ColocarPedido(ctx, arg)
}

func (a *Acotado) AbrirHuecoEnColumna(ctx context.Context, columna uuid.UUID, desde int32) (int64, error) {
	return a.q.AbrirHuecoEnColumna(ctx, sqlc.AbrirHuecoEnColumnaParams{
		ColumnaID: columna, DesdePosicion: desde, Sucursal: a.sucursalPg(),
	})
}

func (a *Acotado) CerrarHuecoEnColumna(ctx context.Context, columna uuid.UUID, desde int32) (int64, error) {
	return a.q.CerrarHuecoEnColumna(ctx, sqlc.CerrarHuecoEnColumnaParams{
		ColumnaID: columna, DesdePosicion: desde, Sucursal: a.sucursalPg(),
	})
}

func (a *Acotado) QuitarPedidoDelTablero(ctx context.Context, pedido uuid.UUID) (sqlc.QuitarPedidoDelTableroRow, error) {
	return a.q.QuitarPedidoDelTablero(ctx, sqlc.QuitarPedidoDelTableroParams{
		PedidoID: pedido, Sucursal: a.sucursalPg(),
	})
}

func (a *Acotado) PedidosDeColumnaParaArmarRuta(ctx context.Context, columna uuid.UUID) ([]sqlc.PedidosDeColumnaParaArmarRutaRow, error) {
	return a.q.PedidosDeColumnaParaArmarRuta(ctx, sqlc.PedidosDeColumnaParaArmarRutaParams{
		ColumnaID: columna, Sucursal: a.sucursalPg(),
	})
}

func (a *Acotado) QuitarDelTableroLosDeRuta(ctx context.Context, ruta uuid.UUID) (int64, error) {
	return a.q.QuitarDelTableroLosDeRuta(ctx, sqlc.QuitarDelTableroLosDeRutaParams{
		RutaID: aPg(&ruta), Sucursal: a.sucursalPg(),
	})
}

// ---------------------------------------------------------------------------
// Armar la ruta de una columna — consultas COMPARTIDAS con el armador de siempre
// ---------------------------------------------------------------------------

// TableroOrigenes son los puntos de partida. Se usan para resolver desde dónde se mide la
// cercanía; el filtro por sucursal concreta lo hace el manejador sobre lo devuelto,
// porque el alcance de un Super Admin es «todas» y aun así el tablero es de una.
func (a *Acotado) TableroOrigenes(ctx context.Context) ([]sqlc.ListarOrigenesRow, error) {
	return a.q.ListarOrigenes(ctx, a.sucursalPg())
}

func (a *Acotado) TableroObtenerPedido(ctx context.Context, id uuid.UUID) (sqlc.ObtenerPedidoRow, error) {
	return a.q.ObtenerPedido(ctx, sqlc.ObtenerPedidoParams{ID: id, Sucursal: a.sucursalPg()})
}

// TableroVehiculoParaCapacidad no lleva alcance porque la consulta no lo admite: sólo
// devuelve capacidad y estado, y su `branch_id` viene en la fila para que el manejador lo
// coteje. Se llama con un vehículo que ya salió de una columna del alcance.
func (a *Acotado) TableroVehiculoParaCapacidad(ctx context.Context, id uuid.UUID) (sqlc.ObtenerVehiculoParaCapacidadRow, error) {
	return a.q.ObtenerVehiculoParaCapacidad(ctx, id)
}

// TableroContarRutasDelDia no lleva alcance a propósito: el `NNN` de `RT-YYYYMMDD-NNN` es
// de TODA la casa. Numerar por sucursal daría dos rutas con el mismo código el mismo día,
// y ese código es lo que la gente se dice por teléfono.
func (a *Acotado) TableroContarRutasDelDia(ctx context.Context, prefijo string) (int64, error) {
	return a.q.ContarRutasDelDia(ctx, prefijo)
}

// TableroCrearRuta: la ruta NACE en la sucursal del tablero, no en la del alcance — el
// Super Admin no tiene alcance y aun así la ruta que arma es de la sucursal que está
// mirando. Por eso `branch_id` llega por argumento.
func (a *Acotado) TableroCrearRuta(ctx context.Context, arg sqlc.CrearRutaParams) (sqlc.CrearRutaRow, error) {
	arg.CreadoPor = a.ActorRef()
	return a.q.CrearRuta(ctx, arg)
}

func (a *Acotado) TableroEngancharPedidoARuta(ctx context.Context, arg sqlc.EngancharPedidoARutaParams) (int64, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.EngancharPedidoARuta(ctx, arg)
}

func (a *Acotado) TableroFijarTotalesDeRuta(ctx context.Context, arg sqlc.FijarTotalesDeRutaParams) (sqlc.FijarTotalesDeRutaRow, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.FijarTotalesDeRuta(ctx, arg)
}

// ---------------------------------------------------------------------------
// El espejo
// ---------------------------------------------------------------------------

// EspejoGuardarProducto NO lleva alcance, y es lo correcto: la bajada del catálogo entra
// con clave de servicio y recorre las ocho sucursales de una vez. Lo que acota cada fila
// es su `sucursal_codigo`, que viene del lote, no de quien llama.
func (a *Acotado) EspejoGuardarProducto(ctx context.Context, arg sqlc.GuardarProductoDelCatalogoParams) (sqlc.GuardarProductoDelCatalogoRow, error) {
	return a.q.GuardarProductoDelCatalogo(ctx, arg)
}

// EspejoMarcarCatalogoTraido es global: `settings` tiene una sola fila para toda la casa.
func (a *Acotado) EspejoMarcarCatalogoTraido(ctx context.Context) error {
	return a.q.MarcarCatalogoTraido(ctx)
}

// EspejoListarProductos y EspejoListarClientes: UNA TANDA del catálogo o del padrón.
//
// `desplazamiento` no es un adorno de paginación: es lo que hace que `truncado` sea una
// promesa que se puede cumplir. Hasta el 15/09/2026 las dos servían siempre las primeras
// `limite` filas ordenadas por nombre y se marcaba `truncado` al llegar al tope, pero la
// tanda siguiente pedía EXACTAMENTE LO MISMO — no había por dónde seguir. Contra
// producción eso dejó el aparato con `clientes = 2000` redondos de los 8.034 que hay, y
// la bajada se dio por buena.
//
// Se pagina por desplazamiento y no por marca de tiempo porque estas dos no tienen una
// marca útil para eso: el orden es por nombre, y `synced_at` lo comparten a miles las
// filas que PEDIDO trae de una vez —una sola transacción, una sola hora—, así que un corte
// por marca o no avanza o parte el grupo.
//
// `cambiadoDesde` es lo que hace que un arranque con el padrón al día NO cueste cinco
// idas y vueltas. Va EN EL SQL y no en un `if` al recorrer las filas: filtrando después,
// la tanda llega al tope igual, se marca `truncado` igual y el aparato encadena las cinco
// para no aplicar ni una fila. Nil = todo, que es la carga inicial.
func (a *Acotado) EspejoListarProductos(ctx context.Context, limite, desplazamiento int32, cambiadoDesde *time.Time) ([]sqlc.Product, error) {
	return a.q.ListarProductos(ctx, sqlc.ListarProductosParams{
		Sucursal:       a.Codigo(), // el catálogo se acota por CÓDIGO, no por uuid
		Limite:         limite,
		Desplazamiento: desplazamiento,
		CambiadoDesde:  marcaOpcional(cambiadoDesde),
	})
}

// marcaOpcional traduce el `desde` de la bajada a lo que espera sqlc. Nil es «sin filtro»,
// no «el principio de los tiempos»: un cero se compararía y dejaría fuera las filas sin
// marca.
func marcaOpcional(t *time.Time) pgtype.Timestamptz {
	if t == nil {
		return pgtype.Timestamptz{}
	}
	return pgtype.Timestamptz{Time: *t, Valid: true}
}

func (a *Acotado) EspejoListarRutas(ctx context.Context) ([]sqlc.ListarRutasRow, error) {
	return a.q.ListarRutas(ctx, sqlc.ListarRutasParams{Sucursal: a.sucursalPg()})
}

func (a *Acotado) EspejoListarClientes(ctx context.Context, limite, desplazamiento int32, cambiadoDesde *time.Time) ([]sqlc.ListarClientesRow, error) {
	return a.q.ListarClientes(ctx, sqlc.ListarClientesParams{
		SucursalDelAlcance: a.Codigo(), // clientes también van por código
		Limite:             limite,
		Desplazamiento:     desplazamiento,
		CambiadoDesde:      marcaOpcional(cambiadoDesde),
	})
}

// ---------------------------------------------------------------------------
// La bajada del aparato: las diferencias de pedidos
// ---------------------------------------------------------------------------

// VentanaDeBajada es el trozo de tiempo que se pide, más la sucursal que lo pide.
//
// `Hasta` va SIEMPRE puesto y lo pone quien contesta la bajada con SU reloj, nunca el
// aparato: el de un teléfono se cambia a mano, se va con la batería y salta de huso, y un
// reloj atrasado se saltaría cambios para siempre sin que nadie lo note.
//
// `Desde` nil es la CARGA INICIAL: el aparato empieza vacío y se le manda lo que hay.
type VentanaDeBajada struct {
	Desde *time.Time
	Hasta time.Time
	// Sucursal es la que PIDE quien llama. Nil = la del alcance. Lo que no puede es
	// ampliar: el alcance va aparte y en AND, así que quien sólo ve una sucursal no se
	// lleva la de otra escribiéndola en la barra del navegador.
	Sucursal *uuid.UUID
	// Tope acota la tanda. Lo que no quepa se pide en la siguiente con la marca de la
	// última fila servida.
	Tope int32
}

// EspejoDiferenciasDePedidos: lo que cambió en la ventana, ordenado por su marca.
//
// LOS ARCHIVADOS SÓLO EN LAS DIFERENCIAS, no en la carga inicial. En la carga inicial el
// aparato empieza vacío: un pedido archivado hace ocho meses no hay que quitárselo, porque
// no lo tiene, y bajárselo sería llenarle el tope con el histórico y dejar fuera lo del
// día. En una bajada por diferencias es al revés: archivar es justo lo que hay que
// contarle, para que lo BORRE.
func (a *Acotado) EspejoDiferenciasDePedidos(ctx context.Context, v VentanaDeBajada) ([]sqlc.DiferenciasDePedidosRow, error) {
	return a.q.DiferenciasDePedidos(ctx, sqlc.DiferenciasDePedidosParams{
		Desde:         marcaPg(v.Desde),
		Hasta:         marcaPg(&v.Hasta),
		Sucursal:      a.sucursalPg(), // el alcance, que aquí no se negocia
		BranchID:      aPg(v.Sucursal),
		ConArchivados: v.Desde != nil,
		Tope:          v.Tope,
	})
}

// EspejoPedidosQueSalieron: las lápidas de la ventana — borrados y mudados de sucursal.
//
// NO SE LLAMA EN LA CARGA INICIAL y por eso no tiene sentido sin `Desde`: al aparato que
// empieza vacío no hay nada que quitarle, y mandarle los borrados de los últimos dos años
// es gastarle la conexión en decirle que borre lo que nunca tuvo.
func (a *Acotado) EspejoPedidosQueSalieron(ctx context.Context, v VentanaDeBajada) ([]sqlc.PedidosQueSalieronDelAlcanceRow, error) {
	return a.q.PedidosQueSalieronDelAlcance(ctx, sqlc.PedidosQueSalieronDelAlcanceParams{
		Desde:    marcaPg(v.Desde),
		Hasta:    marcaPg(&v.Hasta),
		Sucursal: a.sucursalPg(),
		BranchID: aPg(v.Sucursal),
		Tope:     v.Tope,
	})
}

// marcaPg: una hora nuestra en el tipo que espera sqlc. Nil = NULL = «sin límite por ese
// lado», que es como el SQL lo entiende.
func marcaPg(t *time.Time) pgtype.Timestamptz {
	if t == nil {
		return pgtype.Timestamptz{}
	}
	return pgtype.Timestamptz{Time: *t, Valid: true}
}
