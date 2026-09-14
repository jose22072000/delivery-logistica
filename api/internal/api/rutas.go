// LAS RUTAS DE REPARTO. La pieza central: armar el camión, despacharlo y cerrarlo.
//
// El pliego es `docs/contratos-api.md` (sección routes) y `docs/reglas-negocio.md` §15.
// Lo que aquí se repite en comentarios es el PORQUÉ, que es lo que no se puede leer del
// código y lo que se rompe cuando alguien "simplifica".
//
// Las tres cosas que hay que tener delante todo el rato:
//
//  1. UNA RUTA SE ARMA CON PEDIDOS QUE YA EXISTEN y que están libres (`route_id` NULL).
//     Teclear paradas creaba pedidos sin folio de PEDIDO —sin factura que atarles y por
//     tanto imposibles de cobrar—; esa puerta se cerró el 03/09/2026.
//  2. `route_id` Y `ultima_ruta_id` SON DOS PREGUNTAS DISTINTAS. El primero es «va
//     cargado ahora»; el segundo, «en qué camión viajó». Al cerrar, un devuelto suelta el
//     primero y CONSERVA el segundo: soltar los dos lo borraba de la hoja de cierre.
//  3. EL CAMIÓN NO SE OCUPA AL ARMAR. Se ocupa al despachar (`in_progress`) y se libera
//     al completar o al borrar la ruta. Ocuparlo al armar impedía preparar la ruta de
//     mañana mientras el camión está fuera, que es justo cuando se prepara.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// ---------------------------------------------------------------------------
// Mensajes literales del pliego
// ---------------------------------------------------------------------------
//
// Van aquí y no en `httpx` porque son SÓLO de rutas; los de `httpx` son los que comparten
// varios recursos. Son visibles: salen en la pantalla del logístico. No se tocan.

const (
	msgFaltanCoordenadas = "Las coordenadas del punto de partida son requeridas"
	msgFaltaVehiculo     = "Se requiere un vehículo para crear la ruta"
	// El literal lleva las comillas invertidas alrededor de `orderIds`. Están en el
	// contrato y se ven en la pantalla: no son formato de Markdown.
	msgSinPedidos           = "Una ruta se arma eligiendo pedidos ya existentes. Manda `orderIds`."
	msgPedidosNoDisponibles = "Los pedidos seleccionados ya no están disponibles"
	// Femenino y distinto del `No encontrado` de `/api/routes/[id]`: así viene del
	// contrato y así se queda.
	msgRutaNoEncontrada = "No encontrada"
	msgSinResultados    = "No vino ningún resultado"
	msgParadaAjena      = "ese pedido no va en esta ruta"
)

// ---------------------------------------------------------------------------
// Geometría  (reglas-negocio §1.1 a §1.3)
// ---------------------------------------------------------------------------

// La distancia en línea recta es `kmHaversine`, en `clientes.go`: UNA sola en todo el
// paquete. Aquí había una tercera copia (`haversineKm`) escrita en paralelo con las otras
// dos; son la misma cuenta y ahora hay una.
//
// LO QUE NO SE PUEDE PERDER DE AQUÍ: se usa SIN REDONDEAR. El redondeo es cosa de quien lo
// enseña, y redondear antes de ordenar cambia el orden de visita cuando dos paradas caen
// casi a la misma distancia.

// paradaGeo es lo mínimo que hace falta para ordenar: dónde está cada pedido.
type paradaGeo struct {
	id  uuid.UUID
	lat float64
	lng float64
}

// ordenVecinoMasProximo devuelve los ids en el orden en que el camión los visita.
//
// Vecino más próximo (greedy) desde el origen, sin 2-opt ni nada después. No es el
// recorrido óptimo y no pretende serlo: es el que delivery lleva usando, y cambiarlo aquí
// cambiaría el orden de las paradas de todas las rutas sin que nadie lo hubiera pedido.
//
// DOS DETALLES QUE PARECEN MENUDENCIAS Y NO LO SON:
//
//   - El desempate lo gana el PRIMERO de la lista (comparación estricta `<`). Con dos
//     clientes en el mismo edificio —que los hay— un `<=` daría un orden distinto cada
//     vez que cambie el orden de lectura de la base.
//   - No se cierra el circuito: el regreso al almacén no es una parada. Los kilómetros
//     de la vuelta los suma quien calcula el total, no este orden.
func ordenVecinoMasProximo(origenLat, origenLng float64, paradas []paradaGeo) []uuid.UUID {
	if len(paradas) == 0 {
		return nil
	}
	pendientes := append([]paradaGeo(nil), paradas...)
	orden := make([]uuid.UUID, 0, len(pendientes))
	actualLat, actualLng := origenLat, origenLng
	for len(pendientes) > 0 {
		mejor := 0
		mejorKm := math.Inf(1)
		for i, p := range pendientes {
			km := kmHaversine(actualLat, actualLng, p.lat, p.lng)
			if km < mejorKm {
				mejorKm = km
				mejor = i
			}
		}
		elegida := pendientes[mejor]
		orden = append(orden, elegida.id)
		actualLat, actualLng = elegida.lat, elegida.lng
		pendientes = append(pendientes[:mejor], pendientes[mejor+1:]...)
	}
	return orden
}

// ---------------------------------------------------------------------------
// El aviso a PEDIDO y el aviso a las pantallas
// ---------------------------------------------------------------------------
//
// Son VARIABLES de paquete y no llamadas directas por dos razones: la prueba las sustituye
// sin levantar nada, y el día que exista el canal de verdad se cambia aquí y en un sitio.

// ParteAPedido es lo que se le contesta al cliente sobre el aviso: la forma la fija el
// contrato (`aPedido: {ok, enviados, aplicados, error?}`).
type ParteAPedido struct {
	Ok        bool   `json:"ok"`
	Enviados  int    `json:"enviados"`
	Aplicados int    `json:"aplicados"`
	Error     string `json:"error,omitempty"`
}

// AvisoDeParada es un pedido y en qué punto del reparto quedó.
type AvisoDeParada struct {
	// PedidoID es el id EN PEDIDO, no el nuestro. Cada copia del espejo lo guarda en
	// `external_id`; un pedido sin él no tiene a quién avisarle y no entra en el lote.
	PedidoID string `json:"pedidoId"`
	Estado   string `json:"estado"`
	Nota     string `json:"nota,omitempty"`

	// At es LA HORA DEL SUCESO, no la de la llamada.
	//
	// Es la diferencia entre que en PEDIDO ponga las cuatro o las siete y media. Con el
	// trabajo sin conexión, el logístico marca el cierre a las 16:04 en un patio sin
	// señal y la cola sube a las 19:30: el vendedor tiene que ver cuándo recibió su
	// cliente, no cuándo pilló señal el teléfono (`docs/sincronizacion.md`, «La hora es
	// la del aparato»).
	//
	// `omitzero` y no `omitempty`: un `time.Time` vacío no es «vacío» para el JSON, se
	// serializaría como el año 1, y PEDIDO se creería esa fecha. Sin hora, el campo no
	// va y PEDIDO pone la suya, que es lo que dice el contrato (`at?`).
	At time.Time `json:"at,omitzero"`
}

// horaDelSuceso: CUÁNDO PASÓ, que no siempre es cuándo se está contando.
//
// El sincronizador reenvía cada apunte de la cola de un aparato con `X-Hecho-At`, la hora
// que marcó el aparato cuando la persona pulsó el botón (ver `sync/internal/reparto`). Si
// viene, es LA buena. Si no viene, quien llama tiene señal ahora mismo y la hora de la
// llamada ES la del suceso.
//
// POR QUÉ SE LEE DE LA CABECERA Y NO DEL CUERPO: el cuerpo es el contrato con la pantalla,
// que no sabe nada de colas ni de reintentos y manda lo mismo tenga o no señal. La hora
// del aparato es cosa del transporte, y ponerla en el cuerpo obligaría a que cada
// pantalla se acordara de rellenarla —y la que se olvidara mentiría sin que nada fallara.
func horaDelSuceso(r *http.Request) time.Time {
	if crudo := strings.TrimSpace(r.Header.Get("X-Hecho-At")); crudo != "" {
		if t, err := time.Parse(time.RFC3339Nano, crudo); err == nil {
			return t.UTC()
		}
		// Una cabecera ilegible NO tumba el aviso y NO se cuela: se cae a la hora de
		// ahora, que es peor dato pero es un dato honesto. Lo que no puede pasar es que
		// un reloj mal escrito ponga en PEDIDO una fecha del año 1970.
		httpx.Registro(r).Warn("X-Hecho-At no se entiende: se usa la hora de ahora", "valor", crudo)
	}
	return time.Now().UTC()
}

