// EL PANEL DE LA MAÑANA  (GET /api/dashboard).
//
// Es la primera pantalla del día: dice cuánto hay pendiente de repartir y por dónde
// empezar. Ocho números y un desglose, sin parámetros.
//
// SE CUENTA POR SUCURSAL, NUNCA POR CUENTA. En delivery el panel contaba «los pedidos de
// la cuenta que mira», y eso era el fallo: las ocho sucursales las dio de alta el Super
// Admin y los 3.528 pedidos importados quedaron a su nombre, así que el logístico de
// Holguín abría el panel y veía ceros —con un 200, sin una sola traza y sin forma de
// distinguirlo de «todavía no hay nada»—. Aquí el único campo que decide es `branch_id`, y
// lo pone el alcance: este fichero no escribe ni un solo filtro de sucursal, porque el que
// se escribe a mano es el que un día se olvida.
package api

import (
	"net/http"
	"time"

	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/httpx"
)

// SinSucursal es el nombre que se enseña cuando el pedido no tiene sucursal —o tiene una
// que ya no existe—. Literal del contrato; sale en la pantalla tal cual.
const SinSucursal = "Sin sucursal"

// PanelSalida es la forma del contrato. Los nombres de los campos son los que lee la
// pantalla y NO se tocan aunque las columnas de la base se llamen de otra manera: la fila
// cambia cuando cambia una consulta; el contrato con el cliente, no.
type PanelSalida struct {
	TotalOrders     int64                 `json:"totalOrders"`
	SinRuta         int64                 `json:"sinRuta"`
	RutasActivas    int64                 `json:"rutasActivas"`
	EntregadosHoy   int64                 `json:"entregadosHoy"`
	TotalVehicles   int64                 `json:"totalVehicles"`
	VehiculosEnRuta int64                 `json:"vehiculosEnRuta"`
	PesoPendiente   float64               `json:"pesoPendiente"`
	TotalDomicilios float64               `json:"totalDomicilios"`
	PorSucursal     []PanelSucursalSalida `json:"porSucursal"`
}

type PanelSucursalSalida struct {
	Sucursal string  `json:"sucursal"`
	Pedidos  int64   `json:"pedidos"`
	PesoKg   float64 `json:"pesoKg"`
}

// rutasPanel monta el panel. `admin` no se usa: el panel no escribe nada, así que no hay
// nada aquí que pedirle a un administrador; lo que decide qué se ve es el alcance.
func (s *Servidor) rutasPanel(rt *httpx.Router, sesion, admin []httpx.Medio) {
	rt.ManejarFunc(http.MethodGet, "/api/dashboard", s.panel, sesion...)
}

// GET /api/dashboard
func (s *Servidor) panel(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	ctx := r.Context()

	// «Hoy» se calcula AQUÍ y se manda a la consulta, no se resuelve en Postgres con
	// `date_trunc('day', now())`. El contrato dice «las 00:00 de hoy en la hora local del
	// servidor», y la hora local del motor no tiene por qué ser la del proceso: el
	// contenedor va en UTC y Cuba está cinco horas por detrás, así que «entregados hoy»
	// arrancaría a las siete de la tarde de ayer.
	resumen, err := a.PanelResumen(ctx, medianocheDeHoy(time.Now()))
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	rutasActivas, err := a.ContarRutasActivas(ctx)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	totalVehiculos, err := a.ContarVehiculos(ctx)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	enRuta, err := a.ContarVehiculosEnRuta(ctx)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	porSucursal, err := a.PanelPorSucursal(ctx)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	// Lista vacía y no `null`: la pantalla recorre `porSucursal` sin mirar antes si es
	// nula, y un null ahí es una pantalla en blanco en vez del «No queda nada sin ruta.»
	desglose := make([]PanelSucursalSalida, 0, len(porSucursal))
	for _, f := range porSucursal {
		nombre := SinSucursal
		if f.SucursalNombre != nil {
			nombre = *f.SucursalNombre
		}
		desglose = append(desglose, PanelSucursalSalida{
			Sucursal: nombre, Pedidos: f.Pedidos, PesoKg: f.PesoKg,
		})
	}

	httpx.JSON(w, r, http.StatusOK, PanelSalida{
		TotalOrders:     resumen.TotalPedidos,
		SinRuta:         resumen.SinRuta,
		RutasActivas:    rutasActivas,
		EntregadosHoy:   resumen.EntregadosHoy,
		TotalVehicles:   totalVehiculos,
		VehiculosEnRuta: enRuta,
		PesoPendiente:   resumen.PesoPendiente,
		TotalDomicilios: resumen.TotalDomicilios,
		PorSucursal:     desglose,
	})
}

// medianocheDeHoy devuelve las 00:00 del día de `t`, EN SU MISMA ZONA. Se pasa el reloj
// por parámetro en vez de llamar a time.Now() dentro para que se pueda probar sin esperar
// a que cambie el día.
func medianocheDeHoy(t time.Time) pgtype.Timestamptz {
	medianoche := time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
	return pgtype.Timestamptz{Time: medianoche, Valid: true}
}
