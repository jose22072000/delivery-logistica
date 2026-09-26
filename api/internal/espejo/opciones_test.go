package espejo

import (
	"strings"
	"testing"
	"time"
)

// entorno arma un `os.Getenv` de mentira: las pruebas no ensucian el del proceso.
func entorno(pares map[string]string) func(string) string {
	return func(k string) string { return pares[k] }
}

func TestLosValoresPorDefectoSonLosMedidos(t *testing.T) {
	// No son números elegidos al gusto: salen de los datos de verdad. El minuto de ciclo
	// existe porque cinco minutos mirando una pantalla que no cambia se leen como que está
	// roto.
	//
	// LOS 60 DÍAS DE HISTÓRICO ERAN 420, y el cambio está medido — 26/09/2026. Decía aquí
	// que el año hacía falta «porque una ruta se arma también con pedidos ya completados»,
	// y los datos dicen otra cosa: **el reparto tiene 5.480 pedidos y el más viejo es de
	// hace 27 días**. Nada de lo que el barrido traía de los días 30 a 420 se quedaba —
	// PEDIDO filtra por repartible y la puerta rechaza lo que no tiene geolocalización ni
	// factura—, así que de **101.445 pedidos traídos en un día se quedaron 5.480**: el 95%
	// era trabajo para tirarlo, por la conexión de allá.
	//
	// Sesenta es el doble de lo que hoy sobrevive: margen para que un cambio en los filtros
	// de allá no deje un hueco, sin traer un año «por si acaso».
	o, err := Cargar(entorno(map[string]string{"SERVICE_API_KEY": "k"}))
	if err != nil {
		t.Fatalf("con la llave puesta tenía que cargar: %v", err)
	}
	if o.Poll != time.Minute {
		t.Errorf("el ciclo por defecto es de un minuto; salió %v", o.Poll)
	}
	if o.HistoricoDias != 60 || o.HistoricoPorCiclo != 30 || o.RepasoDias != 3 {
		t.Errorf("el histórico por defecto salió %d/%d/%d y tenía que ser 60/30/3: ver arriba "+
			"la medida que lo bajó de 420", o.HistoricoDias, o.HistoricoPorCiclo, o.RepasoDias)
	}
	if !o.SoloRepartibles {
		t.Error("por defecto sólo se trae lo que puede subir a un camión: era el 2 % del catálogo")
	}
	if o.SoloDomicilio || o.SoloCotizados {
		t.Error("los dos filtros finos van apagados: con ellos el reparto se quedaba con seis pedidos")
	}
}

func TestSoloElUnoEnciendeElCatalogoEntero(t *testing.T) {
	// Comparar con «cualquier cosa que no sea vacío» haría que un `SYNC_TODOS=false`
	// heredado de otro sitio encendiera justo lo contrario de lo que dice.
	o, _ := Cargar(entorno(map[string]string{"SERVICE_API_KEY": "k", "SYNC_TODOS": "false"}))
	if !o.SoloRepartibles {
		t.Error("«false» no puede encender el catálogo entero")
	}
	o, _ = Cargar(entorno(map[string]string{"SERVICE_API_KEY": "k", "SYNC_TODOS": "1"}))
	if o.SoloRepartibles {
		t.Error("«1» sí tiene que encenderlo")
	}
}

func TestLaBarraFinalDeLasDireccionesSeQuita(t *testing.T) {
	// Con ella las rutas salen con `//` en medio, y hay quien contesta 404 a eso sin decir
	// por qué.
	o, _ := Cargar(entorno(map[string]string{
		"SERVICE_API_KEY": "k",
		"PEDIDO_API_URL":  "https://pedido.procovar.cloud/",
	}))
	if o.PedidoURL != "https://pedido.procovar.cloud" {
		t.Errorf("la dirección quedó %q", o.PedidoURL)
	}
}

func TestUnNumeroMalPuestoNoSeIgnora(t *testing.T) {
	// Un cero o una letra en un número de éstos no se puede tragar en silencio: el espejo
	// se quedaría dando vueltas sin recorrer nada y sin un solo error.
	_, err := Cargar(entorno(map[string]string{"SERVICE_API_KEY": "k", "SYNC_TRAMO_DIAS": "0"}))
	if err == nil || !strings.Contains(err.Error(), "SYNC_TRAMO_DIAS") {
		t.Fatalf("tenía que quejarse del tramo; se quejó de %v", err)
	}
}

