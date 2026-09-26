package api

import (
	"context"
	"log/slog"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/store/sqlc"
)

// UN CANAL ROTO TIENE QUE AVISAR — Y UN CANAL SANO TIENE QUE CALLARSE.
//
// Hasta el 26/09/2026 el canal con PEDIDO podía romperse entero sin que se enterara nadie:
// un aviso atascado o rechazado sólo se veía si alguien abría `/admin/webhook`, y un PEDIDO
// caído no levanta ninguna alarma porque no da ningún error — sólo deja de pasar cosas.
// Jose, 26/09/2026: «créame un mensaje en notify para cuando haya un error de esto».
//
// LAS PRUEBAS VAN EN PAREJA Y LA SEGUNDA MITAD ES LA QUE IMPORTA. «Avisa» se cumple
// avisando siempre, y un aviso que sale siempre deja de leerse —y entonces tampoco se lee el
// día que importa (`CLAUDE.md` §3-quinquies, que ya costó una vuelta con otro aviso de este
// mismo proyecto)—. Así que por cada prueba de que el aviso sale hay otra de que NO sale:
//
//   - atascado sí / veinte pendientes de hace tres minutos no
//   - rechazado sí / ninguno rechazado no / el mismo rechazado nunca dos veces
//   - media jornada sin recibir sí / una noche entera no / UN FIN DE SEMANA no
//   - el mismo atasco dos vueltas seguidas: UN aviso, no dos
//   - PEDIDO parpadeando una hora: unos pocos, no uno por episodio
//
// LAS FECHAS DE LOS CASOS NO SON AL AZAR, y hay que mirarlas antes de tocar una: el listón de
// la entrada muda se cuenta en horas de JORNADA LABORABLE, así que un caso escrito en sábado
// da cero y pasa por la razón equivocada. El reloj de las pruebas del atasco es un jueves a
// propósito.

// canalFalso es la parte de la base que le hace falta al vigía, encima del buzón falso que
// ya usa el drenaje (`el_buzon_no_pierde_avisos_test.go`).
type canalFalso struct {
	buzonFalso

	resumen  sqlc.ResumenDelWebhookRow
	rechazos []sqlc.ListarAvisosAPedidoRow
	// errorAlLeerMotivos: para probar que sin motivos NO se manda un correo a medias.
	errorAlLeerMotivos error
	// motivosPedidos cuenta las consultas de motivos: se piden sólo cuando se va a avisar.
	motivosPedidos int
	// comoLosPidio guarda los PARÁMETROS con los que se pidieron. Un doble que ignora los
	// params deja sin vigilar justo lo que se copia a mano en Go, que es el agujero del
	// §3-bis de `CLAUDE.md`: quitar un campo ahí deja toda la suite en verde.
	comoLosPidio []sqlc.ListarAvisosAPedidoParams
	// siguiendoAlBuzon hace que el resumen refleje lo que el drenaje acaba de hacer, como en
	// producción. Ver `ResumenDelWebhook` aquí abajo.
	siguiendoAlBuzon bool
}

func (c *canalFalso) ResumenDelWebhook(context.Context) (sqlc.ResumenDelWebhookRow, error) {
	// EL RESUMEN SALE DE LA BASE, así que en producción refleja lo que el drenaje acabó de
	// hacer un instante antes. Con `siguiendoAlBuzon` el doble lo imita: en cuanto un aviso se
	// marca enviado, deja de haber pendientes. Sin esto, el ORDEN entre drenar y mirar no se
	// puede probar, porque el resumen sale igual se mire antes o después.
	if c.siguiendoAlBuzon && len(c.enviados) > 0 {
		return sqlc.ResumenDelWebhookRow{}, nil
	}
	return c.resumen, nil
}

func (c *canalFalso) ListarAvisosAPedido(
	_ context.Context, p sqlc.ListarAvisosAPedidoParams,
) ([]sqlc.ListarAvisosAPedidoRow, error) {
	c.motivosPedidos++
	c.comoLosPidio = append(c.comoLosPidio, p)
	if c.errorAlLeerMotivos != nil {
		return nil, c.errorAlLeerMotivos
	}
	return c.rechazos, nil
}

// elReloj: JUEVES 24/09/2026 a las 15:00 UTC, dentro de la jornada (la franja va de 12:00 a
// 21:00 UTC). Un instante fijo y laborable: los silencios se prueban sin esperarlos —una
// prueba que duerme seis horas no es una prueba— y ningún caso pasa por ser fin de semana.
var elReloj = time.Date(2026, 9, 24, 15, 0, 0, 0, time.UTC)

func marca(t time.Time) pgtype.Timestamptz { return pgtype.Timestamptz{Time: t, Valid: true} }

// vigiaDePrueba monta el vigía con un canal de avisos de mentira que apunta lo que sale.
func vigiaDePrueba(t *testing.T, fallo error) (*VigiaDelCanal, *[]AvisoParaNotify, *int) {
	t.Helper()
	var salieron []AvisoParaNotify
	intentos := 0
	s := &Servidor{
		reg: slog.New(slog.DiscardHandler),
		avisos: func(_ context.Context, a AvisoParaNotify) error {
			intentos++
			if fallo != nil {
				return fallo
			}
			salieron = append(salieron, a)
			return nil
		},
	}
	return NuevoVigiaDelCanal(s, nil), &salieron, &intentos
}

// --------------------------------------------------------------------------- la salida atascada