// Los cinco estados del contrato. `despachado` al armar, `en_transito` al salir y los
// tres del cierre.
const (
	estadoDespachado = "despachado"
	estadoEnTransito = "en_transito"
)

// EL CANAL YA NO ES UN GANCHO VACÍO: lo monta `NuevoServidor` a partir de la
// configuración y vive en `s.aPedido` (ver `canal_pedido.go`). Sigue siendo un campo y no
// una llamada directa por lo de siempre —la prueba lo sustituye sin levantar nada— pero
// cuando hay `PEDIDO_API_URL` y `SERVICE_API_KEY` sale de verdad a la red.
//
// Si NO las hay, el canal que se monta es el mudo: no llama a nadie, lo dice en el parte y
// lo deja en el registro. Nunca `ok: true` sin haber avisado.

// avisarCambio publica «algo cambió en rutas» para que las pantallas abiertas se enteren.
// Mientras no haya Redis no hace nada, y por eso NO devuelve error: una ruta no se deja de
// crear porque el aviso no salga.
var avisarCambioDeRutas = func(_ context.Context) {}

// ---------------------------------------------------------------------------
// La forma de la respuesta
// ---------------------------------------------------------------------------

// RutaSalida es el contrato con el cliente. No se devuelve la fila de sqlc: la fila cambia
// en cuanto alguien toca una consulta y el cliente deja de encontrar un campo sin que nada
// falle al compilar.
type RutaSalida struct {
	ID            uuid.UUID  `json:"id"`
	Name          *string    `json:"name"`
	RouteCode     *string    `json:"routeCode"`
	Status        string     `json:"status"`
	OriginAddress *string    `json:"originAddress"`
	OriginLat     *float64   `json:"originLat"`
	OriginLng     *float64   `json:"originLng"`
	TotalDistance float64    `json:"totalDistance"`
	TotalWeight   float64    `json:"totalWeight"`
	TotalPrice    float64    `json:"totalPrice"`
	DeliveryDate  *time.Time `json:"deliveryDate"`
	VehicleID     *uuid.UUID `json:"vehicleId"`
	BranchID      *uuid.UUID `json:"branchId"`
	CreadoPor     *string    `json:"creadoPor"`
	StartedAt     *time.Time `json:"startedAt"`
	FinishedAt    *time.Time `json:"finishedAt"`
	Optimized     bool       `json:"optimized"`
	CreatedAt     *time.Time `json:"createdAt"`
	UpdatedAt     *time.Time `json:"updatedAt"`
	// `branch` no venía en delivery y tuvo que añadirse: el Super Admin veía las rutas de
	// las ocho sucursales en una lista sin nada que las distinguiera, y dos rutas del
	// mismo día con el mismo aspecto podían ser de Holguín y de La Habana.
	Branch  *SucursalDeRuta `json:"branch"`
	Vehicle *CamionDeRuta   `json:"vehicle"`
	Orders  []ParadaSalida  `json:"orders"`
}

type SucursalDeRuta struct {
	ID         uuid.UUID `json:"id"`
	Name       *string   `json:"name"`
	ExternalID *string   `json:"externalId"`
}

type CamionDeRuta struct {
	ID       uuid.UUID `json:"id"`
	Name     *string   `json:"name"`
	Type     *string   `json:"type"`
	Plate    *string   `json:"plate"`
	Capacity *float64  `json:"capacity"`
}

// ParadaSalida es un pedido visto como parada del camión.
//
// `segmentKm` ENGAÑA y se conserva el nombre a propósito: NO es el tramo anterior→actual
// sino la distancia RADIAL del almacén a ese cliente, que es la medida con la que se cobra
// un domicilio. Cambiarle el sentido cambiaría el precio de todos los domicilios.
type ParadaSalida struct {
	ID              uuid.UUID         `json:"id"`
	OperationNumber *string           `json:"operationNumber"`
	CustomerName    string            `json:"customerName"`
	CustomerPhone   *string           `json:"customerPhone"`
	Address         string            `json:"address"`
	EndAddress      *string           `json:"endAddress"`
	EndLat          *float64          `json:"endLat"`
	EndLng          *float64          `json:"endLng"`
	Lat             *float64          `json:"lat"`
	Lng             *float64          `json:"lng"`
	Status          string            `json:"status"`
	Weight          float64           `json:"weight"`
	Price           *float64          `json:"price"`
	PedidoCosto     *float64          `json:"pedidoCosto"`
	SegmentKm       *float64          `json:"segmentKm"`
	StopOrder       *int32            `json:"stopOrder"`
	TripLeg         string            `json:"tripLeg"`
	Municipio       *string           `json:"municipio"`
	ExternalID      *string           `json:"externalId"`
	Resultado       *string           `json:"resultado"`
	ResultadoAt     *time.Time        `json:"resultadoAt"`
	ResultadoNota   *string           `json:"resultadoNota"`
	DeliveredAt     *time.Time        `json:"deliveredAt"`
	Items           []RenglonDeParada `json:"items"`
}

// RenglonDeParada es una línea de la hoja de carga. En delivery `items` era una columna
// JSON; aquí son filas de `order_items`, con su número de línea.
type RenglonDeParada struct {
	Linea       int32      `json:"linea"`
	Description string     `json:"description"`
	Quantity    float64    `json:"quantity"`
	Packs       *float64   `json:"packs"`
	ProductID   *uuid.UUID `json:"productId"`
}

// ---------------------------------------------------------------------------
// El montaje
// ---------------------------------------------------------------------------

// rutasDeReparto cuelga las seis rutas del recurso.
//
// TODAS van con sesión y alcance, NINGUNA con `admin`: el contrato dice «Auth: usuario»
// en las seis. Armar y cerrar rutas es el trabajo diario del logístico, no una tarea de
// administración; exigir admin aquí dejaría a la sucursal sin poder despachar. El
// parámetro `admin` se recibe igual para que el montaje se lea idéntico al de los demás
// recursos y para no tener que cambiar la firma el día que alguna lo pida.
func (s *Servidor) rutasDeReparto(rt *httpx.Router, sesion, admin []httpx.Medio) {
	_ = admin

	rt.ManejarFunc(http.MethodGet, "/api/routes", s.listarRutas, sesion...)
	rt.ManejarFunc(http.MethodPost, "/api/routes", s.crearRuta, sesion...)
	rt.ManejarFunc(http.MethodGet, "/api/routes/{id}", s.obtenerRuta, sesion...)
	rt.ManejarFunc(http.MethodPatch, "/api/routes/{id}", s.actualizarRuta, sesion...)
	rt.ManejarFunc(http.MethodDelete, "/api/routes/{id}", s.borrarRuta, sesion...)
	rt.ManejarFunc(http.MethodPost, "/api/routes/{id}/results", s.cerrarRuta, sesion...)
}

// ---------------------------------------------------------------------------
// GET /api/routes
// ---------------------------------------------------------------------------

