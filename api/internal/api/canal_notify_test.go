package api

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"procovar/reparto-api/internal/config"
)

// EL AVISO TIENE QUE ENTRAR EN NOTIFY DE VERDAD, NO «SALIR» DE AQUÍ.
//
// Un servidor de mentira que contesta 200 a cualquier cosa no prueba nada de esto: prueba que
// `http.Post` funciona. Lo que hay que comprobar es que la petición que sale es una que notify
// ACEPTA, y eso son cuatro cosas que se pueden romper por separado y ninguna se ve desde aquí
// —el motivo que se lee siempre es «401»—:
//
//  1. La ruta firmada y la ruta pedida son la misma, y es `/v1/notifications`.
//  2. La cadena canónica es la de notify: METODO \n RUTA \n CONSULTA \n sha256(CUERPO) \n
//     SELLO, con la línea de la consulta PRESENTE aunque esté vacía.
//  3. El sello va en SEGUNDOS y en hora: notify rechaza más de 300 s de desvío con
//     `signature_expired`, y eso se lee igual que un secreto equivocado.
//  4. El cuerpo lleva el tipo, el destinatario y LAS VARIABLES QUE PIDE LA PLANTILLA.
//
// Por eso el servidor de estas pruebas RECALCULA la firma como la recalcula notify
// (`notify/backend/internal/auth/hmac.go`, `Sign`) y contesta 401 si no cuadra. Está escrito
// aparte a propósito: si las dos partes usaran la misma función, una errata en la función
// cuadraría consigo misma y la prueba saldría verde.

const (
	claveDeNotifyEnPruebas   = "key_de_prueba"
	secretoDeNotifyEnPruebas = "un secreto de prueba que no es el de nadie"
	// DesvioQueNotifyAdmite: `HMAC_TIMESTAMP_SKEW_SECONDS`, 300 s por defecto.
	DesvioQueNotifyAdmite = 300 * time.Second
)

// firmaComoLaRecalcularaNotify es la mitad del servidor, escrita desde el código de notify y
// no desde `firmarParaNotify`.
func firmaComoLaRecalcularaNotify(secreto, metodo, ruta, consulta string, cuerpo []byte, sello string) string {
	h := sha256.Sum256(cuerpo)
	aFirmar := strings.Join([]string{metodo, ruta, consulta, hex.EncodeToString(h[:]), sello}, "\n")
	mac := hmac.New(sha256.New, []byte(secreto))
	mac.Write([]byte(aFirmar))
	return hex.EncodeToString(mac.Sum(nil))
}

// notifyDeMentira levanta un notify que se comporta como el de verdad en lo que importa.
type peticionANotify struct {
	Ruta   string
	Cuerpo map[string]any
}

func notifyDeMentira(t *testing.T) (*httptest.Server, *[]peticionANotify, *[]string) {
	t.Helper()
	var entraron []peticionANotify
	var rechazos []string

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cuerpo, _ := io.ReadAll(r.Body)

		sello := r.Header.Get("X-QBN-Timestamp")
		seg, err := strconv.ParseInt(sello, 10, 64)
		if err != nil {
			rechazos = append(rechazos, "el sello no es un entero: "+sello)
			http.Error(w, `{"title":"invalid_timestamp"}`, http.StatusUnauthorized)
			return
		}
		// EL SELLO EN SEGUNDOS Y EN HORA. En milisegundos esto se va treinta y cinco mil
		// años, y notify contesta `signature_expired` — que se lee como un secreto malo.
		desvio := time.Since(time.Unix(seg, 0))
		if desvio < -DesvioQueNotifyAdmite || desvio > DesvioQueNotifyAdmite {
			rechazos = append(rechazos, "signature_expired: el sello se desvía "+desvio.String())
			http.Error(w, `{"title":"signature_expired"}`, http.StatusUnauthorized)
			return
		}
		if r.Header.Get("X-QBN-Key-Id") != claveDeNotifyEnPruebas {
			rechazos = append(rechazos, "X-QBN-Key-Id no es la que se configuró")
			http.Error(w, `{"title":"unauthorized"}`, http.StatusUnauthorized)
			return
		}

		// LA FIRMA SE RECALCULA SOBRE LO QUE DE VERDAD LLEGÓ: la ruta de la petición y su
		// consulta, no las que el cliente diga que firmó.
		quiere := firmaComoLaRecalcularaNotify(
			secretoDeNotifyEnPruebas, r.Method, r.URL.Path, r.URL.Query().Encode(), cuerpo, sello)
		if r.Header.Get("X-QBN-Signature") != quiere {
			rechazos = append(rechazos, "la firma no cuadra con la cadena canónica de notify")
			http.Error(w, `{"title":"invalid_signature"}`, http.StatusUnauthorized)
			return
		}

		var leido map[string]any
		if err := json.Unmarshal(cuerpo, &leido); err != nil {
			rechazos = append(rechazos, "el cuerpo no es JSON")
			http.Error(w, `{"title":"bad_request"}`, http.StatusBadRequest)
			return
		}
		entraron = append(entraron, peticionANotify{Ruta: r.URL.Path, Cuerpo: leido})
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusAccepted)
		_, _ = w.Write([]byte(`{"id":"00000000-0000-0000-0000-000000000000","status":"PENDING"}`))
	}))
	t.Cleanup(srv.Close)
	return srv, &entraron, &rechazos
}