// LA SALIDA ATASCADA: algo lleva más de diez minutos sin irse.
func TestAvisaCuandoLaSalidaHaciaPedidoSeAtasca(t *testing.T) {
	c := &canalFalso{resumen: sqlc.ResumenDelWebhookRow{
		AvisosPendientes:  3,
		PendienteMasViejo: marca(elReloj.Add(-22 * time.Minute)),
	}}
	v, salieron, _ := vigiaDePrueba(t, nil)
	v.ahora = func() time.Time { return elReloj }

	v.Mirar(context.Background(), acotadoDeBuzon(c))

	if len(*salieron) != 1 {
		t.Fatalf(
			"con un aviso esperando desde hace 22 minutos no salió ningún correo: un canal "+
				"atascado sólo se ve abriendo /admin/webhook, que es lo que se vino a "+
				"arreglar. Salieron %d", len(*salieron),
		)
	}
	a := (*salieron)[0]
	if a.Clase != ClaseSalidaAtascada {
		t.Fatalf("la clase del aviso no es la del atasco: %q", a.Clase)
	}
	if !strings.Contains(a.Detalle, "22m") {
		t.Fatalf("el aviso no dice cuánto lleva atascado, que es el número que decide si es "+
			"un temblor o una avería: %q", a.Detalle)
	}
	if !strings.Contains(a.Detalle, "/admin/webhook") {
		t.Fatalf("el aviso no dice dónde mirar: %q", a.Detalle)
	}
}

// Y LA OTRA MITAD: el ritmo normal NO avisa.
//
// Veinte avisos esperando de hace tres minutos es lo que pasa cada vez que se cierra una
// ruta. Si eso avisara, saldría un correo por cada cierre y en dos días esto estaría
// silenciado — que es el fallo que la pareja de pruebas viene a evitar.
func TestNoAvisaPorElRitmoNormalDeUnCierreDeRuta(t *testing.T) {
	c := &canalFalso{resumen: sqlc.ResumenDelWebhookRow{
		AvisosPendientes:  20,
		PendienteMasViejo: marca(elReloj.Add(-3 * time.Minute)),
	}}
	v, salieron, intentos := vigiaDePrueba(t, nil)
	v.ahora = func() time.Time { return elReloj }

	v.Mirar(context.Background(), acotadoDeBuzon(c))

	if len(*salieron) != 0 || *intentos != 0 {
		t.Fatalf(
			"salió un correo por veinte avisos esperando de hace tres minutos, que es el "+
				"ritmo normal de un cierre de ruta: un aviso que sale siempre deja de "+
				"leerse. Salieron %d", len(*salieron),
		)
	}
}

// NO SE REPITE: dos vueltas seguidas con el mismo atasco mandan UN aviso, no dos.
//
// El drenaje da una vuelta cada minuto. Sin esta guarda serían 1.440 correos al día sobre la
// misma avería, y una regla de filtro en el buzón de Jose — que es la forma educada de
// apagar esto para siempre.
func TestElMismoAtascoNoAvisaDosVeces(t *testing.T) {
	c := &canalFalso{resumen: sqlc.ResumenDelWebhookRow{
		AvisosPendientes:  3,
		PendienteMasViejo: marca(elReloj.Add(-22 * time.Minute)),
	}}
	v, salieron, _ := vigiaDePrueba(t, nil)

	ahora := elReloj
	v.ahora = func() time.Time { return ahora }
	v.Mirar(context.Background(), acotadoDeBuzon(c))

	// La vuelta siguiente del temporizador, un minuto después. La cuenta de pendientes se
	// mueve —el drenaje sigue intentándolo— pero el atasco es el mismo.
	ahora = elReloj.Add(time.Minute)
	c.resumen.AvisosPendientes = 7
	v.Mirar(context.Background(), acotadoDeBuzon(c))

	if len(*salieron) != 1 {
		t.Fatalf(
			"el mismo atasco avisó %d veces en dos vueltas del temporizador: un aviso cada "+
				"minuto sobre lo mismo es peor que ninguno", len(*salieron),
		)
	}
}

// PASADO EL SILENCIO LARGO SE RECUERDA. Lo que sigue mal medio día vuelve a decirse: el
// primer correo se lee y se aparca.
func TestLoQueSigueAtascadoSeRecuerdaPasadasSeisHoras(t *testing.T) {
	c := &canalFalso{resumen: sqlc.ResumenDelWebhookRow{
		AvisosPendientes:  3,
		PendienteMasViejo: marca(elReloj.Add(-22 * time.Minute)),
	}}
	v, salieron, _ := vigiaDePrueba(t, nil)

	ahora := elReloj
	v.ahora = func() time.Time { return ahora }
	v.Mirar(context.Background(), acotadoDeBuzon(c))

	ahora = elReloj.Add(SilencioLargo + time.Minute)
	v.Mirar(context.Background(), acotadoDeBuzon(c))

	if len(*salieron) != 2 {
		t.Fatalf(
			"pasadas más de %s con el mismo atasco no salió el recordatorio: salieron %d avisos",
			SilencioLargo, len(*salieron),
		)
	}
}

