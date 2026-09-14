// EL ESPEJO: las rutas por las que esta base se pone al día con las de fuera, y la que
// deja al aparato ponerse al día con ésta.
//
// Son tres y ninguna la abre una persona mirando una pantalla:
//
//	POST /api/products/sync   el catálogo de Ventra, sucursal por sucursal
//	POST /api/admin/recompute el recosteo de lo de los últimos N días, vía PEDIDO
//	GET  /api/sync/cambios    la BAJADA del aparato (`docs/sincronizacion.md`)
//
// LO QUE TIENEN EN COMÚN, y por eso están juntas: ninguna es idempotente por casualidad.
// Las tres se llaman desde un temporizador o desde un aparato que reintenta, así que
// repetirlas tiene que ser barato y no puede duplicar nada. El catálogo se escribe con un
// `ON CONFLICT (sucursal_codigo, sku)`; el recosteo no escribe aquí, delega; y la bajada
// sólo lee.
//
// Y LO QUE NO HACEN: ninguna borra lo que deja de venir. Media lista por un corte de VPN
// no puede vaciar el catálogo de una sucursal — lo viejo se nota por `traido_at`, que dice
// si lo que se está mirando es de hace diez minutos o de hace tres días.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// rutasEspejo monta las tres. Lo llama `Rutas()` en servidor.go.
func (s *Servidor) rutasEspejo(rt *httpx.Router, sesion, admin []httpx.Medio) {
	_ = admin

	// `products/sync` admite LAS DOS PUERTAS —clave de servicio o sesión— porque la
	// dispara un temporizador y también un administrador que ve el catálogo viejo y le
	// da al botón. Dejar sólo la de servicio obligaría a repartir la clave a mano.
	servicioOSesion := []httpx.Medio{s.servicioOSesion, s.porteria.Exigir}
	rt.ManejarFunc(http.MethodPost, "/api/products/sync", s.sincronizarProductos, servicioOSesion...)

	// `admin/recompute` es de PERSONA y no de servicio: usa la clave de servicio para
	// hablar con PEDIDO, pero quien la dispara tiene que estar identificado, porque de su
	// alcance sale a qué sucursal se le recuesta lo de los últimos treinta días.
	rt.ManejarFunc(http.MethodPost, "/api/admin/recompute", s.recomputar, sesion...)

	// La bajada del aparato.
	rt.ManejarFunc(http.MethodGet, "/api/sync/cambios", s.cambiosDesde, sesion...)
}

// servicioOSesion deja pasar a quien traiga la clave de servicio O una sesión válida.
//
// Cuando entra por la clave, se cuelga del contexto una persona SIN sucursal: no es un
// disfraz para saltarse nada, es que el alcance necesita alguien de quien partir y el
// espejo, por definición, recorre las ocho sucursales. Si se dejara sin persona, el
// middleware del alcance respondería 401 y la ruta no se podría llamar nunca desde el
// temporizador.
//
// El orden importa: primero la clave. Un servicio que además arrastre una cookie caducada
// no puede quedarse fuera por la cookie.
func (s *Servidor) servicioOSesion(siguiente http.Handler) http.Handler {
	conLlave := auth.LlaveDeServicio(s.cfg.ServiceAPIKey)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if s.cfg.ServiceAPIKey != "" && r.Header.Get("X-Api-Key") != "" {
			conLlave(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				ctx := auth.ConUsuario(r.Context(), &auth.Usuario{
					ID: "servicio:espejo", Rol: "SUPER ADMIN",
				})
				siguiente.ServeHTTP(w, r.WithContext(ctx))
			})).ServeHTTP(w, r)
			return
		}
		s.verif.Exigir(siguiente).ServeHTTP(w, r)
	})
}

// ---------------------------------------------------------------------------
// POST /api/products/sync
// ---------------------------------------------------------------------------

// FilaDeVentra es una línea del catálogo tal como la da Ventra. Es lo mínimo que hace
// falta para escribir un producto; lo demás de Ventra no se guarda porque no se usa, y un
// campo guardado que nadie lee es un campo que nadie mantiene.
type FilaDeVentra struct {
	Sku               string
	Nombre            string
	PesoKg            *float64
	Categoria         string
	Unidad            string
	Envase            string
	UnidadesPorEnvase *float64
	Precio            *float64
	Existencias       *float64
	// Activo=false NO se guarda: es un producto retirado en Ventra, y ofrecerlo en el
	// buscador es prometer mercancía que no hay.
	Activo bool
}

