// EL CANAL DE AVISOS A LAS PERSONAS: notify, y nada más que notify.
//
// POR QUÉ EXISTE: hasta el 26/09/2026 el canal con PEDIDO podía romperse entero sin que se
// enterara nadie. Un aviso atascado o rechazado sólo se veía si alguien abría
// `/admin/webhook`, que es una pantalla de administración que nadie tiene abierta, y un
// PEDIDO caído no levanta ninguna alarma: sólo deja de pasar cosas. Jose, 26/09/2026:
// «créame un mensaje en notify para cuando haya un error de esto». Eso es exactamente el
// fallo que más caro sale en este proyecto: el que no se ve.
//
// POR QUÉ NOTIFY Y NO UN GUION EN EL SERVIDOR: es regla de `procovar/CLAUDE.md`. Los
// correos y los avisos de la casa los manda notify, que es donde están las plantillas, los
// SMTP y el registro de si el correo llegó. Un `sendmail` metido en este contenedor sería
// un canal más que nadie sabe que existe, sin forma de ver si salió, y que se pierde en el
// siguiente despliegue.
//
// LA FORMA DE HABLAR CON NOTIFY ESTÁ COPIADA, NO ADIVINADA. Sale de dos sitios que ya
// funcionan en producción: `notify/backend/internal/auth/hmac.go` (la cadena canónica, que
// es lo que el servidor recalcula) y `procovar/auth/src/lib/notifications.ts`, que es el
// cliente de Accesos y la prueba de que esa firma entra. La ruta es `/v1/notifications`, la
// firma cubre método, ruta, consulta, cuerpo y sello de tiempo, y las tres cabeceras se
// llaman `X-QBN-*`.
//
// Y LO QUE NO HACE, que es la mitad del diseño:
//
//   - **No decide CUÁNDO avisar.** Eso es del vigía (`vigia_del_canal.go`), y está separado
//     a propósito: quién manda el correo y cuándo merece la pena mandarlo son dos
//     decisiones distintas y la segunda es la que decide si esto sirve o si se silencia.
//   - **No miente.** Sin configuración devuelve un error que NOMBRA la variable que falta,
//     nunca un `nil` de «ya está mandado». Es la lección del canal de Entrega, que existía
//     con clave y secreto y **sin URL**: no salía nada y no se veía en ningún registro.
//   - **No tumba a quien lo llama.** Devuelve error y se sigue. Lo que importa es que los
//     avisos salgan hacia PEDIDO; el correo es secundario.
package api

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"procovar/reparto-api/internal/config"
)

// RutaDeNotify es la puerta pública de notify. Entra EN LA FIRMA, así que no se puede
// tocar sin tocar también lo que se firma — y una ruta distinta de la firmada da un 401
// que manda a mirar el secreto, que es lo último que está mal.
const RutaDeNotify = "/v1/notifications"

// PlazoDeNotify: ninguna petición sin plazo.
//
// Quince segundos y no los veinte de PEDIDO: esto lo llama una tarea de fondo que vuelve
// cada minuto, y una llamada colgada más de una vuelta entera se solaparía consigo misma.
const PlazoDeNotify = 15 * time.Second

// ClienteDeNotify es el http.Client del canal. Variable de paquete para que las pruebas
// puedan apuntarlo a un servidor de mentira, igual que `ClienteDePedido`.
var ClienteDeNotify = &http.Client{Timeout: PlazoDeNotify}

// PrioridadDelAviso: estos avisos son de los que hay que leer hoy, no mañana.
//
// notify admite LOW | NORMAL | HIGH | URGENT y con HIGH la notificación entra en la cola
// `critical` de asynq. URGENT se deja para lo que despierta a alguien de noche; un canal
// atascado se arregla por la mañana.
const PrioridadDelAviso = "HIGH"

