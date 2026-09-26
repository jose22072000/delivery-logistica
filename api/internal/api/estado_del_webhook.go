package api

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// CÓMO VA EL WEBHOOK, EN LOS DOS SENTIDOS. Sólo para administración.
//
// Jose, 26/09/2026: «aparte de recibir y enviar, tener también para ver cómo está
// funcionando el webhook, tanto lo que envía como lo que recibe» y «de salida también, para
// saber si llegó correcto o no». Y quién puede mirarlo: «esto es para administración, esta
// vista no la puede ver nadie».
//
// POR QUÉ ES DE ADMINISTRACIÓN Y NO DE TODOS. Esto no son datos de una sucursal: es el
// estado de una tubería entre dos sistemas, con motivos de error de PEDIDO dentro. A quien
// arma rutas no le sirve de nada y sólo puede confundirle —«hay 12 rechazados» no es una
// tarea suya—. Va detrás de `ExigirAdmin`, que es el mismo listón del resto de lo
// administrativo, y **no se pone en el menú**.
//
// LO QUE CONTESTA, y son tres preguntas distintas que la gente confunde:
//
//  1. **¿Respira?** Las horas de la última tanda de cada lado. Un webhook que lleva seis
//     horas sin recibir nada no da ningún error: sólo deja de pasar cosas. `null` es
//     «nunca», que no es «hace mucho» y se dice con otras palabras.
//  2. **¿Llega lo que sale?** Cada tanda enviada con su código HTTP y su motivo literal.
//     Un aviso sin enviar puede ser «PEDIDO está caído» —la llamada no llegó— o «PEDIDO lo
//     rechazó» —llegó perfectamente y dijo que no—: desde fuera se ven igual.
//  3. **¿Se escribe lo que entra?** Cada tanda recibida con cuántos traía y cuántos se
//     escribieron. Cuando un pedido no aparece en el reparto, esto dice de quién es el
//     problema.

// TopeDelEstadoDelWebhook: cuántas líneas de cada lado se devuelven.
//
// Esto se mira para responder «¿qué pasó hace un rato?», no para auditar el mes. Con
// veinte de cada lado se ve el ritmo; con mil, la pantalla deja de leerse y la consulta
// empieza a pesar.
const TopeDelEstadoDelWebhook = 20

// TopeMaximoDelEstadoDelWebhook: hasta dónde se deja subir con `?tope=`.
const TopeMaximoDelEstadoDelWebhook = 200

type EstadoDelWebhookSalida struct {
	Resumen   ResumenDelWebhookSalida `json:"resumen"`
	Enviados  []EnvioDelWebhookSalida `json:"enviados"`
	Recibidos []RecepcionDelWebhook   `json:"recibidos"`
	SinMandar []AvisoSinMandar        `json:"sinMandar"`

	// LA CUARTA PREGUNTA, desde el 26/09/2026: **¿se está midiendo desde donde hay que
	// medir?** Va aquí y no en una pantalla nueva porque es la misma tubería —lo que PEDIDO
	// manda y lo que este lado hace con ello— y porque es de administración por el mismo
	// motivo: no es un dato de una sucursal, es el estado de un acuerdo entre dos sistemas.
	//
	// Lo que pasa cuando esto no está: la distancia del domicilio se mide DESDE EL ALMACÉN, y
	// hasta hoy había uno por sucursal. Ahora hay varios, y en Santiago **dos de cada tres
	// pedidos salen de AURORA** mientras el principal es PV-STGO. Un pedido medido desde el
	// principal porque su almacén no estaba dado de alta tiene el mismo aspecto que uno bien
	// medido: mismos decimales, misma tarjeta. Sin esta lista, la única forma de enterarse es
	// que alguien de PEDIDO cuente los renglones por almacén, que es como se descubrió.
	SinMedir []AlmacenSinMedirSalida `json:"sinMedir"`
	// SinMedirTruncado: si el tope se comió filas. Ver `CLAUDE.md` §3 — pedir un tope y no
	// mirar si se alcanzó es el fallo que más caro sale aquí, y esta lista está ORDENADA POR
	// CUENTA DESCENDENTE, así que lo que el tope se come son los almacenes de uno o dos
	// pedidos: precisamente el que acaba de aparecer y hay que cazar temprano.
	SinMedirTruncado bool `json:"sinMedirTruncado"`

	ServidorAt time.Time `json:"servidorAt"`
}