func (s *Servidor) listarRutas(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	filas, err := a.ListarRutas(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	ids := make([]uuid.UUID, 0, len(filas))
	for _, f := range filas {
		ids = append(ids, f.ID)
	}
	// TRES consultas fijas y no una por ruta: el tablero sale sin filtro de fecha y con
	// un año de trabajo son cientos de rutas.
	porRuta, err := s.paradasPorRuta(r, a, ids)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	salida := make([]RutaSalida, 0, len(filas))
	for _, f := range filas {
		salida = append(salida, deFilaDeLista(f, porRuta[f.ID]))
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// paradasPorRuta trae las paradas de varias rutas con sus renglones, ya agrupadas.
func (s *Servidor) paradasPorRuta(r *http.Request, a *alcance.Acotado, rutas []uuid.UUID) (map[uuid.UUID][]ParadaSalida, error) {
	porRuta := map[uuid.UUID][]ParadaSalida{}
	if len(rutas) == 0 {
		return porRuta, nil
	}
	paradas, err := a.ParadasDeRutas(r.Context(), rutas)
	if err != nil {
		return nil, err
	}
	renglones, err := a.RenglonesDeRutas(r.Context(), rutas)
	if err != nil {
		return nil, err
	}
	porPedido := map[uuid.UUID][]RenglonDeParada{}
	for _, g := range renglones {
		porPedido[g.OrderID] = append(porPedido[g.OrderID], RenglonDeParada{
			Linea: g.Linea, Description: g.Description, Quantity: g.Quantity,
			Packs: g.Packs, ProductID: idOpcional(g.ProductID),
		})
	}
	for _, p := range paradas {
		if !p.RouteID.Valid {
			continue // no puede pasar (el WHERE va por route_id), pero no se supone
		}
		ruta := uuid.UUID(p.RouteID.Bytes)
		porRuta[ruta] = append(porRuta[ruta], ParadaSalida{
			ID: p.ID, OperationNumber: p.OperationNumber, CustomerName: p.CustomerName,
			CustomerPhone: p.CustomerPhone, Address: p.Address, EndAddress: p.EndAddress,
			EndLat: p.EndLat, EndLng: p.EndLng, Lat: p.Lat, Lng: p.Lng,
			Status: string(p.Status), Weight: p.Weight, Price: p.Price,
			PedidoCosto: p.PedidoCosto, SegmentKm: p.SegmentKm, StopOrder: p.StopOrder,
			TripLeg: string(p.TripLeg), Municipio: p.Municipio, ExternalID: p.ExternalID,
			Resultado: textoDeResultado(p.Resultado), ResultadoAt: hora(p.ResultadoAt),
			ResultadoNota: p.ResultadoNota, DeliveredAt: hora(p.DeliveredAt),
			// Siempre una lista, nunca null: un `orders[].items` que a veces es null
			// obliga a comprobarlo en cada pantalla, y donde se olvide revienta.
			Items: append([]RenglonDeParada{}, porPedido[p.ID]...),
		})
	}
	return porRuta, nil
}

// ---------------------------------------------------------------------------
// POST /api/routes — EL ARMADO
// ---------------------------------------------------------------------------

type cuerpoRuta struct {
	Name          httpx.Opcional[string]  `json:"name"`
	VehicleID     httpx.Opcional[string]  `json:"vehicleId"`
	OriginAddress httpx.Opcional[string]  `json:"originAddress"`
	OriginLat     httpx.Opcional[float64] `json:"originLat"`
	OriginLng     httpx.Opcional[float64] `json:"originLng"`
	DeliveryDate  httpx.Opcional[string]  `json:"deliveryDate"`
	BranchID      httpx.Opcional[string]  `json:"branchId"`
	// Crudo a propósito: el contrato dice que lo que NO sea un array de ids se trata
	// como «no vinieron pedidos» y sale por su mensaje, no por «cuerpo no válido».
	OrderIds json.RawMessage `json:"orderIds"`
}

// errPedidosEscapados corta la transacción del armado cuando un pedido dejó de estar libre
// ENTRE el SELECT que lo dio por bueno y el UPDATE que lo engancha. Va como error —y no
// como una cuenta que se ignora— porque la ruta tiene que salir entera o no salir: media
// ruta creada es un camión cargado con la mitad de lo que dice la hoja.
var errPedidosEscapados = errors.New("un pedido se enganchó a otra ruta mientras se armaba ésta")

func (s *Servidor) crearRuta(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	var c cuerpoRuta
	if !httpx.LeerJSON(w, r, &c) {
		return
	}

	// --- Validaciones, EN ESTE ORDEN (contrato §15.1) -----------------------
	//
	// El orden importa: quien manda un cuerpo vacío tiene que enterarse primero de que le
	// faltan las coordenadas, que es el primer campo del asistente.

	// `== null` del contrato: el cero es una coordenada válida (Golfo de Guinea, sí, pero
	// también es lo que llega cuando el mapa no ha terminado de cargar). Lo que se
	// rechaza es la ausencia, no el valor.
	if c.OriginLat.Valor == nil || c.OriginLng.Valor == nil {
		httpx.Error(w, r, http.StatusBadRequest, msgFaltanCoordenadas)
		return
	}
	origenLat, origenLng := *c.OriginLat.Valor, *c.OriginLng.Valor

	vehiculoPedido := strings.TrimSpace(c.VehicleID.Con(""))
	if vehiculoPedido == "" {
		httpx.Error(w, r, http.StatusBadRequest, msgFaltaVehiculo)
		return
	}

	idsPedidos := leerIdsDePedidos(c.OrderIds)
	if len(idsPedidos) == 0 {
		httpx.Error(w, r, http.StatusBadRequest, msgSinPedidos)
		return
	}

	entrega, ok := fechaDeEntrega(w, r, c.DeliveryDate.Con(""))
	if !ok {
		return
	}

	// --- La sucursal de la ruta --------------------------------------------
	//
	// El alcance MANDA: quien pertenece a una sucursal no puede pasar otra por el cuerpo.
	// Quien no tiene alcance (Super Admin) la dice en el primer paso del asistente; sin
	// eso, su ruta nacía sin sucursal o con la del primer pedido, por casualidad.
	ar := a.EnSucursal(sucursalDelCuerpo(r, c.BranchID.Con("")))

	// --- Los pedidos que TODAVÍA se pueden meter ---------------------------
	//
	// Esta consulta ES la validación, no una lectura previa a ella: pide por ids y
	// devuelve sólo los que siguen libres, facturados en el espejo y con coordenadas.
	pedidos, err := ar.PedidosParaArmarRuta(r.Context(), soloUuids(idsPedidos))
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if len(pedidos) == 0 {
		httpx.Error(w, r, http.StatusBadRequest, msgPedidosNoDisponibles)
		return
	}
	if len(pedidos) < len(idsPedidos) {
		// Se dice CUÁNTOS faltan y no un «no se pudo»: con el mensaje genérico alguien
		// crea la ruta creyendo que lleva diez paradas y lleva nueve.
		httpx.Error(w, r, http.StatusConflict, mensajeYaEnOtraRuta(len(idsPedidos)-len(pedidos), len(idsPedidos)))
		return
	}

	// --- Sólo entra lo facturado y que cuadre ------------------------------
	//
	// Se comprueba aquí aunque la pantalla ya filtre: basta con que alguien mande los ids
	// a mano, o con que un pedido se coteje otra vez entre que se eligió y se armó la
	// ruta. Lo que se carga tiene que ser lo que se cobró.
	if mensaje := mensajeNoFacturados(pedidos); mensaje != "" {
		httpx.Error(w, r, http.StatusConflict, mensaje)
		return
	}

	// --- El domicilio sin calcular: AVISO, no portazo ----------------------
	//
	// Decisión de Jose el 14/09/2026, tomada con los datos reales delante: de los 686
	// pedidos repartibles que llevan domicilio, 657 no tienen el costo puesto. El 96%. Con
	// un portazo aquí no se podría armar NI UNA ruta con domicilio.
	//
	// Y no es un fallo de los datos: ese costo lo pone la APK de Entrega, que todavía no
	// está encendida. El día que lo esté, estos avisos se apagan solos.
	//
	// Así que la ruta se arma y el aviso viaja en la respuesta. Lo que NO se hace es
	// callarlo, que era el problema original: el armador suma `pedido_costo || 0`, o sea
	// que un pedido sin costo entra valiendo cero y el total de la ruta sale más bajo sin
	// que nadie lo note hasta cuadrar la caja.
	avisoSinCosto := mensajeSinCalcular(pedidos)
	sinCosto := cuantosSinCosto(pedidos)

	// --- Capacidad por peso ------------------------------------------------
	var pesoTotal, precioTotal float64
	for _, p := range pedidos {
		pesoTotal += p.Weight // un peso sin resolver cuenta 0 kg, como en delivery
		if p.PedidoCosto != nil {
			precioTotal += *p.PedidoCosto
		}
		// El que no tiene costo NO suma. Ver `sinCosto` arriba: el total que sale de aquí
		// es el de lo que sí está costeado, y la respuesta dice cuántos faltan. Un total
		// a secas, sin ese número al lado, es un número que parece completo y no lo es.
	}
	// Si el id del camión no es un uuid o no existe, NO se valida capacidad y la ruta se
	// crea igual —así lo dice el contrato— pero se crea SIN camión: guardar un id que no
	// está en `vehicles` reventaría contra la clave ajena con un 500 sin explicación.
	var vehiculo *sqlc.ObtenerVehiculoParaCapacidadRow
	if id, err := uuid.Parse(vehiculoPedido); err == nil {
		v, err := ar.ObtenerVehiculoParaCapacidad(r.Context(), id)
		switch {
		case err == nil:
			vehiculo = &v
		case errors.Is(err, pgx.ErrNoRows):
			httpx.Registro(r).Warn("la ruta se arma sin camión: el vehículo pedido no existe",
				"vehiculo", vehiculoPedido)
		default:
			httpx.ErrorInterno(w, r, err)
			return
		}
	} else {
		httpx.Registro(r).Warn("la ruta se arma sin camión: el vehículo pedido no es un id",
			"vehiculo", vehiculoPedido)
	}
	// Estrictamente mayor: igualar la capacidad exacta SÍ pasa. El peso se enseña con un
	// decimal y la capacidad tal cual está guardada, como en delivery.
	if vehiculo != nil && pesoTotal > vehiculo.Capacity {
		httpx.Error(w, r, http.StatusBadRequest, fmt.Sprintf(
			"Peso total (%.1f kg) supera la capacidad del vehículo (%s kg)",
			pesoTotal, strconv.FormatFloat(vehiculo.Capacity, 'f', -1, 64)))
		return
	}

	// --- El recorrido -------------------------------------------------------
	//
	// Se ordena por el DESTINO (`end_lat`/`end_lng`), no por `lat`/`lng`: el camión va a
	// donde se entrega, no a donde se facturó.
	geo := make([]paradaGeo, 0, len(pedidos))
	for _, p := range pedidos {
		if p.EndLat == nil || p.EndLng == nil {
			continue // el SQL ya los excluye; aquí es sólo por no desreferenciar
		}
		geo = append(geo, paradaGeo{id: p.ID, lat: *p.EndLat, lng: *p.EndLng})
	}
	orden := ordenVecinoMasProximo(origenLat, origenLng, geo)
	porID := map[uuid.UUID]paradaGeo{}
	for _, g := range geo {
		porID[g.id] = g
	}

	// DOS MEDIDAS DISTINTAS Y NO SE PUEDEN CONFUNDIR:
	//  - `totalDistance` son los km REALES del camión: origen→p1→…→pn→origen, con la
	//    vuelta incluida. Sin la vuelta, las rutas largas salen a la mitad de lo que son.
	//  - `segmentKm` de cada pedido es la distancia RADIAL del origen a ese cliente, que
	//    es con lo que se cobra el domicilio. No es el tramo del recorrido.
	var distanciaTotal float64
	segmentos := map[uuid.UUID]float64{}
	anteriorLat, anteriorLng := origenLat, origenLng
	for _, id := range orden {
		p := porID[id]
		distanciaTotal += kmHaversine(anteriorLat, anteriorLng, p.lat, p.lng)
		segmentos[id] = kmHaversine(origenLat, origenLng, p.lat, p.lng)
		anteriorLat, anteriorLng = p.lat, p.lng
	}
	if len(orden) > 0 {
		distanciaTotal += kmHaversine(anteriorLat, anteriorLng, origenLat, origenLng)
	}

	// --- El código de ruta --------------------------------------------------
	//
	// `RT-YYYYMMDD-NNN` con la fecha de HOY EN UTC, y el NNN de contar las del día. Se
	// cuenta, no se lee el máximo: si se borra una ruta del día el siguiente código se
	// repite, y dos armados a la vez pueden chocar. Se hereda tal cual porque ese código
	// es lo que la gente se dice por teléfono; si empieza a chocar, la salida es una
	// secuencia por día, no un reintento.
	prefijo := "RT-" + time.Now().UTC().Format("20060102") + "-"
	delDia, err := ar.ContarRutasDelDia(r.Context(), prefijo)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	codigo := fmt.Sprintf("%s%03d", prefijo, delDia+1)

	// La ruta pertenece a la sucursal elegida o, si no hay ninguna, a la de sus pedidos.
	sucursalRuta := pedidos[0].BranchID
	if propia := ar.Sucursal(); propia != nil {
		sucursalRuta = pgDe(*propia)
	}

	// --- La escritura, ENTERA O NADA ---------------------------------------
	//
	// Delivery actualizaba los pedidos «una a una y sin transacción». Aquí va en una: si
	// falla a mitad, lo que queda es una ruta con la mitad de las paradas y la otra mitad
	// de los pedidos enganchados a una ruta que nadie va a mirar. La regla de la casa es
	// que a medias no vale.
	var creada sqlc.CrearRutaRow
	var escapados int
	err = ar.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		var err error
		creada, err = tx.CrearRuta(r.Context(), sqlc.CrearRutaParams{
			Name:          aTexto(strings.TrimSpace(c.Name.Con(""))),
			RouteCode:     &codigo,
			OriginAddress: aTexto(strings.TrimSpace(c.OriginAddress.Con(""))),
			OriginLat:     &origenLat,
			OriginLng:     &origenLng,
			DeliveryDate:  entrega,
			VehicleID:     idDelVehiculo(vehiculo),
			BranchID:      sucursalRuta,
			// `creado_por` lo pone el alcance: es constancia de quién armó la ruta y NO
			// filtra nada. Filtrar por el creador es lo que escondió los pedidos de
			// Holguín a los propios compañeros de Holguín.
		})
		if err != nil {
			return err
		}
		for i, id := range orden {
			parada := int32(i + 1) // el orden de visita empieza en 1, no en 0
			km := segmentos[id]
			filas, err := tx.EngancharPedidoARuta(r.Context(), sqlc.EngancharPedidoARutaParams{
				PedidoID:  id,
				RutaID:    pgDe(creada.ID),
				StopOrder: &parada,
				SegmentKm: &km,
				// `price` se COPIA de `pedidoCosto`, que es lo que puso el repartidor en
				// PEDIDO; un `null` se guarda como 0. Aquí no se calcula ningún precio:
				// eso lo hace la APK de Entrega y nadie más.
				Price: costoDelPedido(pedidos, id),
			})
			if err != nil {
				return err
			}
			if filas == 0 {
				escapados++
			}
		}
		if escapados > 0 {
			return errPedidosEscapados
		}
		_, err = tx.FijarTotalesDeRuta(r.Context(), sqlc.FijarTotalesDeRutaParams{
			TotalDistance: distanciaTotal,
			TotalWeight:   pesoTotal,
			TotalPrice:    precioTotal,
			ID:            creada.ID,
		})
		return err
	})
	if errors.Is(err, errPedidosEscapados) {
		httpx.Error(w, r, http.StatusConflict, mensajeYaEnOtraRuta(escapados, len(idsPedidos)))
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	// El vendedor se entera AQUÍ de que su pedido se movió. Va de fondo: si PEDIDO no
	// contesta la ruta se crea igual — lo que no puede pasar es no poder armar una ruta
	// porque otra aplicación esté caída.
	// La hora se lee UNA vez y se reparte: todos estos pedidos se cargaron en el mismo
	// acto —armar la ruta— y tienen que constar con la misma hora, no con la de cada
	// vuelta del bucle.
	cuando := horaDelSuceso(r)
	var avisos []AvisoDeParada
	for _, p := range pedidos {
		if p.Source != nil && *p.Source == sqlc.ProcedenciaPedido && p.ExternalID != nil {
			avisos = append(avisos, AvisoDeParada{
				PedidoID: *p.ExternalID, Estado: estadoDespachado, At: cuando,
			})
		}
	}
	s.avisarDeFondo(r, avisos)
	avisarCambioDeRutas(r.Context())

	// El aviso viaja CON la ruta creada, no en su lugar.
	//
	// Si hay pedidos con domicilio sin costear, la pantalla tiene que poder decirlo encima
	// del total: «no incluye N pedidos». Un total a secas parece completo y no lo es.
	if sinCosto > 0 {
		s.reg.WarnContext(r.Context(), "ruta armada con domicilios sin costear",
			"ruta", creada.ID, "sin_costo", sinCosto, "de", len(pedidos))
	}
	s.responderConLaRutaYAvisos(w, r, ar, creada.ID, http.StatusCreated, avisoSinCosto, sinCosto)
}

// ---------------------------------------------------------------------------
// GET /api/routes/{id}
// ---------------------------------------------------------------------------

func (s *Servidor) obtenerRuta(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	s.responderConLaRuta(w, r, a, id, http.StatusOK)
}

// responderConLaRuta relee la ruta entera —cabecera, sucursal, camión y paradas— y la
// escribe. Se relee después de escribir a propósito: así el cliente ve lo que quedó
// guardado y no lo que creíamos haber guardado.
// responderConLaRutaYAvisos es responderConLaRuta más lo que hay que decir de ella.
//
// Se separa en vez de meterle dos parámetros a la de siempre porque la mayoría de las
// respuestas no tienen nada que avisar, y un `"", 0` repetido por todo el fichero se acaba
// copiando mal.
func (s *Servidor) responderConLaRutaYAvisos(w http.ResponseWriter, r *http.Request, ar *alcance.Acotado, id uuid.UUID, codigo int, aviso string, sinCosto int) {
	if aviso == "" {
		s.responderConLaRuta(w, r, ar, id, codigo)
		return
	}
	fila, err := ar.ObtenerRuta(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	porRuta, err := s.paradasPorRuta(r, ar, []uuid.UUID{id})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	cuerpo := map[string]any{
		"ruta": deFilaDeDetalle(fila, porRuta[id]),
		"avisos": map[string]any{
			"sinCosto":  sinCosto,
			"detalle":   aviso,
			"elTotalNo": "incluye los pedidos sin costo de domicilio",
		},
	}
	httpx.JSON(w, r, codigo, cuerpo)
}

func (s *Servidor) responderConLaRuta(w http.ResponseWriter, r *http.Request, a *alcance.Acotado, id uuid.UUID, codigo int) {
	fila, err := a.ObtenerRuta(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	porRuta, err := s.paradasPorRuta(r, a, []uuid.UUID{id})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, codigo, deFilaDeDetalle(fila, porRuta[id]))
}

// ---------------------------------------------------------------------------
// PATCH /api/routes/{id}
// ---------------------------------------------------------------------------

type cuerpoActualizarRuta struct {
	VehicleID httpx.Opcional[string] `json:"vehicleId"`
	Name      httpx.Opcional[string] `json:"name"`
	Status    httpx.Opcional[string] `json:"status"`
}

func (s *Servidor) actualizarRuta(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	var c cuerpoActualizarRuta
	if !httpx.LeerJSON(w, r, &c) {
		return
	}

	// Se lee ANTES por dos cosas: el 404 con el alcance puesto y el camión ANTERIOR, que
	// hay que liberar si la ruta cambia de vehículo o se cierra.
	antes, err := a.ObtenerRuta(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	nombre := c.Name.Puntero()
	var estado *sqlc.RouteStatus
	if c.Status.Presente && c.Status.Valor != nil {
		e, ok := estadoDeRutaValido(w, r, *c.Status.Valor)
		if !ok {
			return
		}
		estado = &e
	}

	// CAMINO A: cambiar el camión. Tiene prioridad y retorna antes, tal como el contrato;
	// aquí no se tocan `startedAt`/`finishedAt` ni se avisa a PEDIDO.
	if c.VehicleID.Presente {
		s.cambiarCamionDeRuta(w, r, a, antes, c, nombre, estado)
		return
	}

	// CAMINO B: el estado. Las horas de salida y regreso las pone el SQL —`started_at`
	// sólo la primera vez— para que dos peticiones simultáneas no se pisen la hora.
	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		if _, err := tx.ActualizarEstadoDeRuta(r.Context(), sqlc.ActualizarEstadoDeRutaParams{
			ID: id, Name: nombre, Status: estado,
		}); err != nil {
			return err
		}
		if estado == nil || !antes.VehicleID.Valid {
			return nil
		}
		vehiculo := uuid.UUID(antes.VehicleID.Bytes)
		switch {
		// Despachar OCUPA el camión: es ahora cuando sale, no cuando se armó la ruta.
		case *estado == sqlc.RouteStatusInProgress:
			_, err := tx.CambiarEstadoDeVehiculo(r.Context(), vehiculo, sqlc.VehicleStatusInUse)
			return err
		// Completar lo LIBERA. Si ya estaba disponible no se toca: alguien pudo haberlo
		// liberado a mano y volver a escribirlo sólo mueve `updated_at`.
		case *estado == sqlc.RouteStatusCompleted &&
			antes.VehiculoEstado != nil && *antes.VehiculoEstado == sqlc.VehicleStatusInUse:
			_, err := tx.CambiarEstadoDeVehiculo(r.Context(), vehiculo, sqlc.VehicleStatusAvailable)
			return err
		}
		return nil
	})
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	// Al SALIR se avisa a PEDIDO; al completar NO, porque cada pedido ya tiene su propio
	// resultado y un «entregado» genérico pisaría a los devueltos.
	if estado != nil && *estado == sqlc.RouteStatusInProgress {
		s.avisarDeFondo(r, s.avisosDeLasParadas(r, a, id, estadoEnTransito))
	}
	avisarCambioDeRutas(r.Context())
	s.responderConLaRuta(w, r, a, id, http.StatusOK)
}

// cambiarCamionDeRuta es el camino A del PATCH: soltar el camión viejo y ocupar el nuevo.
func (s *Servidor) cambiarCamionDeRuta(w http.ResponseWriter, r *http.Request, a *alcance.Acotado,
	antes sqlc.ObtenerRutaRow, c cuerpoActualizarRuta, nombre *string, estado *sqlc.RouteStatus) {

	// Un `vehicleId` vacío o null desengancha el camión. Uno con valor tiene que EXISTIR y
	// ser alcanzable: si no, la clave ajena daría un 500 con la jerga de Postgres dentro.
	var nuevo *uuid.UUID
	if pedido := strings.TrimSpace(c.VehicleID.Con("")); pedido != "" {
		id, err := uuid.Parse(pedido)
		if err != nil {
			// Un id mal escrito es lo mismo que uno que no está: 400 con un mensaje que
			// se entiende, y no el 500 de la clave ajena con la jerga de Postgres dentro.
			httpx.Error(w, r, http.StatusBadRequest, fmt.Sprintf("No existe el vehículo '%s'", pedido))
			return
		}
		// Se comprueba CON ALCANCE: el camión de Holguín no se engancha a una ruta de
		// Santiago ni sabiendo su id. Los compartidos (`branch_id` NULL) sí pasan, que
		// para eso están.
		_, err = a.ObtenerVehiculo(r.Context(), id)
		if errors.Is(err, pgx.ErrNoRows) {
			httpx.Error(w, r, http.StatusBadRequest, fmt.Sprintf("No existe el vehículo '%s'", pedido))
			return
		}
		if err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
		nuevo = &id
	}

	err := a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		// El camión viejo se libera SÓLO si estaba ocupado y de verdad cambia: una ruta
		// que se reasigna al mismo camión no tiene por qué dejarlo libre.
		if antes.VehicleID.Valid {
			viejo := uuid.UUID(antes.VehicleID.Bytes)
			cambia := nuevo == nil || *nuevo != viejo
			ocupado := antes.VehiculoEstado != nil && *antes.VehiculoEstado == sqlc.VehicleStatusInUse
			if cambia && ocupado {
				if _, err := tx.CambiarEstadoDeVehiculo(r.Context(), viejo, sqlc.VehicleStatusAvailable); err != nil {
					return err
				}
			}
		}
		if nuevo != nil {
			if _, err := tx.CambiarEstadoDeVehiculo(r.Context(), *nuevo, sqlc.VehicleStatusInUse); err != nil {
				return err
			}
		}
		_, err := tx.CambiarVehiculoDeRuta(r.Context(), sqlc.CambiarVehiculoDeRutaParams{
			ID: antes.ID, VehicleID: aPgOpcional(nuevo), Name: nombre, Status: estado,
		})
		return err
	})
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisarCambioDeRutas(r.Context())
	s.responderConLaRuta(w, r, a, antes.ID, http.StatusOK)
}

