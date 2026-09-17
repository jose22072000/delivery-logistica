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
		if err := generar(*pbf, nivel, *salida); err != nil {
			fmt.Fprintf(os.Stderr, "nivel %s: %v\n", nivel.Clave, err)
			os.Exit(1)
		}
	}
}

func generar(pbf string, nivel Nivel, carpeta string) error {
	arranque := time.Now()
	fmt.Printf("\n══ %s — %s (hasta z%d)\n", nivel.Clave, nivel.Titulo, nivel.ZoomMax)

	f, err := os.Open(pbf)
	if err != nil {
		return err
	}
	defer f.Close()

	extraido, err := Extraer(f, nivel)
	if err != nil {
		return err
	}
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
	}
	b, _ := json.Marshal(map[string]any{
		"name":          "Cuba — " + n.Titulo,
		"description":   n.Explicacion,
		"attribution":   LaAtribucion,
		"type":          "baselayer",
		"format":        "pbf",
		"nivel":         n.Clave,
		"generado":      time.Now().UTC().Format(time.RFC3339),
		"vector_layers": capas,
	})
	return b
}
