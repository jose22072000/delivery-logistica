package main

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/paulmach/orb"
	"github.com/paulmach/orb/encoding/mvt"
	"github.com/paulmach/osm"
)

// Los identificadores de la especificacion, a mano. Si la curva de Hilbert se
// escribe al reves el fichero sigue saliendo, sigue pesando lo mismo y **ningun
// otro lector lo entiende**: es el fallo que no se ve hasta el telefono del
// repartidor.
func TestIdDeTeselaEsElDeLaEspecificacion(t *testing.T) {
	casos := []struct {
		z        uint8
		x, y     uint32
		esperado uint64
	}{
		{0, 0, 0, 0},
		{1, 0, 0, 1},
		{1, 0, 1, 2},
		{1, 1, 1, 3},
		{1, 1, 0, 4},
		{2, 0, 0, 5},
		{3, 0, 0, 21},
	}
	for _, c := range casos {
		if dio := idDeTesela(c.z, c.x, c.y); dio != c.esperado {
			t.Errorf("idDeTesela(%d,%d,%d) = %d; la especificación dice %d",
				c.z, c.x, c.y, dio, c.esperado)
		}
	}
}

// nivelDe tiene que deshacer el desplazamiento de idDeTesela para TODOS los
// niveles que se generan, no solo para el primero.
func TestNivelDeDeshaceElDesplazamiento(t *testing.T) {
	for z := uint8(0); z <= 15; z++ {
		n := uint32(1) << z
		for _, xy := range [][2]uint32{{0, 0}, {n - 1, n - 1}, {n / 2, n / 3}} {
			id := idDeTesela(z, xy[0], xy[1])
			if dio := nivelDe(id); dio != z {
				t.Fatalf("z%d %d/%d → id %d → nivelDe dice z%d", z, xy[0], xy[1], id, dio)
			}
		}
	}
}

// Escribir y volver a leer. Es la unica prueba que comprueba el formato de
// verdad: contar entradas no dice nada si los desplazamientos apuntan mal.
func TestSeEscribeYSeVuelveALeer(t *testing.T) {
	carpeta := t.TempDir()
	e, err := NuevoEscritor(filepath.Join(carpeta, "tmp"))
	if err != nil {
		t.Fatal(err)
	}
	puestas := map[[3]uint32][]byte{}
	// Bastantes teselas para obligar a que haya directorios hoja: con todo en
	// la raiz nunca se ejercita el salto, que es donde se rompen estas cosas.
	for z := uint8(0); z <= 8; z++ {
		n := uint32(1) << z
		for x := uint32(0); x < n && x < 12; x++ {
			for y := uint32(0); y < n && y < 12; y++ {
				contenido := []byte("tesela " + string(rune('a'+int(z))) + string(rune('0'+int(x))) + string(rune('0'+int(y))))
				if err := e.Anadir(z, x, y, contenido); err != nil {
					t.Fatal(err)
				}
				puestas[[3]uint32{uint32(z), x, y}] = contenido
			}
		}
	}
	destino := filepath.Join(carpeta, "prueba.pmtiles")
	if err := e.Cerrar(destino, []byte(`{"attribution":"© OpenStreetMap"}`), 0, 8, Caja{-85, 19, -74, 24}); err != nil {
		t.Fatal(err)
	}

	f, err := os.Open(destino)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	c, err := LeerCabecera(f)
	if err != nil {
		t.Fatal(err)
	}
	if int(c.Entradas) != len(puestas) {
		t.Fatalf("se metieron %d teselas y la cabecera dice %d", len(puestas), c.Entradas)
	}
	for clave, esperado := range puestas {
		dio, err := TeselaDe(f, c, uint8(clave[0]), clave[1], clave[2])
		if err != nil {
			t.Fatalf("%d/%d/%d: %v", clave[0], clave[1], clave[2], err)
		}
		if !bytes.Equal(dio, esperado) {
			t.Fatalf("%d/%d/%d devolvió %q y se había metido %q",
				clave[0], clave[1], clave[2], dio, esperado)
		}
	}
	// Y una que NO se metió: tiene que decir que no está, no devolver la de al
	// lado. Una tesela equivocada dibuja otro sitio y no se ve como un error.
	if dio, err := TeselaDe(f, c, 8, 200, 200); err != nil || dio != nil {
		t.Fatalf("una tesela que no se metió devolvió %d bytes (err=%v)", len(dio), err)
	}
}

// LA REGRESION DEL FALLO QUE SE ENCONTRÓ GENERANDO (17/09/2026).
//
// `orb` proyecta MUTANDO la geometría. Un rasgo que cae en varias teselas y en
// varios zooms se lo llevaba proyectado la primera tesela que lo tocaba, y las
// demás dibujaban basura. No saltaba ningún error: salían niveles enteros sin
// una sola tesela y el fichero pesaba la cuarta parte de lo que tenía que pesar.
func TestUnRasgoSaleEnTodasLasTeselasQueToca(t *testing.T) {
	// Una línea que cruza Cuba de punta a punta: a z6 cae en varias teselas.
	linea := orb.LineString{{-84, 22.5}, {-80, 22.0}, {-76, 20.5}}
	rasgos := []Rasgo{{
		Geo: linea, Capa: capaCarretera, Clase: "autopista", Nombre: "Autopista Nacional",
		Desde: 0, Caja: linea.Bound(),
	}}
	nivel := Nivel{
		Clave: "prueba", ZoomMax: 8, NombresDesde: 0,
		Carreteras: map[string]uint8{"autopista": 0},
	}

	carpeta := t.TempDir()
	e, err := NuevoEscritor(filepath.Join(carpeta, "tmp"))
	if err != nil {
		t.Fatal(err)
	}
	cuenta, err := Teselar(e, rasgos, nivel, func(string) {})
	if err != nil {
		t.Fatal(err)
	}
	// Con la mutación puesta, los zooms de arriba se quedan a cero.
	for z := uint8(0); z <= 8; z++ {
		if cuenta.PorZoom[z] == 0 {
			t.Errorf("z%d se quedó sin una sola tesela: la geometría se está "+
				"mutando entre teselas (clonar() en teselar.go)", z)
		}
	}
	if cuenta.Teselas <= 9 {
		t.Errorf("sólo %d teselas para una línea que cruza la isla en 9 niveles: "+
			"cada nivel tendría que aportar al menos una", cuenta.Teselas)
	}
}

// Las teselas que salen tienen que ser MVT de verdad, no bytes cualesquiera.
func TestLaTeselaEsMvtDeVerdad(t *testing.T) {
	linea := orb.LineString{{-82.40, 23.10}, {-82.35, 23.12}}
	rasgos := []Rasgo{{
		Geo: linea, Capa: capaCarretera, Clase: "calle", Nombre: "Calle 23",
		Desde: 0, Caja: linea.Bound(),
	}}
	datos, cuantos, err := unaTesela(rasgos, []int{0},
		Nivel{NombresDesde: 0, Carreteras: map[string]uint8{"calle": 0}},
		14, uint32(aX(-82.40, 14)), uint32(aY(23.10, 14)))
	if err != nil {
		t.Fatal(err)
	}
	if cuantos != 1 {
		t.Fatalf("la tesela dice traer %d rasgos y se metió 1", cuantos)
	}
	capas, err := mvt.UnmarshalGzipped(datos)
	if err != nil {
		t.Fatalf("lo que salió no es MVT: %v", err)
	}
	if len(capas) != 1 || capas[0].Name != capaCarretera {
		t.Fatalf("capas %v; se esperaba sólo %q", capas, capaCarretera)
	}
	if n := capas[0].Features[0].Properties["nombre"]; n != "Calle 23" {
		t.Errorf("el nombre llegó como %v", n)
	}
}

