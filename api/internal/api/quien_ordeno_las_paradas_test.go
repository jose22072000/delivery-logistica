// QUIÉN ORDENÓ LAS PARADAS, Y QUE LA RUTA LO DIGA.
//
// `optimized` no es un adorno del modelo: es la firma de quién decidió el orden de visita.
// Estaba clavado a `true` en el SQL (`FijarTotalesDeRuta`), así que una ruta armada
// respetando el orden que puso el logístico a mano se guardaba diciendo que la había
// calculado la máquina.
//
// El daño no se ve el día que pasa. Se ve después: la pantalla no ofrece reoptimizar «lo
// que ya está optimizado», el informe cuenta esa ruta entre las calculadas, y el orden que
// puso una persona que conoce las calles de su distrito queda indistinguible del greedy.
// Es el mismo fallo de familia que el `price: pedido_costo || 0`: un dato creíble y falso,
// que nadie desmiente porque nada parece roto.
//
// Las dos pruebas van EN PAREJA a propósito. Una sola —«respetar el orden deja `false`»—
// la hace pasar entera un `optimized = false` clavado, que es el mismo fallo del revés.
package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
)

// cuerpoDeArmadoCon es `cuerpoDeArmado` más el campo que dice quién ordena. Se escribe el
// JSON a mano, y no se serializa una struct, porque lo que se prueba es lo que llega por el
// cable: el caso que importa es justamente el del campo AUSENTE.
func cuerpoDeArmadoCon(vehiculo string, optimizar *bool, pedidos ...uuid.UUID) string {
	ids := make([]string, 0, len(pedidos))
	for _, id := range pedidos {
		ids = append(ids, `"`+id.String()+`"`)
	}
	campo := ""
	if optimizar != nil {
		campo = fmt.Sprintf(`"optimizar":%t,`, *optimizar)
	}
	return fmt.Sprintf(`{"name":"Reparto de la mañana","vehicleId":%q,%s"originLat":0,"originLng":0,"orderIds":[%s]}`,
		vehiculo, campo, strings.Join(ids, ","))
}

// armarConOrden arma la ruta y devuelve el id, fallando con el cuerpo entero si no sale.
func armarConOrden(t *testing.T, h http.Handler, jwt string, optimizar *bool, pedidos ...uuid.UUID) uuid.UUID {
	t.Helper()
	w := llamarRutas(t, h, http.MethodPost, "/api/routes", jwt,
		cuerpoDeArmadoCon(camionStg.String(), optimizar, pedidos...))
	if w.Code != http.StatusCreated {
		t.Fatalf("no se pudo armar la ruta (%d): %s", w.Code, w.Body.String())
	}
	var ruta RutaSalida
	if err := json.Unmarshal(w.Body.Bytes(), &ruta); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	return ruta.ID
}

// El camino de siempre: se manda una lista y ordena la máquina. `optimized` tiene que
// quedar en `true` — y el orden, el del cálculo y no el de la lista.
func TestArmarDejandoQueOrdeneLaMaquinaQuedaOptimizada(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)

	// `stg` viene [lejos, cerca, medio]: se manda tal cual, de peor a mejor. Si el orden
	// guardado fuese el de la lista, esta prueba no distinguiría nada.
	lejos, cerca, medio := stg[0], stg[1], stg[2]
	ruta := armarConOrden(t, h, deSantiagoEnRutas(t), nil, lejos, cerca, medio)

	if !d.rutas[ruta].optimized {
		t.Fatal("la ruta la ordenó la máquina y quedó guardada como orden de la persona: " +
			"quien la lea después creerá que el orden lo puso alguien a mano")
	}
	esperado := map[uuid.UUID]int32{cerca: 1, medio: 2, lejos: 3}
	for id, posicion := range esperado {
		p := d.pedidos[id]
		if p.stopOrder == nil || *p.stopOrder != posicion {
			t.Fatalf("%s tenía que ser la parada %d y fue %s: no se optimizó el orden",
				p.cliente, posicion, queParada(p.stopOrder))
		}
	}
}

