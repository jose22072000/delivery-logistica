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
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
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

// YA NO HAY `var Ventra`: el lector es `s.ventra`, un campo del servidor (ver
// `servidor.go`). Estaba como variable de paquete a regañadientes, porque `Servidor` se
// construye en `servidor.go` y este fichero no lo tocaba mientras se escribían los dos a
// la vez. Se enchufa al arrancar con `PonerLectorDeVentra`.
//
// LO QUE NO CAMBIA: mientras sea nil, la ruta contesta 502 y NO 200 con ceros. Un catálogo
// que dice «he escrito 0 productos» cuando en realidad no ha preguntado a nadie deja al
// logístico mirando precios de hace tres semanas sin un solo aviso.

// CatalogoCadaMs es el intervalo por defecto de la bajada, en milisegundos. Se puede
// cambiar con `CATALOGO_CADA_MS` y saltar de una vez con `?forzar=1`.
const CatalogoCadaMs = 12 * 60 * 60 * 1000

// PonerLectorDeVentra enchufa el lector. Lo llama el arranque, una vez, ANTES de servir:
// no hay candado porque no está pensado para cambiarse con el servidor ya en pie.
func (s *Servidor) PonerLectorDeVentra(v LectorDeVentra) { s.ventra = v }

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
		if time.Since(ajustes.CatalogoTraidoAt.Time) < s.intervaloDelCatalogo() {
			httpx.JSON(w, r, http.StatusOK, map[string]any{
				"saltado": true, "traidoAt": hora(ajustes.CatalogoTraidoAt),
			})
			return
		}
	}

	if s.ventra == nil {
		httpx.Error(w, r, http.StatusBadGateway,
			"No se pudo preguntar a Ventra (¿VPN?): este servicio todavía no tiene lector de Ventra configurado")
		return
	}
	bases, err := s.ventra.Bases(r.Context())
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
	lineas, err := s.ventra.Catalogo(r.Context(), base)
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

