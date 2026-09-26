// EL VIGÍA DEL CANAL CON PEDIDO: decidir CUÁNDO merece la pena despertar a alguien.
//
// Esto es la otra mitad del aviso por notify, y la que decide si sirve. Mandar el correo es
// `canal_notify.go` y son cuarenta líneas; saber cuándo NO mandarlo es este fichero.
//
// LA REGLA QUE MANDA AQUÍ ESTÁ ESCRITA EN `CLAUDE.md` §3-quinquies Y YA COSTÓ UNA VUELTA:
// «un aviso que sale siempre deja de leerse, y entonces tampoco se lee el día que importa».
// El primer intento de otro aviso de este proyecto saltaba en CADA gesto porque un apunte
// está legítimamente pendiente ese instante. Por eso aquí no se avisa de cada fallo suelto:
// veinte avisos esperando de hace un minuto es el ritmo normal de un cierre de ruta, y un
// PEDIDO que tarda cinco minutos no es una avería.
//
// LAS TRES COSAS QUE SÍ SIGNIFICAN ALGO, y son tres y no una:
//
//  1. **La salida atascada** — hay algo en `avisos_a_pedido` en `pendiente` desde hace más
//     de [ListonDeAtasco]. Con el canal sano no pasa de unos segundos. El listón es el
//     MISMO que usa la pantalla (`app/lib/pantallas/webhook/datos/estado_del_webhook.dart`,
//     `estaAtascado`) y el mismo que la pantalla de PEDIDO, acordado entre las dos sesiones
//     el 26/09/2026: si el correo y la pantalla usaran listones distintos, el correo diría
//     «atascado» sobre una pantalla en verde y no habría forma de creerse ninguno.
//  2. **Un rechazo de PEDIDO** — `situacion = 'rechazado'`. Eso NO se reintenta nunca y se
//     queda ahí hasta que una persona decida, así que si nadie abre `/admin/webhook` se
//     queda para siempre. Va **con su motivo literal dentro**: «no existe aquí (¿otra
//     sucursal?)» dice dónde mirar, «no se pudo» no dice nada.
//  3. **La entrada muda** — hace mucho que PEDIDO no empuja nada. Un canal parado no da
//     ningún error, sólo deja de pasar cosas, y desde el 26/09/2026 el ciclo del espejo es
//     de tres horas (`internal/espejo/opciones.go`, `PollConAvisos`), así que la red de
//     seguridad tarda ocho veces más que antes en enterarse.
//
// Y NO SE REPITE. Un aviso cada minuto sobre el mismo atasco es peor que ninguno: son
// 1.440 correos al día y una regla de filtro en el buzón de Jose, que es la forma educada
// de desactivar esto para siempre. Hay DOS frenos y hacen falta los dos, porque el primero
// vive en la RAM de este proceso:
//
//   - **El recuerdo por clase** (aquí): [SilencioMinimo] es un freno duro que ni un cambio
//     de situación rompe, y [SilencioLargo] es el recordatorio de lo que sigue mal.
//   - **La clave de idempotencia de notify** (`claveDelAviso`): tapa el hueco que deja el
//     primero. Un despliegue o un reinicio del contenedor borra la memoria de este proceso,
//     y sin la clave el mismo atasco volvería a avisar en cada arranque — que es justo el
//     día en que hay más arranques.
//
// Cuando la situación DESAPARECE se olvida la clase, a propósito: el episodio siguiente tiene
// que avisar en el acto y no esperarse al final de un silencio que ya no cuenta nada. Pero se
// olvida CON HISTÉRESIS — ver [SanoParaOlvidar]—, porque «cada episodio es una avería nueva» y
// «esto no inunda el buzón» son la misma pregunta y la respuesta fácil se equivoca.
//
// ---------------------------------------------------------------------------
// POR DÓNDE SE PUEDE QUEDAR CALLADO ESTE VIGÍA — 26/09/2026
// ---------------------------------------------------------------------------
//
// Esto lee SÓLO `ResumenDelWebhook`, y hay tres fallos reales del canal que no dejan rastro
// ahí. Están escritos aquí porque un vigía con puntos ciegos que nadie ha apuntado es peor que
// no tenerlo: se confía en él justo el día que no mira.
//
//  1. **Armar una ruta y pasarla a en tránsito NO encolan en el buzón.** `avisarDeFondo` en
//     `rutas.go` dispara y olvida: no escribe en `avisos_a_pedido` ni apunta la tanda en
//     `envios_del_webhook`. Sólo el cierre encola. O sea que con PEDIDO caído toda una mañana
//     de despachos no queda ni una fila `pendiente`, `pendienteMasViejo` sigue nulo y este
//     vigía ve un canal sanísimo mientras se pierde todo. Se arregla encolando como el cierre,
//     no aquí.
//  2. **Un 401 en la puerta de entrada no cuenta como nada.** `POST /api/webhooks/pedido` va
//     detrás de `mediosDelWebhook`, así que con la clave mal la petición muere en el medio y
//     `ApuntarRecepcionDelWebhook` no llega a correr: ni entrada, ni fallo. Hoy mismo hay tres
//     401 de verdad ahí. Con una instancia de PEDIDO llevando la clave vieja y las otras bien,
//     `ultimaEntrada` sigue fresquísima por las que entran y se pierde una tanda de cada tres
//     sin que esto diga una palabra. Lo cazaría un contador de 401/403 en la puerta, no la
//     hora de la última entrada.
//  3. **`ultimaEntrada` mide si hay negocio, no si el canal funciona.** Es la razón de la
//     franja y del fin de semana, y es un techo: un sábado con tres pedidos no se distingue de
//     un sábado con el canal roto mirando si entran pedidos. El testigo que sí los distingue es
//     el propio espejo, que cada tres horas sabe si puede leer el canal aunque no haya nada que
//     leer. Eso no está hecho.
package api

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"sync"
	"time"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/store/sqlc"
)

