package api

import (
	"testing"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/store/sqlc"
)

// EL ORDEN DE LA COLUMNA TIENE QUE SER EL MISMO QUE EL DE LA RUTA.
//
// Jose, 21/09/2026: «esa planificada está mal, no hace ruta lógica ni nada». El armador ya
// pasa 2-opt y Or-opt sobre el circuito; esta pantalla se había quedado con el greedy
// pelado. Y lo peor no es que ordene peor: es que **ordena DISTINTO**, así que el logístico
// ve un orden en el tablero y otro en la ruta que sale de ese mismo tablero, sin nada que
// explique la diferencia.
func TestLaColumnaSeOrdenaComoSeOrdenaraLaRuta(t *testing.T) {
	// Un cruce evidente: el greedy va al más cercano y luego tiene que cruzar para volver.
	const almacenLat, almacenLng = 23.1300, -82.3800
	sitios := []struct {
		nombre   string
		lat, lng float64
	}{
		{"A", 23.1350, -82.3700},
		{"B", 23.1250, -82.3600},
		{"C", 23.1340, -82.3550},
		{"D", 23.1260, -82.3750},
	}

	filas := make([]sqlc.PedidosDeColumnaParaArmarRutaRow, 0, len(sitios))
	paradas := make([]paradaGeo, 0, len(sitios))
	porID := map[uuid.UUID]string{}
	for i, s := range sitios {
		id := uuid.New()
		lat, lng := s.lat, s.lng
		filas = append(filas, sqlc.PedidosDeColumnaParaArmarRutaRow{
			ID: id, CustomerName: s.nombre, EndLat: &lat, EndLng: &lng, Posicion: int32(i),
		})
		paradas = append(paradas, paradaGeo{id: id, lat: lat, lng: lng})
		porID[id] = s.nombre
	}

	quiere := ordenDeVisita(almacenLat, almacenLng, paradas)
	salida := porCercania(filas, almacenLat, almacenLng)

	if len(salida) != len(quiere) {
		t.Fatalf("se esperaban %d pedidos y salieron %d", len(quiere), len(salida))
	}
	for i, id := range quiere {
		if salida[i].ID != id {
			t.Fatalf("LA COLUMNA Y LA RUTA SE ORDENAN DISTINTO: en el puesto %d la columna pone %q y "+
				"la ruta pondrá %q. Las dos tienen que salir de `ordenDeVisita`, o el logístico ve un "+
				"orden en el tablero y otro en la ruta que sale de ese mismo tablero.",
				i, porID[salida[i].ID], porID[id])
		}
	}
}

// UN PEDIDO SIN COORDENADAS NO PUEDE ARRASTRAR EL ORDEN DE LOS DEMÁS.
//
// Antes entraba al cálculo con `coord(nil) == 0` —el golfo de Guinea— y desde ahí el vecino
// más próximo elegía el siguiente. El orden salía completo, creíble y equivocado, que es lo
// peor que le puede pasar a esta pantalla. Ahora se quedan al final, en su orden, donde se
// ven y se arreglan.
func TestElPedidoSinCoordenadasSeQuedaAlFinalYNoTiraDelResto(t *testing.T) {
	const almacenLat, almacenLng = 23.1300, -82.3800
	lat1, lng1 := 23.1350, -82.3700
	lat2, lng2 := 23.1250, -82.3600

	sinSitio := uuid.New()
	filas := []sqlc.PedidosDeColumnaParaArmarRutaRow{
		{ID: sinSitio, CustomerName: "sin dirección", Posicion: 0},
		{ID: uuid.New(), CustomerName: "A", EndLat: &lat1, EndLng: &lng1, Posicion: 1},
		{ID: uuid.New(), CustomerName: "B", EndLat: &lat2, EndLng: &lng2, Posicion: 2},
	}

	salida := porCercania(filas, almacenLat, almacenLng)

	if len(salida) != 3 {
		t.Fatalf("SE PERDIÓ UN PEDIDO: entraron 3 y salieron %d. Nada se descarta en silencio.", len(salida))
	}
	if salida[len(salida)-1].ID != sinSitio {
		t.Errorf("EL PEDIDO SIN COORDENADAS NO ESTÁ AL FINAL: salió en otro puesto, así que entró al "+
			"cálculo como si estuviera en el golfo de Guinea y se llevó por delante el orden de los "+
			"demás. Orden obtenido: %v", nombres(salida))
	}
}

func nombres(filas []sqlc.PedidosDeColumnaParaArmarRutaRow) []string {
	s := make([]string, 0, len(filas))
	for _, f := range filas {
		s = append(s, f.CustomerName)
	}
	return s
}