// PEDIDO PARPADEANDO OCHO HORAS NO PUEDE INUNDAR EL BUZÓN.
//
// Ésta es la prueba que cazó el fallo de verdad, y costó DOS intentos de arreglo — 26/09/2026:
//
//  1. `olvidar` borraba la entrada entera del recuerdo, así que cada episodio entraba por
//     «primera vez de esta clase» y avisaba en el acto: cuarenta correos en ocho horas.
//  2. Conservando el `intento` seguía el freno de quince minutos — pero quince minutos ES el
//     techo y con la condición entrando y saliendo el techo se alcanza: treinta correos.
//
// Y un parpadeo de dieciséis minutos no es un caso de laboratorio ni el peor imaginable: es EL
// peor, porque el más viejo tiene que envejecer otros diez minutos para volver a contar, así
// que el periodo natural no baja de diez u once. Es la conexión de Cuba alternando con
// Starlink, y es PEDIDO reiniciándose en un despliegue.
//
// Una avería continua de ocho horas manda dos correos (el primero y el recordatorio). La misma
// avería intermitente tiene que mandar los mismos: dos episodios seguidos no son dos averías.
func TestPedidoParpadeandoOchoHorasNoInundaElBuzon(t *testing.T) {
	c := &canalFalso{}
	v, salieron, _ := vigiaDePrueba(t, nil)

	ahora := elReloj
	v.ahora = func() time.Time { return ahora }

	// Ocho horas de vueltas del temporizador —una por minuto— con el atasco apareciendo y
	// desapareciendo cada ocho minutos, o sea el ciclo de dieciséis.
	for i := 0; i < 8*60; i++ {
		ahora = elReloj.Add(time.Duration(i) * time.Minute)
		if (i/8)%2 == 0 {
			c.resumen = sqlc.ResumenDelWebhookRow{
				AvisosPendientes: 1,
				// Cada episodio trae un más viejo distinto: si la huella fuera ésa, cada uno
				// sería una «situación nueva» y la idempotencia de notify tampoco lo taparía.
				PendienteMasViejo: marca(ahora.Add(-11 * time.Minute)),
			}
		} else {
			c.resumen = sqlc.ResumenDelWebhookRow{}
		}
		v.Mirar(context.Background(), acotadoDeBuzon(c))
	}

	// Lo mismo que daría la avería continua: el primero y el recordatorio de las seis horas.
	techo := int(8*time.Hour/SilencioLargo) + 1
	if len(*salieron) > techo {
		t.Fatalf(
			"ocho horas de PEDIDO parpadeando mandaron %d correos, y una avería CONTINUA de "+
				"ocho horas manda %d: dos episodios seguidos no son dos averías, y cada uno "+
				"con su correo es el aviso que se silencia el mismo día",
			len(*salieron), techo,
		)
	}
	if len(*salieron) == 0 {
		t.Fatalf("ocho horas de atascos de once minutos no avisaron de nada: el freno se comió el aviso")
	}
}

// PERO UNA AVERÍA NUEVA DESPUÉS DE UNA HORA EN VERDE SÍ AVISA EN EL ACTO.
//
// Es la otra mitad, y sin ella el arreglo del parpadeo se convierte en un vigía que se calla
// para siempre después del primer correo. Una hora seguida en verde es lo que separa dos
// averías: un parpadeo no la acumula nunca, una tarde tranquila sí.
func TestUnaAveriaNuevaTrasUnaHoraEnVerdeAvisaEnElActo(t *testing.T) {
	elAtasco := sqlc.ResumenDelWebhookRow{
		AvisosPendientes:  3,
		PendienteMasViejo: marca(elReloj.Add(-22 * time.Minute)),
	}
	c := &canalFalso{resumen: elAtasco}
	v, salieron, _ := vigiaDePrueba(t, nil)

	ahora := elReloj
	v.ahora = func() time.Time { return ahora }
	v.Mirar(context.Background(), acotadoDeBuzon(c))
	if len(*salieron) != 1 {
		t.Fatalf("el primer atasco no avisó: %d", len(*salieron))
	}

	// Una hora y pico en verde, vuelta a vuelta.
	for i := 1; i <= 70; i++ {
		ahora = elReloj.Add(time.Duration(i) * time.Minute)
		c.resumen = sqlc.ResumenDelWebhookRow{}
		v.Mirar(context.Background(), acotadoDeBuzon(c))
	}
	if len(*salieron) != 1 {
		t.Fatalf("con el buzón limpio salió otro correo: %d", len(*salieron))
	}

	// Y ahora se rompe otra vez. Es otra avería, no la de antes.
	ahora = ahora.Add(time.Minute)
	c.resumen = sqlc.ResumenDelWebhookRow{
		AvisosPendientes:  1,
		PendienteMasViejo: marca(ahora.Add(-15 * time.Minute)),
	}
	v.Mirar(context.Background(), acotadoDeBuzon(c))

	if len(*salieron) != 2 {
		t.Fatalf(
			"tras una hora entera en verde, una avería NUEVA no avisó: el vigía seguía "+
				"callado por la de antes, que ya estaba arreglada. Salieron %d avisos",
			len(*salieron),
		)
	}
}

// --------------------------------------------------------------------------- los rechazos

func rechazoDePedido(folio, motivo string) sqlc.ListarAvisosAPedidoRow {
	return sqlc.ListarAvisosAPedidoRow{
		ID: uuid.New(), PedidoID: "ped-1", Folio: &folio, Estado: "entregado",
		Situacion: sqlc.AvisoAPedidoEstadoRechazado, Motivo: &motivo,
		CreatedAt: marca(elReloj.Add(-time.Hour)),
	}
}

// UN RECHAZO DE PEDIDO AVISA, Y EL MOTIVO VIAJA LITERAL DENTRO DEL CORREO.
//
// Es la regla de `CLAUDE.md` §3-quinquies: «no existe aquí (¿otra sucursal?)» le dice a
// alguien dónde mirar; «no se pudo» no le dice nada. Y un rechazo no se reintenta nunca, así
// que si nadie abre la pantalla se queda ahí para siempre.
func TestUnRechazoDePedidoAvisaConSuMotivoLiteral(t *testing.T) {
	c := &canalFalso{
		resumen:  sqlc.ResumenDelWebhookRow{AvisosRechazados: 2},
		rechazos: []sqlc.ListarAvisosAPedidoRow{rechazoDePedido("X-2992", "no existe aquí (¿otra sucursal?)")},
	}
	v, salieron, _ := vigiaDePrueba(t, nil)
	v.ahora = func() time.Time { return elReloj }

	v.Mirar(context.Background(), acotadoDeBuzon(c))

	if len(*salieron) != 1 {
		t.Fatalf("un rechazo de PEDIDO no avisó: no se reintenta nunca, así que nadie se "+
			"enteraría jamás. Salieron %d", len(*salieron))
	}
	a := (*salieron)[0]
	if a.Clase != ClaseRechazoDePedido {
		t.Fatalf("la clase del aviso no es la del rechazo: %q", a.Clase)
	}
	if !strings.Contains(a.Detalle, "no existe aquí (¿otra sucursal?)") {
		t.Fatalf(
			"el motivo LITERAL de PEDIDO no viaja dentro del aviso. «no existe aquí» dice "+
				"dónde mirar, «hay 2 rechazados» no dice nada. Salió: %q", a.Detalle,
		)
	}
	if !strings.Contains(a.Detalle, "X-2992") {
		t.Fatalf("el aviso no dice de qué pedido habla: %q", a.Detalle)
	}
}