// ---------------------------------------------------------------------------
// DELETE /api/routes/{id}
// ---------------------------------------------------------------------------

// errRutaNoEstaba corta la transacción del borrado cuando la ruta no es de esta sucursal o
// ya no existe. Va como error para DESHACER lo ya soltado: si no, un intento contra un id
// ajeno dejaría los pedidos de otra sucursal sin ruta.
var errRutaNoEstaba = errors.New("ruta no encontrada en el alcance")

func (s *Servidor) borrarRuta(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	antes, err := a.ObtenerRuta(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		// Borrar la ruta LIBERA el camión: si no, queda ocupado por una ruta que ya no
		// existe y no hay pantalla donde soltarlo.
		if antes.VehicleID.Valid && antes.VehiculoEstado != nil && *antes.VehiculoEstado == sqlc.VehicleStatusInUse {
			if _, err := tx.CambiarEstadoDeVehiculo(r.Context(), uuid.UUID(antes.VehicleID.Bytes), sqlc.VehicleStatusAvailable); err != nil {
				return err
			}
		}
		// Los pedidos NO se borran: se sueltan y vuelven a la lista de disponibles.
		// `ultima_ruta_id` se conserva — el pasado de un pedido no se reescribe porque
		// alguien deshaga la ruta de hoy.
		if _, err := tx.SoltarPedidosDeRuta(r.Context(), id); err != nil {
			return err
		}
		filas, err := tx.BorrarRuta(r.Context(), id)
		if err != nil {
			return err
		}
		if filas == 0 {
			return errRutaNoEstaba
		}
		return nil
	})
	if errors.Is(err, errRutaNoEstaba) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisarCambioDeRutas(r.Context())
	httpx.JSON(w, r, http.StatusOK, map[string]bool{"success": true})
}

