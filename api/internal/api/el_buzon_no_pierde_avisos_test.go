package api

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/store/sqlc"
)

// EL BUZÓN NO PIERDE UN AVISO PORQUE PEDIDO NO ESTUVIERA.
//
// El reparto le cuenta a PEDIDO en qué punto va cada pedido, y hasta el 26/09/2026 lo hacía
// **de una sola vez o nunca**: la llamada salía al cerrar la ruta y, si PEDIDO estaba caído
// o la red iba mal, el aviso desaparecía. El pedido quedaba entregado aquí y eterno «en
// proceso» allá, sin un error en ninguna pantalla y sin nadie a quien reclamarle. Jose,
// 26/09/2026: «el de enviar el estado de los pedidos de delivery, para que PEDIDO se entere
// de eso».
//
// LAS TRES SITUACIONES SON TRES Y NO DOS, y ésa es toda la prueba:
//
//   - **enviado** — llegó y se aplicó.
//   - **rechazado** — llegó PERFECTAMENTE y PEDIDO dijo que no. No se reintenta: repetir lo
//     mismo da lo mismo. Se queda a la vista con su motivo literal.
//   - **pendiente** — no se pudo ni preguntar. Eso NO es un rechazo, y confundirlos daría
//     por perdido lo que sólo estaba esperando.
//
// Juntar las dos últimas es el fallo que esto viene a evitar: si un «PEDIDO está caído» se
// guardara como rechazo, el aviso no se volvería a mandar nunca y nadie lo sabría.

// buzonFalso es la parte de la base que le hace falta al drenaje, y nada más.
type buzonFalso struct {
	sqlc.Querier

	pendientes []sqlc.AvisosAPedidoPendientesRow
	enviados   []uuid.UUID
	rechazados map[uuid.UUID]string
	reintentos map[uuid.UUID]string
	envios     []sqlc.ApuntarEnvioDelWebhookParams
}

func (b *buzonFalso) AvisosAPedidoPendientes(context.Context, int32) ([]sqlc.AvisosAPedidoPendientesRow, error) {
	return b.pendientes, nil
}

func (b *buzonFalso) AvisoAPedidoEnviado(_ context.Context, id uuid.UUID) error {
	b.enviados = append(b.enviados, id)
	return nil
}

func (b *buzonFalso) AvisoAPedidoRechazado(_ context.Context, p sqlc.AvisoAPedidoRechazadoParams) error {
	if b.rechazados == nil {
		b.rechazados = map[uuid.UUID]string{}
	}
	motivo := ""
	if p.Motivo != nil {
		motivo = *p.Motivo
	}
	b.rechazados[p.ID] = motivo
	return nil
}

func (b *buzonFalso) AvisoAPedidoSeReintenta(_ context.Context, p sqlc.AvisoAPedidoSeReintentaParams) error {
	if b.reintentos == nil {
		b.reintentos = map[uuid.UUID]string{}
	}
	motivo := ""
	if p.Motivo != nil {
		motivo = *p.Motivo
	}
	b.reintentos[p.ID] = motivo
	return nil
}

func (b *buzonFalso) ApuntarEnvioDelWebhook(_ context.Context, p sqlc.ApuntarEnvioDelWebhookParams) error {
	b.envios = append(b.envios, p)
	return nil
}

func avisoEnElBuzon(pedido string) sqlc.AvisosAPedidoPendientesRow {
	return sqlc.AvisosAPedidoPendientesRow{
		ID:        uuid.New(),
		PedidoID:  pedido,
		Estado:    "entregado",
		OcurrioAt: pgtype.Timestamptz{Time: time.Date(2026, 9, 26, 16, 4, 0, 0, time.UTC), Valid: true},
	}
}

