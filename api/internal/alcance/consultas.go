package alcance

// LA PUERTA A LAS CONSULTAS.
//
// Cada consulta con alcance se expone aquí como un método de `Acotado`, y es ESTE fichero
// —no el manejador— quien rellena el parámetro `sucursal`. Lo que traiga el manejador en
// ese campo se pisa sin preguntar: un alcance que se pueda pasar desde fuera no es un
// alcance, es una sugerencia.
//
// PARA AÑADIR UN RECURSO (pedidos, rutas, clientes, productos...):
//
//  1. Añade aquí el método, copiando el de al lado. Pon el parámetro de sucursal con
//     `a.sucursalPg()` y no lo aceptes como argumento.
//  2. Si la consulta NO lleva alcance, va en la sección de abajo, con un comentario que
//     diga POR QUÉ no lo lleva. Sin ese porqué no se acepta: lo global se justifica, no
//     se supone.
//  3. El manejador recibe `*alcance.Acotado` y nunca un `sqlc.Querier`. Si un manejador
//     necesita el Querier pelado, es que la consulta que le falta hay que añadirla aquí.

import (
	"context"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/store/sqlc"
)

// ---------------------------------------------------------------------------
// Sucursales
// ---------------------------------------------------------------------------

// ListarSucursalesVisibles: «a cuáles puedo llegar», que depende sólo de la persona y no
// de la que tenga elegida arriba. Ver `personaPg`.
func (a *Acotado) ListarSucursalesVisibles(ctx context.Context) ([]sqlc.ListarSucursalesRow, error) {
	return a.q.ListarSucursales(ctx, a.personaPg())
}

func (a *Acotado) ObtenerSucursal(ctx context.Context, id uuid.UUID) (sqlc.Branch, error) {
	return a.q.ObtenerSucursal(ctx, sqlc.ObtenerSucursalParams{ID: id, Sucursal: a.sucursalPg()})
}

// CrearSucursal NO lleva alcance, y es lo correcto: una sucursal que todavía no existe no
// puede pertenecer a ninguna. La puerta aquí es el rol —sólo administradores—, y eso lo
// pone el router con `auth.ExigirAdmin`.
func (a *Acotado) CrearSucursal(ctx context.Context, arg sqlc.CrearSucursalParams) (sqlc.Branch, error) {
	arg.CreadoPor = a.ActorRef() // constancia de quién la dio de alta. NO filtra nada.
	return a.q.CrearSucursal(ctx, arg)
}

func (a *Acotado) ActualizarSucursal(ctx context.Context, arg sqlc.ActualizarSucursalParams) (sqlc.Branch, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.ActualizarSucursal(ctx, arg)
}

func (a *Acotado) BorrarSucursal(ctx context.Context, id uuid.UUID) (int64, error) {
	return a.q.BorrarSucursal(ctx, sqlc.BorrarSucursalParams{ID: id, Sucursal: a.sucursalPg()})
}

// ContarOrigenesDeSucursal se pregunta de la sucursal que se acaba de tocar, no de la del
// alcance: se usa para decidir si hay que crearle el punto de partida por defecto. El
// alcance ya lo dio por bueno el UPDATE de arriba, que no devolvió fila si no tocaba.
func (a *Acotado) ContarOrigenesDeSucursal(ctx context.Context, sucursal uuid.UUID) (int64, error) {
	return a.q.ContarOrigenesDeSucursal(ctx, aPg(&sucursal))
}

func (a *Acotado) CrearOrigen(ctx context.Context, arg sqlc.CrearOrigenParams) (sqlc.SavedOrigin, error) {
	arg.CreadoPor = a.ActorRef()
	return a.q.CrearOrigen(ctx, arg)
}

// ---------------------------------------------------------------------------
// Vehículos
// ---------------------------------------------------------------------------
//
// OJO con la forma del filtro de vehículos: deja pasar también los de `branch_id` NULL,
// que significan «de todas las sucursales». Eso va en el SQL (`db/queries/vehicles.sql`)
// y no aquí. Un camión compartido que no salga en la lista de nadie es un camión que no
// se puede usar.

func (a *Acotado) ListarVehiculos(ctx context.Context) ([]sqlc.ListarVehiculosRow, error) {
	return a.q.ListarVehiculos(ctx, a.sucursalPg())
}

func (a *Acotado) ObtenerVehiculo(ctx context.Context, id uuid.UUID) (sqlc.ObtenerVehiculoRow, error) {
	return a.q.ObtenerVehiculo(ctx, sqlc.ObtenerVehiculoParams{ID: id, Sucursal: a.sucursalPg()})
}

// CrearVehiculo: el camión NACE en la sucursal del alcance. Quien no tiene alcance —el
// Super Admin— lo deja sin sucursal, que quiere decir «de todas».
func (a *Acotado) CrearVehiculo(ctx context.Context, arg sqlc.CrearVehiculoParams) (sqlc.Vehicle, error) {
	arg.BranchID = a.sucursalPg()
	return a.q.CrearVehiculo(ctx, arg)
}

func (a *Acotado) ActualizarVehiculo(ctx context.Context, arg sqlc.ActualizarVehiculoParams) (sqlc.Vehicle, error) {
	arg.Sucursal = a.sucursalPg()
	return a.q.ActualizarVehiculo(ctx, arg)
}

func (a *Acotado) BorrarVehiculo(ctx context.Context, id uuid.UUID) (int64, error) {
	return a.q.BorrarVehiculo(ctx, sqlc.BorrarVehiculoParams{ID: id, Sucursal: a.sucursalPg()})
}