// ListonDeAtasco: desde cuándo un aviso pendiente deja de ser el ritmo normal.
//
// Diez minutos, EL MISMO NÚMERO QUE LA PANTALLA, y por eso está escrito una vez y en un
// sitio con nombre. Con el canal sano un aviso no pasa de unos segundos en `pendiente`: lo
// intenta el cierre de ruta en el acto y, si falla, el drenaje vuelve cada minuto.
const ListonDeAtasco = 10 * time.Minute

// ListonDeEntradaMuda: cuánto puede llevar PEDIDO sin empujar nada antes de que sea raro.
//
// SE CUENTAN HORAS DE TRABAJO, NO DE RELOJ, y ésa es toda la gracia: PEDIDO empuja cuando
// alguien mueve un pedido, así que de noche no empuja nada y eso es lo correcto. Con un
// listón de reloj, todas las mañanas a las ocho saldría un aviso por las catorce horas de
// silencio de la noche — el aviso que sale siempre, otra vez. Ver [horasDeTrabajoEntre].
//
// SEIS HORAS DE TRABAJO son dos tercios de jornada sin que se mueva un solo pedido en las
// ocho sucursales, que no pasa en un día laborable. Y son además dos ciclos completos del
// espejo (tres horas cada uno): si el webhook estuviera roto pero el espejo vivo, el espejo
// ya habría dado dos vueltas y lo que falta no sería una tanda perdida.
const ListonDeEntradaMuda = 6 * time.Hour

// SilencioMinimo es el freno duro: ni un cambio de situación manda un segundo aviso de la
// misma clase antes de esto.
//
// Es lo que impide que una ráfaga —un atasco que aparece y desaparece cada pocos minutos— se
// convierta en un correo por episodio. También es lo que acota el registro cuando notify está
// caído: un intento fallido cada quince minutos por clase, no uno por minuto.
const SilencioMinimo = 15 * time.Minute

// SilencioEntreRechazos es el freno de la clase de rechazos, y es MUY más largo. Cuatro horas.
//
// POR QUÉ NO LE VALE EL DE QUINCE MINUTOS, medido el 26/09/2026 ejecutando la decisión: para
// una ráfaga comprimida —los ochenta y cuatro rechazos del 16/09 en un cuarto de hora— el
// freno corto basta y salen cinco correos. Pero la forma que tiene el fallo de verdad NO es
// la ráfaga: es el GOTEO. Una clave caducada en una sucursal no rechaza ochenta y cuatro en
// quince minutos, rechaza uno cada veinte minutos toda la jornada. Y como la huella de esta
// clase es la CUENTA, cada rechazo nuevo es una situación nueva: con el freno de quince
// minutos eso son cuarenta y tres correos en un día, cuatro por hora sin parar.
//
// Con cuatro horas el goteo cabe en seis correos al día como mucho, y cada uno dice cuántos
// van: «12 rechazados», «19 rechazados». Se pierde inmediatez sobre el segundo rechazo de la
// tarde, y eso no cuesta nada — el primero ya dijo dónde mirar.
const SilencioEntreRechazos = 4 * time.Hour

// silencioMinimoDe devuelve el freno de una clase.
func silencioMinimoDe(clase string) time.Duration {
	if clase == ClaseRechazoDePedido {
		return SilencioEntreRechazos
	}
	return SilencioMinimo
}

// SilencioLargo es el recordatorio de lo que sigue mal sin cambiar.
//
// Seis horas: si algo lleva medio día atascado hay que volver a decirlo, porque el primer
// correo se lee y se aparca. Más corto convierte una avería de fin de semana en una tanda
// de correos; más largo y un atasco del viernes por la tarde llega al lunes con un solo
// aviso enterrado.
const SilencioLargo = 6 * time.Hour

// TopeDeMotivosEnUnAviso: cuántos rechazos se citan con nombre y motivo dentro del correo.
//
// Cinco. El correo tiene que decir QUÉ mirar, no ser el informe: con cinco se ve el patrón
// —todos el mismo motivo, o cinco motivos distintos— y para el resto está `/admin/webhook`,
// que es donde vive la bandeja completa.
const TopeDeMotivosEnUnAviso = 5