// Un nombre por debajo de `NombresDesde` NO viaja. Es la mitad del ahorro de
// los zooms bajos.
func TestElNombreNoViajaEnLosZoomsBajos(t *testing.T) {
	linea := orb.LineString{{-82.40, 23.10}, {-82.00, 23.12}}
	rasgos := []Rasgo{{
		Geo: linea, Capa: capaCarretera, Clase: "principal", Nombre: "Vía Blanca",
		Desde: 0, Caja: linea.Bound(),
	}}
	nivel := Nivel{NombresDesde: 9, Carreteras: map[string]uint8{"principal": 0}}
	datos, _, err := unaTesela(rasgos, []int{0}, nivel, 8, uint32(aX(-82.40, 8)), uint32(aY(23.10, 8)))
	if err != nil {
		t.Fatal(err)
	}
	capas, err := mvt.UnmarshalGzipped(datos)
	if err != nil {
		t.Fatal(err)
	}
	if _, hay := capas[0].Features[0].Properties["nombre"]; hay {
		t.Error("a z8, con NombresDesde=9, el nombre viajó igual")
	}
}

// Un `.pbf` que no deja ni un rasgo es un ERROR, no un fichero vacío
// (`CLAUDE.md` §3: una respuesta vacía no es una respuesta buena).
func TestUnPbfSinNadaDibujableEsUnError(t *testing.T) {
	_, err := Extraer(bytes.NewReader(nil), Niveles[0])
	if err == nil {
		t.Fatal("un .pbf ilegible salió adelante sin decir nada")
	}
}

// Una cabecera que no es una cabecera se dice, no se lee a medias.
func TestLaCabeceraSeComprueba(t *testing.T) {
	casos := map[string][]byte{
		"vacía":        {},
		"corta":        []byte("PMTiles"),
		"otra magia":   append([]byte("MBTILES0"), make([]byte, 119)...),
		"otra versión": append([]byte("PMTiles\x02"), make([]byte, 119)...),
	}
	for nombre, crudo := range casos {
		if _, err := LeerCabecera(bytes.NewReader(crudo)); err == nil {
			t.Errorf("%s: se leyó como si fuera un .pmtiles bueno", nombre)
		}
	}
}

// ── Las tres capas de 21/09/2026: suelo, edificio y tren ──────────────────────

// LA DECISION DE TAMANO DE ESTE FICHERO, ESCRITA COMO PRUEBA.
//
// Los edificios son 582.433 poligonos en Cuba. Metidos un solo zoom mas abajo
// multiplican el paquete —cada uno cae en todas las teselas de todos los
// niveles por debajo— y a ese tamano no se ven: a z13 la tesela entera son 5 km
// y un edificio mide 15 metros. Bajar un numero en `Niveles` no rompe nada, no
// avisa de nada y deja un paquete que ya no cabe en el telefono de nadie. Por
// eso el techo esta aqui y no en un comentario: un comentario no falla.
func TestLosEdificiosSonLaDecisionDeTamano(t *testing.T) {
	for _, n := range Niveles {
		for clase, desde := range n.Edificios {
			if clase != claseEdificio {
				t.Errorf("nivel %q lleva edificios de clase %q; la única que existe es %q",
					n.Clave, clase, claseEdificio)
			}
			if desde < edificiosNuncaPorDebajoDe {
				t.Errorf("nivel %q mete los edificios desde z%d, y el suelo de esta casa "+
					"es z%d: por debajo no se ven y multiplican el fichero. "+
					"Si de verdad hace falta bajarlo, se mide antes (go run . -sin edificio) "+
					"y se cambia también edificiosNuncaPorDebajoDe, no sólo esta tabla",
					n.Clave, desde, edificiosNuncaPorDebajoDe)
			}
			if desde > n.ZoomMax {
				t.Errorf("nivel %q mete los edificios desde z%d y sólo llega a z%d: "+
					"la capa se anuncia y no viaja ni una vez",
					n.Clave, desde, n.ZoomMax)
			}
		}
	}
}

// CADA NIVEL LLEVA TODO LO DEL ANTERIOR, Y ANTES O AL MISMO TIEMPO.
//
// Los niveles se ofrecen como «más» —«todo lo del completo y un acercamiento
// más»— y **son tres descargas distintas: nadie tiene dos**. Si el detallado
// metiera los edificios en el z15 y el completo en el z14, quien se bajó los 96
// MB vería a z14 MENOS manzana que quien se bajó los 44. No saltaría ningún
// error, no habría pantalla en blanco: sólo un mapa peor por pagar más.
//
// Esto se escribió mal la primera vez (21/09/2026, edificios a z15 en el
// detallado) y es lo que encontró esta prueba.
func TestCadaNivelLlevaTodoLoDelAnterior(t *testing.T) {
	saca := func(n Nivel) map[string]map[string]uint8 {
		return map[string]map[string]uint8{
			capaCarretera: n.Carreteras, capaPoblacion: n.Poblaciones,
			capaSuelo: n.Suelos, capaTren: n.Trenes, capaEdificio: n.Edificios,
		}
	}
	for i := 1; i < len(Niveles); i++ {
		flojo, gordo := Niveles[i-1], Niveles[i]
		if gordo.ZoomMax < flojo.ZoomMax {
			t.Errorf("%q llega a z%d y %q, que es más barato, llega a z%d",
				gordo.Clave, gordo.ZoomMax, flojo.Clave, flojo.ZoomMax)
		}
		if gordo.NombresDesde > flojo.NombresDesde {
			t.Errorf("%q trae los nombres desde z%d y %q desde z%d",
				gordo.Clave, gordo.NombresDesde, flojo.Clave, flojo.NombresDesde)
		}
		mFlojo, mGordo := saca(flojo), saca(gordo)
		for capa, clases := range mFlojo {
			for clase, desdeFlojo := range clases {
				desdeGordo, lleva := mGordo[capa][clase]
				if !lleva {
					t.Errorf("%q lleva %s/%s y %q, que ocupa más, no lo lleva",
						flojo.Clave, capa, clase, gordo.Clave)
					continue
				}
				if desdeGordo > desdeFlojo {
					t.Errorf("%q mete %s/%s en z%d y %q —que ocupa más y promete "+
						"«todo lo del anterior»— lo mete en z%d: quien pagó la descarga "+
						"grande vería MENOS a ese zoom que quien pagó la pequeña",
						flojo.Clave, capa, clase, desdeFlojo, gordo.Clave, desdeGordo)
				}
			}
		}
	}
}

// Ninguna clase puede entrar por encima del zoom al que llega su nivel: se
// anunciaria una capa que no viaja nunca, que es el «contador que no cuadra con
// su lista» de `CLAUDE.md` §3-bis con otra ropa.
func TestNingunaClaseEntraPorEncimaDelZoomDelNivel(t *testing.T) {
	for _, n := range Niveles {
		mapas := map[string]map[string]uint8{
			"carretera": n.Carreteras, "poblacion": n.Poblaciones,
			"suelo": n.Suelos, "tren": n.Trenes, "edificio": n.Edificios,
		}
		for capa, m := range mapas {
			for clase, desde := range m {
				if desde > n.ZoomMax {
					t.Errorf("nivel %q: %s/%s entra en z%d y el nivel llega a z%d",
						n.Clave, capa, clase, desde, n.ZoomMax)
				}
			}
		}
	}
}

