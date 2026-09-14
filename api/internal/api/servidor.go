// Los manejadores HTTP.
//
// AQUÍ ESTÁ EL PATRÓN A COPIAR. Están montados los cuatro recursos más simples
// —sucursales, vehículos, tipos de vehículo y ajustes—; los demás (pedidos, rutas,
// clientes, productos, panel, informes) se escriben igual. Lo que hay que respetar:
//
//  1. El manejador NO recibe un `sqlc.Querier`. Recibe `*alcance.Acotado`, que saca de la
//     petición con `alcance.De(r)`, y por ahí es por donde llega a las consultas. Si la
//     consulta que necesitas no está en `internal/alcance/consultas.go`, se añade ALLÍ.
//  2. Los mensajes de error son los LITERALES de `docs/contratos-api.md`. Están como
//     constantes en `internal/httpx`. No se escriben a mano en el manejador.
//  3. La forma de la respuesta se declara en un tipo `…Salida` de este paquete, no se
//     devuelve la fila de sqlc tal cual. La fila cambia cuando cambia una consulta; el
//     contrato con el cliente, no.
//  4. Lo que son varias escrituras va en `a.EnTx(...)`. A medias no vale.
package api

import (
	"context"
	"log/slog"
	"net/http"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
)

// Servidor junta lo que necesitan los manejadores. NO tiene un Querier: la única forma de
// consultar es el alcance de la petición.
type Servidor struct {
	cfg      *config.Config
	reg      *slog.Logger
	porteria *alcance.Porteria
	verif    *auth.Verificador
	// salud es sólo el ping a la base. Una función y no el almacén entero para que las
	// pruebas no tengan que levantar un pool.
	salud func(ctx context.Context) error
}

func NuevoServidor(cfg *config.Config, reg *slog.Logger, p *alcance.Porteria, v *auth.Verificador, salud func(ctx context.Context) error) *Servidor {
	if reg == nil {
		reg = slog.Default()
	}
	if salud == nil {
		salud = func(context.Context) error { return nil }
	}
	return &Servidor{cfg: cfg, reg: reg, porteria: p, verif: v, salud: salud}
}

// Rutas monta el router entero.
//
// Los middlewares comunes van en el router —una vez, para todo— y los de sesión y alcance
// en cada ruta que los necesita. Escribirlos ruta por ruta en vez de dentro del manejador
// es lo que hace que el alcance NO SE PUEDA OLVIDAR: se ve de un vistazo cuál lo lleva y
// cuál no, en una sola pantalla, en vez de tener que abrir treinta y cinco ficheros.
func (s *Servidor) Rutas() http.Handler {
	rt := httpx.NuevoRouter(
		httpx.IDDePeticion,
		httpx.ConRegistro(s.reg),
		httpx.RecuperarPanico,
		httpx.RegistrarPeticiones,
		httpx.CORS(s.cfg.OrigenesPermitidos),
		httpx.SinCache,
	)

	// --- Sin sesión ------------------------------------------------------------
	// /health lo sondea el desplegador; /version lo lee la APK para saber si tiene
	// que actualizarse. Pedir token en cualquiera de las dos las vuelve inútiles.
	rt.ManejarFunc(http.MethodGet, "/health", s.salud_)
	rt.ManejarFunc(http.MethodGet, "/version", s.version)
	rt.ManejarFunc(http.MethodGet, "/api/version", s.version)

	// --- Con sesión y con alcance ----------------------------------------------
	conSesion := s.verif.Exigir
	conAlcance := s.porteria.Exigir
	sesion := []httpx.Medio{conSesion, conAlcance}
	admin := []httpx.Medio{conSesion, auth.ExigirAdmin, conAlcance}

	// Sucursales. El GET va con la sucursal DE LA PERSONA, no con la elegida: ver
	// `alcance.ListarSucursalesVisibles`.
	rt.ManejarFunc(http.MethodGet, "/api/branches", s.listarSucursales, sesion...)
	rt.ManejarFunc(http.MethodPost, "/api/branches", s.crearSucursal, admin...)
	rt.ManejarFunc(http.MethodGet, "/api/branches/{id}", s.obtenerSucursal, sesion...)
	rt.ManejarFunc(http.MethodPatch, "/api/branches/{id}", s.actualizarSucursal, admin...)
	rt.ManejarFunc(http.MethodDelete, "/api/branches/{id}", s.borrarSucursal, admin...)

	// Vehículos.
	rt.ManejarFunc(http.MethodGet, "/api/vehicles", s.listarVehiculos, sesion...)
	rt.ManejarFunc(http.MethodPost, "/api/vehicles", s.crearVehiculo, sesion...)
	rt.ManejarFunc(http.MethodGet, "/api/vehicles/{id}", s.obtenerVehiculo, sesion...)
	rt.ManejarFunc(http.MethodPatch, "/api/vehicles/{id}", s.actualizarVehiculo, sesion...)
	rt.ManejarFunc(http.MethodDelete, "/api/vehicles/{id}", s.borrarVehiculo, sesion...)

	// Tipos de vehículo. RECURSO NUEVO: en delivery esto se mandaba dentro de
	// `PUT /api/settings` con la clave `tiposVehiculo`, un campo que NUNCA EXISTIÓ en el
	// esquema — la pantalla creaba tipos, los guardaba y se perdían sin un solo error.
	// Ahora es una tabla, así que es un recurso con sus rutas.
	rt.ManejarFunc(http.MethodGet, "/api/vehicle-types", s.listarTiposDeVehiculo, sesion...)
	rt.ManejarFunc(http.MethodPost, "/api/vehicle-types", s.crearTipoDeVehiculo, admin...)
	rt.ManejarFunc(http.MethodPatch, "/api/vehicle-types/{id}", s.actualizarTipoDeVehiculo, admin...)
	rt.ManejarFunc(http.MethodDelete, "/api/vehicle-types/{id}", s.borrarTipoDeVehiculo, admin...)

	// Ajustes. Globales: llevan sesión pero el alcance no pinta nada (y aun así se monta,
	// porque es por donde se llega a las consultas).
	rt.ManejarFunc(http.MethodGet, "/api/settings", s.obtenerAjustes, sesion...)
	rt.ManejarFunc(http.MethodPut, "/api/settings", s.guardarAjustes, sesion...)

	// --- El resto de los recursos ----------------------------------------------
	//
	// Cada módulo registra las suyas en su propio fichero y aquí sólo se llaman. No es
	// una manía de orden: este fichero lo tocan todos, y con doce recursos escribiendo
	// sus `ManejarFunc` aquí dentro, dos personas trabajando a la vez chocan siempre.
	// Así cada uno es dueño de su fichero y esto es la lista de lo que hay montado.
	//
	// El orden no importa para el enrutado —ServeMux resuelve por especificidad, no por
	// orden de registro— pero sí para leerlo: primero lo que se usa todos los días.
	s.rutasPedidos(rt, sesion, admin)
	s.rutasDeReparto(rt, sesion, admin)
	s.rutasTablero(rt, sesion, admin)
	s.rutasClientes(rt, sesion, admin)
	s.rutasProductos(rt, sesion, admin)
	s.rutasAlmacenes(rt, sesion, admin)
	s.rutasCotizacion(rt, sesion, admin)
	s.rutasPanel(rt, sesion, admin)
	s.rutasInformes(rt, sesion, admin)
	s.rutasEventos(rt, sesion, admin)
	s.rutasYo(rt, sesion, admin)
	s.rutasEspejo(rt, sesion, admin)

	return rt.Handler()
}