// Las clases de aviso. Son la clave del recuerdo y viajan dentro del correo, así que
// renombrar una es empezar a contar de cero: durante un silencio se mandaría un aviso
// repetido de la clase vieja con nombre nuevo.
const (
	ClaseSalidaAtascada  = "salida_atascada"
	ClaseRechazoDePedido = "rechazo_de_pedido"
	ClaseEntradaMuda     = "entrada_muda"
)

// VigiaDelCanal mira cómo va el canal y avisa cuando hace falta.
//
// Guarda el recuerdo de lo que ya avisó EN MEMORIA y no en la base a propósito: es una
// decisión de este proceso sobre su propio ruido, no un dato del reparto, y meterla en
// Postgres obligaría a una migración y a una tabla que nadie consulta. Lo que cuesta —que
// un reinicio la borra— lo tapa la clave de idempotencia de notify, que sí es permanente.
type VigiaDelCanal struct {
	srv *Servidor
	reg *slog.Logger

	// ahora es el reloj. Inyectable para poder probar los silencios sin esperarlos: una
	// prueba que duerme seis horas no es una prueba.
	ahora func() time.Time

	mu       sync.Mutex
	recuerdo map[string]recuerdoDeAviso
}

// recuerdoDeAviso es lo que se sabe de la última vez que se habló de una clase.
//
// LA DIFERENCIA ENTRE `intento` Y `mandado` ES LA QUE IMPIDE MENTIR: un aviso que se intentó y
// no salió —notify caído, o sin configurar— NO cuenta como mandado y hay que volver a por él,
// pero sí cuenta para el freno, que es lo que evita llenar el registro de intentos.
type recuerdoDeAviso struct {
	// huella es QUÉ situación se contó la última vez que el aviso SALIÓ de verdad.
	huella string
	// mandado es cuándo salió. Cero = NUNCA salió ninguno de esta clase, y no significa
	// nada más: es lo que hace que un aviso fallido se reintente. `olvidar` no lo toca.
	mandado time.Time
	// intento es cuándo se intentó por última vez, saliera o no.
	intento time.Time
	// sano es desde cuándo la situación ya NO se da. Cero = se está dando ahora mismo. Es
	// la histéresis: ver `olvidar` y [SanoParaOlvidar].
	sano time.Time
}

// NuevoVigiaDelCanal lo arma. `ahora` nil usa el reloj de verdad.
func NuevoVigiaDelCanal(srv *Servidor, ahora func() time.Time) *VigiaDelCanal {
	if ahora == nil {
		ahora = func() time.Time { return time.Now().UTC() }
	}
	reg := slog.Default()
	if srv != nil && srv.reg != nil {
		reg = srv.reg
	}
	return &VigiaDelCanal{srv: srv, reg: reg, ahora: ahora, recuerdo: map[string]recuerdoDeAviso{}}
}

// Mirar lee cómo va el canal y avisa de lo que haga falta.
//
// NO DEVUELVE ERROR, y es deliberado: lo llama el temporizador del drenaje, no una persona,
// y lo único razonable que puede hacer con un fallo es volver a mirar dentro de un minuto.
// Lo que sí hace es dejarlo escrito donde se puede ver.
func (v *VigiaDelCanal) Mirar(ctx context.Context, a *alcance.Acotado) {
	if v == nil || a == nil {
		return
	}
	res, err := a.ResumenDelWebhook(ctx)
	if err != nil {
		v.reg.Error("no se pudo leer cómo va el canal con PEDIDO: no se vigila esta vuelta", "err", err)
		return
	}
	ahora := v.ahora()

	v.mirarLaSalidaAtascada(ctx, res, ahora)
	v.mirarLosRechazos(ctx, a, res, ahora)
	v.mirarLaEntradaMuda(ctx, res, ahora)
}