// Y el camino que faltaba: el logístico ya puso su orden y se respeta. La ruta tiene que
// quedar diciendo LA VERDAD, que no la ordenó ninguna máquina.
func TestArmarRespetandoElOrdenDelLogisticoNoQuedaOptimizada(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)

	// El orden que pone la persona: lejos, cerca, medio. Es EXACTAMENTE el que el greedy
	// no daría —él saca cerca, medio, lejos—, y por eso vale como prueba: si el servidor
	// reordenara, las posiciones lo delatan.
	lejos, cerca, medio := stg[0], stg[1], stg[2]
	no := false
	ruta := armarConOrden(t, h, deSantiagoEnRutas(t), &no, lejos, cerca, medio)

	if d.rutas[ruta].optimized {
		t.Fatal("el orden lo puso una persona y la ruta se guardó firmada como calculada: " +
			"eso es el `optimized = true` clavado en FijarTotalesDeRuta")
	}
	esperado := map[uuid.UUID]int32{lejos: 1, cerca: 2, medio: 3}
	for id, posicion := range esperado {
		p := d.pedidos[id]
		if p.stopOrder == nil || *p.stopOrder != posicion {
			t.Fatalf("%s tenía que ser la parada %d y fue %s: se reordenó el trabajo "+
				"de la persona en vez de respetarlo", p.cliente, posicion, queParada(p.stopOrder))
		}
	}
}

// Las APK ya instaladas NO mandan `optimizar`, y su lista viene ordenada por la máquina del
// aparato. Sin este caso, poner el defecto en `false` dejaría las dos pruebas de arriba en
// verde y marcaría en falso todas las rutas de la calle — el mismo fallo al revés.
func TestSinElCampoOptimizarSeDaPorCalculadaComoSiempre(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)

	ruta := armarRutaDePrueba(t, h, deSantiagoEnRutas(t), stg[0], stg[1], stg[2])
	if !d.rutas[ruta].optimized {
		t.Fatal("un cuerpo sin `optimizar` es el de las APK instaladas: su orden lo calculó " +
			"el aparato y la ruta tiene que seguir diciendo que está optimizada")
	}
}

// queParada escribe el número, no el puntero. Un fallo que dice «fue
// 0x30b62eb9d108» obliga a quien lo lee a ir al código antes de entender nada, y
// una prueba que no se entiende sola es media prueba.
func queParada(orden *int32) string {
	if orden == nil {
		return "ninguna (no quedó enganchado)"
	}
	return fmt.Sprintf("%d", *orden)
}

// EL ARMADOR DEL TABLERO TAMBIÉN TIENE QUE DECIR QUIÉN ORDENÓ.
//
// Cerrado el 21/09/2026. Esta llamada era la única que no mandaba el campo, y el SQL deja
// `optimized` en `true` cuando no se le dice nada: una ruta armada arrastrando tarjetas a
// mano quedaba firmada como calculada por la máquina. Aquí cuela más fácil que en
// `POST /api/routes`, porque en el tablero el orden por defecto **es el de la persona**
// (§5.4 de `tablero.md`): lo normal era que mintiera, no la excepción.
//
// Los dos casos van en pareja: con uno solo, un `false` clavado pasaría tan desapercibido
// como el `true` clavado que había.
func TestElTableroDiceQuienOrdenoLasParadas(t *testing.T) {
	for _, caso := range []struct {
		nombre string
		cuerpo string
		quiere bool
	}{
		{"sin pedir nada, el orden lo puso la persona", `{}`, false},
		{"pidiendo cercanía, lo ordenó la máquina", `{"optimizar":true}`, true},
		{"pidiendo que no, el orden lo puso la persona", `{"optimizar":false}`, false},
	} {
		t.Run(caso.nombre, func(t *testing.T) {
			q := nuevoTablero()
			q.tresPuestas()
			q.capacidad = 1000
			h := montarTab(t, q)

			w := pedirTab(t, h, http.MethodPost,
				"/api/board/columns/"+colCentro.String()+"/route",
				tokenTab(t, sucStg.String()), caso.cuerpo)
			if w.Code != http.StatusCreated {
				t.Fatalf("código %d: %s", w.Code, w.Body.String())
			}
			if q.totales == nil {
				t.Fatal("no se fijaron los totales: no se armó nada")
			}
			if q.totales.Optimizado == nil {
				t.Fatal("EL TABLERO NO DICE QUIÉN ORDENÓ LAS PARADAS: sin el campo, el SQL " +
					"deja `optimized` en true y una ruta ordenada a mano queda firmada como " +
					"calculada por la máquina")
			}
			if *q.totales.Optimizado != caso.quiere {
				quien := map[bool]string{true: "la máquina", false: "la persona"}
				t.Errorf("se guardó optimized=%v y el orden lo puso %s",
					*q.totales.Optimizado, quien[caso.quiere])
			}
		})
	}
}