// AlmacenSinMedirSalida es una fila de «no se midió desde su almacén»: qué llegó, por qué no
// se pudo usar, cuántos pedidos y desde cuándo.
//
// CADA MOTIVO SE ARREGLA EN UN SITIO DISTINTO y por eso viaja: dar de alta el almacén en
// Accesos, ponerle el punto, ponerle el código, o que PEDIDO empiece a mandar el campo. Con un
// «hay 300 pedidos mal medidos» sin motivo, nadie sabe qué hacer.
type AlmacenSinMedirSalida struct {
	SucursalCodigo *string    `json:"sucursalCodigo"`
	Motivo         *string    `json:"motivo"`
	Codigo         *string    `json:"codigo"`
	Nombre         *string    `json:"nombre"`
	Pedidos        int64      `json:"pedidos"`
	Desde          *time.Time `json:"desde"`
	Hasta          *time.Time `json:"hasta"`
}

type ResumenDelWebhookSalida struct {
	// `null` = NUNCA. No es lo mismo que «hace mucho» y la pantalla lo dice distinto.
	UltimaEntrada *time.Time `json:"ultimaEntrada"`
	UltimaSalida  *time.Time `json:"ultimaSalida"`

	EscritosHoy        int64 `json:"escritosHoy"`
	RechazadosAlEntrar int64 `json:"rechazadosAlEntrar"`

	AvisosPendientes int64 `json:"avisosPendientes"`
	AvisosRechazados int64 `json:"avisosRechazados"`
	// El más viejo sin mandar. Es EL número que dice si esto está atascado: veinte
	// pendientes de hace un minuto es el ritmo normal; uno de hace seis horas, no.
	PendienteMasViejo *time.Time `json:"pendienteMasViejo"`
}

type EnvioDelWebhookSalida struct {
	Destino    string    `json:"destino"`
	Mandados   int32     `json:"mandados"`
	Aceptados  int32     `json:"aceptados"`
	Rechazados int32     `json:"rechazados"`
	HTTP       *int32    `json:"http"`
	Motivo     *string   `json:"motivo"`
	DuracionMs int32     `json:"duracionMs"`
	CreatedAt  time.Time `json:"createdAt"`
}

type RecepcionDelWebhook struct {
	Origen     string    `json:"origen"`
	Traidos    int32     `json:"traidos"`
	Escritos   int32     `json:"escritos"`
	Rechazados int32     `json:"rechazados"`
	Motivos    *string   `json:"motivos"`
	DuracionMs int32     `json:"duracionMs"`
	CreatedAt  time.Time `json:"createdAt"`
}

// AvisoSinMandar: los que no llegaron, con su motivo. Es la bandeja que alguien tiene que
// mirar — un rechazado no se reintenta solo y se queda ahí a propósito.
type AvisoSinMandar struct {
	PedidoID  string     `json:"pedidoId"`
	Folio     *string    `json:"folio"`
	Estado    string     `json:"estado"`
	Situacion string     `json:"situacion"`
	Intentos  int32      `json:"intentos"`
	Motivo    *string    `json:"motivo"`
	OcurrioAt *time.Time `json:"ocurrioAt"`
	CreatedAt time.Time  `json:"createdAt"`
}

