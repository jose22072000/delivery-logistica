// LA COTIZACIÓN. Las cuatro rutas de `/api/quote` y `/api/tasa`.
//
// AQUÍ UN ERROR NO REVIENTA: DA UN NÚMERO DISTINTO, y nadie se entera hasta que no cuadra
// la caja. Por eso las cuentas NO están en este fichero: viven en `internal/cotizar`, que
// es un paquete de funciones puras con pruebas de tabla —entrada concreta, salida
// concreta— sacadas de correr las fórmulas del pliego en Node. Este fichero sólo hace de
// puerta: valida el cuerpo en el ORDEN del contrato, busca los datos y llama a la fórmula.
//
// Pliego: `../../../docs/reglas-negocio.md` §1 (geometría), §2 (pesos y armado del Order),
// §7 (el costo del domicilio), §8 (la tasa), §10 (almacenes); y `docs/contratos-api.md`
// para las cuatro rutas, sus códigos y sus mensajes literales.
//
// LA REGLA DE FONDO DE TODO ESTO: **el precio del domicilio lo pone la APK de Entrega y
// nadie más.** Aquí no se calcula un precio propio: `/api/quote` está retirado y el
// `price` del lote es SIEMPRE null. Lo único que se calcula es el costo de UN domicilio
// (`/api/quote/home-delivery`) y se calcula con la fórmula de Entrega, calcada, para que
// un pedido metido a mano salga por el mismo número que uno hecho desde el teléfono.
package api

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/cotizar"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// ---------------------------------------------------------------------------
// Mensajes literales del contrato
// ---------------------------------------------------------------------------
//
// Salen tal cual de `docs/contratos-api.md`. Se enseñan en la pantalla del logístico y
// hay quien los compara, así que no se tocan ni se «mejoran».
//
// Por el patrón (ver la cabecera de `servidor.go`) su sitio natural es `internal/httpx`,
// con los demás. Están aquí porque este encargo no toca ese fichero; al primer cambio de
// `httpx/respuesta.go` se mueven allí y se borran de aquí.
const (
	msgCotizadorRetirado = "El cotizador individual se retiró. El costo del domicilio lo pone Entrega y lo escribe en PEDIDO. Para el reparto de carga de delivery, usa POST /api/quote/batch."
	msgLoteSinPedidos    = "Se espera { orders: [...] }"
	msgFaltaSucursal     = "Falta sucursalCodigo"
	msgFaltaUbicacion    = "Falta la ubicación del cliente (lat/lng)"
	msgFaltaPeso         = "Falta el peso (pesoKg > 0)"
	msgSinCalculo        = "No se pudo calcular con los datos que hay"

	// Los que llevan el código o el nombre de la sucursal dentro. Se nombra SIEMPRE a la
	// sucursal: «no hay tasa» a secas obliga a adivinar cuál de las ocho falta.
	msgSucursalDesconocidaF = "No hay sucursal con código %s"
	msgSinAlmacenF          = "%s no tiene ningún almacén con coordenadas"
	msgSinTasaEnAccesosF    = "No hay tasa de cambio de %s en Accesos"
	msgSinTarifaEnEntregaF  = "No hay tarifa base de %s en Entrega"

	// Avisos de `/api/tasa`. Son 200, no errores: que falte la tasa es un estado normal.
	avisoVariasSucursales = "Elegí una sucursal arriba para ver los importes en CUP: cada una tiene su tasa."
	avisoSinTasaF         = "%s no tiene tasa de cambio todavía: los importes sólo se pueden ver en USD."
	avisoTasaViejaF       = "La tasa es del %s y puede estar desfasada."
	// El sujeto del aviso cuando la sucursal del alcance no tiene nombre.
	sucursalSinNombre = "Esta sucursal"
)

// ---------------------------------------------------------------------------
// La tasa y la tarifa: de Entrega, por Accesos
// ---------------------------------------------------------------------------
//
// LA TASA SE PIDE A ACCESOS, NO SE TECLEA AQUÍ (§8). Antes vivía en Configuración →
// «Monedas»: alguien escribía un número a mano y ése usaba toda la aplicación, mientras
// PEDIDO la traía de Entrega. *Dos tasas para lo mismo se separan en cuanto una se olvida
// —y se olvida, porque la de aquí no la refresca nadie—, y el mismo domicilio vale
// distinto según dónde se mire. Eso no falla en pantalla: sale un importe creíble y cuadra
// mal en la caja, que es donde se descubre tarde.*
//
// De los almacenes se encarga `Accesos` (ver `almacenes.go`): NO se abre aquí un segundo
// cliente ni una segunda caché, que sería el mismo error otra vez con otro dato.

// RutaTasasDeAccesos es el endpoint de las tasas. Accesos contesta **200 con `tasa: null`**
// cuando esa sucursal no tiene: que falte es un estado normal, no un error, y por eso no
// viene como 404.
const RutaTasasDeAccesos = "/api/service/tasas"

// ClienteTasas es por dónde se piden las tasas. Interfaz para que las pruebas no tengan
// que levantar un Accesos, igual que `ClienteAccesos`.
type ClienteTasas interface {
	// TasaDeSucursal devuelve (nil, nil) cuando Accesos dice que esa sucursal no tiene.
	TasaDeSucursal(ctx context.Context, codigo string) (*cotizar.Tasa, error)
}

// Tasas es el cliente que usan los manejadores. Variable de paquete por lo mismo que
// `Accesos`: `servidor.go` no se toca en este cambio.
var Tasas ClienteTasas = &tasasDeAccesos{}