func canalDeAvisosDePrueba(t *testing.T, url string) CanalDeAvisos {
	t.Helper()
	return nuevoCanalDeAvisos(&config.Config{Notify: config.Notify{
		URL:     url,
		KeyID:   claveDeNotifyEnPruebas,
		Secreto: secretoDeNotifyEnPruebas,
		Tipo:    config.TipoDeAvisoPorDefecto,
		Destino: "avisos@ejemplo.com",
	}}, slog.New(slog.DiscardHandler))
}

func avisoDePrueba() AvisoParaNotify {
	return AvisoParaNotify{
		Clase:   ClaseSalidaAtascada,
		Huella:  "2026-09-24T14:38:00Z",
		Asunto:  "Reparto: la salida hacia PEDIDO está atascada",
		Detalle: "Hay 3 avisos esperando y el más viejo lleva 22m sin irse.",
		Datos:   map[string]any{"pendientes": 3},
		Cuando:  time.Now().UTC(),
	}
}

// EL AVISO ENTRA: ruta, firma, sello y cuerpo, los cuatro.
func TestElAvisoEntraEnNotifyFirmadoComoLoEspera(t *testing.T) {
	srv, entraron, rechazos := notifyDeMentira(t)
	canal := canalDeAvisosDePrueba(t, srv.URL)

	if err := canal(context.Background(), avisoDePrueba()); err != nil {
		t.Fatalf("notify no aceptó el aviso: %v (rechazos: %v)", err, *rechazos)
	}
	if len(*entraron) != 1 {
		t.Fatalf("no entró el aviso: %v", *rechazos)
	}
	p := (*entraron)[0]

	// LA RUTA, comprobada aparte de la firma. Cambiar `RutaDeNotify` cambia a la vez lo que
	// se pide y lo que se firma, así que la firma seguiría cuadrando y notify contestaría un
	// 404 que ninguna firma caza.
	if p.Ruta != "/v1/notifications" {
		t.Fatalf("la petición no fue a /v1/notifications sino a %q: notify no tiene esa "+
			"puerta y contesta 404", p.Ruta)
	}
	if p.Cuerpo["type"] != config.TipoDeAvisoPorDefecto {
		t.Fatalf("el tipo que viaja no es el configurado: %v", p.Cuerpo["type"])
	}
	dest, _ := p.Cuerpo["recipient"].(map[string]any)
	if dest == nil || dest["email"] != "avisos@ejemplo.com" {
		t.Fatalf("el aviso salió sin destinatario: notify lo pide en CADA petición, el tipo "+
			"sólo trae el SMTP de salida. Salió: %v", p.Cuerpo["recipient"])
	}
	// LA PRIORIDAD, con el literal y no con la constante: comparar la constante consigo misma
	// sale verde aunque alguien la baje a `LOW`. Con `HIGH` la notificación entra en la cola
	// `critical` de asynq, que es la que se atiende con peso 6 de 10; en `LOW` cae a la de peso
	// 1 y el correo de un canal roto puede esperar detrás de lo que no corre prisa.
	if p.Cuerpo["priority"] != "HIGH" {
		t.Fatalf("el aviso no sale con prioridad HIGH sino con %v: un canal roto no puede "+
			"esperar en la cola lenta de asynq", p.Cuerpo["priority"])
	}
	if p.Cuerpo["idempotencyKey"] == nil || p.Cuerpo["idempotencyKey"] == "" {
		t.Fatalf("el aviso salió sin clave de idempotencia: es lo único que impide que un " +
			"reinicio del contenedor vuelva a mandar el mismo aviso")
	}
}