// mirarLaSalidaAtascada: hay algo esperando desde hace demasiado.
//
// LA HUELLA DE ESTA CLASE ES CONSTANTE, y no es pereza: es la decisión que cierra el parpadeo.
// La cuenta de pendientes se mueve en cada vuelta del drenaje, y la hora del más viejo cambia
// en cada episodio —vaciar el buzón y volver a atascarse trae un más viejo nuevo—. Con
// cualquiera de las dos como huella, dos episodios seguidos entran por «la situación cambió» y
// avisan los dos: eso son treinta correos en ocho horas de red mala, medido. Pero **la salida
// atascada es UNA situación**, no una por aviso atascado: lo que hay que contar es que no sale
// nada, y eso no cambia porque cambie cuál es el primero de la cola. Con la huella constante,
// los episodios seguidos entran por el recordatorio de seis horas, que es lo correcto, y una
// avería nueva de verdad se separa por la hora en verde de [SanoParaOlvidar].
//
// Los NÚMEROS del aviso —cuántos esperan, desde cuándo el más viejo— siguen siendo los de
// ahora mismo: lo que no dependen de ellos es la decisión de mandarlo.
func (v *VigiaDelCanal) mirarLaSalidaAtascada(ctx context.Context, res sqlc.ResumenDelWebhookRow, ahora time.Time) {
	if !res.PendienteMasViejo.Valid || ahora.Sub(res.PendienteMasViejo.Time) <= ListonDeAtasco {
		v.olvidar(ClaseSalidaAtascada, ahora)
		return
	}
	masViejo := res.PendienteMasViejo.Time.UTC()
	llevaAsi := ahora.Sub(masViejo)

	v.avisar(ctx, AvisoParaNotify{
		Clase: ClaseSalidaAtascada,
		// Constante a propósito. Ver la cabecera de esta función.
		Huella: "atascada",
		Asunto: "Reparto: la salida hacia PEDIDO está atascada",
		Detalle: fmt.Sprintf(
			"Hay %d avisos esperando para salir hacia PEDIDO y el más viejo lleva %s sin "+
				"irse (desde las %s UTC). Con el canal sano un aviso no pasa de unos "+
				"segundos ahí. Mientras esto dure, los pedidos que el reparto ya entregó "+
				"siguen «en proceso» en PEDIDO y el vendedor no ve nada. La bandeja entera "+
				"está en /admin/webhook.",
			res.AvisosPendientes, enPalabras(llevaAsi), masViejo.Format("15:04"),
		),
		Datos: map[string]any{
			"pendientes":        res.AvisosPendientes,
			"masViejoDesde":     masViejo.Format(time.RFC3339),
			"masViejoMinutos":   int(llevaAsi.Minutes()),
			"rechazados":        res.AvisosRechazados,
			"listonDeAtascoMin": int(ListonDeAtasco.Minutes()),
		},
		Cuando: ahora,
	})
}

// mirarLosRechazos: PEDIDO recibió el aviso y dijo que NO.
//
// OJO CON ESTA ALARMA: HOY CASI NO PUEDE SALTAR, y eso no es cosa del vigía — 26/09/2026. El
// drenaje marca `rechazado` sólo cuando `parte.Ok` es cierto y PEDIDO aplicó menos de los que
// se mandaron (`drenaje_del_buzon.go`), pero `ParteAPedido.Ok` es `Error == ""` y
// `mandarTanda` (`canal_pedido.go`) pone el motivo del rechazo en `Error` aunque PEDIDO haya
// contestado 200 perfectamente. O sea que un rechazo de verdad entra por la rama de «no se
// pudo ni preguntar» y el aviso se queda `pendiente`, reintentándose cada minuto para siempre:
// lo que salta entonces es la alarma del ATASCO, diciendo «atascado» sobre lo que en realidad
// es un rechazo — justo la confusión que estas dos tablas se crearon para eliminar.
//
// SE DEJA ESCRITO AQUÍ Y NO SE ARREGLA AQUÍ: el arreglo está en `canal_pedido.go` y
// `drenaje_del_buzon.go` y lo lleva otra mano. Lo que no puede pasar es que quede una alarma
// vigilando un estado inalcanzable sin que lo diga el código, porque eso es una prueba verde
// que no prueba nada y alguien lo descubre tres meses después. En cuanto el drenaje distinga
// los dos casos, esta alarma empieza a servir sin tocar una línea de aquí.
//
// LA CUENTA ES UN ACUMULADO DE TODA LA VIDA DEL DESPLIEGUE, no «los que hay ahora».
// `avisos_a_pedido` no se purga nunca y nada baja `AvisosRechazados`: `/api/admin/webhook` es
// un GET y en `internal/alcance` no hay ninguna operación inversa. Por eso el aviso dice
// «acumulados» y no «hay»: dentro de seis meses ese número llevará dentro los de hace meses,
// ya resueltos a mano, y un correo que dice «PEDIDO rechazó 1.482 avisos» sobre un rechazo
// nuevo es un correo que miente con un número creíble.
//
// La huella es la CUENTA, al contrario que en el atasco, y también a propósito: cada rechazo
// nuevo es un hecho nuevo que nadie va a ver porque no se reintenta nunca. Lo que evita que un
// goteo se convierta en cuarenta correos al día es [SilencioEntreRechazos].
//
// LOS MOTIVOS SE PIDEN SÓLO SI SE VA A AVISAR. Preguntarlos en cada vuelta serían 1.440
// consultas al día para tirar 1.439, y la que importa es la primera.
func (v *VigiaDelCanal) mirarLosRechazos(
	ctx context.Context, a *alcance.Acotado, res sqlc.ResumenDelWebhookRow, ahora time.Time,
) {
	if res.AvisosRechazados == 0 {
		v.olvidar(ClaseRechazoDePedido, ahora)
		return
	}
	huella := fmt.Sprintf("%d", res.AvisosRechazados)
	if !v.hayQueAvisar(ClaseRechazoDePedido, huella, ahora) {
		return
	}

	rechazado := sqlc.AvisoAPedidoEstadoRechazado
	filas, err := a.ListarAvisosAPedido(ctx, sqlc.ListarAvisosAPedidoParams{
		Situacion: &rechazado, Tope: TopeDeMotivosEnUnAviso,
	})
	if err != nil {
		// SE APUNTA EL INTENTO Y NO SE MANDA NADA. Sin los motivos el correo diría «hay 12
		// rechazados» y nada más, que es la mitad del aviso que no sirve: el motivo literal
		// es lo que dice dónde mirar. Apuntar el intento es lo que evita repetir esta misma
		// consulta fallida cada minuto.
		v.reg.Error("hay rechazos de PEDIDO pero no se pudieron leer sus motivos: no se avisa sin ellos",
			"rechazados", res.AvisosRechazados, "err", err)
		v.apuntarIntento(ClaseRechazoDePedido, ahora)
		return
	}

	v.avisar(ctx, AvisoParaNotify{
		Clase:  ClaseRechazoDePedido,
		Huella: huella,
		Asunto: fmt.Sprintf("Reparto: PEDIDO ha rechazado %d avisos de estado", res.AvisosRechazados),
		Detalle: fmt.Sprintf(
			"PEDIDO recibió estos avisos perfectamente y dijo que NO. Un rechazo no se "+
				"reintenta —repetir lo mismo da lo mismo— así que se quedan ahí hasta que "+
				"una persona decida. Los últimos:\n\n%s\n\nEl número son los rechazados "+
				"ACUMULADOS desde que se desplegó esto, no los de hoy: nada los quita y no "+
				"baja solo. La bandeja entera, en /admin/webhook.",
			motivosEnTexto(filas),
		),
		Datos: map[string]any{
			"rechazados": res.AvisosRechazados,
			"pendientes": res.AvisosPendientes,
			"motivos":    motivosEnTexto(filas),
		},
		Cuando: ahora,
	})
}

