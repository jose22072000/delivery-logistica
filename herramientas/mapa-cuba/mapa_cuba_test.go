package main

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/paulmach/orb"
	"github.com/paulmach/orb/encoding/mvt"
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