// ---------------------------------------------------------------------------
// POST /api/routes/{id}/results — EL CIERRE
// ---------------------------------------------------------------------------

type cuerpoCierre struct {
	Resultados []entradaDeCierre `json:"resultados"`
}

type entradaDeCierre struct {
	OrderID string `json:"orderId"`
	// Punteros para poder distinguir «no vino» de «vino vacío»: el mensaje de rechazo
	// interpola el valor tal cual, y un resultado ausente sale como `undefined`.
	Resultado *string `json:"resultado"`
	Nota      *string `json:"nota"`
}

type aplicadoDeCierre struct {
	OrderID   string `json:"orderId"`
	Resultado string `json:"resultado"`
}

type rechazadoDeCierre struct {
	OrderID string `json:"orderId"`
	Motivo  string `json:"motivo"`
}

type salidaDeCierre struct {
	Aplicados  []aplicadoDeCierre  `json:"aplicados"`
	Rechazados []rechazadoDeCierre `json:"rechazados"`
	APedido    ParteAPedido        `json:"aPedido"`
}

func (s *Servidor) cerrarRuta(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	// Femenino: «No encontrada». Distinto del de `/api/routes/[id]` y así está
	// inventariado; hay clientes que comparan el texto.
	id, ok := idDeRuta(w, r, msgRutaNoEncontrada)
	if !ok {
		return
	}
	ruta, err := a.ObtenerRuta(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, msgRutaNoEncontrada)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	// Un cuerpo ilegible se trata como `{}` y sale por «No vino ningún resultado», no por
	// «Cuerpo de la petición no válido»: lo dice el contrato y además es lo útil — quien
	// cierra una ruta desde el móvil con mala cobertura ve el mismo mensaje que si no
	// hubiera marcado nada, que es lo que le pasó.
	var c cuerpoCierre
	_ = json.NewDecoder(http.MaxBytesReader(w, r.Body, topeCuerpoCierre)).Decode(&c)
	defer r.Body.Close()
	if len(c.Resultados) == 0 {
		httpx.Error(w, r, http.StatusBadRequest, msgSinResultados)
		return
	}

	// EL UNIVERSO SON LOS QUE VIAJARON EN ESTA RUTA, por `ultima_ruta_id` y no por
	// `route_id`: así se puede corregir el resultado de un devuelto, que ya soltó su
	// `route_id` al cerrarse. Con `route_id` media hoja de cierre sería incorregible.
	viajaron, err := a.ParadasQueViajaronEnRuta(r.Context(), ruta.ID)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	universo := map[uuid.UUID]sqlc.ListarParadasQueViajaronEnRutaRow{}
	for _, p := range viajaron {
		universo[p.ID] = p
	}

	salida := salidaDeCierre{Aplicados: []aplicadoDeCierre{}, Rechazados: []rechazadoDeCierre{}}
	var avisos []AvisoDeParada

	// LA HORA DEL CIERRE, que es el caso por el que existe todo esto. Una hoja de cierre
	// se marca en el patio, sin señal, y sube cuando la hay: el apunte llega con
	// `X-Hecho-At` puesto por el sincronizador y ésa es la hora que va a PEDIDO. Toda la
	// hoja comparte una sola hora porque un apunte es un acto: si algún día hiciera falta
	// la hora parada por parada, tendría que venir en el cuerpo y eso es cambiar el
	// contrato con la pantalla.
	cuando := horaDelSuceso(r)

	// NO ABORTA: acumula. Cada parada es un hecho independiente —el camión volvió y ese
	// pedido se entregó—, así que tumbar las nueve buenas porque la décima venga mal
	// borraría información real que ya nadie va a volver a teclear. Por lo mismo esto no
	// va en una transacción.
	for _, e := range c.Resultados {
		pedidoID, err := uuid.Parse(strings.TrimSpace(e.OrderID))
		if err != nil {
			salida.Rechazados = append(salida.Rechazados, rechazadoDeCierre{OrderID: e.OrderID, Motivo: msgParadaAjena})
			continue
		}
		parada, iba := universo[pedidoID]
		if !iba {
			salida.Rechazados = append(salida.Rechazados, rechazadoDeCierre{OrderID: e.OrderID, Motivo: msgParadaAjena})
			continue
		}
		resultado, ok := resultadoValido(e.Resultado)
		if !ok {
			salida.Rechazados = append(salida.Rechazados, rechazadoDeCierre{
				OrderID: e.OrderID,
				Motivo:  fmt.Sprintf("resultado '%s' desconocido", valorTalCual(e.Resultado)),
			})
			continue
		}

		nota := notaDeCierre(e.Nota)
		// Aquí está TODO lo delicado del cierre, y va en una sola sentencia SQL:
		//   - un entregado fija `delivered_at` y conserva su `route_id`;
		//   - un devuelto o un cancelado SUELTAN `route_id` —vuelven a la lista de
		//     disponibles para mañana— pero NO `ultima_ruta_id` ni `stop_order`, que son
		//     la hoja de lo que bajó del camión;
		//   - `delivered_at` se limpia cuando no se entregó, o un devuelto con la hora de
		//     un intento anterior se pinta «entregado» en la lista;
		//   - ni devuelto ni cancelado tocan INVENTARIO: el reintegro lo hace Ventra.
		filas, err := a.MarcarResultadoDeParada(r.Context(), ruta.ID, pedidoID, resultado, nota)
		if err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
		if filas == 0 {
			// El WHERE lleva `ultima_ruta_id` y el alcance: cero filas es el mismo
			// rechazo, comprobado contra la base y no contra una lectura ya vieja.
			salida.Rechazados = append(salida.Rechazados, rechazadoDeCierre{OrderID: e.OrderID, Motivo: msgParadaAjena})
			continue
		}
		salida.Aplicados = append(salida.Aplicados, aplicadoDeCierre{OrderID: pedidoID.String(), Resultado: string(resultado)})
		if parada.Source != nil && *parada.Source == sqlc.ProcedenciaPedido && parada.ExternalID != nil {
			aviso := AvisoDeParada{PedidoID: *parada.ExternalID, Estado: string(resultado), At: cuando}
			if nota != nil {
				aviso.Nota = *nota
			}
			avisos = append(avisos, aviso)
		}
	}

	// El aviso del CIERRE se espera (síncrono): el vendedor tiene que poder ver en PEDIDO
	// lo que pasó con su pedido, y aquí ya no hay prisa por contestar.
	salida.APedido = s.aPedido(r.Context(), avisos)
	if !salida.APedido.Ok && len(avisos) > 0 {
		httpx.Registro(r).Error("el cierre se guardó pero PEDIDO no se enteró",
			"ruta", ruta.ID, "avisos", len(avisos), "err", salida.APedido.Error)
	}
	avisarCambioDeRutas(r.Context())
	httpx.JSON(w, r, http.StatusOK, salida)
}

