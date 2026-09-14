package cotizar

import (
	"math"
	"reflect"
	"testing"
)

// Los números esperados NO están calculados con este código: salen de correr las fórmulas
// del pliego (§1) en Node, que es lo que hace la aplicación de Next. Si algún día este
// paquete deja de darlos, es este paquete el que se movió.
//
// La comparación de la distancia lleva una holgura de 1e-9 km (una milésima de milímetro)
// porque `math.Sin` de Go y el `Math.sin` de V8 pueden separarse en el último bit. Para
// los importes NO hay holgura: se comparan exactos, porque salen ya redondeados a dos
// decimales y ahí el último bit sí decide el céntimo.
const holguraKm = 1e-9

func TestDistanciaHaversineKm(t *testing.T) {
	casos := []struct {
		nombre                 string
		lat1, lon1, lat2, lon2 float64
		esperado               float64
	}{
		// CASO LÍMITE: 0 km. El cliente está en la puerta del almacén. No es un fallo ni
		// un «sin datos»: es una distancia, y da un domicilio de 0, que es distinto de nil.
		{"mismo punto: 0 km exacto", 0, 0, 0, 0, 0},
		{"un grado de longitud en el ecuador", 0, 0, 0, 1, 111.19492664455873},
		{"un grado de latitud", 0, 0, 1, 0, 111.19492664455873},
		{"Santiago de Cuba a un cliente cercano", 20.0247, -75.8219, 20.1, -75.9, 11.689706309991518},
		{"La Habana a Santa Clara", 23.1136, -82.3666, 22.4069, -79.9647, 258.51000488504866},
		{"Camagüey a Holguín", 21.3809, -77.9169, 20.8872, -76.2631, 180.09466280204643},
		// Medio mundo: comprueba que el atan2 no se desborda donde el asin clásico sí.
		{"casi la antípoda", 20.0247, -75.8219, -20.0247, 75.8219, 17056.261496863299},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			got := DistanciaHaversineKm(c.lat1, c.lon1, c.lat2, c.lon2)
			if math.Abs(got-c.esperado) > holguraKm {
				t.Fatalf("%v: %.17g, se esperaba %.17g", c.nombre, got, c.esperado)
			}
		})
	}
}

func TestOrdenPorCercania(t *testing.T) {
	origen := Punto{Lat: 20.0, Lng: -75.8}
	tres := []Parada{
		{ID: "A", Lat: 20.1, Lng: -75.9},
		{ID: "B", Lat: 20.05, Lng: -75.85},
		{ID: "C", Lat: 20.3, Lng: -76.0},
	}
	// Las dos están EXACTAMENTE a 11.11949266445603 km del origen (comprobado en Node).
	// Es el caso que decide si el desempate es `<` o `<=`.
	empate := []Parada{
		{ID: "E1", Lat: 20.1, Lng: -75.8},
		{ID: "E2", Lat: 19.9, Lng: -75.8},
	}

	casos := []struct {
		nombre   string
		paradas  []Parada
		esperado []string
	}{
		// CASO LÍMITE del pliego: sin paradas, lista vacía (un `[]`, nunca nil).
		{"sin paradas", nil, []string{}},
		{"sin paradas, lista vacía", []Parada{}, []string{}},
		// CASO LÍMITE del pliego: una parada, se devuelve sin medir nada.
		{"una parada", []Parada{tres[2]}, []string{"C"}},
		{"tres paradas: la más cercana primero", tres, []string{"B", "A", "C"}},
		// EL DESEMPATE LO GANA EL PRIMERO DE LA LISTA. Con `<=` saldría E2 y el chofer
		// llevaría el orden al revés.
		{"empate exacto: gana el primero de la lista", empate, []string{"E1", "E2"}},
		{"empate al revés: sigue ganando el primero", []Parada{empate[1], empate[0]}, []string{"E2", "E1"}},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			got := OrdenPorCercania(origen, c.paradas)
			if !reflect.DeepEqual(got, c.esperado) {
				t.Fatalf("orden %v, se esperaba %v", got, c.esperado)
			}
		})
	}
}

// OrdenPorCercania no puede vaciar la lista de quien llama: el manejador la sigue usando
// después para sacar las coordenadas de cada parada.
func TestOrdenPorCercaniaNoTocaLaEntrada(t *testing.T) {
	paradas := []Parada{
		{ID: "A", Lat: 20.1, Lng: -75.9},
		{ID: "B", Lat: 20.05, Lng: -75.85},
	}
	antes := append([]Parada(nil), paradas...)
	OrdenPorCercania(Punto{Lat: 20, Lng: -75.8}, paradas)
	if !reflect.DeepEqual(paradas, antes) {
		t.Fatalf("la lista de entrada quedó %v, se esperaba %v", paradas, antes)
	}
}

func TestTramosDeRuta(t *testing.T) {
	origen := Punto{Lat: 20.0, Lng: -75.8}
	a := Parada{ID: "A", Lat: 20.1, Lng: -75.9}
	b := Parada{ID: "B", Lat: 20.05, Lng: -75.85}
	c := Parada{ID: "C", Lat: 20.3, Lng: -76.0}

	casos := []struct {
		nombre   string
		paradas  []Parada
		esperado []float64
	}{
		{"sin paradas", nil, []float64{}},
		{"en el orden del greedy (B, A, C)", []Parada{b, a, c},
			[]float64{7.6286963250778825, 7.627557443221552, 24.565694643340745}},
		// El MISMO conjunto en otro orden da otros kilómetros: por eso los tramos se
		// calculan sobre el orden YA decidido y no al revés.
		{"en el orden de entrada (A, B, C)", []Parada{a, b, c},
			[]float64{15.256253368068217, 7.627557443221552, 31.90415176230392}},
	}
	for _, cs := range casos {
		t.Run(cs.nombre, func(t *testing.T) {
			got := TramosDeRuta(origen, cs.paradas)
			if len(got) != len(cs.esperado) {
				t.Fatalf("%d tramos, se esperaban %d (%v)", len(got), len(cs.esperado), got)
			}
			for i := range got {
				if math.Abs(got[i]-cs.esperado[i]) > holguraKm {
					t.Fatalf("tramo %d: %.17g, se esperaba %.17g", i, got[i], cs.esperado[i])
				}
			}
		})
	}
}