// PEDIDO NO CONTESTA: todos siguen pendientes y se vuelve a por ellos.
func TestSiPedidoNoContestaLosAvisosSiguenPendientes(t *testing.T) {
	b := &buzonFalso{pendientes: []sqlc.AvisosAPedidoPendientesRow{
		avisoEnElBuzon("ped-1"), avisoEnElBuzon("ped-2"),
	}}
	s := servidorConBuzon(t, b, func(context.Context, []AvisoDeParada) ParteAPedido {
		return ParteAPedido{Ok: false, Error: "dial tcp: connection refused"}
	})

	enviados, quedan := s.DrenarElBuzon(context.Background(), acotadoDeBuzon(b))

	if enviados != 0 || quedan != 2 {
		t.Fatalf("enviados=%d quedan=%d; se esperaba 0 y 2", enviados, quedan)
	}
	if len(b.rechazados) != 0 {
		t.Fatalf(
			"un «no se pudo hablar» se guardó como RECHAZO: así no se vuelve a mandar "+
				"nunca y nadie se entera: %v", b.rechazados,
		)
	}
	if len(b.reintentos) != 2 {
		t.Fatalf("no se anotó el reintento de los dos: %v", b.reintentos)
	}
	for _, m := range b.reintentos {
		if m != "dial tcp: connection refused" {
			t.Fatalf("el motivo no es el literal de la red: %q", m)
		}
	}
}

// PEDIDO CONTESTA Y APLICA: se marcan enviados.
func TestLoQuePedidoAplicaSeMarcaEnviado(t *testing.T) {
	b := &buzonFalso{pendientes: []sqlc.AvisosAPedidoPendientesRow{
		avisoEnElBuzon("ped-1"), avisoEnElBuzon("ped-2"),
	}}
	s := servidorConBuzon(t, b, func(context.Context, []AvisoDeParada) ParteAPedido {
		return ParteAPedido{Ok: true, Enviados: 2, Aplicados: 2}
	})

	enviados, quedan := s.DrenarElBuzon(context.Background(), acotadoDeBuzon(b))

	if enviados != 2 || quedan != 0 {
		t.Fatalf("enviados=%d quedan=%d; se esperaba 2 y 0", enviados, quedan)
	}
	if len(b.enviados) != 2 {
		t.Fatalf("no se marcaron los dos como enviados: %v", b.enviados)
	}
}

// PEDIDO CONTESTA Y DICE QUE NO: rechazado con su motivo, y NO se reintenta.
func TestLoQuePedidoRechazaSeQuedaConSuMotivo(t *testing.T) {
	b := &buzonFalso{pendientes: []sqlc.AvisosAPedidoPendientesRow{avisoEnElBuzon("ped-1")}}
	// SE SIEMBRA COMO SIEMBRA PRODUCCIÓN, y antes no: este doble montaba
	// `Ok: true` CON `Error` no vacío, un estado que el canal de verdad **no puede
	// producir** —`parte.Ok = parte.Error == ""`—, así que esta prueba pasaba por una
	// rama que en producción no se recorre nunca. Es el §3 de la skill del auditor: el
	// fixture lo escribe la misma mano que pregunta.
	//
	// Y lo que tapaba era gordo: con el doble puesto como sí es, esta prueba se caía, y
	// eso destapó que **`AvisoAPedidoRechazado` era código muerto**. Ver
	// `ParteAPedido.Rechazo`.
	s := servidorConBuzon(t, b, func(context.Context, []AvisoDeParada) ParteAPedido {
		return ParteAPedido{Ok: false, Rechazo: true, Enviados: 1, Aplicados: 0,
			HTTP: 200, Error: "no existe aquí (¿otra sucursal?)"}
	})

	s.DrenarElBuzon(context.Background(), acotadoDeBuzon(b))

	if len(b.rechazados) != 1 {
		t.Fatalf("no se guardó el rechazo: %v", b.rechazados)
	}
	for _, m := range b.rechazados {
		if m != "no existe aquí (¿otra sucursal?)" {
			t.Fatalf(
				"el motivo no es el literal de PEDIDO: «no se pudo» no le dice nada a "+
					"nadie, «no existe aquí» dice dónde mirar. Salió: %q", m,
			)
		}
	}
	if len(b.reintentos) != 0 {
		t.Fatalf("un rechazo NO se reintenta: repetir lo mismo da lo mismo")
	}
}

