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
	Resumen    ResumenDelWebhookSalida `json:"resumen"`
	Enviados   []EnvioDelWebhookSalida `json:"enviados"`
	Recibidos  []RecepcionDelWebhook   `json:"recibidos"`
	SinMandar  []AvisoSinMandar        `json:"sinMandar"`
	ServidorAt time.Time               `json:"servidorAt"`
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
		Enviados:   make([]EnvioDelWebhookSalida, 0, len(envios)),
		Recibidos:  make([]RecepcionDelWebhook, 0, len(recepciones)),
		SinMandar:  make([]AvisoSinMandar, 0, len(sinMandar)),
		ServidorAt: time.Now().UTC(),
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