// mirarLaEntradaMuda: hace media jornada que PEDIDO no empuja nada.
//
// `ultimaEntrada` nula es NUNCA, y nunca NO avisa. No es lo mismo que «hace mucho»: un
// reparto recién desplegado no ha recibido nada todavía, y mandar un correo por eso sería
// avisar en cada estreno de entorno. Que el canal no se haya estrenado se ve al desplegar,
// que es cuando lo mira quien despliega.
func (v *VigiaDelCanal) mirarLaEntradaMuda(ctx context.Context, res sqlc.ResumenDelWebhookRow, ahora time.Time) {
	if !res.UltimaEntrada.Valid {
		v.olvidar(ClaseEntradaMuda, ahora)
		return
	}
	ultima := res.UltimaEntrada.Time.UTC()
	callado := horasDeTrabajoEntre(ultima, ahora)
	if callado <= ListonDeEntradaMuda {
		v.olvidar(ClaseEntradaMuda, ahora)
		return
	}

	v.avisar(ctx, AvisoParaNotify{
		Clase:  ClaseEntradaMuda,
		Huella: ultima.Format(time.RFC3339),
		Asunto: "Reparto: PEDIDO no está empujando nada",
		Detalle: fmt.Sprintf(
			"La última tanda que entró por el webhook fue el %s UTC: %s de jornada sin "+
				"recibir un solo pedido. Un canal parado no da ningún error, sólo deja de "+
				"pasar cosas. El barrido del espejo son tres horas, así que ya ha dado dos "+
				"vueltas sin traer nada por su cuenta. Mira si PEDIDO sigue empujando y si "+
				"PEDIDO_WEBHOOK_KEY y PEDIDO_WEBHOOK_SECRET siguen cuadrando en los dos "+
				"lados. El detalle está en /admin/webhook.",
			ultima.Format("2006-01-02 15:04"), enPalabras(callado),
		),
		Datos: map[string]any{
			"ultimaEntrada":       ultima.Format(time.RFC3339),
			"horasDeTrabajoMudas": int(callado.Hours()),
			"escritosHoy":         res.EscritosHoy,
			"rechazadosAlEntrar":  res.RechazadosAlEntrar,
		},
		Cuando: ahora,
	})
}

// avisar manda el aviso si toca, y apunta lo que pasó.
//
// UN FALLO AL AVISAR NO PUEDE TUMBAR NADA. Lo que importa es que los avisos salgan hacia
// PEDIDO; el correo es secundario y por eso aquí se registra y se sigue. Lo que sí se hace
// es NO apuntarlo como mandado: un aviso que no salió no está mandado, y hay que volver.
func (v *VigiaDelCanal) avisar(ctx context.Context, aviso AvisoParaNotify) {
	if !v.hayQueAvisar(aviso.Clase, aviso.Huella, aviso.Cuando) {
		return
	}
	canal := v.canal()
	if err := canal(ctx, aviso); err != nil {
		v.reg.Error("no se pudo avisar por notify de un fallo del canal con PEDIDO",
			"clase", aviso.Clase, "err", err)
		v.apuntarIntento(aviso.Clase, aviso.Cuando)
		return
	}
	v.apuntarMandado(aviso.Clase, aviso.Huella, aviso.Cuando)
}

// canal devuelve el canal de avisos, o uno mudo si el servidor se montó sin él.
//
// Un `nil` aquí sería un vigía que no avisa de nada y no lo dice, que es el peor de los
// desenlaces: todo en verde y ningún correo. Con el mudo, cada intento deja en el registro
// qué le falta.
func (v *VigiaDelCanal) canal() CanalDeAvisos {
	if v.srv == nil || v.srv.avisos == nil {
		return canalDeAvisosMudo("QB_NOTIFY_URL")
	}
	return v.srv.avisos
}