// Y LA TANDA QUEDA APUNTADA pase lo que pase, que es la otra pregunta.
//
// Un aviso sin enviar puede ser «PEDIDO está caído» o «PEDIDO lo rechazó»: desde fuera se
// ven igual —«hay avisos sin enviar»— y se arreglan de maneras distintas.
func TestCadaTandaQuedaApuntadaAunqueFalle(t *testing.T) {
	b := &buzonFalso{pendientes: []sqlc.AvisosAPedidoPendientesRow{avisoEnElBuzon("ped-1")}}
	s := servidorConBuzon(t, b, func(context.Context, []AvisoDeParada) ParteAPedido {
		return ParteAPedido{Ok: false, Error: "PEDIDO contestó 502"}
	})

	s.DrenarElBuzon(context.Background(), acotadoDeBuzon(b))

	if len(b.envios) != 1 {
		t.Fatalf("la tanda no se apuntó: sin esto no hay forma de saber si llegó")
	}
	e := b.envios[0]
	if e.Mandados != 1 || e.Aceptados != 0 {
		t.Fatalf("los números de la tanda no cuadran: %+v", e)
	}
	if e.Motivo == nil || *e.Motivo != "PEDIDO contestó 502" {
		t.Fatalf("la tanda se apuntó sin el motivo literal: %+v", e.Motivo)
	}
}

// Sin nada que mandar no se molesta a PEDIDO ni se apunta una tanda vacía.
func TestConElBuzonVacioNoSeLlamaANadie(t *testing.T) {
	b := &buzonFalso{}
	llamadas := 0
	s := servidorConBuzon(t, b, func(context.Context, []AvisoDeParada) ParteAPedido {
		llamadas++
		return ParteAPedido{Ok: true}
	})

	s.DrenarElBuzon(context.Background(), acotadoDeBuzon(b))

	if llamadas != 0 {
		t.Fatalf("se llamó a PEDIDO sin nada que contarle")
	}
	if len(b.envios) != 0 {
		t.Fatalf("se apuntó una tanda vacía: ensucia la pantalla de administración")
	}
}

// CADA TANDA QUE SALE AVISA A LA PANTALLA DEL CANAL — LOS TRES DESENLACES.
//
// Jose, 26/09/2026: «SSE con todo esto igual, nada de polling». La pantalla del canal contesta
// «¿está saliendo algo?», y a eso no se le contesta con una foto de hace un rato.
//
// EL DESENLACE QUE MÁS IMPORTA ES EL SEGUNDO: PEDIDO caído. Es lo que hay que ver aparecer, y
// justo lo que se quedaría sin pintar con un aviso que sólo sale cuando algo va bien. Se
// escribió sin prueba y una mutación lo quitó sin que nada fallara, así que aquí está.
//
// Y LA OTRA MITAD, el cuarto caso: con el buzón VACÍO no se avisa. Sin eso, «avisa siempre» se
// cumple avisando en cada vuelta del temporizador —una al minuto, sin que haya pasado nada—, y
// entonces ocho navegadores se bajan el estado del canal 1.440 veces al día por nada. Un aviso
// que sale siempre deja de significar algo.
func TestCadaTandaQueSaleAvisaALaPantalla(t *testing.T) {
	casos := []struct {
		nombre     string
		pendientes []sqlc.AvisosAPedidoPendientesRow
		parte      ParteAPedido
		quiere     int
	}{
		{"la tanda entró", []sqlc.AvisosAPedidoPendientesRow{avisoEnElBuzon("ped-1")},
			ParteAPedido{Ok: true, Enviados: 1, Aplicados: 1}, 1},
		{"PEDIDO no contestó", []sqlc.AvisosAPedidoPendientesRow{avisoEnElBuzon("ped-1")},
			ParteAPedido{Ok: false, Error: "dial tcp: connection refused"}, 1},
		{"PEDIDO lo rechazó", []sqlc.AvisosAPedidoPendientesRow{avisoEnElBuzon("ped-1")},
			ParteAPedido{Ok: true, Enviados: 1, Aplicados: 0, Error: "no existe aquí"}, 1},
		{"el buzón estaba vacío", nil, ParteAPedido{Ok: true}, 0},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			avisos := 0
			antes := avisarCambioEnElCanal
			avisarCambioEnElCanal = func(context.Context) { avisos++ }
			t.Cleanup(func() { avisarCambioEnElCanal = antes })

			b := &buzonFalso{pendientes: c.pendientes}
			parte := c.parte
			s := servidorConBuzon(t, b, func(context.Context, []AvisoDeParada) ParteAPedido {
				return parte
			})

			s.DrenarElBuzon(context.Background(), acotadoDeBuzon(b))

			if avisos != c.quiere {
				t.Fatalf("con «%s» salieron %d avisos y tenían que salir %d",
					c.nombre, avisos, c.quiere)
			}
		})
	}
}