// AvisoParaNotify es lo que se manda. No es «un correo»: es un hecho con su clase, y notify
// decide con su plantilla cómo se lee.
type AvisoParaNotify struct {
	// Clase es de qué está hablando —atasco, rechazo, entrada muda—. La usa el vigía para
	// no repetirse y viaja dentro del aviso para poder filtrar en notify.
	Clase string
	// Huella es QUÉ situación concreta se está contando. Junto con la clase forma la clave
	// de idempotencia, que es la segunda red contra el aviso repetido: ver `claveDelAviso`.
	Huella string

	Asunto  string
	Detalle string

	// Datos son las variables de la plantilla. Se mandan además del asunto y el detalle
	// porque una plantilla puede querer pintar el número suelto, y porque el día que esto
	// vaya a un tablero en vez de a un correo los números tienen que venir separados del
	// texto.
	Datos map[string]any

	// Cuando es la hora del aviso. Va por parámetro y no de `time.Now()` para que la
	// prueba pueda fijar el reloj — y para que la clave de idempotencia sea la misma en
	// una misma ventana.
	Cuando time.Time
}

// CanalDeAvisos es la firma del canal. Un tipo y no una llamada directa para que la prueba
// lo sustituya sin levantar nada, igual que `CanalAPedido`.
type CanalDeAvisos func(ctx context.Context, aviso AvisoParaNotify) error

// nuevoCanalDeAvisos devuelve el canal ya configurado, o uno que NO MIENTE cuando no hay a
// dónde mandar.
func nuevoCanalDeAvisos(cfg *config.Config, reg *slog.Logger) CanalDeAvisos {
	if cfg == nil {
		return canalDeAvisosMudo("QB_NOTIFY_URL")
	}
	if falta := cfg.Notify.Falta(); falta != "" {
		return canalDeAvisosMudo(falta)
	}
	n := cfg.Notify
	destino := n.URL + RutaDeNotify

	return func(ctx context.Context, aviso AvisoParaNotify) error {
		cuerpo, err := json.Marshal(map[string]any{
			"type": n.Tipo,
			// El destinatario va en CADA petición: el tipo de notify trae el canal, la
			// plantilla y el SMTP de salida, no la dirección de quien lee.
			"recipient": map[string]any{"email": n.Destino},
			"priority":  PrioridadDelAviso,
			"payload":   payloadDelAviso(aviso),
			// LA SEGUNDA RED CONTRA EL AVISO REPETIDO, y hace falta porque la primera
			// —la memoria del vigía— vive en la RAM de este proceso y se borra en cada
			// despliegue. notify tiene una única sobre `(application_id,
			// idempotency_key)`, así que el mismo hecho en la misma ventana entra una
			// sola vez aunque la api se reinicie diez veces. Ver `claveDelAviso`.
			"idempotencyKey": claveDelAviso(aviso),
		})
		if err != nil {
			return fmt.Errorf("no se pudo armar el aviso para notify: %w", err)
		}

		// Plazo PROPIO, además del que trae el cliente: el contexto que llega es el de la
		// tarea de fondo y vive lo que vive el proceso, así que sin esto una llamada
		// colgada se queda esperando para siempre.
		ctx, cancelar := context.WithTimeout(ctx, PlazoDeNotify)
		defer cancelar()

		pet, err := http.NewRequestWithContext(ctx, http.MethodPost, destino, bytes.NewReader(cuerpo))
		if err != nil {
			return err
		}
		pet.Header.Set("Content-Type", "application/json")
		pet.Header.Set("Accept", "application/json")
		// SE FIRMA CON EL RELOJ DE AHORA, NO CON `aviso.Cuando`. Son dos relojes distintos y
		// tenerlos en el mismo campo era un fallo esperando: `Cuando` fija la ventana de
		// idempotencia y la fecha que se lee en el correo, y puede ser anterior al envío
		// —una prueba con reloj fijo, o un reintento— mientras el sello de la firma tiene
		// que estar en hora. notify rechaza un sello desviado más de
		// `HMAC_TIMESTAMP_SKEW_SECONDS` (300 s por defecto) con `401 signature_expired`, y
		// guarda cada firma como nonce durante el doble de eso: dos envíos del MISMO aviso
		// con el mismo sello dan la misma firma y el segundo rebota con
		// `401 signature_replayed`. Las dos cosas se leen como «401», que manda a mirar el
		// secreto, que es lo último que está mal.
		firmarParaNotify(pet, n.KeyID, n.Secreto, RutaDeNotify, cuerpo, time.Now())

		res, err := ClienteDeNotify.Do(pet)
		if err != nil {
			return err
		}
		defer res.Body.Close()
		// Se lee y se cierra SIEMPRE, también cuando el código es de error: un cuerpo sin
		// vaciar no devuelve la conexión al pool.
		crudo, _ := io.ReadAll(io.LimitReader(res.Body, 1<<16))

		if res.StatusCode < 200 || res.StatusCode >= 300 {
			// EL CUERPO ENTRA EN EL ERROR, recortado. notify contesta problem+json con el
			// motivo dentro —`missing_fields`, `type_not_found`, `signature_expired`— y sin
			// él lo único que queda en el registro es «notify contestó 400», que no dice
			// qué arreglar. El reloj desincronizado y un tipo que no existe en la SPA son
			// dos fallos muy distintos que dan el mismo código. `recortar` es la de
			// `espejo.go`: la misma poda para el mismo problema, no una segunda copia.
			return fmt.Errorf("notify contestó %d: %s", res.StatusCode, recortar(crudo, 400))
		}
		reg.Info("aviso mandado por notify", "clase", aviso.Clase, "http", res.StatusCode)
		return nil
	}
}