// LectorDeVentra es por donde se pregunta al catálogo de Ventra, que vive detrás de la
// VPN y en bases MySQL que no son ésta.
//
// ES UNA INTERFAZ Y NO UNA FUNCIÓN SUELTA porque son dos preguntas distintas —qué bases
// hay y qué tiene cada una— y porque así las pruebas de esta ruta no necesitan ni VPN ni
// MySQL: se corren en cada compilación y no «cuando haya una Ventra a mano».
type LectorDeVentra interface {
	// Bases devuelve, por CÓDIGO de sucursal (STG, HOL, CAM...), el nombre de la base de
	// Ventra que le corresponde.
	Bases(ctx context.Context) (map[string]string, error)
	// Catalogo lee el catálogo de una de esas bases.
	Catalogo(ctx context.Context, base string) ([]FilaDeVentra, error)
}

// Ventra es el lector de verdad, que se enchufa al arrancar.
//
// VARIABLE DE PAQUETE Y NO CAMPO DEL SERVIDOR, a regañadientes: `Servidor` se construye en
// `servidor.go` y este fichero no lo toca. Cuando se junte el paquete, esto tiene que
// pasar a ser un campo más de `Servidor`, como `salud`.
//
// MIENTRAS SEA nil, la ruta contesta 502 y NO 200 con ceros. Un catálogo que dice «he
// escrito 0 productos» cuando en realidad no ha preguntado a nadie deja al logístico
// mirando precios de hace tres semanas sin un solo aviso.
var Ventra LectorDeVentra

// CatalogoCadaMs es el intervalo de la bajada. Se puede saltar con `?forzar=1`.
const CatalogoCadaMs = 12 * 60 * 60 * 1000

type SucursalDelCatalogo struct {
	Sucursal string `json:"sucursal"`
	Database string `json:"database"`
	Leidos   int    `json:"leidos"`
	Escritos int    `json:"escritos"`
	Error    string `json:"error,omitempty"`
}

