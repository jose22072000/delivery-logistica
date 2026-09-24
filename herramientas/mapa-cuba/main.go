// mapa-cuba — genera el paquete de mapa que la APK y el escritorio se guardan
// para trabajar sin conexion.
//
//	go run ./herramientas/mapa-cuba -pbf cuba-latest.osm.pbf -nivel completo -salida .
//
// De donde sale el `.pbf`, que sale de aqui y como se cuelga: todo escrito en
// `docs/mapa-sin-conexion.md`. **Este programa no sube nada a ningun sitio** y
// no habla con el VPS: escribe un fichero y dice cuanto pesa y cual es su
// `sha256`, que es exactamente lo que hay que ponerle a la api.
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// LaAtribucion viaja DENTRO del fichero, no solo en la pantalla.
//
// La licencia de OpenStreetMap la exige en cuanto se ensena el mapa, tambien sin
// conexion. Metida en los metadatos del paquete, va con el fichero a donde vaya
// y no se puede perder por el camino aunque alguien cambie la pantalla.
const LaAtribucion = "© OpenStreetMap contributors (ODbL)"

func main() {
	pbf := flag.String("pbf", "", "el .osm.pbf de Geofabrik")
	comprobar := flag.String("comprobar", "", "abrir un .pmtiles ya hecho y decir qué tiene dentro")
	clave := flag.String("nivel", "", "qué nivel generar; vacío los genera todos")
	salida := flag.String("salida", ".", "carpeta donde dejar los .pmtiles")
	// SOLO para sacar la muestra con la que prueba el lector de Dart. No se usa
	// para generar lo que se cuelga: un paquete recortado por arriba deja al
	// chofer sin acercamiento justo donde hace falta.
	zmax := flag.Int("zmax", 0, "recortar el zoom máximo (sólo para sacar muestras de prueba)")
	// Tambien solo para la muestra: en produccion los nombres no viajan por
	// debajo del z9 porque no se pueden leer, y entonces una muestra recortada a
	// z6 sale sin un solo nombre y no sirve para probar que el UTF-8 se lee bien.
	nombresDesde := flag.Int("nombres-desde", -1, "desde qué zoom viajan los nombres (sólo para muestras)")
	// SOLO para medir. El tamano del fichero es la decision de este generador y
	// una decision no se toma con una estimacion: se genera con la capa y sin
	// ella, y se restan los bytes. Ver `Nivel.SinCapas`.
	sin := flag.String("sin", "", "capas a dejar fuera, separadas por comas (sólo para medir el tamaño)")
	// Lo mismo, para la otra decision de tamano del 21/09/2026: los
	// multipoligonos (los bosques grandes, los humedales y la Cienaga de
	// Zapata). Se genera con ellos y sin ellos y se restan los bytes.
	sinRelaciones := flag.Bool("sin-relaciones", false, "dejar fuera los multipolígonos (sólo para medir el tamaño)")
	// La costa del MUNDO, para que alejar el mapa no se acabe en papel blanco
	// (mundo.go). Es `ne_10m_land.geojson` de Natural Earth, dominio publico.
	// **Va en todo lo que se cuelgue**: sin el, el fichero sale con
	// `-sin-mundo` en el nombre para que no se confunda nunca con uno bueno.
	mundo := flag.String("mundo", "", "ne_10m_land.geojson de Natural Earth: la costa del mundo hasta z"+fmt.Sprint(CorteDelMundo))
	flag.Parse()

	if *comprobar != "" {
		resumen, err := Comprobar(*comprobar)
		if err != nil {
			// NO se dice «comprobado» de un fichero que no se pudo abrir. Es el
			// mismo fallo que un «Todo en verde» antes de comprobar nada.
			fmt.Fprintf(os.Stderr, "%s NO vale: %v\n", *comprobar, err)
			os.Exit(1)
		}
		fmt.Print(resumen)
		return
	}

	if *pbf == "" {
		fmt.Fprintln(os.Stderr, "falta -pbf. Ver docs/mapa-sin-conexion.md")
		os.Exit(2)
	}

	quiere := Niveles
	if *clave != "" {
		n, hay := NivelPorClave(*clave)
		if !hay {
			fmt.Fprintf(os.Stderr, "no hay ningún nivel %q\n", *clave)
			os.Exit(2)
		}
		quiere = []Nivel{n}
	}

	for _, nivel := range quiere {
		if *zmax > 0 {
			nivel.ZoomMax = uint8(*zmax)
			nivel.Clave += fmt.Sprintf("-hasta-z%d", *zmax)
		}
		if *nombresDesde >= 0 {
			nivel.NombresDesde = uint8(*nombresDesde)
		}
		if *sinRelaciones {
			nivel.SinRelaciones = true
			nivel.Clave += "-sin-relaciones"
		}
		if *mundo == "" {
			// SE DICE, Y SE DICE EN EL NOMBRE DEL FICHERO. Un paquete sin la
			// costa del mundo se abre igual, pesa un poco menos y sale bien en
			// `-comprobar`: lo unico que cambia es que al alejar vuelve el
			// papel en blanco, y eso no se ve hasta el telefono de un
			// repartidor. Es la misma regla que `-sin` y `-sin-relaciones`.
			nivel.Clave += "-sin-mundo"
		}
		if *sin != "" {
			nivel = nivel.SinCapas(strings.Split(*sin, ","))
			// El nombre del fichero lo dice, porque un `.pmtiles` medido no es
			// uno que se cuelgue y los dos acaban en la misma carpeta.
			nivel.Clave += "-sin-" + strings.ReplaceAll(*sin, ",", "-")
		}
		if err := generar(*pbf, *mundo, nivel, *salida); err != nil {
			fmt.Fprintf(os.Stderr, "nivel %s: %v\n", nivel.Clave, err)
			os.Exit(1)
		}
	}
}