// Las clases que escribe la tabla de niveles tienen que existir en las tablas
// de traduccion de OSM. Una errata (`portuario` escrito `portuaria`) deja esa
// clase fuera del paquete **sin un solo error**: el mapa sale, pesa menos y
// falta una mancha que nadie echa de menos hasta que hace falta.
func TestLasClasesDeLosNivelesExisten(t *testing.T) {
	existe := func(tabla map[string]string) map[string]bool {
		hay := map[string]bool{}
		for _, clase := range tabla {
			hay[clase] = true
		}
		return hay
	}
	casos := []struct {
		capa  string
		tabla map[string]bool
		saca  func(Nivel) map[string]uint8
	}{
		{capaCarretera, existe(clasesDeCarretera), func(n Nivel) map[string]uint8 { return n.Carreteras }},
		{capaPoblacion, existe(clasesDePoblacion), func(n Nivel) map[string]uint8 { return n.Poblaciones }},
		{capaSuelo, existe(clasesDeSuelo), func(n Nivel) map[string]uint8 { return n.Suelos }},
		{capaTren, existe(clasesDeTren), func(n Nivel) map[string]uint8 { return n.Trenes }},
	}
	for _, c := range casos {
		for _, n := range Niveles {
			for clase := range c.saca(n) {
				if !c.tabla[clase] {
					t.Errorf("nivel %q pide %s/%q y ninguna etiqueta de OSM da esa clase: "+
						"esa capa saldría vacía sin decir nada", n.Clave, c.capa, clase)
				}
			}
		}
	}
}

// LO QUE NO SIRVE SE DESCARTA, Y SE CUENTA. Un descarte en silencio es el fallo
// que más caro sale en esta casa: el fichero sale más pequeño y nadie sabe por
// qué.
func TestLoQueNoSirveSeDescartaYSeCuenta(t *testing.T) {
	nivel := Nivel{
		ZoomMax:     15,
		Carreteras:  map[string]uint8{"calle": 13},
		Suelos:      map[string]uint8{"urbano": 9, "bosque": 9, "parque": 11},
		Trenes:      map[string]uint8{"tren": 9},
		Edificios:   map[string]uint8{"edificio": 14},
		Poblaciones: map[string]uint8{},
	}
	via := func(pares ...string) *osm.Way {
		w := &osm.Way{}
		for i := 0; i < len(pares); i += 2 {
			w.Tags = append(w.Tags, osm.Tag{Key: pares[i], Value: pares[i+1]})
		}
		return w
	}

	// EL MOTIVO IMPORTA TANTO COMO EL DESCARTE. La lista que imprime el
	// generador es lo único que explica por qué un fichero adelgazó, y «campo de
	// cultivo, a propósito fuera» y «uso del suelo que no está en la tabla» no
	// significan lo mismo: el primero es una decisión, el segundo es un hueco
	// que a lo mejor hay que tapar. Por eso se comprueba la cadena.
	fuera := []struct {
		por    string
		tags   *osm.Way
		motivo string
	}{
		{"una vía de tren en desuso no es una vía", via("railway", "abandoned"),
			"vía de tren que no es una vía (en desuso, andén…)"},
		{"un andén no es una vía", via("railway", "platform"),
			"vía de tren que no es una vía (en desuso, andén…)"},
		{"una vía de tren en construcción no es una vía", via("railway", "construction"),
			"vía de tren que no es una vía (en desuso, andén…)"},
		{"una aguja de patio", via("railway", "rail", "service", "siding"),
			"vía de tren de patio o apartadero"},
		{"campo de cultivo", via("landuse", "farmland"),
			"campo de cultivo (a propósito fuera)"},
		{"vivero", via("landuse", "greenhouse_horticulture"),
			"campo de cultivo (a propósito fuera)"},
		{"building=no dice que ahí NO hay un edificio", via("building", "no"),
			"building=no (ahí NO hay un edificio)"},
		{"un campo de fútbol no ubica a nadie", via("leisure", "pitch"),
			"uso del suelo que no está en la tabla"},
		{"zona militar", via("landuse", "military"),
			"uso del suelo que no está en la tabla"},
		{"una vía por la que no pasa un camión", via("highway", "footway"),
			"vía por la que no pasa un camión"},
	}
	for _, c := range fuera {
		descartes := map[string]int{}
		_, _, _, _, sirve := queEsLaVia(c.tags, nivel, descartes)
		if sirve {
			t.Errorf("%s: entró en el paquete igual (%v)", c.por, c.tags.Tags)
			continue
		}
		if descartes[c.motivo] != 1 || len(descartes) != 1 {
			t.Errorf("%s: se contó como %v y tenía que contarse como %q. "+
				"Un descarte con el motivo equivocado no se ve cuando el fichero adelgaza",
				c.por, descartes, c.motivo)
		}
	}

	// Una vía que nunca fue candidata a nada —una valla, un muro— NO se cuenta:
	// son millones y ahogarían la lista hasta dejarla inservible.
	descartes := map[string]int{}
	if _, _, _, _, sirve := queEsLaVia(via("barrier", "fence"), nivel, descartes); sirve || len(descartes) != 0 {
		t.Errorf("una valla entró (%v) o se contó como descarte (%v): la lista de "+
			"descartes es para lo que se dejó fuera pudiendo entrar", sirve, descartes)
	}

	dentro := []struct {
		por   string
		tags  *osm.Way
		capa  string
		clase string
		desde uint8
	}{
		{"un edificio", via("building", "yes"), capaEdificio, claseEdificio, 14},
		{"una casa", via("building", "house"), capaEdificio, claseEdificio, 14},
		{"una vía de tren", via("railway", "rail"), capaTren, "tren", 9},
		{"un barrio", via("landuse", "residential"), capaSuelo, "urbano", 9},
		{"un bosque", via("natural", "wood"), capaSuelo, "bosque", 9},
		{"un parque", via("leisure", "park"), capaSuelo, "parque", 11},
		// El edificio gana al suelo: si ganara el suelo, la manzana se pintaría
		// de color de barrio y no habría silueta, que es lo que se busca.
		{"un edificio dentro de un barrio", via("building", "yes", "landuse", "residential"),
			capaEdificio, claseEdificio, 14},
	}
	for _, c := range dentro {
		capa, clase, desde, nombre, sirve := queEsLaVia(c.tags, nivel, map[string]int{})
		if !sirve || capa != c.capa || clase != c.clase || desde != c.desde {
			t.Errorf("%s: dio capa=%q clase=%q desde=%d sirve=%v; se esperaba %q/%q desde z%d",
				c.por, capa, clase, desde, sirve, c.capa, c.clase, c.desde)
		}
		if nombre != "" {
			t.Errorf("%s: viajó con nombre %q y estas tres capas no llevan nombre", c.por, nombre)
		}
	}
}

// Un nivel que NO lleva una capa no la lleva ni un rasgo, y lo dice contándolo.
func TestUnNivelQueNoLlevaLaCapaLaDescarta(t *testing.T) {
	sinNada := Nivel{ZoomMax: 11, Carreteras: map[string]uint8{"calle": 0}}
	casos := map[string][]string{
		"edificio": {"building", "yes"},
		"tren":     {"railway", "rail"},
		"suelo":    {"landuse", "residential"},
	}
	for capa, tags := range casos {
		w := &osm.Way{Tags: osm.Tags{{Key: tags[0], Value: tags[1]}}}
		descartes := map[string]int{}
		if _, _, _, _, sirve := queEsLaVia(w, sinNada, descartes); sirve {
			t.Errorf("%s: el nivel no lleva esa capa y el rasgo entró igual", capa)
		}
		if len(descartes) == 0 {
			t.Errorf("%s: se quedó fuera sin contarse", capa)
		}
	}
}