// --------------------------------------------------------------------------- el montaje

type fuenteDelBuzon struct{ q sqlc.Querier }

func (f fuenteDelBuzon) Consultas() sqlc.Querier { return f.q }
func (f fuenteDelBuzon) EnTx(ctx context.Context, fn func(sqlc.Querier) error) error {
	return fn(f.q)
}

// acotadoDeBuzon: un alcance de SUPER ADMIN sobre el buzón falso.
//
// El buzón va sin alcance a propósito —un aviso encolado es un hecho que ya pasó, y quien
// lo drena es un trabajador sin sucursal ni persona detrás—, así que aquí sólo hace falta
// un Acotado que sepa llegar a las consultas.
func acotadoDeBuzon(q sqlc.Querier) *alcance.Acotado {
	p := alcance.NuevaPorteria(fuenteDelBuzon{q: q}, slog.New(slog.DiscardHandler))
	a, err := p.Resolver(context.Background(), &auth.Usuario{ID: "prueba", Rol: "SUPER ADMIN"}, "")
	if err != nil {
		panic(err)
	}
	return a
}

func servidorConBuzon(t *testing.T, q sqlc.Querier, canal CanalAPedido) *Servidor {
	t.Helper()
	return &Servidor{reg: slog.New(slog.DiscardHandler), aPedido: canal}
}

// EL CIERRE APUNTA EL AVISO ANTES DE INTENTAR MANDARLO.
//
// Es el arreglo entero en una prueba. Con PEDIDO caído, el cierre sigue su curso —un camión
// que volvió con nueve entregas no puede quedarse sin cerrar porque otra aplicación esté
// mal— y el aviso **queda en el buzón**. Antes se perdía ahí mismo: entregado aquí, eterno
// «en proceso» allá, y nadie a quien reclamarle.
func TestElCierreApuntaElAvisoAunquePedidoEsteCaido(t *testing.T) {
	pedido := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "estoy caído", http.StatusServiceUnavailable)
	}))
	defer pedido.Close()

	d, stg, _ := datosDeReparto()
	var registro registroSeguro
	h, s := montarRutasRegistrando(t, d, &registro)
	s.aPedido = canalDePrueba(pedido.URL, "la-clave", slog.New(slog.DiscardHandler))

	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1])

	cuerpo := fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, stg[1])
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)

	if w.Code != http.StatusOK {
		t.Fatalf("PEDIDO caído no puede tumbar el cierre: %d %s", w.Code, w.Body.String())
	}
	if len(d.avisosEncolados) != 1 {
		t.Fatalf(
			"el aviso NO quedó en el buzón: con PEDIDO caído se pierde y el pedido "+
				"queda entregado aquí y «en proceso» allá para siempre. Encolados: %d",
			len(d.avisosEncolados),
		)
	}
	if got := d.avisosEncolados[0].Estado; got != "entregado" {
		t.Fatalf("se apuntó otro estado: %q", got)
	}
	if !d.avisosEncolados[0].OcurrioAt.Valid {
		t.Fatalf("el aviso se apuntó sin la hora del suceso: con trabajo sin conexión " +
			"esa hora y la de la llamada pueden ser tres horas distintas")
	}
}