// Y LA OTRA MITAD: sin rechazos no se avisa, y NI SE PREGUNTA por los motivos.
//
// Lo segundo no es cosmética: preguntarlos en cada vuelta son 1.440 consultas al día para
// tirar 1.439.
func TestSinRechazosNoSeAvisaNiSePreguntaPorLosMotivos(t *testing.T) {
	c := &canalFalso{resumen: sqlc.ResumenDelWebhookRow{AvisosPendientes: 4,
		PendienteMasViejo: marca(elReloj.Add(-time.Minute))}}
	v, salieron, _ := vigiaDePrueba(t, nil)
	v.ahora = func() time.Time { return elReloj }

	v.Mirar(context.Background(), acotadoDeBuzon(c))

	if len(*salieron) != 0 {
		t.Fatalf("salió un aviso de rechazo sin ningún rechazo: %+v", *salieron)
	}
	if c.motivosPedidos != 0 {
		t.Fatalf("se preguntaron los motivos sin haber rechazos: %d consultas", c.motivosPedidos)
	}
}

// UN RECHAZADO QUE NADIE LIMPIA NO PUEDE AVISAR PARA SIEMPRE — y ésta es la prueba de que no
// lo hace, que faltaba.
//
// 26/09/2026: nada baja la cuenta de rechazados. `/api/admin/webhook` es un GET y en
// `internal/alcance` no hay ninguna operación inversa, así que un rechazado se queda ahí
// hasta que alguien haga un UPDATE a mano. Con el recordatorio de seis horas aplicado a esta
// clase, UN solo rechazado son cuatro correos al día y ciento veinte en un mes, todos
// idénticos: el aviso que se deja de leer, por definición. Un rechazo es un hecho puntual, no
// una avería en curso. Ver `seRecuerda`.
func TestUnRechazadoQueNadieLimpiaAvisaUnaVezYNoMas(t *testing.T) {
	c := &canalFalso{
		resumen:  sqlc.ResumenDelWebhookRow{AvisosRechazados: 1},
		rechazos: []sqlc.ListarAvisosAPedidoRow{rechazoDePedido("X-3010", "estado que no conozco")},
	}
	v, salieron, _ := vigiaDePrueba(t, nil)

	ahora := elReloj
	v.ahora = func() time.Time { return ahora }

	// Treinta días de vueltas, una cada seis horas: la peor de las cadencias posibles.
	for i := 0; i < 30*4; i++ {
		ahora = elReloj.Add(time.Duration(i) * SilencioLargo)
		v.Mirar(context.Background(), acotadoDeBuzon(c))
	}

	if len(*salieron) != 1 {
		t.Fatalf(
			"el mismo rechazado avisó %d veces en treinta días: nada baja esa cuenta, así "+
				"que el recordatorio no se acaba nunca y en una semana esto está silenciado",
			len(*salieron),
		)
	}
}

// PERO UN RECHAZO NUEVO SÍ AVISA. Es la otra mitad: callarse los repetidos no puede
// convertirse en callarse los que llegan después.
func TestUnRechazoNuevoSiAvisaAunqueYaHubieraOtro(t *testing.T) {
	c := &canalFalso{
		resumen:  sqlc.ResumenDelWebhookRow{AvisosRechazados: 1},
		rechazos: []sqlc.ListarAvisosAPedidoRow{rechazoDePedido("X-3010", "estado que no conozco")},
	}
	v, salieron, _ := vigiaDePrueba(t, nil)

	ahora := elReloj
	v.ahora = func() time.Time { return ahora }
	v.Mirar(context.Background(), acotadoDeBuzon(c))

	ahora = elReloj.Add(SilencioEntreRechazos + time.Minute)
	c.resumen.AvisosRechazados = 2
	c.rechazos = append(c.rechazos, rechazoDePedido("X-3011", "no existe aquí (¿otra sucursal?)"))
	v.Mirar(context.Background(), acotadoDeBuzon(c))

	if len(*salieron) != 2 {
		t.Fatalf(
			"llegó un rechazo NUEVO y no avisó: no se reintenta, así que ése no lo ve nadie. "+
				"Salieron %d avisos", len(*salieron),
		)
	}
}

// UN GOTEO DE RECHAZOS NO PUEDE SER CUARENTA CORREOS EN UN DÍA.
//
// La forma que tiene el fallo real NO es la ráfaga: una clave caducada en una sucursal no
// rechaza ochenta y cuatro avisos en un cuarto de hora, rechaza uno cada veinte minutos toda
// la jornada. Y como la huella de esta clase es la cuenta, cada rechazo nuevo es una situación
// nueva: con el freno de quince minutos eso da cuarenta y tres correos al día, cuatro por hora
// sin parar. Medido el 26/09/2026. Ver `SilencioEntreRechazos`.
func TestUnGoteoDeRechazosNoInundaElBuzon(t *testing.T) {
	c := &canalFalso{
		resumen:  sqlc.ResumenDelWebhookRow{AvisosRechazados: 0},
		rechazos: []sqlc.ListarAvisosAPedidoRow{rechazoDePedido("X-4001", "403 de la sucursal")},
	}
	v, salieron, _ := vigiaDePrueba(t, nil)

	ahora := elReloj
	v.ahora = func() time.Time { return ahora }

	// Veinticuatro horas de vueltas del temporizador, con un rechazo nuevo cada veinte
	// minutos. 1.440 vueltas, 72 rechazos.
	for i := 0; i < 24*60; i++ {
		ahora = elReloj.Add(time.Duration(i) * time.Minute)
		if i%20 == 0 {
			c.resumen.AvisosRechazados++
		}
		v.Mirar(context.Background(), acotadoDeBuzon(c))
	}

	techo := int(24*time.Hour/SilencioEntreRechazos) + 1
	if len(*salieron) > techo {
		t.Fatalf(
			"un goteo de un rechazo cada veinte minutos mandó %d correos en un día, y el "+
				"techo del freno de %s son %d: cuatro correos por hora es el aviso que se "+
				"silencia en dos días", len(*salieron), SilencioEntreRechazos, techo,
		)
	}
	if len(*salieron) == 0 {
		t.Fatalf("setenta y dos rechazos en un día no avisaron de nada")
	}
}