func TestUnRepasoMasLargoQueElHistoricoNoSeAdmite(t *testing.T) {
	// Dejaría al barrido sin recorrido: giraría en el sitio marcando la misma posición una
	// y otra vez, y el año de en medio no se recuperaría nunca.
	_, err := Cargar(entorno(map[string]string{
		"SERVICE_API_KEY":     "k",
		"SYNC_REPASO_DIAS":    "30",
		"SYNC_HISTORICO_DIAS": "30",
	}))
	if err == nil || !strings.Contains(err.Error(), "SYNC_REPASO_DIAS") {
		t.Fatalf("tenía que quejarse del repaso; se quejó de %v", err)
	}
}

// LOS DOS LADOS TIENEN QUE HABLAR DE LA MISMA COLA Y DEL MISMO REDIS.
//
// Si PEDIDO escribe en `procovar-delivery:in:orders` y el reparto lee de otro nombre, no
// llega nunca nada **y no hay un solo error**: los dos procesos funcionan perfectamente,
// cada uno hablando solo. Es el fallo que no se ve.
//
// Por eso el valor por defecto está escrito aquí y se prueba, y por eso `REDIS_URL` es la
// MISMA variable que usa PEDIDO: copiarla de un servicio a otro no admite equivocación.
func TestElStreamPorDefectoEsElQueEscribePedido(t *testing.T) {
	o := PorDefecto()

	if o.Stream != "procovar-delivery:in:orders" {
		t.Fatalf(
			"el nombre de la cola no es el que escribe PEDIDO: cada uno hablaría solo y "+
				"no habría ningún error. Salió: %q", o.Stream,
		)
	}
}

func TestRedisURLSeLeeIgualQueEnPedido(t *testing.T) {
	o, err := Cargar(func(k string) string {
		switch k {
		case "SERVICE_API_KEY":
			return "la-clave"
		case "REDIS_URL":
			return "redis://:secreta@procovar-redis-bbg3v0:6379/2"
		}
		return ""
	})
	if err != nil {
		t.Fatal(err)
	}

	if o.RedisDireccion != "procovar-redis-bbg3v0:6379" {
		t.Fatalf("dirección: %q", o.RedisDireccion)
	}
	if o.RedisClave != "secreta" {
		t.Fatalf("la clave no se leyó de la URL: sin ella el Redis contesta NOAUTH y no " +
			"entra un solo aviso")
	}
	if o.RedisBase != 2 {
		t.Fatalf("base: %d — cada aplicación tiene la suya y mezclarlas se lleva llaves "+
			"de otra sin avisar", o.RedisBase)
	}
}

// Y SIN REDIS NO SE ENCHUFA NADA, que es lo que deja desplegar esto antes de tocar el
// Redis y hace que un Redis caído no impida arrancar.
func TestSinRedisElEspejoSigueConSuCiclo(t *testing.T) {
	o, err := Cargar(func(k string) string {
		if k == "SERVICE_API_KEY" {
			return "la-clave"
		}
		return ""
	})
	if err != nil {
		t.Fatal(err)
	}

	if o.RedisDireccion != "" || len(o.RedisCentinelas) != 0 {
		t.Fatalf("se inventó un Redis: %q %v", o.RedisDireccion, o.RedisCentinelas)
	}
}