// hayQueAvisar es la decisión entera, en cinco reglas y por este orden.
func (v *VigiaDelCanal) hayQueAvisar(clase, huella string, ahora time.Time) bool {
	v.mu.Lock()
	defer v.mu.Unlock()

	r, hay := v.recuerdo[clase]
	// LA SITUACIÓN SE ESTÁ DANDO AHORA, así que se borra la marca de «esto iba bien». Sin
	// esto la histéresis de `olvidar` acumularía la hora de verde a trozos, en un parpadeo
	// donde no ha habido una hora buena seguida ni por casualidad — y entonces el recuerdo se
	// borraría a mitad del parpadeo y volveríamos al correo por episodio.
	if hay && !r.sano.IsZero() {
		r.sano = time.Time{}
		v.recuerdo[clase] = r
	}

	switch {
	case !hay:
		// Primera vez de esta clase, o la situación había desaparecido y se olvidó. Sale
		// en el acto: es justo el aviso que hay que ver aparecer.
		return true
	case ahora.Sub(r.intento) < silencioMinimoDe(clase):
		// EL FRENO DURO. Ni un cambio de situación lo rompe: es lo que convierte un PEDIDO
		// parpadeando en un correo y no en cuarenta. Cada clase tiene el suyo, porque el
		// goteo de rechazos necesita uno mucho más largo — ver `silencioMinimoDe`.
		return false
	case r.mandado.IsZero():
		// Se intentó y NUNCA salió —notify caído, o sin configurar—. Eso no está avisado.
		return true
	case huella != r.huella:
		// La situación cambió: un atasco nuevo, más rechazos. Es un hecho nuevo.
		return true
	case !seRecuerda(clase):
		// Lo mismo de antes y de una clase que no se recuerda: ya está contado y no se
		// repite nunca. Ver `seRecuerda`.
		return false
	default:
		// Lo mismo de antes: sólo el recordatorio de lo que sigue mal.
		return ahora.Sub(r.mandado) >= SilencioLargo
	}
}

func (v *VigiaDelCanal) apuntarMandado(clase, huella string, ahora time.Time) {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.recuerdo[clase] = recuerdoDeAviso{huella: huella, mandado: ahora, intento: ahora}
}

// apuntarIntento deja constancia de que se intentó y NO salió: se conserva lo último que sí
// se mandó, para que el aviso que no llegó siga contando como no llegado.
func (v *VigiaDelCanal) apuntarIntento(clase string, ahora time.Time) {
	v.mu.Lock()
	defer v.mu.Unlock()
	r := v.recuerdo[clase]
	r.intento = ahora
	v.recuerdo[clase] = r
}

// SanoParaOlvidar: cuánto tiene que llevar BIEN una clase para que se dé por pasada.
//
// ES LA HISTÉRESIS, Y SIN ELLA ESTO NO SIRVE — dos intentos costó, los dos medidos el
// 26/09/2026 ejecutando la decisión contra un PEDIDO parpadeando:
//
//  1. El primero hacía `delete` del recuerdo en cuanto la situación desaparecía. Cada
//     episodio entraba por «primera vez de esta clase» y avisaba en el acto: CUARENTA correos
//     en ocho horas de parpadeo de doce minutos.
//  2. El segundo conservaba el `intento`, así que el freno de quince minutos seguía en pie —
//     pero quince minutos ES el techo, y con la condición entrando y saliendo el techo se
//     alcanza: TREINTA correos en ocho horas con un parpadeo de dieciséis minutos, que además
//     es el peor caso posible (el más viejo tiene que envejecer otros diez para volver a
//     contar, así que el periodo natural no baja de diez u once). De cuarenta a treinta no es
//     un arreglo, es el mismo orden de magnitud.
//
// Y ese parpadeo es la forma que tiene el fallo AQUÍ: la conexión de Cuba alternando con
// Starlink, o PEDIDO reiniciándose en un despliegue. Una avería continua de un día da cuatro
// correos y está bien; la misma avería intermitente daba treinta en ocho horas.
//
// Lo que faltaba es lo mismo que ya se aplicó a los rechazos: DOS EPISODIOS SEGUIDOS NO SON
// DOS AVERÍAS. Una hora seguida en verde es lo que las separa — un parpadeo no la acumula
// nunca, y una tarde tranquila sí. Pasada esa hora se borra el recuerdo entero y la avería
// siguiente avisa en el acto, que es lo que hay que ver aparecer.
const SanoParaOlvidar = time.Hour