// Y LOS MOTIVOS SE PIDEN DE LOS RECHAZADOS, NO DE LOS PENDIENTES.
//
// Esto NO es un detalle de la consulta: `Situacion` se copia a mano en Go, así que quitarlo o
// ponerlo a `pendiente` deja toda la suite en verde y el correo lista avisos PENDIENTES debajo
// de la frase «PEDIDO recibió estos avisos perfectamente y dijo que NO». Eso no es un correo
// feo: es un correo que miente sobre lo que hizo otro sistema y manda a alguien a buscar en
// PEDIDO un rechazo que PEDIDO nunca hizo. Es el §3-bis de `CLAUDE.md` con otra cara — «los
// parámetros se copian a mano en Go… quitar ahí un `Municipio:` deja toda la suite en verde y
// el número vuelve a mentir».
func TestLosMotivosSePidenDeLosRechazadosYNoDeLosPendientes(t *testing.T) {
	c := &canalFalso{
		resumen:  sqlc.ResumenDelWebhookRow{AvisosRechazados: 1},
		rechazos: []sqlc.ListarAvisosAPedidoRow{rechazoDePedido("X-3010", "no existe aquí")},
	}
	v, _, _ := vigiaDePrueba(t, nil)
	v.ahora = func() time.Time { return elReloj }

	v.Mirar(context.Background(), acotadoDeBuzon(c))

	if len(c.comoLosPidio) != 1 {
		t.Fatalf("no se pidieron los motivos una sola vez: %d", len(c.comoLosPidio))
	}
	p := c.comoLosPidio[0]
	if p.Situacion == nil {
		t.Fatalf(
			"los motivos se pidieron SIN filtrar por situación: el correo dice «PEDIDO dijo " +
				"que NO» y debajo listaría avisos pendientes, que PEDIDO no ha rechazado. Es " +
				"un correo que miente sobre lo que hizo otro sistema",
		)
	}
	if *p.Situacion != sqlc.AvisoAPedidoEstadoRechazado {
		t.Fatalf("los motivos se pidieron de los %q y tenían que ser de los %q",
			*p.Situacion, sqlc.AvisoAPedidoEstadoRechazado)
	}
	if p.Tope != TopeDeMotivosEnUnAviso {
		t.Fatalf("el tope de motivos del correo no es %d sino %d", TopeDeMotivosEnUnAviso, p.Tope)
	}
}

// SIN LOS MOTIVOS NO SE MANDA UN CORREO A MEDIAS.
//
// «Hay 12 rechazados» sin decir por qué manda a alguien a abrir la pantalla igualmente, que
// es el punto de partida. El aviso sin motivo es el aviso que no sirve.
func TestSiNoSePuedenLeerLosMotivosNoSeMandaUnAvisoAMedias(t *testing.T) {
	c := &canalFalso{
		resumen:            sqlc.ResumenDelWebhookRow{AvisosRechazados: 12},
		errorAlLeerMotivos: context.DeadlineExceeded,
	}
	v, salieron, intentos := vigiaDePrueba(t, nil)
	v.ahora = func() time.Time { return elReloj }

	v.Mirar(context.Background(), acotadoDeBuzon(c))

	if *intentos != 0 || len(*salieron) != 0 {
		t.Fatalf("se mandó un aviso de rechazo sin un solo motivo dentro: %+v", *salieron)
	}
}

// --------------------------------------------------------------------------- la entrada muda

// LA ENTRADA MUDA: una jornada laborable sin que PEDIDO empuje nada.
//
// Un canal parado no da ningún error. Y desde el 26/09/2026 el barrido del espejo es de tres
// horas, así que la red de seguridad tarda ocho veces más que antes en enterarse.
func TestAvisaCuandoPedidoLlevaUnaJornadaSinEmpujarNada(t *testing.T) {
	// Jueves: entró a las 08:00 UTC y son las 21:00 UTC, o sea las nueve horas enteras de la
	// franja sin recibir un solo pedido.
	ahora := time.Date(2026, 9, 24, 21, 0, 0, 0, time.UTC)
	c := &canalFalso{resumen: sqlc.ResumenDelWebhookRow{
		UltimaEntrada: marca(time.Date(2026, 9, 24, 8, 0, 0, 0, time.UTC)),
	}}
	v, salieron, _ := vigiaDePrueba(t, nil)
	v.ahora = func() time.Time { return ahora }

	v.Mirar(context.Background(), acotadoDeBuzon(c))

	if len(*salieron) != 1 {
		t.Fatalf("una jornada entera sin recibir nada no avisó: un canal parado no da "+
			"ningún error, sólo deja de pasar cosas. Salieron %d", len(*salieron))
	}
	if (*salieron)[0].Clase != ClaseEntradaMuda {
		t.Fatalf("la clase del aviso no es la de la entrada muda: %q", (*salieron)[0].Clase)
	}
}