// topeCuerpoCierre: una hoja de cierre son decenas de paradas con su nota; 1 MiB sobra. Lo
// que no cabe es el intento de tumbar el proceso a base de memoria.
const topeCuerpoCierre = 1 << 20

// ---------------------------------------------------------------------------
// Piezas sueltas
// ---------------------------------------------------------------------------

// leerIdsDePedidos saca los ids TAL Y COMO VINIERON, sin quitar repetidos ni los que no
// son uuid. Se cuentan todos porque el mensaje del 409 dice «N de los M», y esa M es lo
// que la persona eligió en la pantalla.
func leerIdsDePedidos(crudo json.RawMessage) []string {
	if len(crudo) == 0 {
		return nil
	}
	var ids []string
	if err := json.Unmarshal(crudo, &ids); err != nil {
		// Lo que no sea un array de textos es «no vinieron pedidos», que es el caso del
		// contrato. No es un cuerpo inválido: es un armado sin elegir nada.
		return nil
	}
	limpios := make([]string, 0, len(ids))
	for _, id := range ids {
		if id = strings.TrimSpace(id); id != "" {
			limpios = append(limpios, id)
		}
	}
	return limpios
}

// soloUuids es lo que se le pasa a la consulta. Un id que no es uuid no puede estar en la
// base, así que no se busca; sigue contando para la M del mensaje.
func soloUuids(ids []string) []uuid.UUID {
	salida := make([]uuid.UUID, 0, len(ids))
	for _, texto := range ids {
		if id, err := uuid.Parse(texto); err == nil {
			salida = append(salida, id)
		}
	}
	return salida
}

// mensajeYaEnOtraRuta es EL literal del contrato, con sus dos números.
func mensajeYaEnOtraRuta(faltan, pedidos int) string {
	return fmt.Sprintf("%d de los %d pedidos ya están en otra ruta. Vuelve a elegirlos.", faltan, pedidos)
}