// olvidar apunta que una clase está en verde, y la da por pasada cuando lleva bastante así.
//
// NO BORRA `mandado` NI `intento` MIENTRAS NO BORRE LA ENTRADA ENTERA. Borrarlos dejaba el
// cero de `mandado` significando dos cosas —«nunca salió, notify caído» y «esto ya se
// arregló»— y el `case r.mandado.IsZero()` de [VigiaDelCanal.hayQueAvisar] atendía a las dos
// sin distinguirlas: por ahí volvía a colarse el aviso por episodio.
func (v *VigiaDelCanal) olvidar(clase string, ahora time.Time) {
	v.mu.Lock()
	defer v.mu.Unlock()
	r, hay := v.recuerdo[clase]
	if !hay {
		return
	}
	if r.sano.IsZero() {
		r.sano = ahora
	}
	if ahora.Sub(r.sano) >= SanoParaOlvidar {
		delete(v.recuerdo, clase)
		return
	}
	v.recuerdo[clase] = r
}

// seRecuerda dice si una clase vuelve a avisar pasado [SilencioLargo] aunque nada cambie.
//
// LOS RECHAZOS NO SE RECUERDAN, y es por una razón que se midió — 26/09/2026. Un rechazo no
// se reintenta y NADA lo quita: `/api/admin/webhook` es un GET y en `internal/alcance` no hay
// ninguna operación inversa, así que la cuenta de rechazados no baja ni cuando la persona ya
// lo ha visto y decidido — sólo baja con un UPDATE a mano en la base. Con el recordatorio
// puesto, UN solo rechazado que nadie limpia son cuatro correos al día, ciento veinte en un
// mes, todos idénticos. Eso es el §3-quinquies de `CLAUDE.md` cumpliéndose al pie de la
// letra: deja de leerse, y el día que importa tampoco se lee.
//
// Un rechazo es un HECHO PUNTUAL, no una avería en curso: se cuenta cuando pasa, y si llegan
// más se vuelve a contar porque la huella cambia. Lo que no se hace es repetir el mismo.
//
// El atasco y la entrada muda sí se recuerdan, porque sí son averías en curso: lo que sigue
// mal medio día hay que volver a decirlo, que el primer correo se lee y se aparca.
//
// Y LO QUE FALTA PARA CERRARLO DE VERDAD es el botón de «visto» en la pantalla del canal, que
// haga bajar el número. Mientras no exista, esto avisa una vez por rechazo y no más.
func seRecuerda(clase string) bool { return clase != ClaseRechazoDePedido }

// ---------------------------------------------------------------------------
// La jornada, para no avisar de la noche
// ---------------------------------------------------------------------------

// La franja de trabajo, EN UTC: de 12:00 a 21:00, que en Cuba son de las 07:00 a las 16:00
// (una hora más cuando allá corre el horario de verano).
//
// POR QUÉ EN UTC Y CON UN NÚMERO FIJO: este servicio no maneja husos en ningún otro sitio
// —todo va en UTC— y la imagen del contenedor no lleva la base de datos de husos, así que un
// `time.LoadLocation("America/Havana")` fallaría dentro y funcionaría en el portátil, que es
// la peor de las dos cosas. La hora de verano desplaza la franja una hora; con nueve horas
// de ancho y un listón de seis, eso no cambia ninguna decisión.
//
// Y ESTOS NÚMEROS SALEN DE MIRAR LOS DATOS, NO DE SUPONER LA JORNADA — 26/09/2026. El primer
// intento puso la franja de 12:00 a 02:00 UTC (07:00 a 21:00 en Cuba), que es el horario que
// uno imagina y no el que tiene PEDIDO: midiendo los huecos reales entre movimientos de
// pedido de los últimos sesenta días, la actividad se apaga sobre las 20:30 UTC y arranca
// sobre las 12:00. Con la franja ancha, las cinco horas de nadie entre 21:00 y 02:00 se
// contaban como jornada y un jueves normal daba SEIS HORAS EXACTAS de silencio «de trabajo»:
// el aviso a un minuto de saltar cada tarde.
const (
	FranjaDeTrabajoDesde = 12 * time.Hour
	FranjaDeTrabajoDura  = 9 * time.Hour
)

// esDiaDeTrabajo: sábado y domingo NO cuentan, y eso no es una comodidad.
//
// LA FRANJA ARREGLA LA NOCHE Y NO ARREGLABA EL FIN DE SEMANA, que es el mismo fallo a otra
// escala, y esto se cazó midiendo — 26/09/2026. De los huecos reales de los últimos sesenta
// días, NUEVE pasaban del listón contándolo sólo por franjas, y los nueve eran los cuatro
// fines de semana del mes: un domingo en PEDIDO son tres o diez pedidos movidos en todo el
// día contra los trescientos o novecientos de un laborable. O sea dos o tres correos cada
// sábado y cada domingo, para siempre, que es la definición del aviso que se deja de leer.
//
// Y NO SE ARREGLA SUBIENDO EL LISTÓN: para tapar un fin de semana entero habría que pasar de
// las veintiocho horas de trabajo, y entonces una avería de un martes tardaría dos días en
// verse, que es no tener aviso.
//
// LO QUE CUESTA, dicho claro: una avería que empiece un sábado no se ve hasta el lunes. Es el
// precio y es el correcto, porque un sábado con tres pedidos no se distingue de un sábado con
// el canal roto MIRANDO SI ENTRAN PEDIDOS. El testigo que sí los distinguiría es el propio
// espejo, que cada tres horas sabe si puede leer el canal aunque no haya nada que leer; eso
// no está hecho y está en «lo que falta».
func esDiaDeTrabajo(d time.Time) bool {
	switch d.Weekday() {
	case time.Saturday, time.Sunday:
		return false
	default:
		return true
	}
}