// Y LA OTRA MITAD, PRIMERA PARTE: UNA NOCHE NO AVISA.
//
// PEDIDO empuja cuando alguien mueve un pedido, así que de noche no empuja nada y eso es lo
// correcto. Con un listón de reloj, a las siete de la mañana llevaríamos catorce horas de
// silencio legítimo y saldría un correo TODOS LOS DÍAS — el aviso que sale siempre.
func TestUnaNocheEnteraSinRecibirNadaNoAvisa(t *testing.T) {
	// Jueves 20:30 UTC (la franja cierra a las 21:00) a viernes 11:00 UTC: catorce horas y
	// media de reloj, media hora de jornada.
	ahora := time.Date(2026, 9, 25, 11, 0, 0, 0, time.UTC)
	c := &canalFalso{resumen: sqlc.ResumenDelWebhookRow{
		UltimaEntrada: marca(time.Date(2026, 9, 24, 20, 30, 0, 0, time.UTC)),
	}}
	v, salieron, _ := vigiaDePrueba(t, nil)
	v.ahora = func() time.Time { return ahora }

	v.Mirar(context.Background(), acotadoDeBuzon(c))

	if len(*salieron) != 0 {
		t.Fatalf(
			"salió un correo por una noche entera sin que PEDIDO empujara nada, que es lo "+
				"normal: con el listón contado en horas de reloj esto saldría cada mañana y "+
				"en dos días estaría silenciado. Salieron %d", len(*salieron),
		)
	}
}

// Y SEGUNDA PARTE, QUE ES LA QUE FALTABA: UN FIN DE SEMANA TAMPOCO AVISA.
//
// La franja arreglaba la noche y NO el fin de semana, que es el mismo fallo a otra escala, y
// se cazó midiendo los huecos de verdad — 26/09/2026. Un domingo en PEDIDO son tres o diez
// pedidos movidos en todo el día contra los trescientos o novecientos de un laborable: sin
// esta guarda salían dos o tres correos cada sábado y cada domingo, para siempre.
func TestUnFinDeSemanaSinRecibirNadaNoAvisa(t *testing.T) {
	// Sábado 12:00 UTC a domingo 20:00 UTC: treinta y dos horas de reloj, cero de jornada.
	ahora := time.Date(2026, 9, 27, 20, 0, 0, 0, time.UTC)
	c := &canalFalso{resumen: sqlc.ResumenDelWebhookRow{
		UltimaEntrada: marca(time.Date(2026, 9, 26, 12, 0, 0, 0, time.UTC)),
	}}
	v, salieron, _ := vigiaDePrueba(t, nil)
	v.ahora = func() time.Time { return ahora }

	v.Mirar(context.Background(), acotadoDeBuzon(c))

	if len(*salieron) != 0 {
		t.Fatalf(
			"salió un correo porque PEDIDO no empujó nada en un fin de semana: los cuatro "+
				"fines de semana del último mes pasan del listón contándolos por franjas, "+
				"así que esto son dos o tres correos cada sábado, para siempre. Salieron %d",
			len(*salieron),
		)
	}
}

// NUNCA NO ES «HACE MUCHO». Un reparto recién desplegado no ha recibido nada todavía, y un
// correo por eso sería un correo en cada estreno de entorno.
func TestUnCanalQueNuncaHaRecibidoNadaNoAvisa(t *testing.T) {
	c := &canalFalso{resumen: sqlc.ResumenDelWebhookRow{}} // UltimaEntrada inválida = nunca
	v, salieron, _ := vigiaDePrueba(t, nil)
	v.ahora = func() time.Time { return elReloj }

	v.Mirar(context.Background(), acotadoDeBuzon(c))

	if len(*salieron) != 0 {
		t.Fatalf("un canal recién estrenado avisó de que lleva mucho sin recibir: %+v", *salieron)
	}
}

// LA CUENTA DE HORAS DE JORNADA, suelta y CON LOS HUECOS DE VERDAD.
//
// Es la guarda de la que depende que el aviso de la entrada muda no se vuelva ruido, así que
// se prueba por su cuenta y no sólo a través del vigía. Los cuatro últimos casos son huecos
// REALES entre movimientos de pedido de septiembre de 2026, de los que con la primera versión
// de esta cuenta —franja ancha y sin distinguir el fin de semana— pasaban del listón: los
// nueve que había eran los cuatro fines de semana del mes.
func TestLasHorasDeJornadaNoCuentanLaNocheNiElFinDeSemana(t *testing.T) {
	casos := []struct {
		nombre       string
		desde, hasta time.Time
		quiere       time.Duration
	}{
		{"una tarde de jueves, entera dentro de la franja",
			time.Date(2026, 9, 24, 13, 0, 0, 0, time.UTC),
			time.Date(2026, 9, 24, 18, 0, 0, 0, time.UTC), 5 * time.Hour},
		{"la noche no cuenta nada",
			time.Date(2026, 9, 24, 2, 0, 0, 0, time.UTC),
			time.Date(2026, 9, 24, 12, 0, 0, 0, time.UTC), 0},
		{"lo de después de las 21:00 no cuenta",
			time.Date(2026, 9, 24, 20, 0, 0, 0, time.UTC),
			time.Date(2026, 9, 25, 13, 0, 0, 0, time.UTC), 2 * time.Hour},
		{"un día laborable entero son las nueve de la franja",
			time.Date(2026, 9, 23, 11, 0, 0, 0, time.UTC),
			time.Date(2026, 9, 24, 11, 0, 0, 0, time.UTC), 9 * time.Hour},
		{"hacia atrás es cero, no un número negativo",
			time.Date(2026, 9, 24, 18, 0, 0, 0, time.UTC),
			time.Date(2026, 9, 24, 13, 0, 0, 0, time.UTC), 0},

		// Huecos reales de PEDIDO. Con la primera versión de la cuenta daban 10h28m, 9h07m y
		// 9h17m, o sea tres correos de avería sobre tres fines de semana normales.
		{"sábado a domingo (hueco real del 05/09): cero",
			time.Date(2026, 9, 5, 16, 24, 12, 0, time.UTC),
			time.Date(2026, 9, 6, 12, 52, 20, 0, time.UTC), 0},
		{"domingo a lunes antes de abrir (hueco real del 06/09): cero",
			time.Date(2026, 9, 6, 16, 52, 0, 0, time.UTC),
			time.Date(2026, 9, 7, 11, 52, 0, 0, time.UTC), 0},
		{"viernes tarde a sábado (hueco real del 11/09): sólo lo del viernes",
			time.Date(2026, 9, 11, 17, 26, 0, 0, time.UTC),
			time.Date(2026, 9, 12, 12, 43, 0, 0, time.UTC), 3*time.Hour + 34*time.Minute},
		{"un martes de verdad parado sí pasa del listón",
			time.Date(2026, 9, 8, 12, 30, 0, 0, time.UTC),
			time.Date(2026, 9, 8, 19, 30, 0, 0, time.UTC), 7 * time.Hour},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			got := horasDeTrabajoEntre(c.desde, c.hasta)
			if got != c.quiere {
				t.Fatalf("salieron %s de jornada y tenían que ser %s", got, c.quiere)
			}
			// Y lo que decide de verdad: si eso avisa o no.
			if (got > ListonDeEntradaMuda) != (c.quiere > ListonDeEntradaMuda) {
				t.Fatalf("la decisión de avisar cambió con el listón de %s", ListonDeEntradaMuda)
			}
		})
	}
}