// EL RITMO DEL CICLO DEPENDE DE SI A ALGUIEN LE AVISAN, Y HAY DOS PUERTAS.
//
// Cuando entra un aviso —por la cola o por el webhook— el ciclo deja de ser quien se entera
// de las cosas y pasa a ser quien comprueba que nada se quedó por el camino: tres horas, ocho
// vueltas al día (Jose, 26/09/2026).
//
// SIN NINGUNA DE LAS DOS TIENE QUE SEGUIR CADA MINUTO, y ésta es la mitad que importa:
// entonces el ciclo es lo ÚNICO que trae los cambios, y dejarlo en tres horas pondría al
// reparto tres horas por detrás de PEDIDO **sin que nada lo diga**. Ésa es la forma de este
// fallo: no da error, sólo llega tarde.
//
// LA FILA QUE ESTA PRUEBA EXISTE PARA CUBRIR es «la cola apagada y el webhook puesto». Era
// una trampa colocada justo en el camino que íbamos a andar: la decisión miraba sólo la cola,
// así que apagarla el día de la mudanza habría devuelto el ciclo a UN MINUTO —1.440 barridos
// diarios de las ocho sucursales por la conexión de allá— en el momento exacto en que menos
// falta hacían.
func TestElRitmoDelCicloMiraLasDosPuertas(t *testing.T) {
	casos := []struct {
		nombre string
		o      Opciones
		quiere time.Duration
	}{
		{"sólo la cola", Opciones{
			Poll: time.Minute, RedisDireccion: "procovar-redis:6379", EscuchaElStream: true,
		}, PollConAvisos},
		{"sólo el webhook, la cola apagada", Opciones{
			Poll: time.Minute, RedisDireccion: "procovar-redis:6379",
			EscuchaElStream: false, TocanLaPuerta: true,
		}, PollConAvisos},
		{"el webhook sin Redis siquiera", Opciones{
			Poll: time.Minute, TocanLaPuerta: true,
		}, PollConAvisos},
		{"las dos", Opciones{
			Poll: time.Minute, RedisDireccion: "procovar-redis:6379",
			EscuchaElStream: true, TocanLaPuerta: true,
		}, PollConAvisos},
		{"NINGUNA: el ciclo es lo único que trae los cambios", Opciones{
			Poll: time.Minute,
		}, time.Minute},
		{"Redis puesto pero la cola apagada y sin webhook", Opciones{
			Poll: time.Minute, RedisDireccion: "procovar-redis:6379", EscuchaElStream: false,
		}, time.Minute},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			if got := c.o.RitmoDelCiclo(false); got != c.quiere {
				t.Fatalf("con %s el ciclo va cada %v y tenía que ir cada %v",
					c.nombre, got, c.quiere)
			}
		})
	}
}

// TRES HORAS, Y ESTÁ ESCRITO EN UN SOLO SITIO.
//
// El número va aparte porque es una decisión de Jose y no un detalle: «cada 3 lo veo, serían
// 8 veces en el día para comprobar si todo está correcto en el espejo». Si alguien lo cambia
// sin querer —un dedo en el teclado, un `time.Minute` donde iba `time.Hour`— esto lo dice.
func TestElCicloLentoEsDeTresHoras(t *testing.T) {
	if PollConAvisos != 3*time.Hour {
		t.Fatalf("el ciclo lento vale %v: Jose lo puso en 3 horas, ocho vueltas al día",
			PollConAvisos)
	}
}

// EL INTERRUPTOR DE LA COLA: `ESPEJO_ESCUCHA_AVISOS=false` la apaga DEJANDO el Redis puesto.
//
// Es lo que hace posible el orden acordado con la sesión de PEDIDO: la cola se apaga sólo
// cuando se ha visto entrar una tanda por HTTP. Sin esto, apagarla obligaba a quitarle el
// Redis al servicio entero — y el Redis hace más cosas.
func TestLaColaSeApagaSinQuitarElRedis(t *testing.T) {
	entorno := func(valor string) func(string) string {
		return func(k string) string {
			switch k {
			case "SERVICE_API_KEY":
				return "la-clave"
			case "REDIS_URL":
				return "redis://procovar-redis:6379/2"
			case "ESPEJO_ESCUCHA_AVISOS":
				return valor
			}
			return ""
		}
	}

	// Apagada: el Redis sigue configurado y la cola NO se lee.
	o, err := Cargar(entorno("false"))
	if err != nil {
		t.Fatal(err)
	}
	if !o.HayRedis() {
		t.Fatal("se perdió el Redis al apagar la cola: el interruptor tenía que dejarlo puesto")
	}
	if o.EscuchaLosAvisos() {
		t.Fatal("se apagó la cola y sigue diciendo que la lee")
	}

	// LA OTRA MITAD: sin la variable, se lee. Quien no toque nada sigue como estaba, y una
	// errata en el nombre no puede dejar al reparto sin enterarse de nada.
	for _, valor := range []string{"", "true", "si", "lo-que-sea"} {
		o, err := Cargar(entorno(valor))
		if err != nil {
			t.Fatal(err)
		}
		if !o.EscuchaLosAvisos() {
			t.Fatalf("con ESPEJO_ESCUCHA_AVISOS=%q se apagó la cola: sólo `false` y `0` "+
				"apagan, porque el lado seguro es seguir escuchando", valor)
		}
	}
}