// mensajeNoFacturados arma el 409 de facturación, o "" si todos cuadran.
//
// Se dice CUÁLES y por qué: un «no se pudo» a secas obliga a adivinar cuál de los quince
// pedidos es el que sobra. Se nombran los cinco primeros y se cuenta el resto.
func mensajeNoFacturados(pedidos []sqlc.PedidosParaArmarRutaRow) string {
	var malos []sqlc.PedidosParaArmarRutaRow
	for _, p := range pedidos {
		// ESTRICTAMENTE `igual`: más duro que el filtro `con_factura` de la lista de
		// disponibles, que admite también `cambiado`. En el camión sólo sube lo que
		// cuadra con la factura.
		if p.FacturaEstado == nil || *p.FacturaEstado != sqlc.FacturaEstadoIgual {
			malos = append(malos, p)
		}
	}
	if len(malos) == 0 {
		return ""
	}
	detalle := make([]string, 0, 5)
	for _, p := range malos {
		if len(detalle) == 5 {
			break
		}
		quien := p.CustomerName
		if p.OperationNumber != nil && *p.OperationNumber != "" {
			quien = *p.OperationNumber
		}
		detalle = append(detalle, fmt.Sprintf("%s (%s)", quien, motivoDeFactura(p.FacturaEstado)))
	}
	mensaje := fmt.Sprintf("En una ruta sólo entra lo facturado y que cuadre. %d no cumplen: %s",
		len(malos), strings.Join(detalle, ", "))
	if len(malos) > 5 {
		return mensaje + fmt.Sprintf(" y %d más.", len(malos)-5)
	}
	return mensaje + "."
}

// llevaDomicilio dice si este pedido va a casa del cliente.
//
// Se miran las DOS señales. `requiere_domicilio` es la casilla que alguien marcó al tomar
// el pedido; `factura_domicilio` es lo que se cobró en el mostrador, que es más fiable
// porque ya pasó por caja. Con una sola se escapan casos por los dos lados.
func llevaDomicilio(p sqlc.PedidosParaArmarRutaRow) bool {
	if p.FacturaDomicilio != nil {
		return true
	}
	return p.RequiereDomicilio != nil && *p.RequiereDomicilio
}

// cuantosSinCosto cuenta los que llevan domicilio y no traen su costo.
//
// Va aparte del mensaje porque el número viaja en la respuesta y el texto es para leerlo:
// la pantalla necesita poder decir «el total no incluye 12 pedidos» sin tener que parsear
// una frase.
func cuantosSinCosto(pedidos []sqlc.PedidosParaArmarRutaRow) int {
	n := 0
	for _, p := range pedidos {
		if llevaDomicilio(p) && p.PedidoCosto == nil {
			n++
		}
	}
	return n
}

// mensajeSinCalcular arma el AVISO de «este pedido no tiene su domicilio calculado», o "".
//
// # Por qué es un aviso y no un portazo
//
// Lo fue durante unas horas. Con los datos reales delante se vio que habría bloqueado el
// 96% de los pedidos con domicilio, porque el costo lo pone la APK de Entrega y todavía no
// está encendida. Un sistema que no deja armar ninguna ruta no sirve, por muy correcta que
// sea la regla.
//
// # Pero callarlo tampoco vale
//
// Delivery NO CALCULA NADA. Sólo pone en ruta pedidos que ya vienen con su domicilio
// puesto por la APK de Entrega, que es quien lo cobra. El armador se limita a sumar:
//
//	price: pedido_costo || 0
//
// Y ahí está el problema de ese `|| 0`. Un pedido con domicilio y sin calcular no revienta
// nada: entra en la ruta valiendo CERO, el total de la ruta sale más bajo de lo que es, y
// nadie se entera hasta que no cuadra la caja. Es de la misma familia que todo lo que ya
// ha costado semanas: no da error, da un número distinto.
//
// En la lista de disponibles «cotizado» es un filtro que el logístico marca si quiere.
// Aquí no puede serlo: si tiene domicilio y no tiene costo, no sube al camión.
//
// El que NO lleva domicilio se deja pasar sin costo, que es lo correcto: se recoge en el
// almacén y no se le cobra reparto.
func mensajeSinCalcular(pedidos []sqlc.PedidosParaArmarRutaRow) string {
	var malos []sqlc.PedidosParaArmarRutaRow
	for _, p := range pedidos {
		if llevaDomicilio(p) && p.PedidoCosto == nil {
			malos = append(malos, p)
		}
	}
	if len(malos) == 0 {
		return ""
	}
	detalle := make([]string, 0, 5)
	for _, p := range malos {
		if len(detalle) == 5 {
			break
		}
		quien := p.CustomerName
		if p.OperationNumber != nil && *p.OperationNumber != "" {
			quien = *p.OperationNumber
		}
		detalle = append(detalle, quien)
	}
	mensaje := fmt.Sprintf("%d pedidos llevan domicilio y todavía no tienen el costo puesto en Entrega: %s",
		len(malos), strings.Join(detalle, ", "))
	if len(malos) > 5 {
		return mensaje + fmt.Sprintf(" y %d más.", len(malos)-5)
	}
	return mensaje + "."
}

// motivoDeFactura traduce el estado a lo que se lee en la pantalla. Un estado NULL es
// «sin cotejar», igual que cualquier otro valor inesperado: lo que no se comprobó no se
// carga, y decir «sin factura» cuando en realidad nadie la ha mirado sería mentir.
func motivoDeFactura(e *sqlc.FacturaEstado) string {
	if e == nil {
		return "sin cotejar"
	}
	switch *e {
	case sqlc.FacturaEstadoCambiado:
		return "cambió en la factura"
	case sqlc.FacturaEstadoSinFactura:
		return "sin facturar"
	}
	return "sin cotejar"
}

// costoDelPedido devuelve el `pedidoCosto` de ese pedido, que es lo que se copia a `price`.
// NO se calcula aquí ningún precio: el del domicilio lo pone la APK de Entrega.
func costoDelPedido(pedidos []sqlc.PedidosParaArmarRutaRow, id uuid.UUID) *float64 {
	for _, p := range pedidos {
		if p.ID == id {
			return p.PedidoCosto
		}
	}
	return nil
}

func idDelVehiculo(v *sqlc.ObtenerVehiculoParaCapacidadRow) pgtype.UUID {
	if v == nil {
		return pgtype.UUID{}
	}
	return pgDe(v.ID)
}

func aPgOpcional(id *uuid.UUID) pgtype.UUID {
	if id == nil {
		return pgtype.UUID{}
	}
	return pgDe(*id)
}

// sucursalDelCuerpo lee el `branchId` que manda el asistente. Un id mal escrito NO acota:
// se avisa y se sigue, que es la misma regla del alcance para una sucursal que ya no
// existe — esconder el problema devolviendo cero pedidos es lo que nadie sabe diagnosticar.
func sucursalDelCuerpo(r *http.Request, crudo string) *uuid.UUID {
	crudo = strings.TrimSpace(crudo)
	if crudo == "" {
		return nil
	}
	id, err := uuid.Parse(crudo)
	if err != nil {
		httpx.Registro(r).Warn("[rutas] el branchId del cuerpo no es un id: se ignora", "branchId", crudo)
		return nil
	}
	return &id
}

// fechaDeEntrega admite la fecha sola (`2026-09-14`) y la marca completa con zona. Una
// fecha que no se entiende se RECHAZA en vez de guardarse como nula: una ruta planificada
// para el día equivocado se descubre con el camión cargado.
func fechaDeEntrega(w http.ResponseWriter, r *http.Request, crudo string) (pgtype.Timestamptz, bool) {
	crudo = strings.TrimSpace(crudo)
	if crudo == "" {
		return pgtype.Timestamptz{}, true
	}
	for _, formato := range []string{time.RFC3339Nano, time.RFC3339, "2006-01-02T15:04:05", "2006-01-02"} {
		if t, err := time.Parse(formato, crudo); err == nil {
			return pgtype.Timestamptz{Time: t, Valid: true}, true
		}
	}
	httpx.Error(w, r, http.StatusBadRequest,
		fmt.Sprintf("La fecha de entrega '%s' no se entiende. Se espera AAAA-MM-DD", crudo))
	return pgtype.Timestamptz{}, false
}

// estadoDeRutaValido comprueba el enum antes de que lo haga Postgres: dejarlo caer hasta
// la base da un 500 con la jerga del motor dentro, y esto da un 400 que se puede leer.
func estadoDeRutaValido(w http.ResponseWriter, r *http.Request, v string) (sqlc.RouteStatus, bool) {
	switch sqlc.RouteStatus(v) {
	case sqlc.RouteStatusPlanned, sqlc.RouteStatusInProgress, sqlc.RouteStatusCompleted, sqlc.RouteStatusCancelled:
		return sqlc.RouteStatus(v), true
	}
	httpx.Error(w, r, http.StatusBadRequest, fmt.Sprintf(
		"Estado de ruta no válido: '%s'. Sólo 'planned', 'in_progress', 'completed' o 'cancelled'", v))
	return "", false
}