// --------------------------------------------------------------------------- el origen del dato

// LOS NÚMEROS QUE DECIDEN LAS ALARMAS SALEN DE LA CONSULTA QUE TOCA.
//
// Las pruebas de arriba usan un doble que devuelve el `ResumenDelWebhookRow` armado a mano, así
// que NINGUNA llega al SQL: cambiar `min(created_at)` por `max(...)` en `pendiente_mas_viejo`
// —el campo que decide el atasco y el mismo que pinta el punto de color de la pantalla— deja
// toda la suite en verde y la alarma mirando el aviso más NUEVO, que con el canal sano es
// siempre de hace un segundo: el atasco no salta jamás. Lo mismo con las dos cuentas si se les
// cambia la situación.
//
// Se comprueba leyendo el `.sql`, que es el ORIGEN, y vale porque `Dockerfile.api` corre
// `sqlc diff`: el Go generado no puede irse por su cuenta de lo que dice este fichero.
func TestElResumenDelWebhookMiraLoQueLasAlarmasCreenQueMira(t *testing.T) {
	crudo, err := os.ReadFile("../../db/queries/webhook.sql")
	if err != nil {
		t.Fatalf("no se pudo leer la consulta que alimenta las alarmas: %v", err)
	}
	bloque, ok := consultaLlamada(string(crudo), "ResumenDelWebhook")
	if !ok {
		t.Fatalf("no está `-- name: ResumenDelWebhook` en db/queries/webhook.sql")
	}

	quiere := []struct{ trozo, porque string }{
		{
			"(SELECT min(created_at) FROM avisos_a_pedido WHERE situacion = 'pendiente')" +
				"::timestamptz AS pendiente_mas_viejo",
			"`pendiente_mas_viejo` tiene que ser el MÁS VIEJO de los PENDIENTES: con `max` " +
				"devuelve el más nuevo, que con el canal sano es de hace un segundo, y la " +
				"alarma del atasco no salta nunca",
		},
		{
			"(SELECT count(*)::bigint FROM avisos_a_pedido WHERE situacion = 'pendiente') " +
				"AS avisos_pendientes",
			"la cuenta de pendientes es la que sale en el correo del atasco",
		},
		{
			"(SELECT count(*)::bigint FROM avisos_a_pedido WHERE situacion = 'rechazado') " +
				"AS avisos_rechazados",
			"`avisos_rechazados` es lo que dispara la alarma de rechazos: contando " +
				"pendientes, avisaría de un rechazo en cada cierre de ruta",
		},
	}
	normal := unaSolaLinea(bloque)
	for _, q := range quiere {
		if !strings.Contains(normal, q.trozo) {
			t.Fatalf("la consulta ya no dice `%s`.\n%s.\nDice:\n%s", q.trozo, q.porque, normal)
		}
	}
}

// consultaLlamada saca el cuerpo de una consulta de sqlc por su nombre.
func consultaLlamada(fichero, nombre string) (string, bool) {
	marca := "-- name: " + nombre + " "
	i := strings.Index(fichero, marca)
	if i < 0 {
		return "", false
	}
	resto := fichero[i+len(marca):]
	if j := strings.Index(resto, "-- name: "); j >= 0 {
		resto = resto[:j]
	}
	return resto, true
}

// unaSolaLinea colapsa los espacios para poder comparar SQL sin atarse a cómo está sangrado.
func unaSolaLinea(s string) string { return strings.Join(strings.Fields(s), " ") }

// --------------------------------------------------------------------------- no mentir