// TopeDeDiasQueSeCuentan acota el recorrido de [horasDeTrabajoEntre].
//
// Sin tope, una `ultimaEntrada` de hace dos años recorrería setecientos días para contestar
// algo que ya se sabía al tercero. Recortar no cambia la respuesta: cuarenta días de franjas
// son quinientas sesenta horas de trabajo, que están muy por encima de cualquier listón.
const TopeDeDiasQueSeCuentan = 40

// horasDeTrabajoEntre cuenta cuánto del hueco entre dos instantes cae dentro de la jornada.
//
// ES LA GUARDA QUE EVITA EL AVISO DE CADA MAÑANA. PEDIDO empuja cuando alguien mueve un
// pedido, así que de noche no empuja nada — y eso es lo correcto, no una avería. Con un
// listón de reloj, a las ocho de la mañana llevaríamos catorce horas de silencio legítimo y
// saldría un correo todos los días; con éste, la noche suma cero.
func horasDeTrabajoEntre(desde, hasta time.Time) time.Duration {
	desde, hasta = desde.UTC(), hasta.UTC()
	if !hasta.After(desde) {
		return 0
	}
	// Se empieza un día ANTES por si la franja se derramara en el día siguiente. Hoy no lo
	// hace —12:00 + 9 h cierra a las 21:00 del mismo día— pero el día que se toque el ancho
	// esto seguirá contando bien, y descubrir que falta una hora y media al principio de cada
	// silencio es de los fallos que no se ven: el número sale creíble y sale corto.
	dia := time.Date(desde.Year(), desde.Month(), desde.Day(), 0, 0, 0, 0, time.UTC).AddDate(0, 0, -1)

	var total time.Duration
	for i := 0; i < TopeDeDiasQueSeCuentan && !dia.After(hasta); i++ {
		if esDiaDeTrabajo(dia) {
			abre := dia.Add(FranjaDeTrabajoDesde)
			total += solape(desde, hasta, abre, abre.Add(FranjaDeTrabajoDura))
		}
		dia = dia.AddDate(0, 0, 1)
	}
	return total
}

// solape devuelve cuánto se pisan dos intervalos. Cero si no se tocan.
func solape(aDesde, aHasta, bDesde, bHasta time.Time) time.Duration {
	inicio := aDesde
	if bDesde.After(inicio) {
		inicio = bDesde
	}
	fin := aHasta
	if bHasta.Before(fin) {
		fin = bHasta
	}
	if !fin.After(inicio) {
		return 0
	}
	return fin.Sub(inicio)
}

// ---------------------------------------------------------------------------
// Texto para personas
// ---------------------------------------------------------------------------

// enPalabras pone una duración en algo que se lee en un correo.
//
// «22m» o «3h 10m», no «1320000000000» ni «22.000000 minutos»: esto lo lee alguien en el
// teléfono, y la cifra tiene que decir de un vistazo si es un temblor o una avería.
func enPalabras(d time.Duration) string {
	if d < time.Minute {
		return "menos de un minuto"
	}
	horas := int(d.Hours())
	minutos := int(d.Minutes()) % 60
	if horas == 0 {
		return fmt.Sprintf("%dm", minutos)
	}
	return fmt.Sprintf("%dh %02dm", horas, minutos)
}

// motivosEnTexto arma la lista de rechazos que va DENTRO del correo.
//
// EL MOTIVO VA LITERAL Y SIN TOCAR. Es la regla de `CLAUDE.md` §3-quinquies: «no existe aquí
// (¿otra sucursal?)» le dice a alguien qué mirar y «no se pudo guardar» no le dice nada.
// Resumirlo, agruparlo o traducirlo a un código es perder justo el dato por el que se manda
// el correo.
//
// El folio va delante porque es lo que la gente de la oficina sabe buscar; el id de PEDIDO
// detrás, que es lo que se busca en la base. Un aviso sin folio enseña el id, no un hueco.
func motivosEnTexto(filas []sqlc.ListarAvisosAPedidoRow) string {
	if len(filas) == 0 {
		return "(no se pudo leer ningún motivo)"
	}
	var b strings.Builder
	for _, f := range filas {
		quien := f.PedidoID
		if f.Folio != nil && strings.TrimSpace(*f.Folio) != "" {
			quien = *f.Folio + " (" + f.PedidoID + ")"
		}
		motivo := "PEDIDO no dijo por qué"
		if f.Motivo != nil && strings.TrimSpace(*f.Motivo) != "" {
			motivo = *f.Motivo
		}
		fmt.Fprintf(&b, "  · %s → %s: %s\n", quien, f.Estado, motivo)
	}
	return strings.TrimRight(b.String(), "\n")
}