// GET /api/admin/webhook
func (s *Servidor) estadoDelWebhook(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	tope := int32(TopeDelEstadoDelWebhook)
	if n, err := strconv.Atoi(strings.TrimSpace(r.URL.Query().Get("tope"))); err == nil &&
		n > 0 && n <= TopeMaximoDelEstadoDelWebhook {
		tope = int32(n)
	}

	res, err := a.ResumenDelWebhook(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	envios, err := a.ListarEnviosDelWebhook(r.Context(), tope)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	recepciones, err := a.ListarRecepcionesDelWebhook(r.Context(), tope)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// LOS QUE NO LLEGARON, los dos motivos juntos: pendientes y rechazados. Es la bandeja
	// que alguien tiene que mirar, y se pide sin filtro para que salgan los dos —filtrar
	// por uno dejaría la mitad del problema fuera de la pantalla.
	sinMandar, err := a.ListarAvisosAPedido(r.Context(), sqlc.ListarAvisosAPedidoParams{
		Tope: tope,
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	// LO QUE NO SE MIDIÓ DESDE SU ALMACÉN, acotado a lo que esta persona puede ver.
	//
	// SE PIDE UNA FILA DE MÁS. Es lo que convierte «truncado» en un dato y no en una sospecha:
	// si vuelve la de más, hay más; si no vuelve, ésta era toda la lista. Es el molde de
	// `tablero.go`, y aquí hace más falta que allí porque la lista va ordenada por cuenta
	// descendente: sin esto, el almacén que aparece hoy con un pedido —el que hay que cazar
	// antes de que sean mil— se cae por debajo del corte y nadie lo echa en falta.
	//
	// EL ALCANCE SALE DE QUIÉN PREGUNTA y no de la cabecera: `nil` sólo para quien ve las
	// ocho. Con `CodigosDeSucursalesVisibles` un logístico de Camagüey ve lo suyo y nada más
	// — la regla 1 de la casa, la que en delivery dejó a un operador de Santiago viendo los
	// precios de La Habana.
	var visibles []string
	if !a.Todas() {
		codigos, err := a.CodigosDeSucursalesVisibles(r.Context())
		if err != nil {
			httpx.ErrorInterno(w, r, err)
			return
		}
		// Se arranca en `[]string{}` y NO en nil: un nil significa «todas» en la consulta, así
		// que una persona cuya sucursal no tenga código vería las ocho. Con la lista vacía no
		// ve ninguna, que es la verdad y el lado seguro.
		visibles = []string{}
		for _, c := range codigos {
			if c.ExternalID != nil && strings.TrimSpace(*c.ExternalID) != "" {
				visibles = append(visibles, strings.TrimSpace(*c.ExternalID))
			}
		}
	}
	sinMedir, err := a.AlmacenesDelPedidoSinMedir(r.Context(), visibles, tope+1)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	huboMas := int32(len(sinMedir)) > tope
	if huboMas {
		sinMedir = sinMedir[:tope]
	}

	salida := EstadoDelWebhookSalida{
		Resumen: ResumenDelWebhookSalida{
			UltimaEntrada:      hora(res.UltimaEntrada),
			UltimaSalida:       hora(res.UltimaSalida),
			EscritosHoy:        res.EscritosHoy,
			RechazadosAlEntrar: res.RechazadosAlEntrar,
			AvisosPendientes:   res.AvisosPendientes,
			AvisosRechazados:   res.AvisosRechazados,
			PendienteMasViejo:  hora(res.PendienteMasViejo),
		},
		Enviados:         make([]EnvioDelWebhookSalida, 0, len(envios)),
		Recibidos:        make([]RecepcionDelWebhook, 0, len(recepciones)),
		SinMandar:        make([]AvisoSinMandar, 0, len(sinMandar)),
		SinMedir:         make([]AlmacenSinMedirSalida, 0, len(sinMedir)),
		SinMedirTruncado: huboMas,
		ServidorAt:       time.Now().UTC(),
	}
	for _, x := range sinMedir {
		salida.SinMedir = append(salida.SinMedir, AlmacenSinMedirSalida{
			SucursalCodigo: x.SucursalCodigo, Motivo: x.Motivo,
			Codigo: x.Codigo, Nombre: x.Nombre, Pedidos: x.Cuantos,
			Desde: hora(x.Desde), Hasta: hora(x.Hasta),
		})
	}
	for _, e := range envios {
		salida.Enviados = append(salida.Enviados, EnvioDelWebhookSalida{
			Destino: e.Destino, Mandados: e.Mandados, Aceptados: e.Aceptados,
			Rechazados: e.Rechazados, HTTP: e.Http, Motivo: e.Motivo,
			DuracionMs: e.DuracionMs, CreatedAt: e.CreatedAt.Time,
		})
	}
	for _, c := range recepciones {
		salida.Recibidos = append(salida.Recibidos, RecepcionDelWebhook{
			Origen: c.Origen, Traidos: c.Traidos, Escritos: c.Escritos,
			Rechazados: c.Rechazados, Motivos: c.Motivos,
			DuracionMs: c.DuracionMs, CreatedAt: c.CreatedAt.Time,
		})
	}
	for _, v := range sinMandar {
		if v.Situacion == sqlc.AvisoAPedidoEstadoEnviado {
			continue
		}
		salida.SinMandar = append(salida.SinMandar, AvisoSinMandar{
			PedidoID: v.PedidoID, Folio: v.Folio, Estado: v.Estado,
			Situacion: string(v.Situacion), Intentos: v.Intentos, Motivo: v.Motivo,
			OcurrioAt: hora(v.OcurrioAt), CreatedAt: v.CreatedAt.Time,
		})
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}