// UN AVISO CON LA HORA DEL HECHO VIEJA SIGUE ENTRANDO: SE FIRMA CON EL RELOJ DE AHORA.
//
// Son DOS relojes y tenerlos en el mismo campo era un fallo esperando. `Cuando` es la hora del
// hecho: fija la ventana de idempotencia y la fecha que se lee en el correo, y puede ser de
// hace un rato —el vigía mira una condición que empezó antes, y un aviso que falló se reintenta
// quince minutos después—. El sello de la FIRMA, en cambio, tiene que estar en hora: notify
// rechaza más de 300 s de desvío con `signature_expired`. Si se firmara con `Cuando`, un aviso
// de hace diez minutos no entraría NUNCA y el motivo que se lee es «401», que manda a mirar el
// secreto — que es lo último que está mal.
func TestUnAvisoConLaHoraDelHechoViejaSigueEntrando(t *testing.T) {
	srv, entraron, rechazos := notifyDeMentira(t)
	canal := canalDeAvisosDePrueba(t, srv.URL)

	a := avisoDePrueba()
	a.Cuando = time.Now().UTC().Add(-10 * time.Minute) // más allá de la ventana de notify

	if err := canal(context.Background(), a); err != nil {
		t.Fatalf(
			"un aviso cuyo hecho es de hace diez minutos no entró: se está firmando con la "+
				"hora del HECHO y no con la de ahora, así que notify lo rechaza por "+
				"`signature_expired` y en el registro sólo se lee «401». Error: %v (%v)",
			err, *rechazos,
		)
	}
	if len(*entraron) != 1 {
		t.Fatalf("no entró: %v", *rechazos)
	}
	// Y la fecha que se lee en el correo sigue siendo la del hecho, no la del envío.
	payload, _ := (*entraron)[0].Cuerpo["payload"].(map[string]any)
	if payload["fecha"] != a.Cuando.Format(time.RFC3339) {
		t.Fatalf("la fecha del correo no es la del hecho: %v", payload["fecha"])
	}
}