// tasasDeAccesos reutiliza la FIRMA del cliente de almacenes. Accesos no acepta una clave
// suelta en una cabecera: cada aplicación firma con SU llave sobre método, ruta, hora,
// nonce y hash del cuerpo. Aquí no se vuelve a escribir esa firma —una segunda copia es
// una segunda forma de que deje de cuadrar—, se usa la que ya hay.
type tasasDeAccesos struct{ firmante accesosHTTP }

func (t *tasasDeAccesos) TasaDeSucursal(ctx context.Context, codigo string) (*cotizar.Tasa, error) {
	ruta := RutaTasasDeAccesos + "?codigo=" + url.QueryEscape(codigo)
	crudo, err := t.firmante.pedirFirmado(ctx, http.MethodGet, ruta, nil, 10*time.Second)
	if err != nil {
		return nil, err
	}
	var b struct {
		Tasa       json.RawMessage `json:"tasa"`
		Codigo     *string         `json:"codigo"`
		CupPorUsd  *float64        `json:"cupPorUsd"`
		TarifaBase *float64        `json:"tarifaBase"`
		Fuente     *string         `json:"fuente"`
		TraidoAt   *string         `json:"traidoAt"`
		Fresca     *bool           `json:"fresca"`
	}
	if err := json.Unmarshal(crudo, &b); err != nil {
		return nil, fmt.Errorf("Accesos contestó algo que no se entiende: %w", err)
	}
	// Dos formas de decir «no hay»: `tasa: null`, o un `cupPorUsd` que no es un número.
	// Sin tasa no se convierte nada, y NO se echa mano de la de otra sucursal.
	if esNuloJSON(b.Tasa) || b.CupPorUsd == nil {
		return nil, nil
	}
	cod := strings.ToUpper(codigo)
	if b.Codigo != nil {
		cod = *b.Codigo
	}
	traido := ""
	if b.TraidoAt != nil {
		traido = *b.TraidoAt
	}
	return &cotizar.Tasa{
		Codigo:    cod,
		CupPorUsd: *b.CupPorUsd,
		// `tarifaBase` sólo si es número; si no, nil. Un 0 se rechaza más adelante en la
		// fórmula, que es donde tiene que rechazarse.
		TarifaBase: b.TarifaBase,
		Fuente:     b.Fuente,
		TraidoAt:   traido,
		// AUSENTE SIGNIFICA FRESCA: `fresca = (b.fresca !== false)`. Quien decide si la
		// tasa está pasada es ACCESOS, no este servicio.
		Fresca: b.Fresca == nil || *b.Fresca,
	}, nil
}

func esNuloJSON(v json.RawMessage) bool {
	s := strings.TrimSpace(string(v))
	return s == "" || s == "null"
}

// CatalogoDePesos baja el catálogo local de pesos (§5) para el lote. Es el RESPALDO: sólo
// se llama cuando alguna línea del lote no trae peso de PEDIDO. Mientras no esté montado,
// esas líneas se quedan sin peso y el lote lo dice en `weightsSource: "none"` — que es
// mejor que un peso inventado, porque con el peso se cobra y se carga el camión.
var CatalogoDePesos func(ctx context.Context) (cotizar.Catalogo, error)

// GuardarPedidoDelEspejo escribe el pedido del lote (§2.3). Lo monta el manejador del
// espejo de PEDIDO, que es quien tiene las consultas de `orders` y sus renglones.
// Mientras no esté, el lote COTIZA pero no persiste, y cada resultado lo dice.
var GuardarPedidoDelEspejo func(ctx context.Context, a *alcance.Acotado, p PedidoParaGuardar) (uuid.UUID, error)

// recuerdoDeTasas es la caché del proceso (§8): 5 min para una tasa que existe, 20 s para
// el «no hay». Una sola para todo el servicio, porque el lote de 200 pedidos pregunta la
// tasa de su sucursal una vez por pedido.
var recuerdoDeTasas = cotizar.NuevoRecuerdoDeTasas(func(ctx context.Context, codigo string) (*cotizar.Tasa, error) {
	return Tasas.TasaDeSucursal(ctx, codigo)
}, nil)

// almacenesDeCotizacion pide los almacenes con el `.catch(() => [])` que hace la ruta de
// Next: si Accesos falla, la lista queda VACÍA y el camino sigue hasta el 409 con el
// nombre de la sucursal dentro, que es lo que el contrato manda enseñar. Nunca se contesta
// un número aproximado: un importe aproximado se cobra igual que uno bueno.
func almacenesDeCotizacion(ctx context.Context, r *http.Request, codigo string) []cotizar.Almacen {
	crudos, err := Accesos.AlmacenesDeSucursal(ctx, codigo)
	if err != nil {
		httpx.Registro(r).Warn("Accesos no dio los almacenes: se sigue como si no hubiera",
			"sucursal", codigo, "err", err)
		return nil
	}
	// `api.Almacen` es la forma en la que llega de Accesos; `cotizar.Almacen` es la que
	// entiende la fórmula. La traducción va aquí y no en `cotizar` para que ese paquete
	// siga sin saber nada de HTTP ni de Accesos.
	salida := make([]cotizar.Almacen, 0, len(crudos))
	for _, a := range crudos {
		id := ""
		if a.ID != nil {
			id = *a.ID
		}
		salida = append(salida, cotizar.Almacen{
			ID: id, Nombre: a.Nombre, Direccion: a.Direccion,
			Latitud: a.Latitud, Longitud: a.Longitud,
			Principal: a.Principal, Activo: a.Activo,
		})
	}
	return salida
}

// ---------------------------------------------------------------------------
// Montaje
// ---------------------------------------------------------------------------