// DesmarcarReferenciaDeDomicilio desmarca los demás camiones de referencia DE ESTA
// SUCURSAL. Va siempre en la misma transacción que el marcado, o el índice único parcial
// `vehicles_una_referencia_por_sucursal` rechaza el segundo.
func (a *Acotado) DesmarcarReferenciaDeDomicilio(ctx context.Context, exceptoID uuid.UUID) (int64, error) {
	return a.q.DesmarcarReferenciaDeDomicilio(ctx, sqlc.DesmarcarReferenciaDeDomicilioParams{
		ExceptoID: exceptoID,
		Sucursal:  a.sucursalPg(),
	})
}

func (a *Acotado) DesvincularVehiculoDePedidos(ctx context.Context, vehiculo uuid.UUID) (int64, error) {
	return a.q.DesvincularVehiculoDePedidos(ctx, sqlc.DesvincularVehiculoDePedidosParams{
		VehiculoID: aPg(&vehiculo),
		Sucursal:   a.sucursalPg(),
	})
}

func (a *Acotado) DesvincularVehiculoDeRutas(ctx context.Context, vehiculo uuid.UUID) (int64, error) {
	return a.q.DesvincularVehiculoDeRutas(ctx, sqlc.DesvincularVehiculoDeRutasParams{
		VehiculoID: aPg(&vehiculo),
		Sucursal:   a.sucursalPg(),
	})
}

func (a *Acotado) CompletarRutasDeVehiculo(ctx context.Context, vehiculo uuid.UUID) (int64, error) {
	return a.q.CompletarRutasDeVehiculo(ctx, sqlc.CompletarRutasDeVehiculoParams{
		VehiculoID: aPg(&vehiculo),
		Sucursal:   a.sucursalPg(),
	})
}

// BorrarAsignacionesDeVehiculo no lleva sucursal porque `order_vehicles` no tiene esa
// columna. El alcance ya se comprobó antes: sólo se llama con un vehículo que el UPDATE
// o el SELECT acotado devolvió como propio.
func (a *Acotado) BorrarAsignacionesDeVehiculo(ctx context.Context, vehiculo uuid.UUID) (int64, error) {
	return a.q.BorrarAsignacionesDeVehiculo(ctx, vehiculo)
}

// ---------------------------------------------------------------------------
// SIN ALCANCE, a propósito
// ---------------------------------------------------------------------------
//
// Lo de abajo es GLOBAL de la empresa y ninguna de estas tablas tiene columna de sucursal
// que filtrar. No es un olvido; está escrito en el esquema y repetido aquí porque es
// justo lo que hay que mirar dos veces cuando se revisa la seguridad.

// Tipos de vehículo: un «camión» es un camión en las ocho sucursales. Lo que sí es por
// sucursal es qué VEHÍCULO concreto es el de referencia, y eso vive en `vehicles`.
func (a *Acotado) ListarTiposDeVehiculo(ctx context.Context, soloActivos *bool) ([]sqlc.ListarTiposDeVehiculoRow, error) {
	return a.q.ListarTiposDeVehiculo(ctx, soloActivos)
}

func (a *Acotado) ObtenerTipoDeVehiculo(ctx context.Context, id uuid.UUID) (sqlc.VehicleType, error) {
	return a.q.ObtenerTipoDeVehiculo(ctx, id)
}

func (a *Acotado) BuscarTipoDeVehiculoPorNombre(ctx context.Context, nombre string) (sqlc.BuscarTipoDeVehiculoPorNombreRow, error) {
	return a.q.BuscarTipoDeVehiculoPorNombre(ctx, nombre)
}

func (a *Acotado) CrearTipoDeVehiculo(ctx context.Context, arg sqlc.CrearTipoDeVehiculoParams) (sqlc.VehicleType, error) {
	return a.q.CrearTipoDeVehiculo(ctx, arg)
}

func (a *Acotado) ActualizarTipoDeVehiculo(ctx context.Context, arg sqlc.ActualizarTipoDeVehiculoParams) (sqlc.VehicleType, error) {
	return a.q.ActualizarTipoDeVehiculo(ctx, arg)
}

func (a *Acotado) RetirarTipoDeVehiculo(ctx context.Context, id uuid.UUID) (int64, error) {
	return a.q.RetirarTipoDeVehiculo(ctx, id)
}

func (a *Acotado) BorrarTipoDeVehiculoSinUso(ctx context.Context, id uuid.UUID) (int64, error) {
	return a.q.BorrarTipoDeVehiculoSinUso(ctx, id)
}

// Ajustes y monedas: son de toda la empresa. La tasa POR SUCURSAL es otra cosa y vive en
// Accesos, no aquí.
func (a *Acotado) ObtenerAjustes(ctx context.Context) (sqlc.Setting, error) {
	return a.q.ObtenerAjustes(ctx)
}

func (a *Acotado) ActualizarAjustes(ctx context.Context, arg sqlc.ActualizarAjustesParams) (sqlc.Setting, error) {
	return a.q.ActualizarAjustes(ctx, arg)
}

func (a *Acotado) ListarMonedas(ctx context.Context, soloActivas *bool) ([]sqlc.Currency, error) {
	return a.q.ListarMonedas(ctx, soloActivas)
}

func (a *Acotado) GuardarMoneda(ctx context.Context, arg sqlc.GuardarMonedaParams) (sqlc.Currency, error) {
	return a.q.GuardarMoneda(ctx, arg)
}

func (a *Acotado) DesactivarMoneda(ctx context.Context, code string) (int64, error) {
	return a.q.DesactivarMoneda(ctx, code)
}
