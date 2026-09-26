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
	// roto; los 420 días, porque una ruta se arma también con pedidos ya completados.
	o, err := Cargar(entorno(map[string]string{"SERVICE_API_KEY": "k"}))
	if err != nil {
		t.Fatalf("con la llave puesta tenía que cargar: %v", err)
	}
	if o.Poll != time.Minute {
		t.Errorf("el ciclo por defecto es de un minuto; salió %v", o.Poll)
	}
	if o.HistoricoDias != 420 || o.HistoricoPorCiclo != 30 || o.RepasoDias != 3 {
		t.Errorf("el histórico por defecto salió %d/%d/%d", o.HistoricoDias, o.HistoricoPorCiclo, o.RepasoDias)
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

// EL RITMO DEL CICLO DEPENDE DE SI LOS AVISOS ENTRAN.
//
// Con el canal de Redis puesto, el ciclo deja de ser quien se entera de las cosas —eso lo
// hace el stream, que entra en cuanto PEDIDO suelta— y pasa a ser quien comprueba que nada
// se quedó por el camino: quince minutos.
//
// SIN CANAL TIENE QUE SEGUIR CADA MINUTO, y ésta es la mitad que importa: entonces el ciclo
// es lo ÚNICO que trae los cambios, y bajarlo dejaría al reparto quince minutos por detrás
// de PEDIDO **sin que nada lo diga**. Esa es la forma de este fallo: no da error, sólo
// llega tarde.
func TestElCicloVaLentoSoloSiLosAvisosEntran(t *testing.T) {
	conCanal := Opciones{Poll: time.Minute, RedisDireccion: "procovar-redis:6379"}
	if got := conCanal.RitmoDelCiclo(false); got != PollConAvisos {
		t.Fatalf("con los avisos entrando el ciclo sigue corriendo cada %v", got)
	}

	sinCanal := Opciones{Poll: time.Minute}
	if got := sinCanal.RitmoDelCiclo(false); got != time.Minute {
		t.Fatalf(
			"sin canal el ciclo se fue a %v: es lo único que trae los cambios y el "+
				"reparto se quedaría así de atrás sin que nada lo diga", got,
		)
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