// rutasCotizacion monta las cuatro rutas. La llama `Rutas()` en `servidor.go`.
//
// `admin` no se usa: aquí no hay nada reservado a administradores. El lote y el domicilio
// son de SERVICIO (el espejo de PEDIDO, que no es una persona) y `/api/tasa` es de
// cualquiera con sesión, porque es sólo mirar.
func (s *Servidor) rutasCotizacion(rt *httpx.Router, sesion, admin []httpx.Medio) {
	_ = admin

	// La puerta del espejo: `x-api-key`, un actor sintético para que el alcance se pueda
	// resolver, y el alcance. En este orden.
	servicio := []httpx.Medio{
		auth.LlaveDeServicio(s.cfg.ServiceAPIKey),
		soloServicioDeCotizacion,
		s.porteria.Exigir,
	}

	// SIN AUTH Y SIN CUERPO: contesta 410 a todo el mundo. Pedir llave para decir «esto se
	// retiró» sólo consigue que quien todavía llama vea un 401 y crea que es de permisos.
	rt.ManejarFunc(http.MethodPost, "/api/quote", s.cotizadorRetirado)

	rt.ManejarFunc(http.MethodPost, "/api/quote/batch", s.cotizarLote, servicio...)
	rt.ManejarFunc(http.MethodPost, "/api/quote/home-delivery", s.cotizarDomicilio, servicio...)

	rt.ManejarFunc(http.MethodGet, "/api/tasa", s.tasaDelAlcance, sesion...)
}

// soloServicioDeCotizacion cuelga una persona sintética para que la portería pueda resolver el
// alcance: sin persona, `Porteria.Resolver` devuelve error y la ruta daría 500.
//
// SIN SUCURSAL, que es lo que el contrato pide para estas dos rutas («sin alcance por
// sucursal»): el espejo trae pedidos de las ocho y tiene que poder escribirlos todos.
//
// Y SE BORRA LA CABECERA `X-Sucursal-Id` ANTES DE RESOLVER. Si no, quien tenga la llave de
// servicio podría acotarse a una sucursal mandando esa cabecera, y entonces el lote
// nocturno de PEDIDO se comería en silencio los pedidos de las otras siete: cero errores,
// cero pedidos, y nadie mirando.
func soloServicioDeCotizacion(siguiente http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.Header.Del(alcance.CabeceraSucursal)
		u := &auth.Usuario{ID: "servicio:pedido", Nombre: "servicio"}
		siguiente.ServeHTTP(w, r.WithContext(auth.ConUsuario(r.Context(), u)))
	})
}

// ---------------------------------------------------------------------------
// POST /api/quote — RETIRADO
// ---------------------------------------------------------------------------

// cotizadorRetirado contesta 410 siempre, e ignora el cuerpo por completo.
//
// POR QUÉ 410 Y NO BORRAR LA RUTA: un 404 se lee como «me equivoqué de dirección» y quien
// llamaba se pone a buscar la buena. El 410 con este texto dice lo que pasó y a dónde ir.
// La razón de fondo está en §1: éste era la SEGUNDA fórmula viva del domicilio, y *el
// mismo pedido costaba una cosa entrando por el espejo y otra entrando a mano*.
func (s *Servidor) cotizadorRetirado(w http.ResponseWriter, r *http.Request) {
	httpx.Error(w, r, http.StatusGone, msgCotizadorRetirado)
}

// ---------------------------------------------------------------------------
// POST /api/quote/home-delivery — el costo de UN domicilio
// ---------------------------------------------------------------------------

type cuerpoDomicilio struct {
	SucursalCodigo string         `json:"sucursalCodigo"`
	Lat            cotizar.Numero `json:"lat"`
	Lng            cotizar.Numero `json:"lng"`
	PesoKg         cotizar.Numero `json:"pesoKg"`
}

type domicilioSalida struct {
	DistanciaKm float64 `json:"distanciaKm"`
	PesoKg      float64 `json:"pesoKg"`
	USD         float64 `json:"usd"`
	CUP         float64 `json:"cup"`
	TarifaUsd   float64 `json:"tarifaUsd"`
	Desde       string  `json:"desde"`
	Almacen     *string `json:"almacen"`
	Sucursal    string  `json:"sucursal"`
}

