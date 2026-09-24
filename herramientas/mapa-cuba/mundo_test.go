package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/paulmach/orb"
	"github.com/paulmach/orb/encoding/mvt"
	"github.com/paulmach/osm"
)

// ── LA COSTA DEL MUNDO, 22/09/2026 ────────────────────────────────────────────
//
// Jose: «se puede traer otra parte de osm para tener el mundo completo asi
// podemos alejar el mapa mas aun y tener la costa pero solo detallado tener cuba
// entiendes».
//
// Todo lo que hay debajo vigila una sola cosa: que la costa de Natural Earth se
// comporte EXACTAMENTE como la de OpenStreetMap, porque el pintor no sabe que
// son dos fuentes distintas y deduce el mar de las dos igual.

// mundoDePrueba escribe un GeoJSON con la forma de `ne_10m_land.geojson`.
//
// `min_zoom` es el campo de verdad de Natural Earth, no un invento: el fichero
// bueno trae grupos con 0, 1, 1.5, 2, 3, 4, 5, 6 y el 100 de la «Null island».
func mundoDePrueba(t *testing.T, anillos [][][][2]float64, minZoom any) []byte {
	t.Helper()
	props := map[string]any{"featurecla": "Land"}
	if minZoom != nil {
		props["min_zoom"] = minZoom
	}
	doc := map[string]any{
		"type": "FeatureCollection",
		"features": []any{map[string]any{
			"type":       "Feature",
			"properties": props,
			"geometry": map[string]any{
				"type":        "MultiPolygon",
				"coordinates": anillos,
			},
		}},
	}
	b, err := json.Marshal(doc)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// Una isla cuadrada, escrita AL REVES de como la quiere el pintor (horario en
// lon/lat, o sea con la tierra a la derecha). Que venga mal escrita es el caso
// que importa: Natural Earth no promete ningún sentido.
var islaAlReves = [][2]float64{{-80, 20}, {-80, 22}, {-78, 22}, {-78, 20}, {-80, 20}}

func sentidoLonLat(a orb.Ring) orb.Orientation { return a.Orientation() }

// EL SENTIDO DE GIRO, QUE ES TODA LA DECISION DE ESTE FICHERO.
//
// El pintor no dibuja una raya azul: deduce **de qué lado queda la tierra** a
// partir del sentido en que está escrita la costa (`marDeLaCosta`, en
// app/lib/mapa/fondo_del_paquete.dart). La de OpenStreetMap lo cumple por regla
// del proyecto; la de Natural Earth no promete nada, así que se endereza aquí.
//
// Y el sentido bueno está MEDIDO, no supuesto: cosiendo los trozos de
// `natural=coastline` del `.pbf` de Cuba del 22/09/2026 salen 4.406 anillos
// cerrados y **los 4.406 giran CCW en lon/lat**; el mayor es la isla, 103.153
// puntos. Esta prueba ata la costa del mundo a esa medida.
//
// Lo que pasa si se rompe: el fichero sale, pesa lo mismo, se abre igual y
// `-comprobar` no dice nada. En el teléfono, **el Atlántico se pinta del color
// de la tierra y la tierra del color del mar**.
func TestLaCostaDelMundoGiraComoLaDeOsm(t *testing.T) {
	descartes := map[string]int{}
	rasgos, err := LeerElMundo(mundoDePrueba(t, [][][][2]float64{{islaAlReves}}, 0.0), descartes)
	if err != nil {
		t.Fatal(err)
	}
	if len(rasgos) != 1 {
		t.Fatalf("salieron %d rasgos y tenía que salir 1", len(rasgos))
	}
	linea, vale := rasgos[0].Geo.(orb.LineString)
	if !vale {
		t.Fatalf("la costa del mundo salió como %T; el pintor busca líneas", rasgos[0].Geo)
	}
	if dio := sentidoLonLat(orb.Ring(linea)); dio != orb.CCW {
		t.Errorf("la isla salió girando %v y la costa de OpenStreetMap gira %v (CCW) en lon/lat.\n"+
			"Medido sobre el .pbf de Cuba del 22/09/2026: 4.406 de 4.406 anillos cerrados giran CCW.\n"+
			"Al revés, el pintor deduce el mar del otro lado: se pinta de azul la tierra "+
			"y de papel el océano, sin un solo error por ningún lado", dio, orb.CCW)
	}
	if rasgos[0].Capa != capaCosta || rasgos[0].Clase != "costa" {
		t.Errorf("salió en la capa %q clase %q; el pintor busca %q/%q por esa cadena exacta",
			rasgos[0].Capa, rasgos[0].Clase, capaCosta, "costa")
	}
	if !rasgos[0].DelMundo {
		t.Error("el rasgo no viene marcado como DelMundo: entonces no se para en CorteDelMundo " +
			"y pisa la costa de OSM en los zooms de Cuba")
	}
}

// Y LA MISMA PREGUNTA CONTRA LA FUENTE DE VERDAD, dentro de la tesela.
//
// La de arriba compara contra un número escrito a mano. Ésta compara la costa de
// Natural Earth contra una costa de OpenStreetMap que pasa por el MISMO
// extractor y el MISMO teselador, que es donde de verdad se vería si una de las
// dos se diera la vuelta por el camino (proyectar a la tesela invierte el eje Y
// y con él el signo del área).
func TestLasDosCostasLleganALaTeselaGirandoIgual(t *testing.T) {
	// La misma isla por los dos caminos. La de OSM se escribe como la escribe
	// OpenStreetMap —tierra a la izquierda, o sea CCW en lon/lat— y la del
	// mundo se escribe al revés a propósito, para que tenga que enderezarla.
	deOsm := orb.LineString{{-80, 20}, {-78, 20}, {-78, 22}, {-80, 22}, {-80, 20}}
	if sentidoLonLat(orb.Ring(deOsm)) != orb.CCW {
		t.Fatal("la isla de OSM de esta prueba está mal escrita: tiene que ir CCW en lon/lat")
	}
	descartes := map[string]int{}
	delMundo, err := LeerElMundo(mundoDePrueba(t, [][][][2]float64{{islaAlReves}}, 0.0), descartes)
	if err != nil {
		t.Fatal(err)
	}

	giroEnLaTesela := func(r Rasgo) orb.Orientation {
		nivel := Nivel{Clave: "prueba", ZoomMax: 6, ConMundo: true}
		e, err := NuevoEscritor(filepath.Join(t.TempDir(), "tmp"))
		if err != nil {
			t.Fatal(err)
		}
		if _, err := Teselar(e, []Rasgo{r}, nivel, func(string) {}); err != nil {
			t.Fatal(err)
		}
		destino := filepath.Join(t.TempDir(), "x.pmtiles")
		if err := e.Cerrar(destino, []byte("{}"), 0, 6, cajaDe(r.Caja)); err != nil {
			t.Fatal(err)
		}
		// z6 sobre la isla: ahí el anillo entero cabe en la tesela y sigue
		// cerrado, que es la única forma de poder mirarle el sentido.
		capas := abrirLaTesela(t, destino, 6, uint32(aX(-79, 6)), uint32(aY(21, 6)))
		for _, capa := range capas {
			if capa.Name != capaCosta {
				continue
			}
			for _, rasgo := range capa.Features {
				linea, vale := rasgo.Geometry.(orb.LineString)
				if !vale || len(linea) < 4 || linea[0] != linea[len(linea)-1] {
					continue
				}
				return orb.Ring(linea).Orientation()
			}
		}
		t.Fatal("la tesela no trajo ni un anillo de costa cerrado")
		return 0
	}

	unoDeOsm := Rasgo{Geo: deOsm, Capa: capaCosta, Clase: "costa", Desde: 0, Caja: deOsm.Bound()}
	giroOsm := giroEnLaTesela(unoDeOsm)
	giroMundo := giroEnLaTesela(delMundo[0])
	if giroOsm != giroMundo {
		t.Errorf("dentro de la tesela la costa de OSM gira %v y la del mundo %v.\n"+
			"Tienen que girar IGUAL: el pintor no sabe que son dos fuentes y saca el mar "+
			"de las dos con la misma regla. Una al revés pinta su mitad del mundo del revés",
			giroOsm, giroMundo)
	}
}

// El agujero gira al contrario, igual que en un multipolígono. El mar Caspio
// dentro de Asia es agua rodeada de tierra, y la tierra tiene que quedar del
// mismo lado que en la orilla de fuera.
func TestElAguaDeDentroDeUnContinenteGiraAlReves(t *testing.T) {
	fuera := [][2]float64{{-80, 20}, {-80, 26}, {-74, 26}, {-74, 20}, {-80, 20}}
	// Un lago escrito del mismo sentido que el contorno: los dos mal.
	lago := [][2]float64{{-78, 22}, {-78, 24}, {-76, 24}, {-76, 22}, {-78, 22}}
	descartes := map[string]int{}
	rasgos, err := LeerElMundo(mundoDePrueba(t, [][][][2]float64{{fuera, lago}}, 0.0), descartes)
	if err != nil {
		t.Fatal(err)
	}
	if len(rasgos) != 2 {
		t.Fatalf("salieron %d anillos y tenían que salir 2 (la orilla y el lago)", len(rasgos))
	}
	if dio := sentidoLonLat(orb.Ring(rasgos[0].Geo.(orb.LineString))); dio != orb.CCW {
		t.Errorf("la orilla de fuera gira %v y tenía que girar %v", dio, orb.CCW)
	}
	if dio := sentidoLonLat(orb.Ring(rasgos[1].Geo.(orb.LineString))); dio != orb.CW {
		t.Errorf("el lago de dentro gira %v y tenía que girar %v: es agua rodeada de tierra, "+
			"así que la tierra le queda al otro lado. Girando igual que la orilla, el "+
			"pintor lo lee como otra isla y lo pinta de tierra", dio, orb.CW)
	}
}

// EL RELEVO ENTRE LAS DOS COSTAS: ni hueco ni solape.
//
// Son dos números que tienen que encajar exactamente y viven en dos ficheros
// (`CorteDelMundo` en mundo.go, `Nivel.costaDesde` en niveles.go). Un hueco deja
// un zoom entero **sin una sola línea de costa y sin mar en todo el planeta**;
// un solape pone la misma orilla dos veces con geometrías parecidas y no
// iguales, y el pintor, que cose los trozos por sus extremos exactos, se
// encuentra cabos sueltos y se rinde: tesela sin mar.
func TestLasDosCostasSeRelevanSinHuecoNiSolape(t *testing.T) {
	for _, n := range Niveles {
		conMundo := n
		conMundo.ConMundo = true
		for z := uint8(0); z <= conMundo.ZoomMax; z++ {
			mundo := z <= CorteDelMundo
			deOsm := z >= conMundo.costaDesde()
			if mundo == deOsm {
				que := "ninguna de las dos costas"
				if mundo {
					que = "LAS DOS costas a la vez"
				}
				t.Errorf("%s z%d: %s. CorteDelMundo=%d y costaDesde=%d tienen que ser "+
					"consecutivos", n.Clave, z, que, CorteDelMundo, conMundo.costaDesde())
			}
		}
	}
	// Y sin mundo, la de OSM desde el z0 como toda la vida.
	if dio := (Nivel{}).costaDesde(); dio != 0 {
		t.Errorf("sin mundo la costa de OSM empieza en z%d; tiene que empezar en z0, "+
			"que es lo que hace que Cuba se reconozca", dio)
	}
}

// El corte, comprobado sobre el FICHERO y no sobre la tabla: que `CorteDelMundo`
// diga 6 no sirve de nada si el teselador no lo mira.
func TestLaCostaDelMundoNoPasaDeSuCorte(t *testing.T) {
	descartes := map[string]int{}
	rasgos, err := LeerElMundo(mundoDePrueba(t, [][][][2]float64{{islaAlReves}}, 0.0), descartes)
	if err != nil {
		t.Fatal(err)
	}
	nivel := Nivel{Clave: "prueba", ZoomMax: CorteDelMundo + 3, ConMundo: true}
	e, err := NuevoEscritor(filepath.Join(t.TempDir(), "tmp"))
	if err != nil {
		t.Fatal(err)
	}
	cuenta, err := Teselar(e, rasgos, nivel, func(string) {})
	if err != nil {
		t.Fatal(err)
	}
	for z := uint8(0); z <= nivel.ZoomMax; z++ {
		hay := cuenta.PorZoom[z] > 0
		if z <= CorteDelMundo && !hay {
			t.Errorf("z%d se quedó sin la costa del mundo: por debajo del corte la de OSM "+
				"no viaja, así que ese zoom sale sin mar en todo el planeta", z)
		}
		if z > CorteDelMundo && hay {
			t.Errorf("z%d lleva costa del mundo y ahí manda la de OSM: son la misma orilla "+
				"dos veces, y el pintor no sabe coser dos que no casan", z)
		}
	}
}

// Y el otro lado del relevo, también sobre el fichero: con el mundo puesto, la
// costa de OSM no aparece hasta el zoom siguiente al corte.
func TestConMundoLaCostaDeOsmEmpiezaJustoDespuesDelCorte(t *testing.T) {
	nivel := Nivel{Clave: "prueba", ZoomMax: CorteDelMundo + 3, ConMundo: true}
	orilla := orb.LineString{{-80, 20}, {-78, 20}, {-78, 22}, {-80, 22}, {-80, 20}}
	rasgo := Rasgo{Geo: orilla, Capa: capaCosta, Clase: "costa",
		Desde: nivel.costaDesde(), Caja: orilla.Bound()}

	e, err := NuevoEscritor(filepath.Join(t.TempDir(), "tmp"))
	if err != nil {
		t.Fatal(err)
	}
	cuenta, err := Teselar(e, []Rasgo{rasgo}, nivel, func(string) {})
	if err != nil {
		t.Fatal(err)
	}
	for z := uint8(0); z <= nivel.ZoomMax; z++ {
		hay := cuenta.PorZoom[z] > 0
		if z <= CorteDelMundo && hay {
			t.Errorf("z%d trae la costa de OSM y ahí manda la del mundo: la misma orilla dos veces", z)
		}
		if z > CorteDelMundo && !hay {
			t.Errorf("z%d se quedó sin la costa de OSM, que es la de Cuba y la buena", z)
		}
	}
}

// La clasificación de una vía de costa tiene que MIRAR el nivel, no una
// constante suelta. Es lo mismo que la prueba de arriba pero por el otro
// extremo: si `enQueCapaCae` se quedara con un `0` escrito a mano, el corte de
// `Nivel.costaDesde` no llegaría nunca al rasgo.
func TestLaViaDeCostaSeClasificaConElCorteDelNivel(t *testing.T) {
	via := &osm.Way{Tags: osm.Tags{{Key: "natural", Value: "coastline"}}}
	sin := Nivel{}
	con := Nivel{ConMundo: true}
	if _, _, desde, _, _ := queEsLaVia(via, sin, map[string]int{}); desde != 0 {
		t.Errorf("sin mundo la costa de OSM entró en z%d y tenía que entrar en z0", desde)
	}
	if _, _, desde, _, _ := queEsLaVia(via, con, map[string]int{}); desde != CorteDelMundo+1 {
		t.Errorf("con mundo la costa de OSM entró en z%d y tenía que entrar en z%d: "+
			"antes es la misma orilla que la del mundo, dibujada dos veces",
			desde, CorteDelMundo+1)
	}
}

// ENCENDER EL MUNDO Y CARGARLO SON LA MISMA LLAMADA.
//
// Si se pudieran hacer por separado, el fallo sería mudo en los dos sentidos:
// el nivel ajustado sin rasgos deja z0–z6 sin una sola línea de costa, y los
// rasgos sin ajustar el nivel ponen la misma orilla dos veces.
func TestEncenderElMundoYCargarloVanJuntos(t *testing.T) {
	base := Nivel{Clave: "prueba", ZoomMax: 10}

	sinNada, rasgos, err := ConLaCostaDelMundo(nil, base, map[string]int{})
	if err != nil {
		t.Fatal(err)
	}
	if sinNada.ConMundo || len(rasgos) != 0 {
		t.Errorf("sin fichero del mundo el nivel salió con ConMundo=%v y %d rasgos; "+
			"tenía que salir tal cual", sinNada.ConMundo, len(rasgos))
	}

	con, rasgos, err := ConLaCostaDelMundo(
		mundoDePrueba(t, [][][][2]float64{{islaAlReves}}, 0.0), base, map[string]int{})
	if err != nil {
		t.Fatal(err)
	}
	if !con.ConMundo {
		t.Error("con fichero del mundo el nivel salió sin ConMundo: la costa de OSM seguiría " +
			"viajando desde el z0 y se dibujaría la misma orilla dos veces")
	}
	if len(rasgos) == 0 {
		t.Error("el nivel salió con ConMundo y sin un solo rasgo: z0–z6 sin costa y sin mar")
	}
}

// Una respuesta vacía no es una respuesta buena (`CLAUDE.md` §3). Un GeoJSON de
// otra cosa se lee sin un solo error y deja cero anillos: el paquete sale con
// `ConMundo` puesto, pesando MENOS, y sin mar en medio planeta.
func TestUnMundoQueNoTraeTierraEsUnError(t *testing.T) {
	casos := map[string]string{
		"vacío":              ``,
		"no es JSON":         `<html>`,
		"sin rasgos":         `{"type":"FeatureCollection","features":[]}`,
		"líneas de costa":    `{"type":"FeatureCollection","features":[{"type":"Feature","properties":{},"geometry":{"type":"LineString","coordinates":[[-80,20],[-78,20]]}}]}`,
		"todo bajo el corte": `{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"min_zoom":100},"geometry":{"type":"Polygon","coordinates":[[[-80,20],[-80,22],[-78,22],[-78,20],[-80,20]]]}}]}`,
	}
	for nombre, texto := range casos {
		if _, err := LeerElMundo([]byte(texto), map[string]int{}); err == nil {
			t.Errorf("%s: pasó por una costa del mundo buena", nombre)
		}
	}
	// Y `ConLaCostaDelMundo` no puede tragárselo tampoco: es por donde entra de
	// verdad, y un error que se traga deja el nivel a medias.
	if _, _, err := ConLaCostaDelMundo([]byte(`{"type":"FeatureCollection","features":[]}`),
		Nivel{}, map[string]int{}); err == nil {
		t.Error("ConLaCostaDelMundo se tragó un fichero sin tierra")
	}
}

// LA «NULL ISLAND» DE NATURAL EARTH, que existe de verdad: un cuadradito de
// cinco puntos en 0,0 con `min_zoom` 100. No es tierra de nadie y se pintaría
// como una isla en medio del Atlántico. Se tira, **y se cuenta**, que es la
// regla de la casa para todo lo que se queda fuera.
func TestLaTierraQueNaturalEarthNoEnsenaSeTiraYSeCuenta(t *testing.T) {
	descartes := map[string]int{}
	isla := [][][][2]float64{{islaAlReves}}
	mezcla := fmt.Sprintf(`{"type":"FeatureCollection","features":[
	  {"type":"Feature","properties":{"featurecla":"Land","min_zoom":0},"geometry":{"type":"MultiPolygon","coordinates":%s}},
	  {"type":"Feature","properties":{"featurecla":"Null island","min_zoom":100},"geometry":{"type":"Polygon","coordinates":[[[0,0],[0,0.1],[0.1,0.1],[0.1,0],[0,0]]]}}]}`,
		mustJSON(t, isla))
	rasgos, err := LeerElMundo([]byte(mezcla), descartes)
	if err != nil {
		t.Fatal(err)
	}
	if len(rasgos) != 1 {
		t.Fatalf("salieron %d anillos y tenía que salir 1: la Null island entró en el paquete", len(rasgos))
	}
	if descartes["tierra que Natural Earth no enseña hasta pasado el corte"] != 1 {
		t.Errorf("no se contó el descarte. Lo que se queda fuera se dice con su motivo y su "+
			"número; descartes = %v", descartes)
	}
}

// `min_zoom` es de Natural Earth y se usa tal cual: es la misma pregunta que
// este generador le hace a cada clase de calle o de suelo.
func TestDesdeQueZoomSaleDeNaturalEarth(t *testing.T) {
	casos := []struct {
		minZoom any
		desde   uint8
		entra   bool
	}{
		{0.0, 0, true},
		{1.5, 1, true}, // hacia abajo: esconder tierra que existe es peor
		{float64(CorteDelMundo), CorteDelMundo, true},
		{float64(CorteDelMundo) + 1, 0, false},
		{100.0, 0, false},
		{nil, 0, true}, // sin `min_zoom` se enseña: no saber no es razón para esconder
	}
	for _, c := range casos {
		descartes := map[string]int{}
		rasgos, err := LeerElMundo(mundoDePrueba(t, [][][][2]float64{{islaAlReves}}, c.minZoom), descartes)
		if !c.entra {
			if err == nil {
				t.Errorf("min_zoom %v: entró y no tenía que entrar", c.minZoom)
			}
			continue
		}
		if err != nil {
			t.Errorf("min_zoom %v: %v", c.minZoom, err)
			continue
		}
		if rasgos[0].Desde != c.desde {
			t.Errorf("min_zoom %v salió con Desde z%d y tenía que ser z%d",
				c.minZoom, rasgos[0].Desde, c.desde)
		}
	}
}

// LA ANTARTIDA NO CABE EN MERCATOR. A 90° la proyección se va a infinito, y un
// punto así no da un error: da un `Inf` que se propaga a la caja del rasgo, al
// reparto por teselas y a la cabecera del fichero.
func TestLaAntartidaSeRecortaAloQueMercatorSabePintar(t *testing.T) {
	antartida := [][2]float64{{-180, -90}, {180, -90}, {180, -70}, {-180, -70}, {-180, -90}}
	descartes := map[string]int{}
	rasgos, err := LeerElMundo(mundoDePrueba(t, [][][][2]float64{{antartida}}, 0.0), descartes)
	if err != nil {
		t.Fatal(err)
	}
	caja := rasgos[0].Caja
	if caja.Min[1] < -latMaximaDeMercator {
		t.Errorf("la caja baja hasta %v; Mercator no pasa de %v y por debajo salen infinitos",
			caja.Min[1], -latMaximaDeMercator)
	}
	for _, p := range rasgos[0].Geo.(orb.LineString) {
		if y := aY(p[1], 6); y < 0 || y > float64(uint32(1)<<6) {
			t.Fatalf("el punto %v proyecta a y=%v, fuera del mundo", p, y)
		}
	}
	// Y sigue siendo un anillo con el sentido bueno después de recortarlo:
	// recortar cambia el área, y el sentido sale del signo del área.
	if dio := sentidoLonLat(orb.Ring(rasgos[0].Geo.(orb.LineString))); dio != orb.CCW {
		t.Errorf("después de recortar gira %v y tenía que girar %v", dio, orb.CCW)
	}
}

// `-comprobar` TIENE QUE CAZAR UN PAQUETE QUE DICE LLEVAR EL MUNDO Y NO LO
// LLEVA, que es el fallo mudo de todo esto: el fichero sale, se abre, pesa
// menos y no da ni un aviso. Lo único que cambia es que al alejar vuelve el
// papel en blanco, y eso no se ve hasta el teléfono de un repartidor.
func TestComprobarCazaUnPaqueteQueDiceLlevarElMundoYNoLoLleva(t *testing.T) {
	carpeta := t.TempDir()
	// Una costa que sólo está en los zooms de arriba, con los metadatos
	// diciendo que el paquete lleva el mundo. Es exactamente lo que sale si los
	// rasgos de Natural Earth no llegan a entrar.
	orilla := orb.LineString{{-80, 20}, {-78, 20}, {-78, 22}, {-80, 22}, {-80, 20}}
	nivel := Nivel{Clave: "prueba", Titulo: "prueba", ZoomMax: CorteDelMundo + 1, ConMundo: true}
	rasgo := Rasgo{Geo: orilla, Capa: capaCosta, Clase: "costa",
		Desde: nivel.costaDesde(), Caja: orilla.Bound()}

	escribir := func(nombre string, caja orb.Bound) string {
		e, err := NuevoEscritor(filepath.Join(carpeta, nombre+".tmp"))
		if err != nil {
			t.Fatal(err)
		}
		if _, err := Teselar(e, []Rasgo{rasgo}, nivel, func(string) {}); err != nil {
			t.Fatal(err)
		}
		ruta := filepath.Join(carpeta, nombre+".pmtiles")
		if err := e.Cerrar(ruta, metadatos(nivel), 0, nivel.ZoomMax, cajaDe(caja)); err != nil {
			t.Fatal(err)
		}
		return ruta
	}

	// Con la caja del mundo: lo que caza es que z0–z6 no traen costa.
	_, err := Comprobar(escribir("sinCosta", orb.Bound{Min: orb.Point{-180, -85}, Max: orb.Point{180, 83}}))
	if err == nil {
		t.Error("un paquete que dice llevar el mundo y no trae costa en z0–z6 pasó la comprobación: " +
			"eso son siete zooms sin mar en todo el planeta y nadie lo ve")
	} else if !strings.Contains(err.Error(), "SIN MAR") {
		t.Errorf("el motivo no dice qué pasa: %v", err)
	}

	// Con la caja de Cuba: lo que caza es que la caja no es la del mundo.
	_, err = Comprobar(escribir("cajaChica", orilla.Bound()))
	if err == nil {
		t.Error("un paquete que dice llevar el mundo con la caja de un extracto pasó la comprobación")
	} else if !strings.Contains(err.Error(), "no es el mundo") {
		t.Errorf("el motivo no dice qué pasa: %v", err)
	}
}

// Los metadatos dicen si el paquete lleva el mundo, y eso no es adorno: es lo
// que permite mirar un `.pmtiles` colgado y saber si al alejar habrá mar o
// papel, sin abrir una sola tesela. Y la atribución de las DOS fuentes.
func TestLosMetadatosDicenDeDondeSaleCadaCosa(t *testing.T) {
	con := metadatos(Nivel{Clave: "x", ConMundo: true})
	sin := metadatos(Nivel{Clave: "x"})
	for _, quiere := range []string{"OpenStreetMap", "Natural Earth", `"hasta_zoom":6`} {
		if !strings.Contains(string(con), quiere) {
			t.Errorf("los metadatos con mundo no dicen %q: %s", quiere, con)
		}
	}
	if !strings.Contains(string(sin), "OpenStreetMap") {
		t.Error("los metadatos sin mundo perdieron la atribución de OpenStreetMap, que la licencia EXIGE")
	}
	if strings.Contains(string(sin), "Natural Earth") {
		t.Error("un paquete sin mundo se atribuye a Natural Earth: dice tener datos que no tiene")
	}
	if !strings.Contains(string(sin), `"mundo":false`) {
		t.Errorf("los metadatos sin mundo no lo dicen: %s", sin)
	}
}

func mustJSON(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// abrirLaTesela saca una tesela de un `.pmtiles` ya escrito y la decodifica.
func abrirLaTesela(t *testing.T, ruta string, z uint8, x, y uint32) mvt.Layers {
	t.Helper()
	f, err := os.Open(ruta)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	c, err := LeerCabecera(f)
	if err != nil {
		t.Fatal(err)
	}
	crudo, err := TeselaDe(f, c, z, x, y)
	if err != nil {
		t.Fatal(err)
	}
	if crudo == nil {
		t.Fatalf("no hay tesela %d/%d/%d", z, x, y)
	}
	capas, err := mvt.UnmarshalGzipped(crudo)
	if err != nil {
		t.Fatal(err)
	}
	return capas
}