// canalDeAvisosMudo es el canal de cuando no hay a dónde mandar: no llama a nadie y
// devuelve un error que nombra la variable que falta.
//
// DEVUELVE ERROR Y NO `nil`, y eso es todo el punto. Lo cómodo mientras falta la
// configuración sería no molestar a nadie, y entonces el vigía apuntaría el aviso como
// mandado y no volvería a intentarlo hasta dentro de seis horas. Un aviso que nadie recibe
// y que además se declara enviado es peor que no avisar, porque nadie lo busca.
func canalDeAvisosMudo(falta string) CanalDeAvisos {
	return func(context.Context, AvisoParaNotify) error {
		return fmt.Errorf("falta %s: el aviso por notify no se mandó", falta)
	}
}

// VariablesDeLaPlantilla son los nombres que PIDE la plantilla de notify, tal cual.
//
// ESTÁN AQUÍ COMO LISTA PARA PODER ATARLOS CON UNA PRUEBA, y no de adorno. Es el mismo
// problema que el §3-bis de `CLAUDE.md`: dos sitios que tienen que decir lo mismo se atan con
// una prueba y no con un comentario, porque un comentario no falla. Renombrar `asunto` a
// `titulo` aquí compila, pasa `vet` y deja todos los avisos muriendo en un fallo de
// validación de notify que sólo se ve en el registro del contenedor — que es justo lo que
// esta función viene a dejar de necesitar.
//
// Salen de la plantilla `aviso-servidor` (`required: asunto, cuerpo, fecha, nivel,
// servidor`). Ver `config.TipoDeAvisoPorDefecto`.
var VariablesDeLaPlantilla = []string{"asunto", "cuerpo", "fecha", "nivel", "servidor"}

// NivelDelAviso es el `nivel` que pide la plantilla.
//
// Los tres avisos de este vigía son «algo está roto y hay que mirarlo», no informativos: una
// salida atascada, un rechazo que nadie va a ver, o un canal que dejó de recibir. Ninguno
// sale si el canal va bien, así que ninguno es un «info».
const NivelDelAviso = "error"