// UN AVISO QUE NO SALIÓ NO ESTÁ MANDADO, y se vuelve a por él.
//
// Es la lección del canal de Entrega, que existía con clave y secreto y **sin URL**: no
// salía nada y no se veía en ningún registro. Si un fallo de notify contara como aviso
// mandado, el vigía se callaría seis horas por un correo que nadie recibió.
func TestUnAvisoQueNoSalioSeVuelveAIntentar(t *testing.T) {
	c := &canalFalso{resumen: sqlc.ResumenDelWebhookRow{
		AvisosPendientes:  3,
		PendienteMasViejo: marca(elReloj.Add(-22 * time.Minute)),
	}}
	var salieron []AvisoParaNotify
	intentos := 0
	falla := true
	s := &Servidor{
		reg: slog.New(slog.DiscardHandler),
		avisos: func(_ context.Context, a AvisoParaNotify) error {
			intentos++
			if falla {
				return context.DeadlineExceeded
			}
			salieron = append(salieron, a)
			return nil
		},
	}
	v := NuevoVigiaDelCanal(s, nil)

	ahora := elReloj
	v.ahora = func() time.Time { return ahora }
	v.Mirar(context.Background(), acotadoDeBuzon(c))
	if intentos != 1 || len(salieron) != 0 {
		t.Fatalf("intentos=%d salieron=%d; se esperaba un intento y ningún aviso", intentos, len(salieron))
	}

	// La vuelta siguiente, un minuto después: el freno duro impide volver a intentarlo tan
	// pronto. Sin él, notify caído son 1.440 líneas de error al día por clase.
	ahora = elReloj.Add(time.Minute)
	v.Mirar(context.Background(), acotadoDeBuzon(c))
	if intentos != 1 {
		t.Fatalf("se reintentó al minuto: el freno de %s no está frenando (intentos=%d)",
			SilencioMinimo, intentos)
	}

	// Pasado el freno, y con notify de vuelta, el aviso SALE: no se había dado por mandado.
	ahora = elReloj.Add(SilencioMinimo + time.Minute)
	falla = false
	v.Mirar(context.Background(), acotadoDeBuzon(c))
	if len(salieron) != 1 {
		t.Fatalf(
			"el aviso que había fallado se dio por mandado y no se volvió a intentar: un "+
				"aviso que nadie recibe y que además se declara enviado es peor que no "+
				"avisar, porque nadie lo busca. Salieron %d", len(salieron),
		)
	}
}

// EL VIGÍA MIRA DESPUÉS DE DRENAR, Y ESO TIENE QUE TENER PRUEBA.
//
// Era la única guarda de diseño de este cambio que no la tenía: mover `d.vigia.Mirar` a antes
// del drenaje dejaba TODA la suite en verde, y es justo lo que alguien reordena sin darse
// cuenta al refactorizar la vuelta. Y lo que se pierde es lo de siempre: drenar puede haber
// vaciado el buzón en esta misma vuelta, así que mirar antes manda un correo que dice
// «atascada» sobre un canal que acaba de arreglarse. Los avisos falsos son los que enseñan a
// no leer los verdaderos.
func TestElVigiaMiraDespuesDeDrenarYNoAntes(t *testing.T) {
	c := &canalFalso{
		buzonFalso: buzonFalso{pendientes: []sqlc.AvisosAPedidoPendientesRow{
			avisoEnElBuzon("ped-1"),
		}},
		// Un pendiente de hace tres horas: antes de drenar, esto es un atasco de libro.
		resumen: sqlc.ResumenDelWebhookRow{
			AvisosPendientes:  1,
			PendienteMasViejo: marca(time.Now().UTC().Add(-3 * time.Hour)),
		},
		siguiendoAlBuzon: true,
	}
	avisos := 0
	s := &Servidor{
		reg: slog.New(slog.DiscardHandler),
		aPedido: func(context.Context, []AvisoDeParada) ParteAPedido {
			return ParteAPedido{Ok: true, Enviados: 1, Aplicados: 1}
		},
		avisos: func(context.Context, AvisoParaNotify) error { avisos++; return nil },
	}
	d := NuevoDrenadorDelBuzon(s, func(context.Context) (*alcance.Acotado, error) {
		return acotadoDeBuzon(c), nil
	}, time.Minute)

	d.UnaVuelta(context.Background())

	if len(c.enviados) != 1 {
		t.Fatalf("el drenaje no vació el buzón, así que esta prueba no prueba el orden: %d", len(c.enviados))
	}
	if avisos != 0 {
		t.Fatalf(
			"salió un correo diciendo «la salida está atascada» sobre un buzón que el drenaje "+
				"acababa de vaciar en esa misma vuelta: el vigía está mirando ANTES de drenar. "+
				"Salieron %d avisos", avisos,
		)
	}
}

// UN FALLO AL AVISAR NO PUEDE TUMBAR EL DRENAJE.
//
// Lo que importa es que los avisos salgan hacia PEDIDO; el correo es secundario. Con notify
// caído —o sin configurar— la tanda tiene que salir igual y los avisos quedar marcados como
// enviados.
func TestUnFalloDeNotifyNoImpideQueLosAvisosSalganHaciaPedido(t *testing.T) {
	c := &canalFalso{
		buzonFalso: buzonFalso{pendientes: []sqlc.AvisosAPedidoPendientesRow{
			avisoEnElBuzon("ped-1"), avisoEnElBuzon("ped-2"),
		}},
		resumen: sqlc.ResumenDelWebhookRow{
			AvisosPendientes:  2,
			PendienteMasViejo: marca(elReloj.Add(-3 * time.Hour)),
		},
	}
	s := &Servidor{
		reg: slog.New(slog.DiscardHandler),
		aPedido: func(context.Context, []AvisoDeParada) ParteAPedido {
			return ParteAPedido{Ok: true, Enviados: 2, Aplicados: 2}
		},
		// notify no está montado: el canal mudo devuelve error en cada intento.
		avisos: canalDeAvisosMudo("QB_NOTIFY_URL"),
	}
	d := NuevoDrenadorDelBuzon(s, func(context.Context) (*alcance.Acotado, error) {
		return acotadoDeBuzon(c), nil
	}, time.Minute)

	d.UnaVuelta(context.Background())

	if len(c.enviados) != 2 {
		t.Fatalf(
			"con notify caído se quedaron sin salir los avisos hacia PEDIDO: el correo es "+
				"secundario, lo que importa es que PEDIDO se entere. Enviados: %d",
			len(c.enviados),
		)
	}
}
