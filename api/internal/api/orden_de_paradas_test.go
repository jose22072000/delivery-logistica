package api

// EL ORDEN EN QUE EL CAMIÓN VISITA LAS PARADAS, Y QUE SEA EL MISMO QUE EN EL APARATO.
//
// Jose, 21/09/2026, mirando una ruta planificada: «esa planificada está mal, no hace ruta
// lógica ni nada». Y no estaba rota: era el vecino más próximo a secas, que se come los
// clientes cercanos, deja los lejanos sueltos, cruza el recorrido consigo mismo y remata
// con un viaje entero de vuelta al almacén. Ahora ese greedy es sólo el punto de partida
// de `ordenDeVisita`, que le pasa 2-opt y Or-opt sobre el circuito cerrado.
//
// POR QUÉ ESTE FICHERO EXISTE Y NO BASTA UN COMENTARIO (CLAUDE.md §3-bis): el orden se
// calcula DOS VECES —aquí y en `app/lib/pantallas/rutas/datos/geo.dart`, porque la ruta se
// arma en el patio del almacén sin señal— y si los dos no dan EXACTAMENTE lo mismo no falla
// nada: sale una ruta con sentido en el servidor y otra distinta en el teléfono, las dos
// creíbles, y sólo se nota el día que alguien compara. `docs/orden-de-paradas.casos.json` lo
// leen esta prueba y `app/test/pantallas/rutas/geo_test.dart`; tocar un lado y no el otro
// pone una de las dos en rojo.

import (
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
)

// ---------------------------------------------------------------------------
// El fichero compartido
// ---------------------------------------------------------------------------

type casoDeOrden struct {
	Nombre string `json:"nombre"`
	Nota   string `json:"nota"`
	Origen struct {
		Lat float64 `json:"lat"`
		Lng float64 `json:"lng"`
	} `json:"origen"`
	Paradas []struct {
		ID  string  `json:"id"`
		Lat float64 `json:"lat"`
		Lng float64 `json:"lng"`
	} `json:"paradas"`
	OrdenVecinoMasProximo []string `json:"ordenVecinoMasProximo"`
	KmVecinoMasProximo    float64  `json:"kmVecinoMasProximo"`
	OrdenEsperado         []string `json:"ordenEsperado"`
	KmEsperado            float64  `json:"kmEsperado"`
}

type ficheroDeCasos struct {
	MejoraMinimaKm float64       `json:"mejoraMinimaKm"`
	ToleranciaKm   float64       `json:"toleranciaKm"`
	Casos          []casoDeOrden `json:"casos"`
}

// rutaDelFicheroDeCasos: el mismo fichero que lee la prueba del aparato, no una copia. Una
// copia se desincroniza y entonces las dos pruebas salen verdes diciendo cosas distintas.
const rutaDelFicheroDeCasos = "../../../docs/orden-de-paradas.casos.json"

func leerCasos(t *testing.T) ficheroDeCasos {
	t.Helper()
	crudo, err := os.ReadFile(filepath.Clean(rutaDelFicheroDeCasos))
	if err != nil {
		t.Fatalf("sin %s no hay nada que ate el servidor con el aparato: %v", rutaDelFicheroDeCasos, err)
	}
	var doc ficheroDeCasos
	if err := json.Unmarshal(crudo, &doc); err != nil {
		t.Fatalf("%s no se entiende: %v", rutaDelFicheroDeCasos, err)
	}
	if len(doc.Casos) == 0 {
		t.Fatal("el fichero de casos está vacío: una prueba sin casos no prueba nada")
	}
	if doc.MejoraMinimaKm != mejoraMinimaKm {
		t.Fatalf("el epsilon del fichero (%g) y el del código (%g) tienen que ser el mismo: "+
			"con dos números distintos, Go y Dart dejan de decidir igual", doc.MejoraMinimaKm, mejoraMinimaKm)
	}
	return doc
}

// aParadas convierte el caso en lo que come el ordenador de paradas, y devuelve el
// diccionario para volver de los uuid a los nombres legibles del fichero.
func aParadas(c casoDeOrden) ([]paradaGeo, map[uuid.UUID]string) {
	paradas := make([]paradaGeo, 0, len(c.Paradas))
	nombres := map[uuid.UUID]string{}
	for _, p := range c.Paradas {
		id := uuid.New()
		nombres[id] = p.ID
		paradas = append(paradas, paradaGeo{id: id, lat: p.Lat, lng: p.Lng})
	}
	return paradas, nombres
}