// UN RECHAZO NO PARA EL BUZÓN, Y UN FALLO DE TRANSPORTE NO MATA EL AVISO.
//
// Son las dos mitades de lo mismo y hasta el 26/09/2026 se confundían: `ParteAPedido` metía
// «no se pudo preguntar» y «PEDIDO dijo que no» en el mismo campo `Error`, y `Ok` salía de
// si ese campo estaba vacío. Así que **un rechazo entraba por la rama del fallo de
// transporte**: se quedaba `pendiente`, se reenviaba cada minuto para siempre, y como el
// buzón se drena por orden de llegada con `LIMIT 200`, esa fila iba en todas las tandas y
// **nada de lo que viniera detrás llegaba a marcarse enviado**. El canal entero parado por
// un pedido que en PEDIDO no existe.
func TestUnRechazoNoSeConfundeConUnFalloDeTransporte(t *testing.T) {
	casos := []struct {
		nombre           string
		parte            ParteAPedido
		quiereRechazados int
		quiereReintentos int
	}{
		{
			"PEDIDO dijo que no: se marca RECHAZADO y no se reintenta",
			ParteAPedido{Ok: false, Rechazo: true, Enviados: 1, HTTP: 200,
				Error: "no existe aquí (¿otra sucursal?)"},
			1, 0,
		},
		{
			"PEDIDO no contestó: sigue PENDIENTE y se reintenta",
			ParteAPedido{Ok: false, Enviados: 1, Error: "dial tcp: connection refused"},
			0, 1,
		},
		{
			"PEDIDO contestó 502: eso pasa solo, se reintenta",
			ParteAPedido{Ok: false, Enviados: 1, HTTP: 502, Error: "PEDIDO contestó 502"},
			0, 1,
		},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			b := &buzonFalso{pendientes: []sqlc.AvisosAPedidoPendientesRow{avisoEnElBuzon("ped-1")}}
			parte := c.parte
			s := servidorConBuzon(t, b, func(context.Context, []AvisoDeParada) ParteAPedido {
				return parte
			})

			s.DrenarElBuzon(context.Background(), acotadoDeBuzon(b))

			if len(b.rechazados) != c.quiereRechazados {
				t.Fatalf("rechazados=%d y tenían que ser %d — %v",
					len(b.rechazados), c.quiereRechazados, b.rechazados)
			}
			if len(b.reintentos) != c.quiereReintentos {
				t.Fatalf("reintentos=%d y tenían que ser %d: un rechazo repetido para el "+
					"buzón entero, y un fallo de transporte descartado pierde el aviso",
					len(b.reintentos), c.quiereReintentos)
			}
		})
	}
}

// Y EL CÓDIGO HTTP QUEDA APUNTADO. La 00011 creó esa columna para distinguir «un 200 con
// cero aceptados» de «un 502», y **nunca se rellenaba**: estaban confundidos, que es
// justamente lo que la migración decía que no podía pasar.
func TestLaTandaApuntaElCodigoHTTP(t *testing.T) {
	b := &buzonFalso{pendientes: []sqlc.AvisosAPedidoPendientesRow{avisoEnElBuzon("ped-1")}}
	s := servidorConBuzon(t, b, func(context.Context, []AvisoDeParada) ParteAPedido {
		return ParteAPedido{Ok: false, Enviados: 1, HTTP: 502, Error: "PEDIDO contestó 502"}
	})

	s.DrenarElBuzon(context.Background(), acotadoDeBuzon(b))

	if len(b.envios) != 1 {
		t.Fatalf("no quedó constancia de la tanda: %d", len(b.envios))
	}
	if b.envios[0].Http == nil || *b.envios[0].Http != 502 {
		t.Fatalf("el código HTTP no se apuntó: %v. Sin él, un 502 y un 200 con cero "+
			"aceptados se leen igual en la pantalla", b.envios[0].Http)
	}
}

// LA OTRA MITAD: cuando no se llegó a hablar, la columna se queda VACÍA y no en cero.
// Un 0 se lee como un código, y «no hubo respuesta» no es un código.
func TestSinRespuestaElCodigoHTTPQuedaVacio(t *testing.T) {
	b := &buzonFalso{pendientes: []sqlc.AvisosAPedidoPendientesRow{avisoEnElBuzon("ped-1")}}
	s := servidorConBuzon(t, b, func(context.Context, []AvisoDeParada) ParteAPedido {
		return ParteAPedido{Ok: false, Enviados: 1, Error: "dial tcp: connection refused"}
	})

	s.DrenarElBuzon(context.Background(), acotadoDeBuzon(b))

	if len(b.envios) != 1 {
		t.Fatalf("no quedó constancia: %d", len(b.envios))
	}
	if b.envios[0].Http != nil {
		t.Fatalf("se apuntó un código (%d) para una llamada que no llegó a hacerse",
			*b.envios[0].Http)
	}
}
