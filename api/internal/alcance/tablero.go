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

	"github.com/google/uuid"

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
func (a *Acotado) CrearColumna(ctx context.Context, arg sqlc.CrearColumnaParams) (sqlc.BoardColumn, error) {
	arg.Sucursal = a.sucursalPg()
	arg.CreadoPor = a.ActorRef()
	return a.q.CrearColumna(ctx, arg)
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

func (a *Acotado) EspejoListarProductos(ctx context.Context, limite int32) ([]sqlc.Product, error) {
	return a.q.ListarProductos(ctx, sqlc.ListarProductosParams{
		Sucursal: a.Codigo(), // el catálogo se acota por CÓDIGO, no por uuid
		Limite:   limite,
	})
}

func (a *Acotado) EspejoListarRutas(ctx context.Context) ([]sqlc.ListarRutasRow, error) {
	return a.q.ListarRutas(ctx, sqlc.ListarRutasParams{Sucursal: a.sucursalPg()})
}

func (a *Acotado) EspejoListarClientes(ctx context.Context, limite int32) ([]sqlc.ListarClientesRow, error) {
	return a.q.ListarClientes(ctx, sqlc.ListarClientesParams{
		SucursalDelAlcance: a.Codigo(), // clientes también van por código
		Limite:             limite,
	})
}