func generar(pbf, mundo string, nivel Nivel, carpeta string) error {
	arranque := time.Now()
	fmt.Printf("\n══ %s — %s (hasta z%d)\n", nivel.Clave, nivel.Titulo, nivel.ZoomMax)

	f, err := os.Open(pbf)
	if err != nil {
		return err
	}
	defer f.Close()

	// LA COSTA DEL MUNDO SE LEE ANTES QUE EL `.pbf`, y no es por gusto: encender
	// el mundo mueve la costa de OSM de z0 a z7, asi que el nivel tiene que
	// llegar ya ajustado a `Extraer`. Las dos cosas salen de la MISMA llamada
	// para que no puedan quedar a medias (ver `ConLaCostaDelMundo`).
	descartesDelMundo := map[string]int{}
	var crudoDelMundo []byte
	if mundo != "" {
		crudoDelMundo, err = os.ReadFile(mundo)
		if err != nil {
			return fmt.Errorf("leyendo la costa del mundo: %w", err)
		}
	}
	nivel, rasgosDelMundo, err := ConLaCostaDelMundo(crudoDelMundo, nivel, descartesDelMundo)
	if err != nil {
		return err
	}
	if nivel.ConMundo {
		fmt.Printf("  mundo · %d anillos de costa de Natural Earth, z0–z%d\n",
			len(rasgosDelMundo), CorteDelMundo)
	} else {
		fmt.Println("  mundo · NO (al alejar se acaba el mar donde se acaba Cuba) — falta -mundo")
	}

	extraido, err := Extraer(f, nivel)
	if err != nil {
		return err
	}
	for motivo, cuantos := range descartesDelMundo {
		extraido.Descartes[motivo] += cuantos
	}
	for _, r := range rasgosDelMundo {
		extraido.Caja = extraido.Caja.Union(r.Caja)
	}
	extraido.Rasgos = append(extraido.Rasgos, rasgosDelMundo...)
	fmt.Printf("  %d rasgos · recuadro %.4f,%.4f → %.4f,%.4f\n",
		len(extraido.Rasgos),
		extraido.Caja.Min[0], extraido.Caja.Min[1], extraido.Caja.Max[0], extraido.Caja.Max[1])
	// LO QUE SE QUEDO FUERA SE DICE, con su numero y su motivo. Un descarte en
	// silencio es el fallo que mas caro sale en esta casa.
	for motivo, cuantos := range extraido.Descartes {
		fmt.Printf("    fuera · %-45s %8d\n", motivo, cuantos)
	}

	temporal := filepath.Join(carpeta, "."+nivel.Clave+".teselas")
	escritor, err := NuevoEscritor(temporal)
	if err != nil {
		return err
	}

	cuenta, err := Teselar(escritor, extraido.Rasgos, nivel, func(s string) { fmt.Println(s) })
	if err != nil {
		return err
	}

	destino := filepath.Join(carpeta, "cuba-"+nivel.Clave+".pmtiles")
	if err := escritor.Cerrar(destino, metadatos(nivel), 0, nivel.ZoomMax, cajaDe(extraido.Caja)); err != nil {
		return err
	}

	info, err := os.Stat(destino)
	if err != nil {
		return err
	}
	huella, err := huellaDe(destino)
	if err != nil {
		return err
	}

	fmt.Printf("\n  %s\n", destino)
	fmt.Printf("  bytes   %d  (%.1f MB)\n", info.Size(), float64(info.Size())/1e6)
	fmt.Printf("  sha256  %s\n", huella)
	fmt.Printf("  teselas %d · rasgos dibujados %d · en %s\n",
		cuenta.Teselas, cuenta.Rasgos, time.Since(arranque).Round(time.Second))
	return nil
}