// cotizarDomicilio es la única ruta que calcula un importe, y lo calcula con la fórmula de
// Entrega calcada: tarifa base (CUP/km·kg) ÷ tasa × distancia × peso.
//
// LAS VALIDACIONES VAN EN EL ORDEN DEL CONTRATO y no en otro. No es capricho: el mensaje
// que sale es el del PRIMER fallo, y quien lo lee corrige eso. Reordenarlas cambia qué se
// le dice al que llama.
func (s *Servidor) cotizarDomicilio(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}

	c := leerCuerpoDomicilio(r)

	// 1. El código de la sucursal, normalizado. Es la clave que cruza las aplicaciones.
	codigo := strings.ToUpper(strings.TrimSpace(c.SucursalCodigo))
	if codigo == "" {
		httpx.Error(w, r, http.StatusBadRequest, msgFaltaSucursal)
		return
	}
	// 2. La ubicación del cliente.
	if !c.Lat.Finito() || !c.Lng.Finito() {
		httpx.Error(w, r, http.StatusBadRequest, msgFaltaUbicacion)
		return
	}
	// 3. El peso. Aquí sí se exige > 0: un domicilio de 0 kg no es un domicilio, es un
	// pedido al que todavía no se le resolvió el peso, y cotizarlo daría 0 —que se lee
	// como gratis— en vez de decir que falta el dato.
	if !c.PesoKg.Finito() || c.PesoKg.Valor <= 0 {
		httpx.Error(w, r, http.StatusBadRequest, msgFaltaPeso)
		return
	}

	// 4. La sucursal.
	suc, err := sucursalParaCotizar(r.Context(), a, codigo)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if suc == nil {
		httpx.Error(w, r, http.StatusNotFound, fmt.Sprintf(msgSucursalDesconocidaF, codigo))
		return
	}

	// 5. El almacén de origen. ES DESDE DONDE SALE LA MERCANCÍA, que es lo que mide la
	// APK; las coordenadas de la SUCURSAL no valen para esto.
	almacen := cotizar.ElegirAlmacen(almacenesDeCotizacion(r.Context(), r, codigo))
	if almacen == nil {
		httpx.Error(w, r, http.StatusConflict, fmt.Sprintf(msgSinAlmacenF, suc.Name))
		return
	}

	// 6 y 7. Tasa y tarifa, las dos de ESTA sucursal. Nunca las de otra: convertir un
	// importe de Granma con la tasa de La Habana da un número creíble que nadie cuestiona.
	tasa := recuerdoDeTasas.DeSucursal(r.Context(), codigo)
	if tasa == nil || tasa.CupPorUsd <= 0 {
		httpx.Error(w, r, http.StatusConflict, fmt.Sprintf(msgSinTasaEnAccesosF, codigo))
		return
	}
	if tasa.TarifaBase == nil {
		httpx.Error(w, r, http.StatusConflict, fmt.Sprintf(msgSinTarifaEnEntregaF, codigo))
		return
	}

	// 8. La cuenta.
	km := cotizar.DistanciaEntre(almacen.Punto(), cotizar.Punto{Lat: c.Lat.Valor, Lng: c.Lng.Valor})
	costo := cotizar.CostoDomicilioEntrega(*tasa.TarifaBase, tasa.CupPorUsd, km, c.PesoKg.Valor)
	if costo == nil {
		// La fórmula devuelve nil y NUNCA cero, así que llegar aquí es «no se sabe».
		httpx.Error(w, r, http.StatusConflict, msgSinCalculo)
		return
	}

	var nombreAlmacen *string
	if almacen.Nombre != "" {
		n := almacen.Nombre
		nombreAlmacen = &n
	}
	httpx.JSON(w, r, http.StatusOK, domicilioSalida{
		DistanciaKm: costo.DistanciaKm,
		PesoKg:      costo.PesoKg,
		USD:         costo.USD,
		CUP:         costo.CUP,
		TarifaUsd:   costo.TarifaUsd,
		// `desde` dice con qué se midió. Si mañana se midiera desde otro punto, los
		// importes viejos siguen explicándose solos.
		Desde:    "almacen:" + codigo,
		Almacen:  nombreAlmacen,
		Sucursal: suc.Name,
	})
}

// leerCuerpoDomicilio decodifica con la tolerancia de la ruta de Next: **si el cuerpo no
// parsea, se sigue con `{}`** y el fallo sale como «Falta sucursalCodigo», que es un
// mensaje que se entiende, en vez de un «cuerpo no válido» que no dice qué falta.
//
// Los tres numéricos arrancan en «no vino» (NaN) a propósito: ver `cotizar.Numero`. Con el
// cero de Go, un `lat` ausente pasaría la validación y se cotizaría desde el golfo de
// Guinea.
func leerCuerpoDomicilio(r *http.Request) cuerpoDomicilio {
	vacio := cuerpoDomicilio{Lat: cotizar.NoVino(), Lng: cotizar.NoVino(), PesoKg: cotizar.NoVino()}
	defer r.Body.Close()
	crudo, err := io.ReadAll(io.LimitReader(r.Body, maxCuerpoCotizacion))
	if err != nil {
		return vacio
	}
	c := vacio
	if err := json.Unmarshal(crudo, &c); err != nil {
		return vacio
	}
	return c
}

// maxCuerpoCotizacion: el mismo tope que `httpx.LeerJSON`. Un lote del espejo cabe de
// sobra; lo que no cabe es el intento de tumbar el proceso a base de memoria.
const maxCuerpoCotizacion = 8 << 20 // 8 MiB

// ---------------------------------------------------------------------------
// GET /api/tasa — qué tasa está usando quien mira
// ---------------------------------------------------------------------------

type tasaVariasSucursales struct {
	Tasa    *float64 `json:"tasa"`   // siempre null
	Motivo  string   `json:"motivo"` // "varias-sucursales"
	Aviso   string   `json:"aviso"`
	SinTasa []string `json:"sinTasa"`
}

type tasaAusente struct {
	Tasa     *float64 `json:"tasa"`   // siempre null
	Motivo   string   `json:"motivo"` // "sin-tasa"
	Sucursal *string  `json:"sucursal"`
	Aviso    string   `json:"aviso"`
}

type tasaPresente struct {
	Tasa     float64 `json:"tasa"`
	Fuente   *string `json:"fuente"`
	TraidoAt string  `json:"traidoAt"`
	Fresca   bool    `json:"fresca"`
	Sucursal *string `json:"sucursal"`
	Aviso    *string `json:"aviso"`
}