// resultadoValido: sólo los tres del contrato.
func resultadoValido(v *string) (sqlc.StopResult, bool) {
	if v == nil {
		return "", false
	}
	switch sqlc.StopResult(*v) {
	case sqlc.StopResultEntregado, sqlc.StopResultDevuelto, sqlc.StopResultCancelado:
		return sqlc.StopResult(*v), true
	}
	return "", false
}

// valorTalCual es lo que se interpola en «resultado '<v>' desconocido». Un resultado que
// no vino sale como `undefined`, calcado de delivery: el que lee el mensaje está mirando
// el JSON que mandó, y ahí el campo no está.
func valorTalCual(v *string) string {
	if v == nil {
		return "undefined"
	}
	return *v
}

// notaDeCierre limpia la nota: vacía es NULL, y se corta a 500. El corte va por RUNAS y no
// por bytes — cortar por bytes parte una «ñ» por la mitad y lo que queda guardado no es
// texto válido.
func notaDeCierre(v *string) *string {
	if v == nil {
		return nil
	}
	nota := strings.TrimSpace(*v)
	if nota == "" {
		return nil
	}
	if runas := []rune(nota); len(runas) > 500 {
		nota = string(runas[:500])
	}
	return &nota
}

// textoDeResultado saca el enum a texto, o null. `resultado` y `resultadoNota` son cómo
// acabó la parada: de ahí sale el post-despacho.
func textoDeResultado(v *sqlc.StopResult) *string {
	if v == nil {
		return nil
	}
	s := string(*v)
	return &s
}

// avisosDeLasParadas arma el lote de avisos de los pedidos que van EN la ruta y vienen del
// espejo: los tecleados a mano no existen ya, pero un pedido sin `externalId` no tiene a
// quién avisarle.
func (s *Servidor) avisosDeLasParadas(r *http.Request, a *alcance.Acotado, ruta uuid.UUID, estado string) []AvisoDeParada {
	paradas, err := a.ParadasDeRutas(r.Context(), []uuid.UUID{ruta})
	if err != nil {
		httpx.Registro(r).Error("no se pudieron leer las paradas para avisar a PEDIDO", "ruta", ruta, "err", err)
		return nil
	}
	cuando := horaDelSuceso(r)
	var avisos []AvisoDeParada
	for _, p := range paradas {
		if p.Source != nil && *p.Source == sqlc.ProcedenciaPedido && p.ExternalID != nil {
			avisos = append(avisos, AvisoDeParada{PedidoID: *p.ExternalID, Estado: estado, At: cuando})
		}
	}
	return avisos
}

// avisarDeFondo dispara y olvida. Lo que NO puede pasar es que no se pueda armar o
// despachar una ruta porque otra aplicación esté caída; lo que sí tiene que pasar es que
// quede en el registro cuando no sale.
func (s *Servidor) avisarDeFondo(r *http.Request, avisos []AvisoDeParada) {
	if len(avisos) == 0 {
		return
	}
	reg := httpx.Registro(r)
	// El canal se lee AQUÍ y no dentro de la goroutine: así el disparo de fondo no toca
	// el campo del servidor desde otro hilo, que es una carrera de las que sólo se ven en
	// producción y un martes.
	enviar := s.aPedido
	// El contexto de la petición muere al contestar, así que el aviso se lleva uno propio.
	go func() {
		ctx, cancelar := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancelar()
		if parte := enviar(ctx, avisos); !parte.Ok {
			reg.Warn("PEDIDO no se enteró del cambio de estado", "avisos", len(avisos), "err", parte.Error)
		}
	}()
}

// ---------------------------------------------------------------------------
// De fila de sqlc a respuesta
// ---------------------------------------------------------------------------

func deFilaDeLista(f sqlc.ListarRutasRow, paradas []ParadaSalida) RutaSalida {
	return armarRuta(datosDeRuta{
		ID: f.ID, Name: f.Name, RouteCode: f.RouteCode, Status: string(f.Status),
		OriginAddress: f.OriginAddress, OriginLat: f.OriginLat, OriginLng: f.OriginLng,
		TotalDistance: f.TotalDistance, TotalWeight: f.TotalWeight, TotalPrice: f.TotalPrice,
		DeliveryDate: f.DeliveryDate, VehicleID: f.VehicleID, BranchID: f.BranchID,
		CreadoPor: f.CreadoPor, StartedAt: f.StartedAt, FinishedAt: f.FinishedAt,
		Optimized: f.Optimized, CreatedAt: f.CreatedAt, UpdatedAt: f.UpdatedAt,
		SucursalNombre: f.SucursalNombre, SucursalCodigo: f.SucursalCodigo,
		VehiculoNombre: f.VehiculoNombre, VehiculoMatricula: f.VehiculoMatricula,
		VehiculoCapacidad: f.VehiculoCapacidad, VehiculoTipo: f.VehiculoTipo,
	}, paradas)
}

func deFilaDeDetalle(f sqlc.ObtenerRutaRow, paradas []ParadaSalida) RutaSalida {
	return armarRuta(datosDeRuta{
		ID: f.ID, Name: f.Name, RouteCode: f.RouteCode, Status: string(f.Status),
		OriginAddress: f.OriginAddress, OriginLat: f.OriginLat, OriginLng: f.OriginLng,
		TotalDistance: f.TotalDistance, TotalWeight: f.TotalWeight, TotalPrice: f.TotalPrice,
		DeliveryDate: f.DeliveryDate, VehicleID: f.VehicleID, BranchID: f.BranchID,
		CreadoPor: f.CreadoPor, StartedAt: f.StartedAt, FinishedAt: f.FinishedAt,
		Optimized: f.Optimized, CreatedAt: f.CreatedAt, UpdatedAt: f.UpdatedAt,
		SucursalNombre: f.SucursalNombre, SucursalCodigo: f.SucursalCodigo,
		VehiculoNombre: f.VehiculoNombre, VehiculoMatricula: f.VehiculoMatricula,
		VehiculoCapacidad: f.VehiculoCapacidad, VehiculoTipo: f.VehiculoTipo,
	}, paradas)
}

// datosDeRuta es el intermedio entre las dos filas de sqlc —lista y detalle, que traen las
// mismas columnas con distinto tipo— y la salida. Existe para no escribir dos veces el
// mismo armado y que un día se cambie sólo uno.
type datosDeRuta struct {
	ID                uuid.UUID
	Name              *string
	RouteCode         *string
	Status            string
	OriginAddress     *string
	OriginLat         *float64
	OriginLng         *float64
	TotalDistance     float64
	TotalWeight       float64
	TotalPrice        float64
	DeliveryDate      pgtype.Timestamptz
	VehicleID         pgtype.UUID
	BranchID          pgtype.UUID
	CreadoPor         *string
	StartedAt         pgtype.Timestamptz
	FinishedAt        pgtype.Timestamptz
	Optimized         bool
	CreatedAt         pgtype.Timestamptz
	UpdatedAt         pgtype.Timestamptz
	SucursalNombre    *string
	SucursalCodigo    *string
	VehiculoNombre    *string
	VehiculoMatricula *string
	VehiculoCapacidad *float64
	VehiculoTipo      *string
}

func armarRuta(d datosDeRuta, paradas []ParadaSalida) RutaSalida {
	salida := RutaSalida{
		ID: d.ID, Name: d.Name, RouteCode: d.RouteCode, Status: d.Status,
		OriginAddress: d.OriginAddress, OriginLat: d.OriginLat, OriginLng: d.OriginLng,
		TotalDistance: d.TotalDistance, TotalWeight: d.TotalWeight, TotalPrice: d.TotalPrice,
		DeliveryDate: hora(d.DeliveryDate), VehicleID: idOpcional(d.VehicleID),
		BranchID: idOpcional(d.BranchID), CreadoPor: d.CreadoPor,
		StartedAt: hora(d.StartedAt), FinishedAt: hora(d.FinishedAt),
		Optimized: d.Optimized, CreatedAt: hora(d.CreatedAt), UpdatedAt: hora(d.UpdatedAt),
		// Siempre lista, nunca null: ver el comentario de `Items`.
		Orders: paradas,
	}
	if salida.Orders == nil {
		salida.Orders = []ParadaSalida{}
	}
	if d.BranchID.Valid {
		salida.Branch = &SucursalDeRuta{
			ID: uuid.UUID(d.BranchID.Bytes), Name: d.SucursalNombre, ExternalID: d.SucursalCodigo,
		}
	}
	if d.VehicleID.Valid {
		salida.Vehicle = &CamionDeRuta{
			ID: uuid.UUID(d.VehicleID.Bytes), Name: d.VehiculoNombre, Type: d.VehiculoTipo,
			Plate: d.VehiculoMatricula, Capacity: d.VehiculoCapacidad,
		}
	}
	return salida
}