func huellaDe(ruta string) (string, error) {
	f, err := os.Open(ruta)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// metadatos es el bloque JSON que va dentro del `.pmtiles`. Sigue el formato de
// TileJSON que esperan las herramientas de siempre, para que el fichero se pueda
// abrir con `pmtiles show` sin saber nada de este proyecto.
func metadatos(n Nivel) []byte {
	capas := []map[string]any{
		{"id": capaCarretera, "description": "vías por las que pasa un camión",
			"fields": map[string]string{"clase": "String", "nombre": "String"}},
		{"id": capaCosta, "description": "la línea del mar",
			"fields": map[string]string{"clase": "String"}},
		{"id": capaAgua, "description": "embalses, lagunas y ríos anchos",
			"fields": map[string]string{"clase": "String", "nombre": "String"}},
		{"id": capaPoblacion, "description": "núcleos de población con su nombre",
			"fields": map[string]string{"clase": "String", "nombre": "String"}},
		{"id": capaSuelo, "description": "uso del suelo: parque, bosque, humedal, hierba, urbano, industrial, portuario",
			"fields": map[string]string{"clase": "String"}},
		{"id": capaEdificio, "description": "la silueta de las manzanas",
			"fields": map[string]string{"clase": "String"}},
		{"id": capaTren, "description": "vías de tren",
			"fields": map[string]string{"clase": "String"}},
	}
	// SOLO SE ANUNCIAN LAS QUE ESTE NIVEL LLEVA DE VERDAD. Un `vector_layers`
	// que promete edificios en el `basico` hace que quien abra el fichero con
	// `pmtiles show` crea que el paquete esta roto en vez de ver que ese nivel
	// no los trae. Es el mismo fallo que un contador que no cuadra con su lista.
	lleva := map[string]bool{
		capaCarretera: len(n.Carreteras) > 0,
		capaCosta:     true,
		capaAgua:      true,
		capaPoblacion: len(n.Poblaciones) > 0,
		capaSuelo:     len(n.Suelos) > 0,
		capaEdificio:  len(n.Edificios) > 0,
		capaTren:      len(n.Trenes) > 0,
	}
	vivas := capas[:0]
	for _, c := range capas {
		if lleva[c["id"].(string)] {
			vivas = append(vivas, c)
		}
	}
	capas = vivas
	// LA ATRIBUCION DE LOS DOS ORIGENES. La de OSM es obligatoria (ODbL) y la
	// de Natural Earth no lo es —es dominio publico— pero se pone igual: un
	// paquete que no dice de donde salen sus datos no se puede auditar desde
	// fuera. Y `mundo` no es adorno: es lo que permite ver desde el propio
	// fichero si al alejar habra mar o papel.
	atribucion := LaAtribucion
	mundo := any(false)
	if n.ConMundo {
		atribucion += " · " + AtribucionDelMundo
		mundo = map[string]any{"origen": AtribucionDelMundo, "hasta_zoom": CorteDelMundo}
	}
	b, _ := json.Marshal(map[string]any{
		"name":          "Cuba — " + n.Titulo,
		"description":   n.Explicacion,
		"attribution":   atribucion,
		"mundo":         mundo,
		"type":          "baselayer",
		"format":        "pbf",
		"nivel":         n.Clave,
		"generado":      time.Now().UTC().Format(time.RFC3339),
		"vector_layers": capas,
	})
	return b
}