// Un relleno con el contorno abierto NO se dibuja a medias: se cierra solo con
// una cuerda recta que no está en el suelo y sale una manzana con un tajo.
func TestUnRellenoSinCerrarSeTira(t *testing.T) {
	cerrado := orb.LineString{{-82.4, 23.1}, {-82.3, 23.1}, {-82.3, 23.2}, {-82.4, 23.1}}
	if p, vale := rellenoDe(cerrado); !vale || len(p) != 1 || len(p[0]) != 4 {
		t.Errorf("un contorno cerrado de cuatro puntos no salió como polígono: %v %v", p, vale)
	}
	malos := map[string]orb.LineString{
		"abierto":      {{-82.4, 23.1}, {-82.3, 23.1}, {-82.3, 23.2}},
		"de dos":       {{-82.4, 23.1}, {-82.4, 23.1}},
		"de tres":      {{-82.4, 23.1}, {-82.3, 23.1}, {-82.4, 23.1}},
		"casi cerrado": {{-82.4, 23.1}, {-82.3, 23.1}, {-82.3, 23.2}, {-82.4, 23.10001}},
	}
	for nombre, l := range malos {
		if _, vale := rellenoDe(l); vale {
			t.Errorf("un contorno %s pasó por polígono", nombre)
		}
	}
}

// LA MISMA REGRESION DEL `clonar`, PERO EN POLIGONO. Hasta hoy sólo se escribían
// líneas y el agua; las tres capas nuevas son rellenos, y un polígono comparte
// sus anillos igual que una línea comparte sus puntos. Si `clonar` se deja un
// caso, la PRIMERA tesela que toca el polígono se lo lleva proyectado a
// coordenadas de esa tesela y las demás dibujan basura, sin un solo error.
func TestUnRellenoSaleEnTodasLasTeselasQueTocaYNoSeMuta(t *testing.T) {
	// Una mancha del tamaño de la isla: cruza teselas en TODOS los zooms y
	// sobrevive a la simplificación floja de los de abajo (tolerancia 8 a z0
	// se come cualquier cosa más pequeña, y eso es correcto, no un fallo).
	anillo := orb.Ring{{-84.9, 19.9}, {-74.2, 19.9}, {-74.2, 23.2}, {-84.9, 23.2}, {-84.9, 19.9}}
	suelo := orb.Polygon{anillo}
	antes := fmt.Sprint(suelo)

	rasgos := []Rasgo{{
		Geo: suelo, Capa: capaSuelo, Clase: "urbano", Desde: 0, Caja: suelo.Bound(),
	}}
	nivel := Nivel{Clave: "prueba", ZoomMax: 12, NombresDesde: 0,
		Suelos: map[string]uint8{"urbano": 0}}

	e, err := NuevoEscritor(filepath.Join(t.TempDir(), "tmp"))
	if err != nil {
		t.Fatal(err)
	}
	cuenta, err := Teselar(e, rasgos, nivel, func(string) {})
	if err != nil {
		t.Fatal(err)
	}
	for z := uint8(0); z <= 12; z++ {
		if cuenta.PorZoom[z] == 0 {
			t.Errorf("z%d se quedó sin una sola tesela: el polígono se está mutando "+
				"entre teselas (clonar() en teselar.go no cubre orb.Polygon)", z)
		}
	}
	if despues := fmt.Sprint(rasgos[0].Geo); despues != antes {
		t.Errorf("el polígono original salió cambiado del teselado.\n antes: %s\n ahora: %s\n"+
			"`orb` proyecta MUTANDO: sin clonar, el rasgo se pierde para las demás teselas",
			antes, despues)
	}
}