// Y LAS VARIABLES SON LAS QUE PIDE LA PLANTILLA, ATADAS CON UNA PRUEBA Y NO CON UN COMENTARIO.
//
// Es el §3-bis de `CLAUDE.md`: dos sitios que tienen que decir lo mismo se atan ejecutando,
// porque un comentario no falla. Si alguien renombra `asunto` a `titulo`, esto compila, pasa
// `vet`, y todos los avisos mueren en la validación de notify — que sólo se ve en el registro
// del contenedor, o sea justo lo que este aviso viene a dejar de necesitar.
//
// La plantilla `aviso-servidor` pide `asunto`, `cuerpo`, `fecha`, `nivel` y `servidor`
// (comprobado en la base de notify de producción el 26/09/2026).
func TestElAvisoLlevaLasVariablesQuePideLaPlantilla(t *testing.T) {
	srv, entraron, rechazos := notifyDeMentira(t)
	canal := canalDeAvisosDePrueba(t, srv.URL)

	if err := canal(context.Background(), avisoDePrueba()); err != nil {
		t.Fatalf("notify no aceptó el aviso: %v (%v)", err, *rechazos)
	}
	payload, _ := (*entraron)[0].Cuerpo["payload"].(map[string]any)
	if payload == nil {
		t.Fatalf("el aviso salió sin payload")
	}
	for _, v := range VariablesDeLaPlantilla {
		valor, hay := payload[v]
		if !hay {
			t.Fatalf(
				"falta la variable %q, que la plantilla de notify pide como REQUERIDA: el "+
					"envío entero se cae en ValidatePayload y no sale ni un correo. "+
					"Salieron: %v", v, clavesDe(payload),
			)
		}
		if s, ok := valor.(string); ok && strings.TrimSpace(s) == "" {
			t.Fatalf("la variable requerida %q viaja vacía", v)
		}
	}
	// Y el detalle tiene que ir en `cuerpo`, no en un nombre nuestro que la plantilla ignora:
	// un correo con el asunto bien y el cuerpo en blanco no dice nada.
	if got := payload["cuerpo"]; got != avisoDePrueba().Detalle {
		t.Fatalf("el detalle del aviso no viaja en `cuerpo`: %v", got)
	}
	// El `nivel`, con el literal por lo mismo que la prioridad. Los tres avisos de este vigía
	// son «algo está roto y hay que mirarlo»: ninguno sale si el canal va bien, así que
	// ninguno es un `info` — y en un buzón, `info` es lo que se archiva sin abrir.
	if payload["nivel"] != "error" {
		t.Fatalf("el aviso sale con nivel %v: un canal roto no es información, y un `info` se "+
			"archiva sin abrir", payload["nivel"])
	}
}

func clavesDe(m map[string]any) []string {
	var ks []string
	for k := range m {
		ks = append(ks, k)
	}
	return ks
}

// SIN CONFIGURACIÓN EL AVISO NO SE DA POR MANDADO, Y SE DICE QUÉ FALTA.
//
// Es la lección del canal de Entrega, que existía con clave y secreto y **sin URL**: no salía
// nada y no se veía en ningún registro. Un `nil` aquí haría que el vigía apuntara el aviso
// como mandado y se callara seis horas por un correo que nadie recibió.
func TestSinConfiguracionElAvisoPorNotifyNoSeDaPorMandado(t *testing.T) {
	llena := config.Notify{
		URL: "http://notify-api:8080", KeyID: "k", Secreto: "s",
		Tipo: "aviso-servidor", Destino: "avisos@ejemplo.com",
	}
	casos := []struct {
		quita  func(*config.Notify)
		nombre string
	}{
		{func(n *config.Notify) { n.URL = "" }, "QB_NOTIFY_URL"},
		{func(n *config.Notify) { n.KeyID = "" }, "QB_NOTIFY_KEY_ID"},
		{func(n *config.Notify) { n.Secreto = "" }, "QB_NOTIFY_SECRET"},
		{func(n *config.Notify) { n.Tipo = "" }, "QB_NOTIFY_TIPO"},
		{func(n *config.Notify) { n.Destino = "" }, "QB_NOTIFY_DESTINO"},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			n := llena
			c.quita(&n)
			canal := nuevoCanalDeAvisos(&config.Config{Notify: n}, slog.New(slog.DiscardHandler))

			err := canal(context.Background(), avisoDePrueba())

			if err == nil {
				t.Fatalf(
					"sin %s el canal dijo que sí: un aviso que nadie recibe y que además se "+
						"declara enviado es peor que no avisar, porque nadie lo busca", c.nombre,
				)
			}
			if !strings.Contains(err.Error(), c.nombre) {
				t.Fatalf(
					"el error no nombra la variable que falta. «notify no está configurado» "+
						"manda a mirar cinco variables; «falta %s» se arregla en un minuto. "+
						"Dijo: %q", c.nombre, err,
				)
			}
		})
	}
}