// intervaloDelCatalogo: cada cuánto se vuelve a bajar el catálogo. Sale de
// `CATALOGO_CADA_MS`, ya validada en `config` (doce horas por defecto).
//
// Con la configuración a cero se cae a las doce horas y NO a «siempre»: un intervalo de
// cero convierte cada visita a la pantalla en una bajada entera del catálogo de las ocho
// sucursales por la VPN, que es exactamente lo que este freno existe para evitar.
func (s *Servidor) intervaloDelCatalogo() time.Duration {
	if s.cfg != nil && s.cfg.CatalogoCada > 0 {
		return s.cfg.CatalogoCada
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
	// De `config`, que ya la validó y le quitó la barra final. Vacía sigue siendo un 500
	// con el nombre de la variable dentro: sin PEDIDO no hay nada que recostear, y
	// enterarse después de bajar 5.000 pedidos es enterarse tarde.
	pedidoURL := s.cfg.PedidoAPIURL
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
	destino := s.cfg.DeliveryURL
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
	// Continuar es POR DÓNDE SEGUIR en las colecciones que no se pueden trocear por
	// marca de tiempo: el catálogo y el padrón de clientes. El aparato lo devuelve tal
	// cual en la petición siguiente (`?continuar=…`) y no lo mira por dentro.
	//
	// EXISTE PORQUE `truncado` SIN ESTO ES MENTIRA. Estas dos colecciones se ordenan por
	// nombre y no por una marca que avance, así que decir «queda más» y devolver sólo
	// `hasta` deja al aparato pidiendo lo mismo una y otra vez. Contra producción, el
	// 15/09/2026, eso dejó 2.000 clientes redondos de 8.034 en el aparato y la bajada se
	// dio por buena — el modo de fallo que no revienta y que nadie ve hasta que no cuadra
	// el inventario.
	Continuar string `json:"continuar,omitempty"`
}

// porDondeSeguir es lo que viaja dentro de `continuar`.
//
// Lleva `Desde` además de los dos desplazamientos, y ésa es la parte que no se ve venir:
// el catálogo y los clientes se filtran en Go contra el `desde` de la petición, y en la
// segunda tanda ese `desde` ya es el `hasta` de la primera. Sin conservar el original, la
// tanda dos pagina hasta el final del padrón sin emitir una sola fila.
type porDondeSeguir struct {
	// Desde es el de la PRIMERA tanda de la cadena. Vacío = carga inicial.
	Desde string `json:"d,omitempty"`
	// Clientes y Productos son cuántas filas ya se sirvieron de cada uno.
	Clientes  int32 `json:"c,omitempty"`
	Productos int32 `json:"p,omitempty"`
}

// leerPorDondeSeguir saca el cursor de la query. Uno ilegible se trata como «empieza de
// cero» y no como un error: lo peor que pasa es que el aparato se baje otra vez una tanda
// que ya tenía, y eso se resuelve solo con el `insertOnConflictUpdate` de allá. Cortarle
// la bajada del día por un parámetro mal copiado sería mucho peor.
func leerPorDondeSeguir(crudo string) porDondeSeguir {
	var d porDondeSeguir
	crudo = strings.TrimSpace(crudo)
	if crudo == "" {
		return d
	}
	bruto, err := base64.RawURLEncoding.DecodeString(crudo)
	if err != nil {
		return porDondeSeguir{}
	}
	if err := json.Unmarshal(bruto, &d); err != nil {
		return porDondeSeguir{}
	}
	if d.Clientes < 0 {
		d.Clientes = 0
	}
	if d.Productos < 0 {
		d.Productos = 0
	}
	return d
}

func (d porDondeSeguir) escribir() string {
	bruto, err := json.Marshal(d)
	if err != nil {
		return ""
	}
	return base64.RawURLEncoding.EncodeToString(bruto)
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

	// `hasta` CIERRA LA VENTANA POR ARRIBA, y se admite del que llama porque quien llama
	// de verdad es el sincronizador, que lo coge de SU reloj ANTES de preguntar: lo que
	// cambie mientras se responde tiene que caer en la ventana siguiente y no perderse
	// entre las dos. Lo que NO se admite nunca es que lo ponga el aparato, y no puede:
	// entre el aparato y esto está el sincronizador, que lo pisa con el suyo.
	//
	// Sin él, el reloj de este proceso. Un aparato que pregunte directamente sigue
	// funcionando igual.
	hasta := time.Now().UTC()
	if crudo := strings.TrimSpace(q.Get("hasta")); crudo != "" {
		t, err := time.Parse(time.RFC3339, crudo)
		if err != nil {
			httpx.Error(w, r, http.StatusBadRequest,
				"«hasta» tiene que ser una fecha en formato RFC3339 (2026-09-14T11:02:31Z)")
			return
		}
		hasta = t.UTC()
	}

	// POR DÓNDE VA LA CADENA. En la primera tanda viene vacío.
	seguir := leerPorDondeSeguir(q.Get("continuar"))

	// El `desde` con el que se filtran el catálogo y los clientes es el de la PRIMERA
	// tanda, no el de ésta: ver `porDondeSeguir`.
	desdeDelPadron := desde
	if seguir.Desde != "" {
		if t, err := time.Parse(time.RFC3339Nano, seguir.Desde); err == nil {
			desdeDelPadron = &t
		}
	} else if desde != nil {
		seguir.Desde = desde.Format(time.RFC3339Nano)
	}

	salida := CambiosSalida{
		Hasta:    hasta,
		Completa: desde == nil,
		Cambios:  map[string]Conjunto{},
	}
	truncado := false
	// Lo que va a pedir la tanda siguiente. Se copia el cursor de entrada y se van
	// moviendo los desplazamientos de lo que no cupo.
	siguiente := seguir

	// La sucursal de la bajada se resuelve ARRIBA porque los pedidos la necesitan igual
	// que el tablero: el alcance va aparte y en AND, así que esto estrecha y nunca amplía.
	sucursal := sucursalDeLaBajada(r, a)

	tope := int32(topeDeLaBajada(q))
	ventana := alcance.VentanaDeBajada{
		Desde: desde, Hasta: hasta, Sucursal: sucursal, Tope: tope,
	}

	// --- Pedidos ------------------------------------------------------------
	//
	// LO PRIMERO, y no por orden alfabético: es lo que el logístico se baja cada mañana y
	// lo único sin lo cual el día sin conexión no existe.
	pedidos, corte, err := s.pedidosDeLaBajada(r, a, ventana)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	salida.Cambios["orders"] = pedidos
	if corte != nil {
		// NO CABE TODO. La marca que se devuelve deja de ser el reloj y pasa a ser la de
		// la última fila servida: el aparato vuelve a pedir desde ahí y se lleva el
		// resto. Devolverle el reloj entero sería decirle «ya lo tienes todo hasta ahora»
		// con media tanda sin mandar, y eso no se vuelve a pedir nunca.
		truncado = true
		if corte.Before(salida.Hasta) {
			salida.Hasta = *corte
		}
	}

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
			// LA TASA DE CAMBIO DE ESTA SUCURSAL, y de ninguna otra.
			//
			// Viaja DENTRO de la sucursal a propósito. Es un dato suyo —lo mantiene
			// Entrega, lo trae Accesos y lo deja aquí la tarea de fondo de
			// `refresco_de_tasas.go`— y el aparato tiene que poder pintar los importes en
			// CUP sin conexión, así que tiene que bajar con el resto del día.
			//
			// No va en `settings`, que es GLOBAL: una tasa sola para las ocho sucursales
			// es exactamente cómo Granma acabó enseñando los 685 de La Habana como si
			// fueran suyos.
			//
			// Los cuatro pueden venir null, y el que manda es `cupRateTraidoAt`: **la
			// marca de cuándo, no el número**. Sin ella no hay tasa que valga, porque el
			// esquema viejo traía 320 por defecto y un 320 no demuestra que nadie la haya
			// puesto.
			"cupRate":         b.CupRate,
			"cupRateFuente":   b.CupRateFuente,
			"cupRateTraidoAt": hora(b.CupRateTraidoAt),
			// La frescura la decide ACCESOS (allí son 24 h), no nosotros y no el aparato:
			// quien sabe cuándo una tasa está pasada es quien la mantiene. Aquí se copia
			// el booleano tal cual para que el aparato pueda avisar sin decidir nada.
			"cupRateFresca": b.CupRateFresca,
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
	productos, err := a.EspejoListarProductos(r.Context(), tope, seguir.Productos)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// LA TANDA SIGUIENTE EMPIEZA DONDE ACABÓ ÉSTA. Antes esto era
	// `truncado = truncado || len(productos) >= TopeDeBajada` y nada más: se decía que
	// quedaba más y no había por dónde seguir.
	if int32(len(productos)) >= tope {
		truncado = true
		siguiente.Productos = seguir.Productos + int32(len(productos))
	}
	puestos = nil
	for _, p := range productos {
		if !cambioDesde(p.UpdatedAt, desdeDelPadron) {
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
	clientes, err := a.EspejoListarClientes(r.Context(), tope, seguir.Clientes)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if int32(len(clientes)) >= tope {
		truncado = true
		siguiente.Clientes = seguir.Clientes + int32(len(clientes))
	}
	puestos = nil
	for _, c := range clientes {
		if !cambioDesde(c.SyncedAt, desdeDelPadron) {
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
	// `orders` YA NO ESTÁ AQUÍ: se sirve de verdad, arriba, por `DiferenciasDePedidos`.
	//
	// QUEDA `warehouses`, Y QUEDA DECLARADO — no vacío. La decisión, escrita para no
	// tener que volver a tomarla:
	//
	//   Los almacenes viven en ACCESOS, no en esta base, y esto sí se podría preguntar
	//   allí en cada bajada (`s.accesos.AlmacenesDeSucursal`). No se hace, y el motivo no
	//   es la llamada de red: es que **Accesos no da ninguna marca de cambio ni dice qué
	//   borró**. Sin marca no hay diferencias —habría que mandar la lista entera cada
	//   vez— y, sobre todo, sin saber qué se fue, `quitados` sería siempre `[]`: un
	//   almacén retirado en Accesos se quedaría en el aparato para siempre.
	//
	//   Y eso no es un defecto cosmético. Desde el almacén se mide lo que se le cobra al
	//   cliente por el domicilio; un almacén viejo que sigue en el teléfono cobra mal cada
	//   entrega del día y nadie lo nota hasta cuadrar la caja.
	//
	//   Así que se declara. El aparato puede decir en pantalla «los almacenes son los de
	//   la última vez que hubo red», que es la verdad, en vez de creerse al día.
	//
	//   QUÉ LO DESBLOQUEARÍA, por si alguien lo retoma: que Accesos devuelva un
	//   `actualizado_at` por almacén y un id estable siempre presente (hoy es opcional).
	//   Con eso, esta colección se sirve como las demás y se borra este comentario.
	//   Apuntado en `docs/integracion-pendiente.md`.
	salida.Faltan = append(salida.Faltan, "warehouses")
	if salida.Aviso != "" {
		salida.Aviso += "; "
	}
	salida.Aviso += "«warehouses» vive en Accesos, que no da marca de cambio ni dice qué " +
		"borró: se pide allí"

	salida.Truncado = truncado
	if truncado {
		// POR DÓNDE SEGUIR, siempre que se diga que queda más. Va incluso cuando lo que
		// quedó corto fueron los pedidos —que se continúan por `hasta`— porque el cursor
		// lleva además el `desde` original de la cadena, y sin él la tanda siguiente
		// filtraría el padrón de clientes contra una marca que ya avanzó y no emitiría
		// una sola fila.
		salida.Continuar = siguiente.escribir()
	}
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

// ---------------------------------------------------------------------------
// Los pedidos de la bajada
// ---------------------------------------------------------------------------

// pedidosDeLaBajada arma el conjunto `orders`: lo que cambió y lo que hay que borrar.
//
// Devuelve además LA MARCA DE CORTE cuando no cupo todo (nil si cupo): es la de la última
// fila servida, y quien contesta la usa como `hasta` para que el aparato vuelva a pedir
// justo desde ahí. Es lo que hace que un tope no pierda nada.
//
// LAS TRES REGLAS QUE SE CUMPLEN AQUÍ:
//
//  1. Un pedido tocado después de la marca sale; uno anterior, no. Eso lo decide el SQL,
//     que compara contra `cambiado_at` —el más nuevo del pedido y de sus renglones— y no
//     contra `updated_at` a secas.
//  2. UN PEDIDO ARCHIVADO SALE EN `quitados`, no en `puestos`. En PEDIDO archivar es el
//     borrado blando, y son la inmensa mayoría del histórico: dejarlo en `puestos` con su
//     bandera puesta confía en que el aparato la mire, y el día que no la mire el pedido
//     archivado sigue apareciendo en el tablero y alguien lo carga en el camión.
//  3. Los renglones VIAJAN CON SU PEDIDO. Si cambió una línea, lo que hay que mandar no es
//     un aviso: es la lista de mercancía nueva, o el despacho prepara lo de ayer.
func (s *Servidor) pedidosDeLaBajada(r *http.Request, a *alcance.Acotado, v alcance.VentanaDeBajada) (Conjunto, *time.Time, error) {
	ctx := r.Context()
	tope := int(v.Tope)

	// SE PIDE UNA FILA DE MÁS. Es la forma barata de distinguir «caben justo `tope`» de
	// «hay más y no caben»: con exactamente `tope` filas las dos son indistinguibles, y
	// dar por buena la primera deja al aparato sin volver a pedir lo que falta.
	sonda := v
	sonda.Tope = v.Tope + 1

	filas, err := a.EspejoDiferenciasDePedidos(ctx, sonda)
	if err != nil {
		return Conjunto{}, nil, err
	}
	filas, corte := recortarPorMarca(r, filas, tope, func(f sqlc.DiferenciasDePedidosRow) time.Time {
		return f.CambiadoAt.Time
	})

	puestos := make([]any, 0, len(filas))
	quitados := make([]string, 0)

	// Los renglones de una sola vez para toda la tanda, no uno por pedido: con 2.000
	// pedidos, lo segundo son 2.000 idas y vueltas por la conexión de allá.
	vivos := make([]uuid.UUID, 0, len(filas))
	for _, f := range filas {
		if !f.Archivado {
			vivos = append(vivos, f.ID)
		}
	}
	renglones := map[uuid.UUID][]any{}
	if len(vivos) > 0 {
		lineas, err := a.ListarRenglonesDePedidos(ctx, vivos)
		if err != nil {
			return Conjunto{}, nil, err
		}
		for _, l := range lineas {
			renglones[l.OrderID] = append(renglones[l.OrderID], map[string]any{
				"id": l.ID, "linea": l.Linea, "description": l.Description,
				"quantity": l.Quantity, "packs": l.Packs, "productId": idOpcional(l.ProductID),
				"updatedAt": hora(l.UpdatedAt),
			})
		}
	}

	for _, f := range filas {
		if f.Archivado {
			// Archivado en PEDIDO = fuera del aparato. Ver la regla 2 de arriba.
			quitados = append(quitados, f.ID.String())
			continue
		}
		items := renglones[f.ID]
		if items == nil {
			// Lista vacía y no `null`: el aparato recorre lo que llega, y en Dart un nulo
			// donde se espera una lista es una excepción en mitad de la sincronización.
			items = []any{}
		}
		puestos = append(puestos, map[string]any{
			"id":                 f.ID,
			"operationNumber":    f.OperationNumber,
			"customerName":       f.CustomerName,
			"customerPhone":      f.CustomerPhone,
			"address":            f.Address,
			"endAddress":         f.EndAddress,
			"endLat":             f.EndLat,
			"endLng":             f.EndLng,
			"lat":                f.Lat,
			"lng":                f.Lng,
			"weight":             f.Weight,
			"status":             string(f.Status),
			"tripLeg":            string(f.TripLeg),
			"notes":              f.Notes,
			"routeId":            idOpcional(f.RouteID),
			"ultimaRutaId":       idOpcional(f.UltimaRutaID),
			"vehicleId":          idOpcional(f.VehicleID),
			"price":              f.Price,
			"segmentKm":          f.SegmentKm,
			"deliveryPrice":      f.DeliveryPrice,
			"deliveryDistanceKm": f.DeliveryDistanceKm,
			"branchId":           idOpcional(f.BranchID),
			"source":             textoDe(f.Source),
			"externalId":         f.ExternalID,
			"orderDate":          hora(f.OrderDate),
			"estado":             textoDe(f.Estado),
			"archivado":          f.Archivado,
			"fechaComprometida":  hora(f.FechaComprometida),
			"requiereDomicilio":  f.RequiereDomicilio,
			"pedidoCosto":        f.PedidoCosto,
			"municipio":          f.Municipio,
			"vendedor":           f.Vendedor,
			"sucursalCodigo":     f.SucursalCodigo,
			"facturaEstado":      textoDe(f.FacturaEstado),
			"facturaNumero":      f.FacturaNumero,
			"facturaDomicilio":   f.FacturaDomicilio,
			"stopOrder":          f.StopOrder,
			"deliveredAt":        hora(f.DeliveredAt),
			"resultado":          textoDe(f.Resultado),
			"resultadoNota":      f.ResultadoNota,
			"items":              items,
			// La marca que el aparato guarda para la próxima vez. Es `cambiado_at` y NO
			// `updated_at`: con la del pedido a secas, un pedido al que sólo le cambió un
			// renglón volvería a salir en cada bajada para siempre.
			"updatedAt": hora(f.CambiadoAt),
		})
	}

	// --- Lo que se fue ------------------------------------------------------
	//
	// EN LA CARGA INICIAL NO SE PREGUNTA. El aparato empieza vacío: no hay nada que
	// quitarle, y mandarle los borrados de los últimos dos años es gastarle la conexión
	// en decirle que borre lo que nunca tuvo.
	if v.Desde != nil {
		salidas, err := a.EspejoPedidosQueSalieron(ctx, sonda)
		if err != nil {
			return Conjunto{}, nil, err
		}
		salidas, corteSalidas := recortarPorMarca(r, salidas, tope,
			func(f sqlc.PedidosQueSalieronDelAlcanceRow) time.Time { return f.SalioAt.Time })
		for _, f := range salidas {
			quitados = append(quitados, f.OrderID.String())
		}
		// De los dos cortes manda EL MÁS ATRASADO: la marca que se devuelve tiene que ser
		// una que las dos listas hayan servido enteras. Con la más nueva, lo que quedó sin
		// mandar de la otra cae por debajo del próximo `desde` y no se pide nunca más.
		corte = laMasAtrasada(corte, corteSalidas)
	}

	return Conjunto{Puestos: puestos, Quitados: quitados}, corte, nil
}

// recortarPorMarca deja la tanda en `tope` filas y dice por qué marca se cortó.
//
// Devuelve nil como marca cuando cupo todo — que es el caso normal y el que no lleva
// `truncado`.
//
// EL DETALLE QUE PARECE UN ADORNO Y NO LO ES: el corte no puede partir un grupo de filas
// que comparten la misma marca. Postgres le pone a todas las filas de una transacción la
// MISMA hora (`now()` es la del inicio de la transacción), así que una tanda del espejo de
// 200 pedidos son 200 filas con el mismo `updated_at` al microsegundo. Si el corte cayera
// en medio y se devolviera esa marca como `hasta`, la próxima bajada pediría «a partir de
// ahí» y las que quedaron dentro del grupo no saldrían nunca más. Por eso se recorta el
// grupo entero y se corta por la marca anterior.
func recortarPorMarca[T any](r *http.Request, filas []T, tope int, marca func(T) time.Time) ([]T, *time.Time) {
	if tope <= 0 || len(filas) <= tope {
		return filas, nil
	}
	primeraQueNoCabe := marca(filas[tope])
	servidas := filas[:tope]
	ultima := marca(servidas[tope-1])

	if primeraQueNoCabe.After(ultima) {
		// El grupo de `ultima` está entero dentro. Se corta limpio por ahí.
		return servidas, &ultima
	}

	// El grupo está partido: fuera entero.
	i := tope - 1
	for i >= 0 && !marca(servidas[i]).Before(ultima) {
		i--
	}
	if i < 0 {
		// TODA la tanda comparte una sola marca y aun así no cabe: una sola transacción
		// escribió más pedidos que el tope. No hay corte posible que no parta el grupo, así
		// que se sirve lo que cabe y SE DEJA DICHO — es el único caso en que esta bajada
		// puede dejarse filas atrás, y tiene que verse en el registro y no adivinarse.
		httpx.Registro(r).Warn("una sola marca no cabe en el tope de la bajada: puede perderse parte de la tanda",
			"marca", ultima, "tope", tope)
		return servidas, &ultima
	}
	corte := marca(servidas[i])
	return servidas[:i+1], &corte
}

// laMasAtrasada: de dos cortes, el que menos avanza. Nil es «no hubo corte», así que no
// limita nada y gana el otro.
func laMasAtrasada(a, b *time.Time) *time.Time {
	switch {
	case a == nil:
		return b
	case b == nil:
		return a
	case b.Before(*a):
		return b
	default:
		return a
	}
}

// topeDeLaBajada: cuántas filas por colección y por tanda.
//
// Se admite del que llama —el sincronizador lo manda, porque es quien sabe la conexión que
// hay— pero ACOTADO. Un tope de cero o negativo se traga la tanda entera sin `truncado` y
// el aparato se queda sin la mitad del día creyendo que lo tiene todo; uno enorme es
// pedirle a la conexión de allá algo que no va a terminar nunca.
func topeDeLaBajada(q url.Values) int {
	n, err := strconv.Atoi(strings.TrimSpace(q.Get("tope")))
	if err != nil || n <= 0 {
		return TopeDeBajada
	}
	return min(n, TopeDeBajada)
}