func (s *Servidor) sincronizarProductos(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	forzar := r.URL.Query().Get("forzar") == "1"

	ajustes, err := a.ObtenerAjustes(r.Context())
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// El intervalo: sin forzar, no se vuelve a preguntar antes de las doce horas. El
	// catálogo de ocho sucursales por la VPN de allá no es una consulta barata.
	if !forzar && ajustes.CatalogoTraidoAt.Valid {
		if time.Since(ajustes.CatalogoTraidoAt.Time) < intervaloDelCatalogo() {
			httpx.JSON(w, r, http.StatusOK, map[string]any{
				"saltado": true, "traidoAt": hora(ajustes.CatalogoTraidoAt),
			})
			return
		}
	}

	if Ventra == nil {
		httpx.Error(w, r, http.StatusBadGateway,
			"No se pudo preguntar a Ventra (¿VPN?): este servicio todavía no tiene lector de Ventra configurado")
		return
	}
	bases, err := Ventra.Bases(r.Context())
	if err != nil {
		httpx.Error(w, r, http.StatusBadGateway,
			fmt.Sprintf("No se pudo preguntar a Ventra (¿VPN?): %s", err))
		return
	}

	sucursales, err := a.ListarSucursalesVisibles(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	filas := make([]SucursalDelCatalogo, 0, len(sucursales))
	escritosTotal, conError := 0, 0
	for _, suc := range sucursales {
		fila := SucursalDelCatalogo{Sucursal: suc.Name}
		codigo := ""
		if suc.ExternalID != nil {
			codigo = strings.TrimSpace(*suc.ExternalID)
		}
		base, hay := bases[codigo]
		if codigo == "" || !hay {
			// Literal del contrato. NO es un error del servicio: es una sucursal que
			// todavía no tiene su base emparejada, y las demás siguen.
			fila.Error = "sin base de Ventra que le cuadre"
			conError++
			filas = append(filas, fila)
			continue
		}
		fila.Database = base

		// Una sucursal que falla NO tumba a las otras siete. Es la diferencia entre
		// «Holguín se quedó sin catálogo» y «hoy no hay catálogo».
		leidos, escritos, err := s.catalogoDeUnaSucursal(r, a, base, codigo)
		fila.Leidos, fila.Escritos = leidos, escritos
		if err != nil {
			fila.Error = err.Error()
			conError++
			httpx.Registro(r).Warn("el catálogo de una sucursal no se pudo traer",
				"sucursal", suc.Name, "base", base, "err", err)
		}
		escritosTotal += escritos
		filas = append(filas, fila)
	}

	// La hora SÓLO se marca si se escribió algo. Si todas fallaron no se toca, para poder
	// reintentar antes de las doce horas en vez de quedarse medio día con el catálogo a
	// medias y creyendo que está al día.
	if escritosTotal > 0 {
		if err := a.EspejoMarcarCatalogoTraido(r.Context()); err != nil {
			httpx.Registro(r).Error("el catálogo entró pero no se pudo marcar la hora", "err", err)
		}
	}

	httpx.JSON(w, r, http.StatusOK, map[string]any{
		"sucursales": filas,
		"escritos":   escritosTotal,
		"conError":   conError,
	})
}

func (s *Servidor) catalogoDeUnaSucursal(r *http.Request, a *alcance.Acotado, base, codigo string) (int, int, error) {
	lineas, err := Ventra.Catalogo(r.Context(), base)
	if err != nil {
		return 0, 0, err
	}
	escritos := 0
	for _, l := range lineas {
		sku := strings.TrimSpace(l.Sku)
		nombre := strings.TrimSpace(l.Nombre)
		// Sin sku no hay clave por la que reconocer la fila entre pasadas, y sin nombre
		// no hay nada que enseñar. Se saltan, no se inventan.
		if sku == "" || nombre == "" || !l.Activo {
			continue
		}
		cod := codigo
		peso := 0.0
		if l.PesoKg != nil {
			peso = *l.PesoKg
		}
		if _, err := a.EspejoGuardarProducto(r.Context(), sqlc.GuardarProductoDelCatalogoParams{
			Name: nombre, Weight: peso,
			Packaging: aTexto(strings.TrimSpace(l.Envase)),
			// El peso por envase se guarda tal cual venga; un cero no es «no lo sé» y
			// por eso va como puntero desde Ventra.
			UnitsPerPackage: l.UnidadesPorEnvase,
			Category:        aTexto(strings.TrimSpace(l.Categoria)),
			Sku:             &sku,
			SucursalCodigo:  &cod,
			Price:           l.Precio,
			Stock:           l.Existencias,
			Unit:            aTexto(strings.TrimSpace(l.Unidad)),
		}); err != nil {
			// Una línea mala no se lleva por delante el catálogo entero de la sucursal.
			httpx.Registro(r).Warn("una línea del catálogo no entró",
				"sucursal", codigo, "sku", sku, "err", err)
			continue
		}
		escritos++
	}
	return len(lineas), escritos, nil
}

func intervaloDelCatalogo() time.Duration {
	if crudo := strings.TrimSpace(os.Getenv("CATALOGO_CADA_MS")); crudo != "" {
		if ms, err := strconv.Atoi(crudo); err == nil && ms > 0 {
			return time.Duration(ms) * time.Millisecond
		}
	}
	return CatalogoCadaMs * time.Millisecond
}

// ---------------------------------------------------------------------------
// POST /api/admin/recompute
// ---------------------------------------------------------------------------

// ClienteDelEspejo es el http.Client con el que se habla con PEDIDO y con la cotización.
//
// CON PLAZO Y NO EL DE POR DEFECTO, que no tiene ninguno: una petición sin plazo contra la
// VPN de allá se queda colgada para siempre y se lleva una conexión del pool con ella. Y
// como variable de paquete para que las pruebas puedan apuntarlo a un servidor de mentira.
var ClienteDelEspejo = &http.Client{Timeout: 120 * time.Second}

// DiasPorDefecto y los topes del recosteo. Acotado a [1,120] a propósito: con «todos los
// días» esto se convierte en una consulta de 3.500 pedidos por la conexión de Cuba.
const (
	DiasPorDefecto = 30
	DiasMinimo     = 1
	DiasMaximo     = 120
)

func (s *Servidor) recomputar(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	// La clave se comprueba ANTES de nada: sin ella no hay manera de hablar con PEDIDO y
	// el trabajo entero no se puede hacer. Enterarse después de bajar 5.000 pedidos es
	// enterarse tarde.
	if strings.TrimSpace(s.cfg.ServiceAPIKey) == "" {
		httpx.Error(w, r, http.StatusInternalServerError, "SERVICE_API_KEY no configurada en el servidor")
		return
	}
	pedidoURL := strings.TrimRight(strings.TrimSpace(os.Getenv("PEDIDO_API_URL")), "/")
	if pedidoURL == "" {
		httpx.Error(w, r, http.StatusInternalServerError, "PEDIDO_API_URL no configurada en el servidor")
		return
	}

	dias := DiasPorDefecto
	if n, err := strconv.Atoi(strings.TrimSpace(r.URL.Query().Get("dias"))); err == nil && n != 0 {
		dias = n
	}
	dias = min(max(dias, DiasMinimo), DiasMaximo)

	// El alcance se traduce a CÓDIGO porque es lo que entiende PEDIDO: allí las
	// sucursales son STG y HOL, no uuids nuestros. Sin alcance se piden todas.
	codigo := ""
	if c := a.Codigo(); c != nil {
		codigo = *c
	}

	desde := time.Now().AddDate(0, 0, -dias).Format("2006-01-02")
	url := fmt.Sprintf("%s/integration/orders?desde=%s&limit=5000", pedidoURL, desde)
	if codigo != "" {
		url += "&sucursalCodigo=" + codigo
	}

	cuerpo, estado, err := s.pedirAlEspejo(r.Context(), http.MethodGet, url, nil)
	if err != nil {
		httpx.Error(w, r, http.StatusBadGateway, fmt.Sprintf("PEDIDO no contesta: %s", err))
		return
	}
	if estado < 200 || estado >= 300 {
		httpx.Error(w, r, http.StatusBadGateway,
			fmt.Sprintf("PEDIDO %d: %s", estado, recortar(cuerpo, 200)))
		return
	}

	var respuesta struct {
		Orders []json.RawMessage `json:"orders"`
	}
	if err := json.Unmarshal(cuerpo, &respuesta); err != nil {
		httpx.Error(w, r, http.StatusBadGateway,
			fmt.Sprintf("PEDIDO contestó algo que no se entiende: %s", recortar(cuerpo, 200)))
		return
	}

	quien := codigo
	if quien == "" {
		quien = "todas"
	}
	if len(respuesta.Orders) == 0 {
		// 200 y no 404: que no haya nada que recostear no es un fallo, y la pantalla
		// necesita poder decirlo con esas palabras.
		httpx.JSON(w, r, http.StatusOK, map[string]any{
			"total": 0, "recosteados": 0, "dias": dias,
			"message":  fmt.Sprintf("No hay pedidos con geolocalización en los últimos %d días.", dias),
			"sucursal": quien,
		})
		return
	}

	// El recosteo de verdad lo hace `/api/quote/batch`, que es quien sabe repartir la
	// carga. Aquí NO se duplica esa cuenta: dos sitios calculando el mismo precio es la
	// forma más rápida de que discrepen, y este número acaba en la factura del cliente.
	destino := strings.TrimRight(strings.TrimSpace(os.Getenv("DELIVERY_URL")), "/")
	if destino == "" {
		destino = "http://127.0.0.1:" + s.cfg.Puerto
	}
	lote, _ := json.Marshal(map[string]any{
		"preview":             false,
		"useWarehouseWeights": true,
		"orders":              respuesta.Orders,
	})
	cuerpo, estado, err = s.pedirAlEspejo(r.Context(), http.MethodPost, destino+"/api/quote/batch", lote)
	if err != nil {
		httpx.Error(w, r, http.StatusBadGateway, fmt.Sprintf("Cotización no contesta: %s", err))
		return
	}
	if estado < 200 || estado >= 300 {
		httpx.Error(w, r, http.StatusBadGateway,
			fmt.Sprintf("Cotización %d: %s", estado, recortar(cuerpo, 200)))
		return
	}

	var batch struct {
		WeightsSource string `json:"weightsSource"`
		Results       []struct {
			Status string   `json:"status"`
			Price  *float64 `json:"price"`
		} `json:"results"`
	}
	_ = json.Unmarshal(cuerpo, &batch)
	recosteados := 0
	for _, res := range batch.Results {
		if res.Status == "quoted" && res.Price != nil {
			recosteados++
		}
	}
	if batch.WeightsSource == "" {
		batch.WeightsSource = "none"
	}

	httpx.JSON(w, r, http.StatusOK, map[string]any{
		"total": len(respuesta.Orders), "recosteados": recosteados, "dias": dias,
		"weightsSource": batch.WeightsSource, "sucursal": quien,
	})
}

func (s *Servidor) pedirAlEspejo(ctx context.Context, metodo, url string, cuerpo []byte) ([]byte, int, error) {
	var lector io.Reader
	if cuerpo != nil {
		lector = strings.NewReader(string(cuerpo))
	}
	req, err := http.NewRequestWithContext(ctx, metodo, url, lector)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("X-Api-Key", s.cfg.ServiceAPIKey)
	req.Header.Set("Accept", "application/json")
	// `no-store` explícito: por el medio hay proxies y una respuesta guardada del
	// recosteo de ayer es exactamente el número que no se quiere.
	req.Header.Set("Cache-Control", "no-store")
	if cuerpo != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	res, err := ClienteDelEspejo.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer res.Body.Close()
	// Tope de lectura: una respuesta enorme de un servicio que se volvió loco no puede
	// tumbar este proceso por memoria.
	leido, err := io.ReadAll(io.LimitReader(res.Body, 32<<20))
	return leido, res.StatusCode, err
}

func recortar(b []byte, n int) string {
	s := strings.TrimSpace(string(b))
	if len(s) <= n {
		return s
	}
	return s[:n]
}

// ---------------------------------------------------------------------------
// GET /api/sync/cambios — la bajada del aparato
// ---------------------------------------------------------------------------

// Conjunto es la forma de cada colección en la bajada: lo que se puso o cambió, y lo que
// se fue. `quitados` hace falta DE VERDAD: sin él, un pedido archivado o una ruta borrada
// se quedan en el aparato para siempre y la lista local sólo crece.
type Conjunto struct {
	Puestos  []any    `json:"puestos"`
	Quitados []string `json:"quitados"`
}

// CambiosSalida es el sobre del protocolo (`docs/sincronizacion.md`).
type CambiosSalida struct {
	// Hasta LO PONE EL SERVIDOR, nunca el aparato. El reloj de un teléfono se mueve —se
	// cambia a mano, se va con la batería, salta de huso—, y si el aparato dijera desde
	// cuándo pedir, un reloj atrasado se perdería cambios para siempre sin que nadie lo
	// note.
	Hasta    time.Time           `json:"hasta"`
	Completa bool                `json:"completa"`
	Cambios  map[string]Conjunto `json:"cambios"`
	Truncado bool                `json:"truncado"`
	// Faltan son las colecciones que esta versión del servidor NO SABE servir todavía.
	//
	// VAN NOMBRADAS Y NO COMO UN CONJUNTO VACÍO, y ésa es toda la razón de que este campo
	// exista: un `{"puestos":[],"quitados":[]}` le dice al aparato «no ha cambiado nada»,
	// que es exactamente lo contrario de la verdad, y el aparato se queda con la foto de
	// la mañana creyendo que está al día. Ausente y nombrado aquí, el aparato puede
	// decirlo en la pantalla.
	Faltan []string `json:"faltan,omitempty"`
	Aviso  string   `json:"aviso,omitempty"`
}

// TopeDeBajada acota cada colección. Si alguna lo toca, `truncado` va a true y el aparato
// vuelve a pedir con el `hasta` devuelto.
const TopeDeBajada = 2000

func (s *Servidor) cambiosDesde(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()

	var desde *time.Time
	if crudo := strings.TrimSpace(q.Get("desde")); crudo != "" {
		t, err := time.Parse(time.RFC3339, crudo)
		if err != nil {
			httpx.Error(w, r, http.StatusBadRequest,
				"«desde» tiene que ser una fecha en formato RFC3339 (2026-09-14T11:02:31Z)")
			return
		}
		desde = &t
	}

	salida := CambiosSalida{
		Hasta:    time.Now().UTC(),
		Completa: desde == nil,
		Cambios:  map[string]Conjunto{},
	}
	truncado := false

	// --- Sucursales ---------------------------------------------------------
	sucursales, err := a.ListarSucursalesVisibles(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	var puestos []any
	for _, b := range sucursales {
		if !cambioDesde(b.UpdatedAt, desde) {
			continue
		}
		puestos = append(puestos, map[string]any{
			"id": b.ID, "name": b.Name, "externalId": b.ExternalID,
			"address": b.Address, "lat": b.Lat, "lng": b.Lng,
			"originConfigured": b.OriginConfigured, "updatedAt": hora(b.UpdatedAt),
		})
	}
	salida.Cambios["branches"] = conjunto(puestos)

	// --- Vehículos ----------------------------------------------------------
	vehiculos, err := a.ListarVehiculos(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	puestos = nil
	for _, v := range vehiculos {
		if !cambioDesde(v.UpdatedAt, desde) {
			continue
		}
		puestos = append(puestos, map[string]any{
			"id": v.ID, "name": v.Name, "type": v.TipoNombre, "plate": v.Plate,
			"capacity": v.Capacity, "status": string(v.Status),
			"branchId": idOpcional(v.BranchID), "updatedAt": hora(v.UpdatedAt),
		})
	}
	salida.Cambios["vehicles"] = conjunto(puestos)

	// --- Rutas --------------------------------------------------------------
	rutas, err := a.EspejoListarRutas(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	puestos = nil
	for _, rt := range rutas {
		if !cambioDesde(rt.UpdatedAt, desde) {
			continue
		}
		puestos = append(puestos, map[string]any{
			"id": rt.ID, "name": rt.Name, "routeCode": rt.RouteCode,
			"status": string(rt.Status), "originLat": rt.OriginLat, "originLng": rt.OriginLng,
			"totalWeight": rt.TotalWeight, "totalDistance": rt.TotalDistance,
			"vehicleId": idOpcional(rt.VehicleID), "branchId": idOpcional(rt.BranchID),
			"paradas": rt.Paradas, "updatedAt": hora(rt.UpdatedAt),
		})
	}
	salida.Cambios["routes"] = conjunto(puestos)

	// --- Catálogo -----------------------------------------------------------
	productos, err := a.EspejoListarProductos(r.Context(), TopeDeBajada)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	truncado = truncado || len(productos) >= TopeDeBajada
	puestos = nil
	for _, p := range productos {
		if !cambioDesde(p.UpdatedAt, desde) {
			continue
		}
		puestos = append(puestos, map[string]any{
			"id": p.ID, "name": p.Name, "weight": p.Weight, "sku": p.Sku,
			"sucursalCodigo": p.SucursalCodigo, "price": p.Price, "stock": p.Stock,
			"unit": p.Unit, "category": p.Category, "updatedAt": hora(p.UpdatedAt),
		})
	}
	salida.Cambios["products"] = conjunto(puestos)

	// --- Clientes -----------------------------------------------------------
	//
	// OJO: los clientes se filtran por `synced_at` y no por `updated_at`, porque es lo
	// único que trae la consulta. Significan cosas parecidas pero no iguales —`synced_at`
	// es «cuándo lo trajo PEDIDO»—, y mientras sea eso lo que hay, es lo que se usa.
	clientes, err := a.EspejoListarClientes(r.Context(), TopeDeBajada)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	truncado = truncado || len(clientes) >= TopeDeBajada
	puestos = nil
	for _, c := range clientes {
		if !cambioDesde(c.SyncedAt, desde) {
			continue
		}
		puestos = append(puestos, map[string]any{
			"id": c.ID, "name": c.Name, "phone": c.Phone, "address": c.Address,
			"municipio": c.Municipio, "zona": c.Zona, "lat": c.Lat, "lng": c.Lng,
			"sucursalCodigo": c.SucursalCodigo, "codigo": c.Codigo,
			"vendedor": c.Vendedor, "syncedAt": hora(c.SyncedAt),
		})
	}
	salida.Cambios["customers"] = conjunto(puestos)

	// --- Ajustes ------------------------------------------------------------
	ajustes, err := a.ObtenerAjustes(r.Context())
	switch {
	case err == nil:
		puestos = nil
		if cambioDesde(ajustes.UpdatedAt, desde) {
			puestos = append(puestos, map[string]any{
				"currency": ajustes.Currency, "cupRate": ajustes.CupRate,
				"cupRateUpdatedAt": hora(ajustes.CupRateUpdatedAt),
				"catalogoTraidoAt": hora(ajustes.CatalogoTraidoAt),
				"updatedAt":        hora(ajustes.UpdatedAt),
			})
		}
		salida.Cambios["settings"] = conjunto(puestos)
	case errors.Is(err, pgx.ErrNoRows):
		salida.Cambios["settings"] = conjunto(nil)
	default:
		httpx.ErrorInterno(w, r, err)
		return
	}

	// --- El tablero ---------------------------------------------------------
	//
	// Las dos colecciones del tablero son POR SUCURSAL, como el tablero mismo. Si quien
	// pide no dice cuál —un Super Admin sin cabecera—, no se le manda el tablero de las
	// ocho mezclado: se le dice que falta elegir.
	sucursal := sucursalDeLaBajada(r, a)
	if sucursal == nil {
		salida.Faltan = append(salida.Faltan, "boardColumns", "boardPlacements")
		salida.Aviso = "para bajar el tablero hace falta decir la sucursal (?sucursal=<id>)"
	} else {
		columnas, err := a.ListarColumnasDelTablero(r.Context(), *sucursal)
		if err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
		puestos = nil
		for _, c := range columnas {
			if !cambioDesde(c.UpdatedAt, desde) {
				continue
			}
			puestos = append(puestos, map[string]any{
				"id": c.ID, "branchId": c.BranchID, "nombre": c.Nombre,
				"posicion": c.Posicion, "vehiculoId": idOpcional(c.VehicleID),
				"updatedAt": hora(c.UpdatedAt),
			})
		}
		salida.Cambios["boardColumns"] = conjunto(puestos)

		// El origen va en (0,0) A PROPÓSITO: el `km_al_almacen` de esta consulta no se
		// usa en la bajada. El aparato recalcula la cercanía él mismo con el almacén que
		// bajó por la mañana —así el tablero ordena igual sin red—, y mandarle un número
		// medido desde otro sitio sería darle dos verdades.
		colocados, err := a.ListarPedidosColocados(r.Context(), sqlc.ListarPedidosColocadosParams{
			BranchID: *sucursal,
		})
		if err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
		puestos = nil
		for _, p := range colocados {
			if !cambioDesde(p.UpdatedAt, desde) {
				continue
			}
			puestos = append(puestos, map[string]any{
				"pedidoId": p.OrderID, "columnaId": p.ColumnID, "posicion": p.Posicion,
				"colocadoPor": p.ColocadoPor, "colocadoAt": hora(p.ColocadoAt),
				"updatedAt": hora(p.UpdatedAt),
			})
		}
		salida.Cambios["boardPlacements"] = conjunto(puestos)
	}

	// --- Lo que todavía no se puede servir -----------------------------------
	//
	// `orders` NO ESTÁ, y no está nombrado por descuido: ninguna de las consultas de
	// pedidos devuelve `updated_at`, así que hoy no hay manera de decir «lo que cambió
	// desde». La columna existe en la tabla y tiene su trigger; lo que falta es la
	// consulta. Hasta que esté, mandar `orders: {puestos: [], quitados: []}` sería
	// decirle al aparato que no ha cambiado ningún pedido, y ése es justo el fallo que
	// deja al logístico preparando el día con la foto de ayer.
	//
	// `warehouses` tampoco: los almacenes viven en Accesos y no en esta base.
	salida.Faltan = append(salida.Faltan, "orders", "warehouses")
	if salida.Aviso != "" {
		salida.Aviso += "; "
	}
	salida.Aviso += "«orders» necesita una consulta por updated_at que todavía no existe; " +
		"«warehouses» vive en Accesos y se pide allí"

	salida.Truncado = truncado
	httpx.JSON(w, r, http.StatusOK, salida)
}

// sucursalDeLaBajada: la que se pida por query, si no la del alcance, si no ninguna.
func sucursalDeLaBajada(r *http.Request, a *alcance.Acotado) *uuid.UUID {
	if crudo := strings.TrimSpace(r.URL.Query().Get("sucursal")); crudo != "" {
		if id, err := uuid.Parse(crudo); err == nil {
			// Se devuelve tal cual: el alcance lo vuelve a aplicar dentro de cada
			// consulta, así que una sucursal ajena sale vacía y no filtra nada.
			return &id
		}
	}
	return a.Sucursal()
}

// cambioDesde dice si esta fila entra en la bajada.
//
// Sin `desde` entra todo: es la carga inicial. Una fila SIN marca también entra, y no es
// un descuido — «no sé cuándo cambió» tiene que tratarse como «puede haber cambiado»: lo
// contrario es dejarla fuera para siempre.
func cambioDesde(marca pgtype.Timestamptz, desde *time.Time) bool {
	if desde == nil || !marca.Valid {
		return true
	}
	return marca.Time.After(*desde)
}

// conjunto normaliza el nil a lista vacía: el aparato lee JSON y `null` no se recorre.
func conjunto(puestos []any) Conjunto {
	if puestos == nil {
		puestos = []any{}
	}
	return Conjunto{Puestos: puestos, Quitados: []string{}}
}