func nombresDe(orden []uuid.UUID, nombres map[uuid.UUID]string) []string {
	salida := make([]string, 0, len(orden))
	for _, id := range orden {
		salida = append(salida, nombres[id])
	}
	return salida
}

func mismaLista(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// kmDelCircuito: los tramos MÁS el regreso al almacén, que es lo que mide el camión de
// verdad y lo que se guarda en `totalDistance`.
func kmDelCircuito(origenLat, origenLng float64, orden []paradaGeo) float64 {
	if len(orden) == 0 {
		return 0
	}
	total := 0.0
	lat, lng := origenLat, origenLng
	for _, p := range orden {
		total += kmHaversine(lat, lng, p.lat, p.lng)
		lat, lng = p.lat, p.lng
	}
	return total + kmHaversine(lat, lng, origenLat, origenLng)
}

func enOrden(paradas []paradaGeo, orden []uuid.UUID) []paradaGeo {
	porID := map[uuid.UUID]paradaGeo{}
	for _, p := range paradas {
		porID[p.id] = p
	}
	salida := make([]paradaGeo, 0, len(orden))
	for _, id := range orden {
		salida = append(salida, porID[id])
	}
	return salida
}

// ---------------------------------------------------------------------------
// La paridad con el aparato
// ---------------------------------------------------------------------------

func TestLosCasosCompartidosDanElMismoOrdenQueElAparato(t *testing.T) {
	doc := leerCasos(t)
	for _, caso := range doc.Casos {
		t.Run(caso.Nombre, func(t *testing.T) {
			paradas, nombres := aParadas(caso)

			greedy := nombresDe(ordenVecinoMasProximo(caso.Origen.Lat, caso.Origen.Lng, paradas), nombres)
			if !mismaLista(greedy, caso.OrdenVecinoMasProximo) {
				t.Fatalf("el vecino más próximo cambió en el servidor: %v en vez de %v.\n"+
					"Si el cambio es a propósito hay que regenerar «%s» en %s Y cambiar el aparato: "+
					"el orden de las paradas tiene que ser el mismo en los dos.",
					greedy, caso.OrdenVecinoMasProximo, caso.Nombre, rutaDelFicheroDeCasos)
			}

			bueno := nombresDe(ordenDeVisita(caso.Origen.Lat, caso.Origen.Lng, paradas), nombres)
			if !mismaLista(bueno, caso.OrdenEsperado) {
				t.Fatalf("el orden de visita de «%s» ya no es el del fichero compartido: %v en vez de %v.\n"+
					"O se rompió la mejora, o se rompió el desempate, o alguien cambió el algoritmo en un solo lado.",
					caso.Nombre, bueno, caso.OrdenEsperado)
			}

			km := kmDelCircuito(caso.Origen.Lat, caso.Origen.Lng,
				enOrden(paradas, ordenDeVisita(caso.Origen.Lat, caso.Origen.Lng, paradas)))
			if math.Abs(km-caso.KmEsperado) > doc.ToleranciaKm {
				t.Fatalf("los km del circuito de «%s» no cuadran con el fichero: %.6f en vez de %.6f",
					caso.Nombre, km, caso.KmEsperado)
			}
			kmGreedy := kmDelCircuito(caso.Origen.Lat, caso.Origen.Lng,
				enOrden(paradas, ordenVecinoMasProximo(caso.Origen.Lat, caso.Origen.Lng, paradas)))
			if km > kmGreedy+mejoraMinimaKm {
				t.Fatalf("en «%s» el orden «mejorado» mide MÁS que el del vecino más próximo "+
					"(%.6f contra %.6f): la mejora está empeorando la ruta", caso.Nombre, km, kmGreedy)
			}
		})
	}
}

// ---------------------------------------------------------------------------
// Que mejore de verdad
// ---------------------------------------------------------------------------

// LA PRUEBA DE QUE ESTO SIRVE PARA ALGO: un caso con cruce evidente tiene que salir más
// corto y sin cruces. Un cruce es la señal de que la ruta no es lógica —dos tramos que se
// cortan siempre se pueden deshacer y el recorrido siempre sale más corto—, que es
// exactamente lo que Jose estaba viendo en la pantalla.
func TestLaMejoraBajaLosKilometrosYDeshaceElCruce(t *testing.T) {
	origenLat, origenLng := 23.0, -82.4
	paradas := []paradaGeo{
		{id: uuid.New(), lat: 23.01, lng: -82.38}, // cercana
		{id: uuid.New(), lat: 23.06, lng: -82.36}, // noreste
		{id: uuid.New(), lat: 23.02, lng: -82.30}, // este-lejano
		{id: uuid.New(), lat: 23.07, lng: -82.41}, // norte
	}

	greedy := enOrden(paradas, ordenVecinoMasProximo(origenLat, origenLng, paradas))
	bueno := enOrden(paradas, ordenDeVisita(origenLat, origenLng, paradas))

	kmGreedy := kmDelCircuito(origenLat, origenLng, greedy)
	kmBueno := kmDelCircuito(origenLat, origenLng, bueno)
	if kmBueno >= kmGreedy-mejoraMinimaKm {
		t.Fatalf("el orden mejorado (%.3f km) tiene que medir MENOS que el del vecino más próximo (%.3f km)",
			kmBueno, kmGreedy)
	}
	if n := cruces(origenLat, origenLng, greedy); n == 0 {
		t.Fatal("el caso ya no tiene cruce: deja de probar lo que dice probar")
	}
	if n := cruces(origenLat, origenLng, bueno); n != 0 {
		t.Fatalf("el recorrido mejorado todavía se corta a sí mismo en %d sitio(s)", n)
	}
}

// EL ALMACÉN NO ES UNA PARADA. Si 2-opt pudiera moverlo, el camión empezaría en casa de un
// cliente y los km del circuito serían otros sin que fallara nada.
func TestLaPrimeraParadaSaleDelAlmacenYNoSePierdeNinguna(t *testing.T) {
	origenLat, origenLng := 23.125, -82.375
	paradas := []paradaGeo{
		{id: uuid.New(), lat: 23.14, lng: -82.39},
		{id: uuid.New(), lat: 23.09, lng: -82.31},
		{id: uuid.New(), lat: 23.16, lng: -82.27},
		{id: uuid.New(), lat: 23.05, lng: -82.42},
	}
	orden := ordenDeVisita(origenLat, origenLng, paradas)
	if len(orden) != len(paradas) {
		t.Fatalf("el orden de visita perdió paradas: %d de %d", len(orden), len(paradas))
	}
	vistas := map[uuid.UUID]int{}
	for _, id := range orden {
		vistas[id]++
	}
	for _, p := range paradas {
		if vistas[p.id] != 1 {
			t.Fatalf("la parada %s aparece %d veces: el orden tiene que ser una permutación", p.id, vistas[p.id])
		}
	}
	// El primer tramo se mide DESDE el almacén.
	primera := enOrden(paradas, orden)[0]
	esperado := kmHaversine(origenLat, origenLng, primera.lat, primera.lng)
	if got := kmDelCircuito(origenLat, origenLng, enOrden(paradas, orden[:1])); math.Abs(got-2*esperado) > 1e-9 {
		t.Fatalf("el recorrido no arranca en el almacén: ida y vuelta a la primera parada dieron %.6f y no %.6f",
			got, 2*esperado)
	}
}

// MISMO ORDEN DE ENTRADA, MISMO ORDEN DE SALIDA. Sin esto la paridad con el aparato no se
// puede ni plantear, y el fallo no se ve: cada armado da una ruta distinta y todas parecen
// razonables.
func TestElOrdenDeVisitaEsDeterminista(t *testing.T) {
	origenLat, origenLng := 21.3808, -77.9169
	paradas := []paradaGeo{
		{id: uuid.New(), lat: 20.8872, lng: -76.2631},
		{id: uuid.New(), lat: 21.8404, lng: -78.7625},
		{id: uuid.New(), lat: 20.3797, lng: -76.6431},
		{id: uuid.New(), lat: 21.5453, lng: -77.2647},
		{id: uuid.New(), lat: 20.3433, lng: -77.1167},
	}
	antes := append([]paradaGeo(nil), paradas...)
	primera := ordenDeVisita(origenLat, origenLng, paradas)
	for i := 0; i < 5; i++ {
		if otra := ordenDeVisita(origenLat, origenLng, paradas); !mismosIDs(primera, otra) {
			t.Fatalf("dos llamadas iguales dieron órdenes distintos: %v y %v", primera, otra)
		}
	}
	// Y la lista de quien llama no se toca: ordenar no es reordenarle los pedidos al que
	// arma la ruta.
	for i := range antes {
		if antes[i].id != paradas[i].id {
			t.Fatal("ordenar las paradas le movió la lista a quien llamó")
		}
	}
}

func mismosIDs(a, b []uuid.UUID) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// LA PUERTA ABIERTA AL ENRUTADOR POR CALLES. No se prueba el enrutador —lo está escribiendo
// otro— sino que el orden de visita NO depende de la línea recta: con otra forma de medir
// tiene que salir otro orden. Si saliera el mismo, la función que se pasa no se usa.
func TestLaDistanciaSePuedeCambiarPorFuera(t *testing.T) {
	paradas := []paradaGeo{
		{id: uuid.New(), lat: 0.05, lng: 0},
		{id: uuid.New(), lat: 0, lng: 0.1},
		{id: uuid.New(), lat: 0, lng: 0.25},
	}
	// Una calle de mentira: subir en latitud cuesta diez veces más que ir de lado.
	comoSiFueranCalles := func(lat1, lng1, lat2, lng2 float64) float64 {
		return math.Abs(lng1-lng2) + 10*math.Abs(lat1-lat2)
	}
	recta := ordenDeVisita(0, 0, paradas)
	calles := ordenDeVisitaCon(0, 0, paradas, comoSiFueranCalles)
	if mismosIDs(recta, calles) {
		t.Fatalf("la distancia que se pasa por fuera no se está usando: los dos órdenes son %v", recta)
	}
}

// CON 60 PARADAS NO SE CUELGA. El tope de pasadas está justo para esto; la medida se
// imprime para que se vea con `go test -v`.
func TestOrdenarSesentaParadasNoCuelga(t *testing.T) {
	for _, cuantas := range []int{10, 30, 60} {
		paradas := repartoDeMentira(cuantas)
		empezo := time.Now()
		orden := ordenDeVisita(23.125, -82.375, paradas)
		tardo := time.Since(empezo)
		if len(orden) != cuantas {
			t.Fatalf("con %d paradas salieron %d", cuantas, len(orden))
		}
		if tardo > 2*time.Second {
			t.Fatalf("ordenar %d paradas tardó %s: eso es una pantalla congelada", cuantas, tardo)
		}
		t.Logf("%d paradas: %s", cuantas, tardo)
	}
}

// repartoDeMentira: el mismo reparto siempre (la semilla está escrita a mano) para que la
// medida del tiempo se pueda repetir. Es el mismo generador que el de la prueba de Dart.
func repartoDeMentira(cuantas int) []paradaGeo {
	semilla := int64(20260921)
	siguiente := func() float64 {
		semilla = (semilla*1103515245 + 12345) & 0x7fffffff
		return float64(semilla) / float64(0x7fffffff)
	}
	paradas := make([]paradaGeo, 0, cuantas)
	for i := 0; i < cuantas; i++ {
		lat := 23.0 + siguiente()*0.2
		lng := -82.5 + siguiente()*0.3
		paradas = append(paradas, paradaGeo{id: uuid.New(), lat: lat, lng: lng})
	}
	return paradas
}

// cruces cuenta cuántos pares de tramos del circuito se cortan. A la escala de una ciudad,
// medir en el plano lat/lng vale de sobra para esto.
func cruces(origenLat, origenLng float64, orden []paradaGeo) int {
	type punto struct{ lat, lng float64 }
	puntos := []punto{{origenLat, origenLng}}
	for _, p := range orden {
		puntos = append(puntos, punto{p.lat, p.lng})
	}
	puntos = append(puntos, punto{origenLat, origenLng})

	lado := func(p, q, r punto) float64 {
		return (q.lng-p.lng)*(r.lat-p.lat) - (q.lat-p.lat)*(r.lng-p.lng)
	}
	seCortan := func(a, b, c, d punto) bool {
		d1, d2, d3, d4 := lado(c, d, a), lado(c, d, b), lado(a, b, c), lado(a, b, d)
		return (d1 > 0) != (d2 > 0) && (d3 > 0) != (d4 > 0)
	}

	cuantos := 0
	for i := 0; i+1 < len(puntos); i++ {
		for j := i + 2; j+1 < len(puntos); j++ {
			// Los tramos pegados comparten un extremo: tocarse no es cruzarse. El primero
			// y el último comparten el almacén.
			if i == 0 && j+1 == len(puntos)-1 {
				continue
			}
			if seCortan(puntos[i], puntos[i+1], puntos[j], puntos[j+1]) {
				cuantos++
			}
		}
	}
	return cuantos
}