// Y LA PAREJA DEL WEBHOOK SE LEE DE LAS MISMAS DOS VARIABLES QUE LA API.
//
// HACEN FALTA LAS DOS: con una sola, la API contesta 503 y no entra ni un aviso, así que dar
// el ritmo lento por buena con media pareja dejaría el ciclo en tres horas sin que nadie
// estuviera avisando de nada. Eso es el reparto tres horas por detrás y en silencio.
func TestLaMediaParejaDelWebhookNoCuenta(t *testing.T) {
	casos := []struct {
		nombre       string
		key, secreto string
		quiere       bool
	}{
		{"las dos", "rp_k", "s3cr3t", true},
		{"sólo la key", "rp_k", "", false},
		{"sólo el secreto", "", "s3cr3t", false},
		{"ninguna", "", "", false},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			o, err := Cargar(func(k string) string {
				switch k {
				case "SERVICE_API_KEY":
					return "la-clave"
				case "PEDIDO_WEBHOOK_KEY":
					return c.key
				case "PEDIDO_WEBHOOK_SECRET":
					return c.secreto
				}
				return ""
			})
			if err != nil {
				t.Fatal(err)
			}
			if o.TocanLaPuerta != c.quiere {
				t.Fatalf("con %s dice TocanLaPuerta=%v", c.nombre, o.TocanLaPuerta)
			}
		})
	}
}

// Y SI ALGUIEN LO ESCRIBIÓ A MANO, MANDA ÉL. Quien pone `SYNC_POLL_MS` sabe lo que quiere y
// no se le discute; pisarlo con un automatismo es la clase de sorpresa que se descubre un
// martes por la tarde.
func TestSYNCPOLLEscritoAManoManda(t *testing.T) {
	o := Opciones{Poll: 5 * time.Second, RedisDireccion: "procovar-redis:6379"}

	if got := o.RitmoDelCiclo(true); got != 5*time.Second {
		t.Fatalf("se pisó el ritmo que alguien escribió a mano: %v", got)
	}
}

// EL BARRIDO BAJA A UNA VEZ AL DÍA CUANDO A ALGUIEN LE AVISAN — y sólo entonces.
//
// Con el webhook trayendo los cambios en el acto, releer el histórico en cada ciclo es
// traer el año entero para no encontrar nada: 101.445 pedidos en un día sobre una base de
// 67.971, medido el 26/09/2026.
//
// LA OTRA MITAD, que es la que importa: **sin avisos, el barrido vuelve a su ritmo de
// siempre**. Entonces es lo único que caza lo que el `since` se pierde —una carga masiva,
// una corrección por SQL sin tocar `updatedAt`— y dejarlo en una vez al día sería perder
// eso durante un día entero sin que nada lo diga.
func TestElBarridoSoloSeFrenaSiAlguienAvisa(t *testing.T) {
	casos := []struct {
		nombre string
		o      Opciones
		quiere time.Duration
	}{
		{"con la cola", Opciones{
			BarridoCada: 10 * time.Minute, RedisDireccion: "r:6379", EscuchaElStream: true,
		}, BarridoConAvisos},
		{"con el webhook y la cola apagada", Opciones{
			BarridoCada: 10 * time.Minute, TocanLaPuerta: true,
		}, BarridoConAvisos},
		{"NADIE avisa: vuelve a su ritmo", Opciones{
			BarridoCada: 10 * time.Minute,
		}, 10 * time.Minute},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			if got := c.o.RitmoDelBarrido(); got != c.quiere {
				t.Fatalf("con %s el barrido va cada %v y tenía que ir cada %v",
					c.nombre, got, c.quiere)
			}
		})
	}
}

// Y el número, en un solo sitio, porque es una decisión y no un detalle.
func TestElBarridoConAvisosEsUnaVezAlDia(t *testing.T) {
	if BarridoConAvisos != 24*time.Hour {
		t.Fatalf("el barrido con avisos vale %v: se puso en 24 h para que el histórico se "+
			"repase entero cada dos días en vez de cada ciclo", BarridoConAvisos)
	}
}