// tasaDelAlcance contesta 200 SIEMPRE. Que falte la tasa no es un error de nadie: es un
// estado normal que alguien está arreglando en Entrega, y la pantalla tiene que poder
// enseñar los importes en USD mientras tanto.
func (s *Servidor) tasaDelAlcance(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	sucursales, err := a.ListarSucursalesVisibles(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	// --- Sin alcance: el Super Admin mirando las ocho -------------------------
	//
	// NO se elige ninguna tasa. Enseñar la de una sucursal cualquiera cuando se están
	// viendo todas es justo el error que más daño hace: un importe creíble convertido con
	// la tasa que no era.
	if a.Todas() {
		sin := []string{}
		for _, b := range sucursales {
			if b.ExternalID == nil || strings.TrimSpace(*b.ExternalID) == "" {
				continue // sin código no hay nada que preguntarle a Accesos
			}
			if t := recuerdoDeTasas.DeSucursal(r.Context(), *b.ExternalID); t == nil {
				sin = append(sin, b.Name)
			}
		}
		httpx.JSON(w, r, http.StatusOK, tasaVariasSucursales{
			Motivo: "varias-sucursales", Aviso: avisoVariasSucursales, SinTasa: sin,
		})
		return
	}

	// --- Con alcance ----------------------------------------------------------
	var nombre *string
	if id := a.Sucursal(); id != nil {
		for _, b := range sucursales {
			if b.ID == *id {
				n := b.Name
				nombre = &n
				break
			}
		}
	}

	var tasa *cotizar.Tasa
	if cod := a.Codigo(); cod != nil {
		tasa = recuerdoDeTasas.DeSucursal(r.Context(), *cod)
	}
	if tasa == nil {
		// El sujeto del aviso: el nombre si se sabe, «Esta sucursal» si no.
		quien := sucursalSinNombre
		if nombre != nil && *nombre != "" {
			quien = *nombre
		}
		httpx.JSON(w, r, http.StatusOK, tasaAusente{
			Motivo: "sin-tasa", Sucursal: nombre, Aviso: fmt.Sprintf(avisoSinTasaF, quien),
		})
		return
	}

	// `fresca` la decide ACCESOS, no este servicio. Cuando dice que no, se avisa con la
	// fecha: una tasa de hace tres semanas convierte, pero quien mira tiene que saberlo.
	var aviso *string
	if !tasa.Fresca {
		v := fmt.Sprintf(avisoTasaViejaF, fechaCortaEs(tasa.TraidoAt))
		aviso = &v
	}
	httpx.JSON(w, r, http.StatusOK, tasaPresente{
		Tasa: tasa.CupPorUsd, Fuente: tasa.Fuente, TraidoAt: tasa.TraidoAt,
		Fresca: tasa.Fresca, Sucursal: nombre, Aviso: aviso,
	})
}

// fechaCortaEs imita `new Date(traidoAt).toLocaleDateString('es')`: d/m/aaaa, SIN ceros a la
// izquierda. Si la fecha no se puede leer se devuelve tal cual vino, que es más útil que
// un "Invalid Date" y deja ver qué mandó Accesos.
func fechaCortaEs(iso string) string {
	t, err := time.Parse(time.RFC3339, iso)
	if err != nil {
		return iso
	}
	l := t.Local()
	return fmt.Sprintf("%d/%d/%d", l.Day(), int(l.Month()), l.Year())
}

// ---------------------------------------------------------------------------
// POST /api/quote/batch — el espejo de PEDIDO
// ---------------------------------------------------------------------------

type cuerpoLote struct {
	// `preview` se compara como TRUTHY, no como booleano estricto: en la de Next vale
	// tanto `true` como `1` o `"si"`. Por eso llega crudo.
	Preview json.RawMessage `json:"preview"`
	// `useWarehouseWeights !== false`: ausente o null SÍ deja bajar el catálogo.
	UseWarehouseWeights *bool `json:"useWarehouseWeights"`
	// Puntero para poder distinguir «no vino» de «vino vacío»: sin `orders` es un 400,
	// con `orders: []` es un lote de cero pedidos, que es legítimo.
	Orders *[]pedidoDelLote `json:"orders"`
}

type pedidoDelLote struct {
	ExternalID         string            `json:"externalId"`
	OperationNumber    string            `json:"operationNumber"`
	SucursalExternalID string            `json:"sucursalExternalId"`
	CustomerName       string            `json:"customerName"`
	Address            string            `json:"address"`
	Phone              string            `json:"phone"`
	Lat                *float64          `json:"lat"`
	Lng                *float64          `json:"lng"`
	Weight             cotizar.Numero    `json:"weight"`
	RequiereDomicilio  *bool             `json:"requiereDomicilio"`
	FacturaEstado      *string           `json:"facturaEstado"`
	OrderDate          *string           `json:"orderDate"`
	Archivado          *bool             `json:"archivado"`
	PedidoCosto        *float64          `json:"pedidoCosto"`
	Municipio          *string           `json:"municipio"`
	Vendedor           *string           `json:"vendedor"`
	Items              []cotizar.Renglon `json:"items"`
	Meta               json.RawMessage   `json:"meta"`
}

type sucursalDelLote struct {
	ID   uuid.UUID `json:"id"`
	Name string    `json:"name"`
}

type baseDelLote struct {
	Ref        *string         `json:"ref"`
	Status     string          `json:"status"`
	Reason     string          `json:"reason,omitempty"`
	DistanceKm float64         `json:"distanceKm"`
	WeightKg   float64         `json:"weightKg"`
	Branch     sucursalDelLote `json:"branch"`
	OrderID    *string         `json:"orderId,omitempty"`
	Persisted  *bool           `json:"persisted,omitempty"`
}

// loteCotizado es el resultado de un pedido que SÍ lleva domicilio. `price` se emite
// siempre y siempre vale null: delivery ya no cotiza. Un 0 ahí se suma, se ordena y se lee
// como «este domicilio es gratis», que es peor que decir que no se sabe.
type loteCotizado struct {
	baseDelLote
	Price *float64 `json:"price"`
}

// loteSaltado es el resultado de los rechazos de los pasos 1 a 4: ni distancia, ni peso,
// ni sucursal, porque justamente es lo que no se pudo resolver.
type loteSaltado struct {
	Ref    *string `json:"ref"`
	Status string  `json:"status"`
	Reason string  `json:"reason"`
}

type loteSalida struct {
	Total         int    `json:"total"`
	Quoted        int    `json:"quoted"`
	Persisted     int    `json:"persisted"`
	Skipped       int    `json:"skipped"`
	WeightsSource string `json:"weightsSource"`
	Currency      string `json:"currency"`
	Results       []any  `json:"results"`
}

// cotizarLote es el espejo: PEDIDO manda tandas de pedidos y aquí se les resuelve el peso
// y la distancia, y se guardan.
//
// NO SE LES PONE PRECIO. `price` es null en todos, siempre. Lo que se cobra es
// `pedidoCosto`, el costo que la APK de Entrega escribió EN PEDIDO.
func (s *Servidor) cotizarLote(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}

	var c cuerpoLote
	defer r.Body.Close()
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxCuerpoCotizacion))
	if err := dec.Decode(&c); err != nil || c.Orders == nil {
		httpx.Error(w, r, http.StatusBadRequest, msgLoteSinPedidos)
		return
	}
	pedidos := *c.Orders
	preview := esVerdaderoJS(c.Preview)

	// --- El catálogo de pesos, sólo si hace falta -----------------------------
	//
	// Se baja ÚNICAMENTE si alguna línea del lote no trae peso de PEDIDO. Bajarlo siempre
	// es traerse el catálogo entero de Ventra por la conexión de allá para no usarlo.
	faltaAlgunPeso := false
	for _, p := range pedidos {
		for _, it := range p.Items {
			if !it.PesoLineaKg.Positivo() && !it.PesoKg.Positivo() {
				faltaAlgunPeso = true
				break
			}
		}
		if faltaAlgunPeso {
			break
		}
	}
	var catalogo cotizar.Catalogo
	// `useWarehouseWeights !== false`: ausente o null deja bajarlo.
	quiereCatalogo := c.UseWarehouseWeights == nil || *c.UseWarehouseWeights
	if faltaAlgunPeso && quiereCatalogo && CatalogoDePesos != nil {
		if cat, err := CatalogoDePesos(r.Context()); err != nil {
			httpx.Registro(r).Warn("no se pudo bajar el catálogo de pesos: se sigue sin él", "err", err)
		} else {
			catalogo = cat
		}
	}
	// `'warehouse'` está declarado en el contrato pero no se emite nunca; se conserva la
	// rareza porque hay quien lee este campo.
	fuentePesos := "pedido"
	if faltaAlgunPeso {
		fuentePesos = "none"
		if catalogo != nil {
			fuentePesos = "mixto"
		}
	}

	// --- Las sucursales, indexadas por su código ------------------------------
	//
	// Una sola lectura para todo el lote. En la de Next esto era un `findUnique` por
	// pedido con caché por `externalId`; con 200 pedidos y ocho sucursales, traerlas de
	// golpe es lo mismo y se lee mejor.
	sucursales, err := a.ListarSucursalesVisibles(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	porCodigo := map[string]sqlc.ListarSucursalesRow{}
	for _, b := range sucursales {
		if b.ExternalID != nil {
			porCodigo[*b.ExternalID] = b
		}
	}

	salida := loteSalida{
		// `quoted` es SIEMPRE 0: la variable se declara y nunca se incrementa. Está
		// inventariado en el contrato, así que se conserva la rareza en vez de
		// «arreglarla» y romper a quien la lee.
		Quoted:        0,
		WeightsSource: fuentePesos,
		Currency:      "USD",
		Results:       []any{},
	}

	for _, p := range pedidos {
		salida.Total++
		ref := refDelPedidoDelLote(p)

		// 1. Sin coordenadas no hay reparto posible: no se puede ordenar la ruta ni medir
		//    la distancia. `== null` flojo: un 0 es una coordenada válida.
		if p.Lat == nil || p.Lng == nil {
			salida.Skipped++
			salida.Results = append(salida.Results, loteSaltado{ref, "skipped", "sin-geolocalizacion"})
			continue
		}
		// 2. La sucursal tiene que estar mapeada, o el pedido no es de nadie.
		suc, hay := porCodigo[p.SucursalExternalID]
		if p.SucursalExternalID == "" || !hay {
			salida.Skipped++
			salida.Results = append(salida.Results, loteSaltado{ref, "skipped", "sucursal-no-mapeada"})
			continue
		}
		// 3. Sin punto de partida no se puede armar ruta desde esa sucursal.
		if !suc.OriginConfigured {
			salida.Skipped++
			salida.Results = append(salida.Results, loteSaltado{ref, "skipped", "sucursal-sin-punto-de-partida"})
			continue
		}
		// 4. Sin domicilio Y sin factura cotejada: no se guarda nada. Un pedido así no va
		//    a salir en ningún camión y ocuparía sitio en la lista del logístico.
		sinDomicilio := p.RequiereDomicilio != nil && !*p.RequiereDomicilio
		facturaIgual := p.FacturaEstado != nil && *p.FacturaEstado == "igual"
		if sinDomicilio && !facturaIgual {
			salida.Skipped++
			salida.Results = append(salida.Results, loteSaltado{ref, "skipped", "sin-domicilio-y-sin-factura"})
			continue
		}

		// 5. Peso y distancia.
		pesos := cotizar.PesosDeRenglones(p.Items, catalogo)
		peso := pesos.Total
		if !(peso > 0) {
			// Un total de 0 se considera «no resuelto» y cede al peso que trajo el
			// pedido. Un cero de verdad no existe: diría que en el camión cabe todo.
			peso = p.Weight.O(0)
		}
		km := cotizar.DistanciaHaversineKm(suc.Lat, suc.Lng, *p.Lat, *p.Lng)

		base := baseDelLote{
			Ref: ref, Status: "quoted", DistanceKm: km, WeightKg: peso,
			Branch: sucursalDelLote{ID: suc.ID, Name: suc.Name},
		}
		if sinDomicilio {
			// 6. Llega aquí con la factura cotejada: se guarda igual —hace falta para las
			//    rutas y para la capacidad del camión— pero marcado como sin domicilio.
			//    OJO: estos NO cuentan en `skipped`, sólo los de los pasos 1 a 4.
			base.Status = "skipped"
			base.Reason = "sin-domicilio"
		}

		// 7. En vista previa no se escribe nada.
		if preview {
			salida.Results = append(salida.Results, resultadoDelLote(base, sinDomicilio))
			continue
		}
		// 8. Sin nombre de cliente no se guarda: el nombre es lo que el chofer busca en la
		//    puerta, y una fila sin él no se puede repartir.
		if p.CustomerName == "" {
			no := false
			base.Persisted = &no
			base.Reason = "falta-customerName"
			salida.Results = append(salida.Results, resultadoDelLote(base, sinDomicilio))
			continue
		}
		// 9. Persistencia idempotente por (source='pedido', externalId).
		if GuardarPedidoDelEspejo == nil {
			// El manejador del espejo todavía no está montado. Se COTIZA igual —que es lo
			// que esta ruta sabe hacer— y se dice que no se guardó, en vez de contestar
			// `persisted: true` sobre algo que no se escribió.
			httpx.Registro(r).Error("el lote cotiza pero no persiste: falta montar GuardarPedidoDelEspejo")
			no := false
			base.Persisted = &no
			base.Reason = "espejo-no-montado"
			salida.Results = append(salida.Results, resultadoDelLote(base, sinDomicilio))
			continue
		}
		id, err := GuardarPedidoDelEspejo(r.Context(), a, armarPedidoDelLote(p, suc, pesos, peso, km))
		if err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
		texto := id.String()
		si := true
		base.OrderID = &texto
		base.Persisted = &si
		salida.Persisted++
		salida.Results = append(salida.Results, resultadoDelLote(base, sinDomicilio))
	}

	if salida.Persisted > 0 {
		// En la de Next aquí va `avisarCambio('pedidos', …)`, que invalida las pantallas
		// por SSE. Ese canal todavía no existe en este servicio; queda la línea de
		// registro para que se vea cuándo habría tocado avisar.
		httpx.Registro(r).Info("el espejo escribió pedidos", "pedidos", salida.Persisted)
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// resultadoDelLote añade el `price` (siempre null) a los que llevan domicilio. Los de
// `sin-domicilio` no lo llevan: no es que su precio sea desconocido, es que no hay
// domicilio que cobrar.
func resultadoDelLote(base baseDelLote, sinDomicilio bool) any {
	if sinDomicilio {
		return base
	}
	return loteCotizado{baseDelLote: base}
}

// refDelPedidoDelLote es `externalId || operationNumber || null`. Es con lo que PEDIDO reconoce
// cada resultado en la respuesta, así que la cadena vacía NO vale: sería un `ref` que
// parece puesto y no identifica nada.
func refDelPedidoDelLote(p pedidoDelLote) *string {
	if p.ExternalID != "" {
		v := p.ExternalID
		return &v
	}
	if p.OperationNumber != "" {
		v := p.OperationNumber
		return &v
	}
	return nil
}

// esVerdaderoJS aplica la verdad de JavaScript a un valor crudo: false, 0, "", null y el campo
// ausente son falsos; todo lo demás es verdadero (incluido `"false"`, que es una cadena no
// vacía — sí, en JavaScript eso es `true`).
func esVerdaderoJS(v json.RawMessage) bool {
	s := strings.TrimSpace(string(v))
	switch s {
	case "", "null", "false", `""`, "undefined":
		return false
	}
	// Cualquier número que valga 0 es falso (0, -0, 0.0, 0e5). El resto, verdadero.
	// Ojo con la cadena `"0"`: en JavaScript es una cadena NO vacía y por tanto VERDADERA,
	// y por eso se mira aquí el número crudo y no el texto entrecomillado.
	if n, err := strconv.ParseFloat(s, 64); err == nil {
		return n != 0
	}
	return true
}

// ---------------------------------------------------------------------------
// El pedido armado para el espejo (§2.3 `buildOrderData`)
// ---------------------------------------------------------------------------

// PedidoParaGuardar es el pedido ya resuelto, listo para escribir. Lo consume el manejador
// del espejo de PEDIDO.
//
// Se arma AQUÍ y no allí porque las reglas que no son mapeo trivial —el peso resuelto, la
// dirección de respaldo, el precio nulo, el texto de productos— son parte de la
// cotización y están en §2.3.
type PedidoParaGuardar struct {
	ExternalID      *string // `externalId || operationNumber || null`
	Source          string  // "pedido", fijo
	BranchID        uuid.UUID
	OperationNumber *string

	CustomerName  string
	CustomerPhone *string
	// Address nunca va vacío: `address || customerName`. Una fila sin dirección no se
	// puede repartir, y el nombre al menos se puede preguntar.
	Address    string
	EndAddress *string // `address || null`: aquí sí puede faltar
	// Los cuatro se llenan con la MISMA coordenada del cliente (§2.3).
	Lat, Lng, EndLat, EndLng float64

	// Weight es el peso ya resuelto. 0 = SIN PESO RESUELTO, y así entra al generador de
	// rutas (capacidad del camión). No es «no pesa».
	Weight float64
	// DeliveryDistanceKm son los km en línea recta de la sucursal al cliente.
	DeliveryDistanceKm float64
	// DeliveryPrice es SIEMPRE nil: delivery ya no cotiza. Lo que se cobra es PedidoCosto.
	DeliveryPrice *float64

	Renglones []cotizar.RenglonPesado
	// ProductosTexto es la copia EN TEXTO de los nombres, unidos con " · ".
	// POR QUÉ: dentro de un JSON no se puede buscar sin leerse los cincuenta mil pedidos,
	// y ésa es la pregunta del despacho («¿qué pedidos llevan malta?»).
	ProductosTexto *string

	OrderDate         *time.Time
	RequiereDomicilio *bool // tri-estado: true / false / desconocido
	Archivado         bool
	PedidoCosto       *float64 // el costo que la APK puso EN PEDIDO. NO es DeliveryPrice.
	FacturaEstado     *string
	Municipio         *string
	Vendedor          *string
	SucursalCodigo    *string
	Meta              json.RawMessage // sólo si vino: no se borra el payload guardado
}

func armarPedidoDelLote(p pedidoDelLote, suc sqlc.ListarSucursalesRow, pesos cotizar.PesosResueltos, peso, km float64) PedidoParaGuardar {
	// `address || customerName`: nunca vacío.
	direccion := p.Address
	if direccion == "" {
		direccion = p.CustomerName
	}

	out := PedidoParaGuardar{
		ExternalID:      refDelPedidoDelLote(p),
		Source:          "pedido",
		BranchID:        suc.ID,
		OperationNumber: aTexto(p.OperationNumber),
		CustomerName:    p.CustomerName,
		CustomerPhone:   aTexto(p.Phone),
		Address:         direccion,
		EndAddress:      aTexto(p.Address),
		// Los cuatro con la coordenada del cliente. Ya se comprobó que no son nil.
		Lat: *p.Lat, Lng: *p.Lng, EndLat: *p.Lat, EndLng: *p.Lng,
		Weight:             peso,
		DeliveryDistanceKm: km,
		// COMPARACIÓN ESTRICTA CON false: un `requiereDomicilio` ausente o null NO anula
		// el precio. Y como delivery ya no cotiza, aquí es nil en los dos casos.
		DeliveryPrice:     nil,
		Renglones:         pesos.Renglones,
		ProductosTexto:    textoDeProductos(p.Items),
		RequiereDomicilio: p.RequiereDomicilio,
		// `archivado === true` estricto: por defecto false.
		Archivado:      p.Archivado != nil && *p.Archivado,
		PedidoCosto:    p.PedidoCosto,
		FacturaEstado:  p.FacturaEstado,
		Municipio:      p.Municipio,
		Vendedor:       p.Vendedor,
		SucursalCodigo: suc.ExternalID,
		Meta:           p.Meta,
	}
	// `orderDate` existe SEPARADO de `createdAt` por algo: `createdAt` es cuándo lo copió
	// el espejo. Filtrar el día del armador de rutas por `createdAt` daba CERO cualquier
	// día que no fuera hoy, porque el espejo trae quince días de una vez y todos nacen con
	// la fecha de hoy.
	if p.OrderDate != nil {
		if t, err := time.Parse(time.RFC3339, *p.OrderDate); err == nil {
			out.OrderDate = &t
		}
	}
	return out
}

// productosTexto une los nombres con " · ", descartando los vacíos. Nil si no queda nada.
func textoDeProductos(items []cotizar.Renglon) *string {
	nombres := make([]string, 0, len(items))
	for _, it := range items {
		n := it.Name
		if n == "" {
			n = it.Description
		}
		if n != "" {
			nombres = append(nombres, n)
		}
	}
	if len(nombres) == 0 {
		return nil
	}
	v := strings.Join(nombres, " · ")
	return &v
}

// ---------------------------------------------------------------------------
// Ayudas
// ---------------------------------------------------------------------------

// sucursalParaCotizar busca la sucursal por su CÓDIGO de PEDIDO/Ventra (CAM, HAB, STG…), que
// es la clave con la que cotizan las demás aplicaciones. nil si no está.
//
// Va por `ListarSucursalesVisibles` y no por la consulta `BuscarSucursalPorCodigo` —que
// existe en sqlc— porque esa todavía no está expuesta en `internal/alcance/consultas.go`,
// que es el único sitio por el que un manejador puede llegar a la base. Con ocho
// sucursales el recorrido no se nota; cuando la consulta se exponga, esta función se
// cambia por una línea y nada más se mueve.
//
// El alcance viene puesto de la petición: para las rutas de servicio son todas, y para una
// persona con sucursal es la suya. Si pide el código de otra, aquí no aparece.
func sucursalParaCotizar(ctx context.Context, a *alcance.Acotado, codigo string) (*sqlc.ListarSucursalesRow, error) {
	filas, err := a.ListarSucursalesVisibles(ctx)
	if err != nil {
		return nil, err
	}
	for i := range filas {
		if filas[i].ExternalID != nil && *filas[i].ExternalID == codigo {
			return &filas[i], nil
		}
	}
	return nil, nil
}