// EL CORTE POR ZOOM DE LOS EDIFICIOS, comprobado sobre el fichero de verdad: se
// genera, se lee de vuelta y se mira qué capas trae cada tesela. Que la tabla
// diga z15 no sirve de nada si el teselador no la mira.
func TestElEdificioNoViajaPorDebajoDeSuZoom(t *testing.T) {
	// Un bloque de manzana en La Habana y la calle que pasa por delante.
	manzana := orb.Polygon{{{-82.400, 23.100}, {-82.398, 23.100}, {-82.398, 23.102}, {-82.400, 23.102}, {-82.400, 23.100}}}
	calle := orb.LineString{{-82.402, 23.099}, {-82.396, 23.103}}
	rasgos := []Rasgo{
		{Geo: manzana, Capa: capaEdificio, Clase: claseEdificio, Desde: 15, Caja: manzana.Bound()},
		{Geo: calle, Capa: capaCarretera, Clase: "calle", Desde: 13, Caja: calle.Bound()},
	}
	nivel := Nivel{Clave: "prueba", ZoomMax: 15, NombresDesde: 9,
		Carreteras: map[string]uint8{"calle": 13},
		Edificios:  map[string]uint8{claseEdificio: 15}}

	carpeta := t.TempDir()
	e, err := NuevoEscritor(filepath.Join(carpeta, "tmp"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Teselar(e, rasgos, nivel, func(string) {}); err != nil {
		t.Fatal(err)
	}
	destino := filepath.Join(carpeta, "prueba.pmtiles")
	if err := e.Cerrar(destino, []byte(`{"attribution":"© OpenStreetMap"}`), 0, 15,
		Caja{-82.41, 23.09, -82.39, 23.11}); err != nil {
		t.Fatal(err)
	}
	f, err := os.Open(destino)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	c, err := LeerCabecera(f)
	if err != nil {
		t.Fatal(err)
	}

	capasEn := func(z uint8) map[string]int {
		crudo, err := TeselaDe(f, c, z, uint32(aX(-82.399, z)), uint32(aY(23.101, z)))
		if err != nil {
			t.Fatalf("z%d: %v", z, err)
		}
		if crudo == nil {
			return nil
		}
		capas, err := mvt.UnmarshalGzipped(crudo)
		if err != nil {
			t.Fatalf("z%d: lo que salió no es MVT: %v", z, err)
		}
		cuantos := map[string]int{}
		for _, capa := range capas {
			cuantos[capa.Name] = len(capa.Features)
		}
		return cuantos
	}

	for z := uint8(0); z <= 14; z++ {
		if n := capasEn(z)[capaEdificio]; n != 0 {
			t.Errorf("a z%d viajaron %d edificios y la tabla dice que entran en z15: "+
				"el corte por zoom no se está mirando, y eso multiplica el fichero "+
				"por nada que se pueda ver a ese tamaño", z, n)
		}
	}
	if n := capasEn(15)[capaEdificio]; n != 1 {
		t.Errorf("a z15 llegaron %d edificios y se metió 1: la capa no viaja nunca", n)
	}
	if n := capasEn(14)[capaCarretera]; n != 1 {
		t.Errorf("a z14 llegaron %d calles y se metió 1: la prueba no está mirando "+
			"la tesela donde está el rasgo", n)
	}
}

// El relleno llega al otro lado COMO RELLENO, con su clase y sin nombre. Es lo
// que el pintor busca: si llegara como línea pintaría un contorno y no una
// mancha, y una mancha es lo que ubica.
func TestElSueloLlegaComoPoligonoConSuClase(t *testing.T) {
	parque := orb.Polygon{{{-82.40, 23.10}, {-82.39, 23.10}, {-82.39, 23.11}, {-82.40, 23.11}, {-82.40, 23.10}}}
	rasgos := []Rasgo{{Geo: parque, Capa: capaSuelo, Clase: "parque", Desde: 11, Caja: parque.Bound()}}
	datos, cuantos, err := unaTesela(rasgos, []int{0},
		Nivel{NombresDesde: 9, Suelos: map[string]uint8{"parque": 11}},
		13, uint32(aX(-82.395, 13)), uint32(aY(23.105, 13)))
	if err != nil {
		t.Fatal(err)
	}
	if cuantos != 1 {
		t.Fatalf("la tesela dice traer %d rasgos y se metió 1", cuantos)
	}
	capas, err := mvt.UnmarshalGzipped(datos)
	if err != nil {
		t.Fatalf("lo que salió no es MVT: %v", err)
	}
	if len(capas) != 1 || capas[0].Name != capaSuelo {
		t.Fatalf("capas %v; se esperaba sólo %q", capas, capaSuelo)
	}
	f := capas[0].Features[0]
	if f.Properties["clase"] != "parque" {
		t.Errorf("la clase llegó como %v; el pintor la busca por ese nombre exacto", f.Properties["clase"])
	}
	if _, hay := f.Properties["nombre"]; hay {
		t.Errorf("el suelo viajó con nombre y hoy nadie lo dibuja: son bytes que nadie lee")
	}
	if d := f.Geometry.Dimensions(); d != 2 {
		t.Errorf("el suelo llegó con dimensión %d; un relleno tiene que llegar como polígono (2), "+
			"o el pintor dibuja un contorno en vez de una mancha", d)
	}
}

// CADA CAPA VIAJA CON SU FORMA: mancha las que se rellenan, línea las demás.
//
// Es lo primero que el pintor da por hecho. Si el suelo llegara como línea
// dibujaría el contorno de un barrio en vez de la mancha, que es justo lo que
// Jose echaba de menos; y no saltaría ningún error, porque una línea es una
// geometría perfectamente válida.
func TestCadaCapaViajaConSuForma(t *testing.T) {
	cerrado := orb.LineString{{-82.4, 23.1}, {-82.3, 23.1}, {-82.3, 23.2}, {-82.4, 23.1}}
	abierto := orb.LineString{{-82.4, 23.1}, {-82.3, 23.15}}

	manchas := []string{capaAgua, capaSuelo, capaEdificio}
	lineas := []string{capaCarretera, capaCosta, capaTren}

	for _, capa := range manchas {
		g, vale := geometriaDe(capa, cerrado)
		if !vale {
			t.Errorf("%s: un contorno cerrado no salió", capa)
			continue
		}
		if d := g.Dimensions(); d != 2 {
			t.Errorf("%s salió con dimensión %d y tiene que salir como polígono (2): "+
				"el pintor dibujaría un contorno en vez de una mancha", capa, d)
		}
		if _, vale := geometriaDe(capa, abierto); vale {
			t.Errorf("%s: un contorno abierto pasó por mancha", capa)
		}
	}
	for _, capa := range lineas {
		g, vale := geometriaDe(capa, abierto)
		if !vale || g.Dimensions() != 1 {
			t.Errorf("%s salió como %v (dimensión %d) y tiene que salir como línea (1): "+
				"una carretera rellena se pinta como una mancha gris", capa, vale, g.Dimensions())
		}
	}
}

// Los metadatos anuncian LAS CAPAS QUE ESE NIVEL LLEVA, ni una más. Prometer
// edificios en el `básico` hace que quien abra el fichero crea que está roto.
func TestLosMetadatosNoPrometenCapasQueNoViajan(t *testing.T) {
	for _, n := range Niveles {
		meta := string(metadatos(n))
		for _, c := range []struct {
			capa  string
			lleva bool
		}{
			{capaSuelo, len(n.Suelos) > 0},
			{capaEdificio, len(n.Edificios) > 0},
			{capaTren, len(n.Trenes) > 0},
		} {
			anunciada := strings.Contains(meta, `"id":"`+c.capa+`"`)
			if anunciada != c.lleva {
				t.Errorf("nivel %q: los metadatos anuncian %q = %v y el nivel la lleva = %v",
					n.Clave, c.capa, anunciada, c.lleva)
			}
		}
		if !strings.Contains(meta, "OpenStreetMap") {
			t.Errorf("nivel %q: los metadatos se quedaron sin la atribución", n.Clave)
		}
	}
}

// `SinCapas` es sólo para medir, pero si apagara la capa equivocada la tabla de
// tamaños mentiría, y esa tabla es la que decide qué se cuelga.
func TestSinCapasApagaSoloLaQueSeLePide(t *testing.T) {
	completo, _ := NivelPorClave("completo")
	sin := completo.SinCapas([]string{capaEdificio})
	if len(sin.Edificios) != 0 {
		t.Error("-sin edificio dejó los edificios puestos: la medición diría que no cuestan nada")
	}
	if len(sin.Suelos) == 0 || len(sin.Trenes) == 0 || len(sin.Carreteras) == 0 {
		t.Error("-sin edificio se llevó por delante otra capa: la resta de bytes no sería de esa capa")
	}
	if len(completo.Edificios) == 0 {
		t.Error("SinCapas modificó el nivel original en vez de devolver una copia")
	}
}

// ── Los multipolígonos, 21/09/2026 por la tarde ───────────────────────────────

// COSER ES EL PROBLEMA DE VERDAD DE UN MULTIPOLÍGONO.
//
// Los trozos de contorno vienen en el orden en que alguien los metió en la
// relación, no en el que encajan, y cada uno puede venir del revés. Si el
// armado se equivoca no salta ningún error: sale un anillo que no cierra, o uno
// que cierra por donde no toca, y entonces la Ciénaga de Zapata se dibuja como
// una mancha con un tajo diagonal.
func TestUnContornoSeCoseAunqueVengaEnTrozosYDelReves(t *testing.T) {
	// Un cuadrado partido en cuatro lados: el segundo al revés, el tercero al
	// final y el cuarto empezando por donde acaba el primero.
	trozos := [][]osm.NodeID{
		{1, 2},
		{3, 2}, // del revés
		{4, 1},
		{3, 4},
	}
	anillos, cosido := coser(trozos)
	if !cosido {
		t.Fatal("no se pudo coser un cuadrado partido en sus cuatro lados. " +
			"En OSM los trozos NUNCA vienen en orden y la mitad vienen al revés: " +
			"sin esto no entra ni un bosque grande")
	}
	if len(anillos) != 1 {
		t.Fatalf("salieron %d anillos de un solo cuadrado: %v", len(anillos), anillos)
	}
	a := anillos[0]
	if a[0] != a[len(a)-1] {
		t.Errorf("el anillo no cierra: empieza en %d y acaba en %d. "+
			"Un contorno abierto se cierra solo con una cuerda recta que no está en el suelo", a[0], a[len(a)-1])
	}
	vistos := map[osm.NodeID]bool{}
	for _, id := range a[:len(a)-1] {
		if vistos[id] {
			t.Errorf("el nodo %d sale dos veces en el anillo %v: un trozo se cosió dos veces", id, a)
		}
		vistos[id] = true
	}
	if len(vistos) != 4 {
		t.Errorf("el anillo tiene %d nodos distintos y el cuadrado tiene 4: %v", len(vistos), a)
	}

	// Dos contornos sueltos en la misma relación salen como dos anillos: es el
	// caso de un bosque en dos manchas separadas.
	dos, cosido := coser([][]osm.NodeID{{1, 2, 3}, {3, 1}, {7, 8, 9}, {9, 7}})
	if !cosido || len(dos) != 2 {
		t.Errorf("dos contornos sueltos dieron %v (cosido=%v); tenían que salir dos anillos", dos, cosido)
	}
}

// UN CONTORNO AL QUE LE FALTA UN TROZO NO SE DIBUJA. Es la misma regla que las
// vías cortadas por el borde del extracto: a medias no se dibuja nada.
func TestUnContornoAlQueLeFaltaUnTrozoNoSeDibuja(t *testing.T) {
	malos := map[string][][]osm.NodeID{
		"le falta un lado":           {{1, 2}, {2, 3}, {3, 4}},
		"un trozo de un solo nodo":   {{1}},
		"dos trozos que no se tocan": {{1, 2}, {5, 6}},
	}
	for nombre, trozos := range malos {
		if _, cosido := coser(trozos); cosido {
			t.Errorf("%s: se dio por cosido (%v). Media Ciénaga de Zapata se cierra sola "+
				"con una cuerda recta que no está en el suelo", nombre, trozos)
		}
	}
}

// UN AGUJERO VA EN EL CONTORNO QUE LO RODEA, y no en cualquiera.
//
// Con dos manchas en la misma relación y una laguna dentro de una de ellas,
// meterla en la otra pinta un hueco donde no lo hay **y** deja la laguna
// tapada de verde: dos errores de una vez, y ninguno de los dos da error.
func TestElAgujeroVaEnElContornoQueLoRodea(t *testing.T) {
	cuadro := func(x0, y0, x1, y1 float64) orb.Ring {
		return orb.Ring{{x0, y0}, {x1, y0}, {x1, y1}, {x0, y1}, {x0, y0}}
	}
	grande := cuadro(0, 0, 10, 10)
	pequeno := cuadro(20, 0, 24, 4)
	laguna := cuadro(21, 1, 22, 2) // dentro del pequeño
	suelto := cuadro(50, 50, 51, 51)

	poligonos, huerfanos := repartirAgujeros([]orb.Ring{grande, pequeno}, []orb.Ring{laguna, suelto})
	if len(poligonos) != 2 {
		t.Fatalf("salieron %d polígonos de dos contornos", len(poligonos))
	}
	if len(poligonos[0]) != 1 {
		t.Errorf("la mancha grande se quedó con %d agujeros y no tiene ninguna laguna dentro: "+
			"el agujero se metió en el contorno equivocado", len(poligonos[0])-1)
	}
	if len(poligonos[1]) != 2 {
		t.Fatalf("la mancha pequeña se quedó con %d agujeros y la laguna cae dentro de ella", len(poligonos[1])-1)
	}
	if huerfanos != 1 {
		t.Errorf("huérfanos = %d; el anillo de fuera de todo no cabe en ningún contorno y "+
			"tiene que contarse, no pintarse: un hueco sin nada alrededor pintado como mancha "+
			"pone verde encima de una laguna", huerfanos)
	}

	// Contornos ANIDADOS: la laguna va en el más pequeño que la contenga. Si
	// ganara el más grande, el hueco saldría debajo de la otra mancha y no se
	// vería nada.
	fuera := cuadro(0, 0, 100, 100)
	dentro := cuadro(10, 10, 40, 40)
	charca := cuadro(20, 20, 25, 25)
	ps, _ := repartirAgujeros([]orb.Ring{fuera, dentro}, []orb.Ring{charca})
	if len(ps[1]) != 2 {
		t.Errorf("con dos contornos anidados el agujero fue a parar al grande: "+
			"tiene que ir al más pequeño que lo contenga (anillos: %d y %d)", len(ps[0]), len(ps[1]))
	}
}

// DE UN PLAN DE RELACIÓN A LA MANCHA CON SU HUECO, que es lo que este trabajo
// venía a arreglar.
func TestArmarUnMultipoligonoDaLaManchaConSuHueco(t *testing.T) {
	// El contorno, en dos trozos, y uno de ellos del revés. La laguna, entera.
	nodosDe := map[osm.WayID][]osm.NodeID{
		10: {1, 2, 3},
		11: {1, 4, 3}, // cierra el contorno, al revés
		12: {5, 6, 7, 8, 5},
	}
	donde := map[osm.NodeID]orb.Point{
		1: {-81.30, 22.30}, 2: {-81.10, 22.30}, 3: {-81.10, 22.50}, 4: {-81.30, 22.50},
		5: {-81.25, 22.35}, 6: {-81.20, 22.35}, 7: {-81.20, 22.40}, 8: {-81.25, 22.40},
	}
	plan := planDeRelacion{
		ID: 1, Capa: capaSuelo, Clase: "humedal", Desde: 9,
		Fuera: []osm.WayID{10, 11}, Dentro: []osm.WayID{12},
	}
	descartes := map[string]int{}
	poligonos := armarRelacion(plan, nodosDe, donde, descartes)
	if len(poligonos) != 1 {
		t.Fatalf("salieron %d polígonos y la relación es una sola mancha (descartes: %v)", len(poligonos), descartes)
	}
	if len(poligonos[0]) != 2 {
		t.Fatalf("la mancha salió con %d anillos: se esperaba el contorno y su laguna", len(poligonos[0]))
	}
	if len(descartes) != 0 {
		t.Errorf("una relación que se cosió entera dejó descartes: %v", descartes)
	}

	// Un nodo que cae fuera del extracto tumba la relación entera Y SE CUENTA.
	delete(donde, 2)
	descartes = map[string]int{}
	if p := armarRelacion(plan, nodosDe, donde, descartes); p != nil {
		t.Errorf("con un nodo fuera del extracto salió mancha igual: %v", p)
	}
	if descartes[fueraSinCoser] != 1 {
		t.Errorf("se descartó sin contarlo, o con otro motivo: %v. Un descarte en silencio "+
			"es el fallo que más caro sale en esta casa", descartes)
	}
}

// LOS AGUJEROS NO TUMBAN LA MANCHA. Si el contorno se cosió y una laguna de
// dentro no, lo que hay que dibujar es el bosque sin ese hueco: quedarse sin
// bosque por un agujero roto es cambiar un fallo pequeño por uno grande.
func TestUnAgujeroRotoNoSeLlevaLaManchaPorDelante(t *testing.T) {
	nodosDe := map[osm.WayID][]osm.NodeID{
		10: {1, 2, 3, 4, 1},
		12: {5, 6}, // una laguna que no cierra
	}
	donde := map[osm.NodeID]orb.Point{
		1: {-81.30, 22.30}, 2: {-81.10, 22.30}, 3: {-81.10, 22.50}, 4: {-81.30, 22.50},
		5: {-81.25, 22.35}, 6: {-81.20, 22.35},
	}
	plan := planDeRelacion{Capa: capaSuelo, Clase: "bosque", Desde: 9,
		Fuera: []osm.WayID{10}, Dentro: []osm.WayID{12}}
	poligonos := armarRelacion(plan, nodosDe, donde, map[string]int{})
	if len(poligonos) != 1 || len(poligonos[0]) != 1 {
		t.Fatalf("la mancha se perdió por un agujero que no cerraba: %v", poligonos)
	}
}

// EL HUECO LLEGA COMO HUECO, Y NO COMO UNA MANCHA ENCIMA. **Ésta es la prueba
// del sentido de giro**, y se hace leyendo de vuelta lo que se escribió.
//
// En MVT un agujero no se marca con ninguna etiqueta: se marca **dando la
// vuelta al anillo**. La especificación pide el de fuera en horario y los de
// dentro en antihorario, en coordenadas de tesela; con la Y hacia abajo eso es
// `orb.CCW` y `orb.CW` respectivamente. Si no se enderezan, el decodificador ve
// dos anillos que giran igual, los toma por DOS MANCHAS y pinta el bosque encima
// de la laguna. No salta ningún error y el fichero pesa lo mismo.
func TestElHuecoLlegaComoHuecoYNoComoManchaEncima(t *testing.T) {
	// Un bosque de ~2 km con una laguna dentro, los dos anillos girando en el
	// MISMO sentido a propósito: es como salen de `repartirAgujeros` y como
	// vienen de OSM, donde el sentido de giro no significa nada.
	bosque := orb.Ring{{-82.410, 23.090}, {-82.390, 23.090}, {-82.390, 23.110}, {-82.410, 23.110}, {-82.410, 23.090}}
	laguna := orb.Ring{{-82.404, 23.096}, {-82.396, 23.096}, {-82.396, 23.104}, {-82.404, 23.104}, {-82.404, 23.096}}
	if bosque.Orientation() != laguna.Orientation() {
		t.Fatal("la prueba no está probando lo que cree: los dos anillos ya vienen al revés")
	}
	conHueco := orb.Polygon{bosque, laguna}

	const z = uint8(12)
	rasgos := []Rasgo{{Geo: conHueco, Capa: capaSuelo, Clase: "bosque", Desde: 0, Caja: conHueco.Bound()}}
	datos, _, err := unaTesela(rasgos, []int{0},
		Nivel{NombresDesde: 9, Suelos: map[string]uint8{"bosque": 0}},
		z, uint32(aX(-82.400, z)), uint32(aY(23.100, z)))
	if err != nil {
		t.Fatal(err)
	}
	capas, err := mvt.UnmarshalGzipped(datos)
	if err != nil {
		t.Fatalf("lo que salió no es MVT: %v", err)
	}
	if len(capas) != 1 || len(capas[0].Features) != 1 {
		t.Fatalf("salieron %d capas con %v rasgos; se metió una mancha", len(capas), capas)
	}
	geo := capas[0].Features[0].Geometry
	p, esPoligono := geo.(orb.Polygon)
	if !esPoligono {
		t.Fatalf("la mancha con hueco volvió como %T y no como orb.Polygon. "+
			"El decodificador separa los anillos por su sentido de giro: si el de dentro "+
			"gira igual que el de fuera lo toma por OTRA MANCHA, y entonces el bosque "+
			"se pinta encima de la laguna en vez de dejar el hueco "+
			"(enderezarAnillos, en teselar.go)", geo)
	}
	if len(p) != 2 {
		t.Fatalf("la mancha volvió con %d anillos y se metió con dos: el contorno y su laguna", len(p))
	}
	if p[0].Orientation() != orb.CCW {
		t.Errorf("el anillo de fuera volvió girando al revés. La especificación MVT lo pide " +
			"horario en coordenadas de tesela, que con la Y hacia abajo es orb.CCW")
	}
	if p[1].Orientation() != orb.CW {
		t.Errorf("el agujero volvió girando igual que el contorno: eso NO es un agujero, " +
			"es una mancha encima. Es justo lo que se viene a arreglar")
	}
}

// Y EL SENTIDO DE GIRO VALE PARA TODOS LOS ZOOMS Y PARA LAS DEMÁS CAPAS, no
// sólo para la tesela que mira la prueba de arriba. Se comprueba con el mismo
// `mirarLosAnillos` que usa `-comprobar` antes de colgar un fichero.
func TestTodoLoQueSeRellenaSaleConSuSentidoDeGiro(t *testing.T) {
	bosque := orb.Polygon{
		{{-82.45, 23.05}, {-82.35, 23.05}, {-82.35, 23.15}, {-82.45, 23.15}, {-82.45, 23.05}},
		{{-82.43, 23.07}, {-82.37, 23.07}, {-82.37, 23.13}, {-82.43, 23.13}, {-82.43, 23.07}},
	}
	manzana := orb.Polygon{{{-82.401, 23.101}, {-82.399, 23.101}, {-82.399, 23.103}, {-82.401, 23.103}, {-82.401, 23.101}}}
	rasgos := []Rasgo{
		{Geo: bosque, Capa: capaSuelo, Clase: "bosque", Desde: 0, Caja: bosque.Bound()},
		{Geo: manzana, Capa: capaEdificio, Clase: claseEdificio, Desde: 0, Caja: manzana.Bound()},
	}
	nivel := Nivel{NombresDesde: 9,
		Suelos:    map[string]uint8{"bosque": 0},
		Edificios: map[string]uint8{claseEdificio: 0}}

	mirados := 0
	for z := uint8(6); z <= 15; z++ {
		datos, _, err := unaTesela(rasgos, []int{0, 1}, nivel, z,
			uint32(aX(-82.400, z)), uint32(aY(23.100, z)))
		if err != nil {
			t.Fatal(err)
		}
		if len(datos) == 0 {
			continue
		}
		capas, err := mvt.UnmarshalGzipped(datos)
		if err != nil {
			t.Fatalf("z%d: lo que salió no es MVT: %v", z, err)
		}
		for _, capa := range capas {
			for _, rasgo := range capa.Features {
				if _, err := mirarLosAnillos(rasgo.Geometry); err != nil {
					t.Errorf("z%d capa %q: %v", z, capa.Name, err)
				}
				mirados++
			}
		}
	}
	if mirados == 0 {
		t.Fatal("no se miró ni un anillo: la prueba está mirando teselas vacías")
	}
}

// UNA RELACIÓN SE CLASIFICA EXACTAMENTE IGUAL QUE UNA VÍA, con la misma tabla.
// Dos tablas acabarían diciendo cosas distintas sin que nadie se entere.
func TestUnaRelacionSeClasificaConLaMismaTablaQueUnaVia(t *testing.T) {
	nivel := Niveles[1] // el completo
	etiquetas := func(pares ...string) osm.Tags {
		var t osm.Tags
		for i := 0; i+1 < len(pares); i += 2 {
			t = append(t, osm.Tag{Key: pares[i], Value: pares[i+1]})
		}
		return t
	}
	casos := []struct {
		por   string
		tags  osm.Tags
		capa  string
		clase string
	}{
		{"la Ciénaga de Zapata", etiquetas("natural", "wetland"), capaSuelo, "humedal"},
		{"un humedal a la vieja usanza", etiquetas("natural", "marsh"), capaSuelo, "humedal"},
		{"un bosque grande", etiquetas("landuse", "forest"), capaSuelo, "bosque"},
		{"un embalse", etiquetas("landuse", "reservoir"), capaAgua, "agua"},
		{"una laguna", etiquetas("natural", "water"), capaAgua, "agua"},
	}
	for _, c := range casos {
		capa, clase, _, _, sirve := enQueCapaCae(c.tags, nivel, map[string]int{})
		if !sirve || capa != c.capa || clase != c.clase {
			t.Errorf("%s: dio %q/%q (sirve=%v); se esperaba %q/%q",
				c.por, capa, clase, sirve, c.capa, c.clase)
			continue
		}
		if !esDeRelleno(capa) {
			t.Errorf("%s: cayó en la capa %q, que no se pinta rellena. Una relación es un ÁREA: "+
				"dibujada como línea pinta una telaraña", c.por, capa)
		}
	}
}

// EL HUMEDAL ES CLASE PROPIA Y LA LLEVAN LOS TRES NIVELES. Estaba fuera con el
// motivo escrito en `niveles.go` —«casi todos están mapeados como relación, y
// las relaciones no entran»— y ese motivo se acabó. Si la clase existiera en la
// tabla de OSM pero no en la de un nivel, la Ciénaga de Zapata seguiría sin
// salir y el fichero no diría nada.
func TestElHumedalEntraEnLosTresNiveles(t *testing.T) {
	if clasesDeSuelo["natural=wetland"] != "humedal" {
		t.Fatalf("natural=wetland da la clase %q: la Ciénaga de Zapata es un wetland",
			clasesDeSuelo["natural=wetland"])
	}
	for _, n := range Niveles {
		if _, entra := n.Suelos["humedal"]; !entra {
			t.Errorf("el nivel %q no lleva humedal: es la mancha más grande de Cuba "+
				"y es lo que Jose echó de menos comparando su teléfono con la web", n.Clave)
		}
	}
}

// LA MISMA MANCHA NO SE PINTA DOS VECES, pero **sólo si la relación llegó a
// dibujarse**. Quitar la vía de una relación rota deja un hueco donde había una
// mancha, que es peor que unos bytes de más.
func TestLaViaQueYaDibujaSuRelacionSeQuitaSoloSiLaRelacionSeCosio(t *testing.T) {
	nuevo := func() *Extraido {
		return &Extraido{Descartes: map[string]int{}, Rasgos: []Rasgo{
			{Capa: capaSuelo, Clase: "bosque"}, // 0: la vía de la relación cosida
			{Capa: capaSuelo, Clase: "bosque"}, // 1: la vía de la relación rota
			{Capa: capaCarretera, Clase: "calle"},
		}}
	}
	tapadas := []tapada{{Rasgo: 0, Plan: 0}, {Rasgo: 1, Plan: 1}}

	s := nuevo()
	quitarLasTapadas(s, tapadas, []bool{true, false})
	if len(s.Rasgos) != 2 {
		t.Fatalf("quedaron %d rasgos; tenía que irse sólo el de la relación cosida", len(s.Rasgos))
	}
	if s.Descartes[fueraYaEnUnaRel] != 1 {
		t.Errorf("se quitó sin contarlo, o con otro motivo: %v", s.Descartes)
	}

	// Y si no se cosió ninguna, no se quita nada NI SE APUNTA UN CERO: un
	// motivo que sale siempre con un 0 al lado deja de leerse.
	s = nuevo()
	quitarLasTapadas(s, tapadas, []bool{false, false})
	if len(s.Rasgos) != 3 {
		t.Errorf("se quitaron vías de relaciones que no se cosieron: quedan %d de 3", len(s.Rasgos))
	}
	if _, hay := s.Descartes[fueraYaEnUnaRel]; hay {
		t.Errorf("se apuntó el motivo sin haber quitado nada: %v", s.Descartes)
	}
}

// EL MARGEN DE RECORTE DE LAS MANCHAS ES LA OTRA DECISIÓN DE TAMAÑO, la del
// 21/09/2026 por la tarde.
//
// `orb` recorta por defecto de -4096 a 8191: **una tesela de margen por cada
// lado, un cuadrado de 3×3**. Para una línea hace falta —una carretera cortada
// justo en el borde deja una costura blanca entre dos teselas—, pero una mancha
// no tiene grosor y ese margen es pagar nueve veces por un contorno que nadie
// pinta. Mientras las manchas fueron manzanas y parques no se notó: caben
// enteras en una tesela. Un bosque cosido de una relación cruza cientos, y ahí
// se vio: la capa `suelo` del `completo` pasaba de 11,4 a 34,4 MB, y con el
// recorte ajustado se queda en 15,4. **Son 21,3 MB del `completo` y 38 del
// `detallado`, que es lo que hace que quepa por debajo del techo.**
//
// Bajar este número no rompe nada y no avisa de nada; subirlo tampoco, y
// devuelve el fichero por encima del techo. Por eso está aquí y no sólo en un
// comentario: un comentario no falla.
func TestElMargenDeLasManchasEsLaDecisionDeTamano(t *testing.T) {
	manchas := recorteDe(capaSuelo)
	lineas := recorteDe(capaCarretera)

	if !(manchas.Max[0]-manchas.Min[0] < lineas.Max[0]-lineas.Min[0]) {
		t.Errorf("las manchas se recortan hasta %v, igual o más lejos que las líneas (%v). "+
			"Con el margen que trae orb por defecto cada tesela se lleva el contorno de sus "+
			"ocho vecinas: son 21,3 MB de más en el completo y 38 en el detallado", manchas, lineas)
	}
	// Pero margen TIENE que haber: la simplificación puede mover un punto hasta
	// `tolerancia` unidades, y si ese punto se mete hacia dentro de la tesela
	// aparece una raya del color del papel entre dos manchas que se tocan.
	margen := -manchas.Min[0]
	masFloja := 0.0
	for z := uint8(0); z <= 15; z++ {
		if tolerancia(z) > masFloja {
			masFloja = tolerancia(z)
		}
	}
	if margen < masFloja {
		t.Errorf("el margen de las manchas es %v y la simplificación puede mover un punto %v: "+
			"un borde que se meta hacia dentro deja una costura del color del papel entre "+
			"dos teselas", margen, masFloja)
	}
	// Y las líneas se quedan con el suyo, que es el que evita la costura de una
	// carretera cortada justo en el borde.
	if lineas != mvt.MapboxGLDefaultExtentBound {
		t.Errorf("las líneas se recortan hasta %v y no hasta el margen de orb (%v): "+
			"una carretera cortada en el borde se dibuja con su grosor y deja costura",
			lineas, mvt.MapboxGLDefaultExtentBound)
	}
	// La costa es línea, no mancha, aunque separe mar de tierra.
	if recorteDe(capaCosta) != lineas || recorteDe(capaTren) != lineas {
		t.Errorf("la costa o el tren se están recortando como manchas y son líneas")
	}
}

// UN AGUJERO APLASTADO NO VIAJA, y no es una limpieza de adorno.
//
// Al proyectar a la tesela las coordenadas se redondean a enteros: una isla más
// pequeña que una unidad de tesela se queda en una raya sin área. Eso ocupa,
// no pinta nada y —lo que importa— **no se puede enderezar**: una raya no gira
// ni para un lado ni para el otro, así que un fichero con rayas dentro no se
// puede comprobar de verdad. Lo encontró `-comprobar` sobre el `.pbf` de Cuba:
// 1.879 de los 11.832 anillos de dentro del `basico`.
func TestUnAgujeroAplastadoNoViaja(t *testing.T) {
	fuera := orb.Ring{{0, 0}, {1000, 0}, {1000, 1000}, {0, 1000}, {0, 0}}
	aplastado := orb.Ring{{100, 100}, {140, 100}, {100, 100}, {100, 100}}
	deVerdad := orb.Ring{{500, 500}, {600, 500}, {600, 600}, {500, 600}, {500, 500}}

	p := enderezarPoligono(orb.Polygon{fuera, aplastado, deVerdad})
	if len(p) != 2 {
		t.Fatalf("quedaron %d anillos; tenían que quedar el contorno y el agujero de verdad, "+
			"y irse el aplastado: %v", len(p), p)
	}
	if p[0].Orientation() != orb.CCW {
		t.Errorf("el contorno no se enderezó")
	}
	if p[1].Orientation() != orb.CW {
		t.Errorf("el agujero que sí tiene área no se enderezó, o se tiró el que no tocaba")
	}
	// Y lo que sale de aquí tiene que pasar la comprobación dura de -comprobar,
	// que es la que se le pasa a un fichero antes de colgarlo.
	if _, err := mirarLosAnillos(p); err != nil {
		t.Errorf("lo que salió de enderezarPoligono no pasa -comprobar: %v", err)
	}
}