// UN NOTIFY QUE CONTESTA MAL NO SE DA POR MANDADO, Y EL MOTIVO LITERAL ENTRA EN EL ERROR.
//
// notify contesta problem+json con el motivo dentro —`notification_type_not_found`,
// `signature_expired`, un fallo de validación de variables—. Sin el cuerpo, en el registro
// sólo queda «notify contestó 400», que no dice qué arreglar: un tipo que no existe en la SPA
// y un reloj desincronizado dan el mismo código y se arreglan en sitios distintos.
func TestUnNotifyQueContestaMalNoSeDaPorMandado(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/problem+json")
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(`{"title":"notification_type_not_found","detail":"aviso-servidor"}`))
	}))
	defer srv.Close()

	err := canalDeAvisosDePrueba(t, srv.URL)(context.Background(), avisoDePrueba())

	if err == nil {
		t.Fatalf("notify contestó 404 y el canal lo dio por mandado")
	}
	if !strings.Contains(err.Error(), "404") {
		t.Fatalf("el error no dice el código que contestó notify: %q", err)
	}
	if !strings.Contains(err.Error(), "notification_type_not_found") {
		t.Fatalf(
			"el motivo literal de notify no entra en el error: «notify contestó 404» no dice "+
				"si el tipo no existe, si la clave es de otra aplicación o si el reloj está "+
				"mal. Dijo: %q", err,
		)
	}
}

// LA CLAVE DE IDEMPOTENCIA: la misma dentro de la ventana, distinta en la siguiente.
//
// Es la segunda red contra el aviso repetido, y hace falta porque la primera —la memoria del
// vigía— vive en la RAM de este proceso y se borra en cada despliegue. La única de notify es
// PERMANENTE, sin caducidad, así que sin la ventana dentro el recordatorio de las seis horas
// se quedaría fuera para siempre y el aviso se mandaría una vez en la vida.
func TestLaClaveDeIdempotenciaAguantaUnReinicioYDejaPasarElRecordatorio(t *testing.T) {
	a := avisoDePrueba()
	a.Cuando = time.Date(2026, 9, 24, 15, 0, 0, 0, time.UTC)

	otraVezIgual := a
	otraVezIgual.Cuando = a.Cuando.Add(SilencioMinimo) // el mismo hecho tras un reinicio
	if claveDelAviso(a) != claveDelAviso(otraVezIgual) {
		t.Fatalf(
			"el mismo aviso dentro de la misma ventana da dos claves distintas: un reinicio " +
				"del contenedor volvería a mandarlo y la memoria del vigía no puede taparlo",
		)
	}

	elRecordatorio := a
	elRecordatorio.Cuando = a.Cuando.Add(SilencioLargo + time.Minute)
	if claveDelAviso(a) == claveDelAviso(elRecordatorio) {
		t.Fatalf("el recordatorio de las %s reusa la clave, así que notify lo descarta y lo "+
			"que sigue mal no se vuelve a decir nunca", SilencioLargo)
	}

	otroHecho := a
	otroHecho.Huella = "2026-09-24T16:10:00Z"
	if claveDelAviso(a) == claveDelAviso(otroHecho) {
		t.Fatalf("dos atascos distintos comparten clave: el segundo lo descartaría notify")
	}
}

// Y LA CLASE QUE NO SE RECUERDA NO LLEVA VENTANA, a propósito.
//
// Un rechazado que nadie limpia se cuenta una vez y nunca más, ni después de un despliegue: la
// única permanente de notify es la que lo garantiza. Con la ventana dentro, cada reinicio en
// una ventana nueva volvería a mandar el mismo correo, y esa cuenta no baja sola — no hay
// forma de quitar un rechazado sin un UPDATE a mano.
func TestElAvisoDeRechazoTieneLaMismaClaveParaSiempre(t *testing.T) {
	a := AvisoParaNotify{
		Clase:  ClaseRechazoDePedido,
		Huella: "1",
		Cuando: time.Date(2026, 9, 24, 15, 0, 0, 0, time.UTC),
	}
	b := a
	b.Cuando = a.Cuando.AddDate(0, 0, 20)

	if claveDelAviso(a) != claveDelAviso(b) {
		t.Fatalf(
			"el mismo rechazado da claves distintas veinte días después: cada reinicio del " +
				"contenedor manda otro correo idéntico y en una semana esto está silenciado",
		)
	}
}