// payloadDelAviso arma las variables que ve la plantilla de notify.
//
// Las CINCO primeras son las requeridas y se llaman como ella las pide. Las demás van
// además, para el día que la plantilla quiera pintar un número suelto o esto vaya a un
// tablero en vez de a un correo: notify no pone `additionalProperties: false`, así que una
// clave de más no rompe nada — lo que rompe un envío es una requerida que no está.
func payloadDelAviso(a AvisoParaNotify) map[string]any {
	p := map[string]any{
		"asunto": a.Asunto,
		"cuerpo": a.Detalle,
		// En RFC3339 con zona, no «hace 12 minutos»: un correo se lee tres horas más tarde
		// y un tiempo relativo dentro de un correo viejo miente.
		"fecha": a.Cuando.UTC().Format(time.RFC3339),
		"nivel": NivelDelAviso,
		// `servidor` en la plantilla es «de quién viene esto». Aquí no viene de una máquina
		// sino de un tubo entre dos aplicaciones, y eso es lo que hay que leer en el asunto
		// para no confundirlo con un aviso del VPS.
		"servidor": "reparto — canal con PEDIDO",

		// Y lo nuestro, que la plantilla de hoy no usa.
		"clase": a.Clase,
	}
	for k, v := range a.Datos {
		p[k] = v
	}
	return p
}

// claveDelAviso es la clave de idempotencia: clase + huella + —sólo a veces— la ventana del
// recordatorio.
//
// LA VENTANA ENTRA EN LAS CLASES QUE SE RECUERDAN Y NO EN LAS DEMÁS, y las dos mitades tienen
// su razón, porque la única de notify es PERMANENTE, sin caducidad:
//
//   - En una avería en curso —la salida atascada, la entrada muda— sin la ventana el
//     recordatorio de las seis horas se quedaría fuera para siempre y el aviso se mandaría una
//     vez en la vida. Con ella, el mismo hecho repetido dentro de la misma ventana se descarta
//     —eso es lo que tapa el reinicio del contenedor— y el recordatorio de la siguiente entra.
//   - En un hecho puntual que no se recuerda —un rechazo de PEDIDO— la ventana sería un
//     agujero: nada baja la cuenta de rechazados, así que cada reinicio en una ventana nueva
//     volvería a mandar el mismo correo idéntico. Sin ventana, la única de notify lo descarta
//     para siempre, que es exactamente lo que se quiere.
//
// Ver `seRecuerda`.
func claveDelAviso(a AvisoParaNotify) string {
	if !seRecuerda(a.Clase) {
		return fmt.Sprintf("reparto-canal:%s:%s", a.Clase, a.Huella)
	}
	ventana := a.Cuando.UTC().Unix() / int64(SilencioLargo/time.Second)
	return fmt.Sprintf("reparto-canal:%s:%s:%d", a.Clase, a.Huella, ventana)
}

// firmarParaNotify pone las tres cabeceras `X-QBN-*`.
//
// La cadena canónica es la de `notify/backend/internal/auth/hmac.go`:
//
//	METODO \n RUTA \n CONSULTA \n sha256hex(CUERPO) \n SELLO
//
// La consulta va vacía porque aquí no hay ninguna, y va vacía **en la cadena también**: no
// es que se omita la línea, es que la línea está y no tiene nada. Quitarla desplaza todo lo
// demás y la firma no cuadra.
//
// EL SELLO ES EN SEGUNDOS y el reloj tiene que estar en hora: notify admite 300 s de
// desvío y fuera de ahí contesta `401 signature_expired`. Si algún día empiezan a fallar
// todos los avisos con un 401, lo primero que hay que mirar es el reloj del contenedor, no
// el secreto.
func firmarParaNotify(pet *http.Request, keyID, secreto, ruta string, cuerpo []byte, ahora time.Time) {
	sello := strconv.FormatInt(ahora.UTC().Unix(), 10)
	huellaDelCuerpo := sha256.Sum256(cuerpo)
	aFirmar := pet.Method + "\n" + ruta + "\n" + "" + "\n" +
		hex.EncodeToString(huellaDelCuerpo[:]) + "\n" + sello

	mac := hmac.New(sha256.New, []byte(secreto))
	mac.Write([]byte(aFirmar))

	pet.Header.Set("X-QBN-Key-Id", keyID)
	pet.Header.Set("X-QBN-Timestamp", sello)
	pet.Header.Set("X-QBN-Signature", hex.EncodeToString(mac.Sum(nil)))
}
