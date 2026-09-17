// EL CONTENEDOR: PMTiles v3, escrito a mano.
//
// POR QUE A MANO Y NO UNA BIBLIOTECA: el formato entero cabe en este fichero
// —una cabecera de 127 bytes y unos directorios de varints— y a cambio el
// generador no arrastra ninguna dependencia mas. La razon de peso, sin embargo,
// es otra: **el lector de Dart lo escribimos nosotros** (`app/lib/mapa/`), y
// tener el escritor delante, en el mismo repositorio, es lo unico que permite
// probar los dos contra el mismo fichero.
//
// El formato es el publico (github.com/protomaps/PMTiles, spec v3), no uno
// nuestro: un `.pmtiles` que salga de aqui se abre con `pmtiles show`, con
// protomaps.js y con cualquier herramienta de las de siempre, y al reves —un
// fichero que salga de `tippecanoe --output=x.pmtiles`— lo lee la aplicacion
// sin tocar nada. Esa es la puerta de salida si un dia este generador se queda
// corto.
//
// Lo que NO hace este escritor, a proposito:
//
//   - no escribe teselas vacias. Cuba es una isla en una caja que es casi toda
//     mar: contar el mar como tesela es lo que convierte 113.000 teselas de
//     tierra en 492.000 de caja.
//   - no repite un contenido identico. Dos teselas con los mismos bytes
//     comparten sitio (`num_tile_contents` < `num_tile_entries`).
package main

import (
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/binary"
	"fmt"
	"io"
	"math"
	"os"
	"sort"
)

// Los enumerados del formato, con nombre para no sembrar numeros sueltos.
const (
	compresionGzip = 2 // internal_compression y tile_compression
	tipoMVT        = 1 // tile_type
)

// idDeTesela traduce `z/x/y` al identificador de PMTiles: el desplazamiento del
// nivel mas la posicion en la **curva de Hilbert** de ese nivel.
//
// Por que Hilbert y no fila a fila: la curva mantiene juntos en el fichero los
// vecinos en el mapa, y asi un directorio cubre una zona en vez de una tira.
// Eso es lo que permite leer por rangos sin bajarse el fichero entero — que hoy
// no hace falta porque se baja entero, pero es la puerta que deja abierta.
func idDeTesela(z uint8, x, y uint32) uint64 {
	if z > 31 {
		panic("zoom fuera de rango")
	}
	acumulado := (uint64(1)<<(2*uint64(z)) - 1) / 3
	var rx, ry uint32
	var d uint64
	for s := uint32(1) << z / 2; s > 0; s /= 2 {
		rx, ry = 0, 0
		if x&s > 0 {
			rx = 1
		}
		if y&s > 0 {
			ry = 1
		}
		d += uint64(s) * uint64(s) * uint64((3*rx)^ry)
		// La rotacion del cuadrante, que es lo que hace que la curva sea
		// continua. Copiada letra a letra de la especificacion: cambiar el
		// orden de estas cuatro lineas da una curva que tambien "funciona" y
		// que ningun otro lector entiende.
		if ry == 0 {
			if rx == 1 {
				x = s - 1 - x
				y = s - 1 - y
			}
			x, y = y, x
		}
	}
	return acumulado + d
}

// entrada es una fila de directorio.
type entrada struct {
	ID       uint64
	Desde    uint64 // desplazamiento dentro del bloque de datos (o de las hojas)
	Largo    uint32
	Repetida uint32 // 1 en una tesela; 0 significa «esto apunta a un directorio hoja»
}

// serializarDirectorio escribe las entradas tal y como manda la especificacion:
// cuatro tiras de varints —ids delta, repeticiones, largos, desplazamientos— y
// no una tira de estructuras. Agrupar por columna es lo que hace que gzip
// encuentre algo que comprimir.
func serializarDirectorio(entradas []entrada) []byte {
	var b bytes.Buffer
	var tmp [binary.MaxVarintLen64]byte
	poner := func(v uint64) {
		n := binary.PutUvarint(tmp[:], v)
		b.Write(tmp[:n])
	}

	poner(uint64(len(entradas)))
	var ultimo uint64
	for _, e := range entradas {
		poner(e.ID - ultimo)
		ultimo = e.ID
	}
	for _, e := range entradas {
		poner(uint64(e.Repetida))
	}
	for _, e := range entradas {
		poner(uint64(e.Largo))
	}
	for i, e := range entradas {
		// `0` no es un desplazamiento: significa «va pegada a la anterior».
		// Cualquier otro valor va sumado uno, para dejar el cero libre.
		if i > 0 && e.Desde == entradas[i-1].Desde+uint64(entradas[i-1].Largo) {
			poner(0)
		} else {
			poner(e.Desde + 1)
		}
	}
	return b.Bytes()
}

func comprimir(datos []byte) []byte {
	var b bytes.Buffer
	w, _ := gzip.NewWriterLevel(&b, gzip.BestCompression)
	_, _ = w.Write(datos)
	_ = w.Close()
	return b.Bytes()
}

// El techo del directorio raiz, de la especificacion. No es un capricho: es lo
// que cabe en una peticion de rango de las que hace un navegador.
const techoDelDirectorioRaiz = 16384

// armarDirectorios parte las entradas en un directorio raiz y, si no caben, en
// hojas. Se prueba primero con todo en la raiz y se va doblando el tamano de
// hoja hasta que la raiz cabe: es el mismo procedimiento de la implementacion
// de referencia, y da ficheros que otras herramientas leen igual.
func armarDirectorios(entradas []entrada) (raiz, hojas []byte, cuantasHojas int) {
	if len(entradas) < techoDelDirectorioRaiz {
		if r := comprimir(serializarDirectorio(entradas)); len(r) <= techoDelDirectorioRaiz {
			return r, nil, 0
		}
	}
	porHoja := 4096
	for {
		var conHojas bytes.Buffer
		var deRaiz []entrada
		for i := 0; i < len(entradas); i += porHoja {
			hasta := min(i+porHoja, len(entradas))
			bloque := comprimir(serializarDirectorio(entradas[i:hasta]))
			deRaiz = append(deRaiz, entrada{
				ID:    entradas[i].ID,
				Desde: uint64(conHojas.Len()),
				Largo: uint32(len(bloque)),
				// `Repetida = 0` es LA marca de «esto es una hoja». Ponerle 1
				// haria que un lector devolviera el directorio como si fuera
				// una tesela, y eso se ve como un mapa en blanco, no como un
				// error.
				Repetida: 0,
			})
			conHojas.Write(bloque)
		}
		r := comprimir(serializarDirectorio(deRaiz))
		if len(r) <= techoDelDirectorioRaiz {
			return r, conHojas.Bytes(), len(deRaiz)
		}
		porHoja *= 2
	}
}

// Caja es el recuadro que se anuncia en la cabecera. Sale de lo que de verdad
// se metio, no de una constante: si un dia se genera solo una provincia, el
// fichero lo dice.
type Caja struct {
	MinLon, MinLat, MaxLon, MaxLat float64
}

// Escritor junta teselas y al final las vuelca. Las teselas NO se guardan en
// memoria: se escriben segun llegan a un fichero temporal de datos, y solo se
// guarda la entrada. Con 88 MB de teselas, guardarlas todas en RAM y volcarlas
// al final es la diferencia entre generar en un portatil y no generar.
type Escritor struct {
	datos       *os.File
	desde       uint64
	entradas    []entrada
	yaEstaban   map[[32]byte]entrada // dedup por contenido
	direcciones uint64               // num_addressed_tiles
}

func NuevoEscritor(temporal string) (*Escritor, error) {
	f, err := os.Create(temporal)
	if err != nil {
		return nil, err
	}
	return &Escritor{datos: f, yaEstaban: map[[32]byte]entrada{}}, nil
}

// Anadir mete la tesela `z/x/y` con su contenido YA comprimido.
func (e *Escritor) Anadir(z uint8, x, y uint32, contenido []byte) error {
	if len(contenido) == 0 {
		return nil // una tesela vacia no se escribe: ver la cabecera del fichero
	}
	e.direcciones++
	huella := sha256.Sum256(contenido)
	if vieja, hay := e.yaEstaban[huella]; hay {
		e.entradas = append(e.entradas, entrada{
			ID: idDeTesela(z, x, y), Desde: vieja.Desde, Largo: vieja.Largo, Repetida: 1,
		})
		return nil
	}
	if _, err := e.datos.Write(contenido); err != nil {
		return err
	}
	nueva := entrada{ID: idDeTesela(z, x, y), Desde: e.desde, Largo: uint32(len(contenido)), Repetida: 1}
	e.desde += uint64(len(contenido))
	e.yaEstaban[huella] = nueva
	e.entradas = append(e.entradas, nueva)
	return nil
}

// Cerrar vuelca el `.pmtiles` completo.
func (e *Escritor) Cerrar(salida string, metadatos []byte, zMin, zMax uint8, caja Caja) error {
	defer func() {
		nombre := e.datos.Name()
		_ = e.datos.Close()
		_ = os.Remove(nombre)
	}()
	if _, err := e.datos.Seek(0, io.SeekStart); err != nil {
		return err
	}

	sort.Slice(e.entradas, func(i, j int) bool { return e.entradas[i].ID < e.entradas[j].ID })
	raiz, hojas, _ := armarDirectorios(e.entradas)
	meta := comprimir(metadatos)

	f, err := os.Create(salida)
	if err != nil {
		return err
	}
	defer f.Close()

	const cabecera = 127
	desdeRaiz := uint64(cabecera)
	desdeMeta := desdeRaiz + uint64(len(raiz))
	desdeHojas := desdeMeta + uint64(len(meta))
	desdeDatos := desdeHojas + uint64(len(hojas))

	h := make([]byte, cabecera)
	copy(h, "PMTiles")
	h[7] = 3
	u64 := func(pos int, v uint64) { binary.LittleEndian.PutUint64(h[pos:], v) }
	i32 := func(pos int, v float64) {
		binary.LittleEndian.PutUint32(h[pos:], uint32(int32(math.Round(v*1e7))))
	}
	u64(8, desdeRaiz)
	u64(16, uint64(len(raiz)))
	u64(24, desdeMeta)
	u64(32, uint64(len(meta)))
	u64(40, desdeHojas)
	u64(48, uint64(len(hojas)))
	u64(56, desdeDatos)
	u64(64, e.desde)
	u64(72, e.direcciones)
	u64(80, uint64(len(e.entradas)))
	u64(88, uint64(len(e.yaEstaban)))
	// `clustered = 0`, y es la verdad, no una omision: las teselas se vuelcan en
	// el orden en que se generan —por filas— y no en el de la curva de Hilbert,
	// y ademas dos iguales comparten sitio. Poner `1` aqui le diria a un lector
	// que puede suponer desplazamientos crecientes, y es justo lo que no puede
	// suponer.
	h[96] = 0
	h[97] = compresionGzip
	h[98] = compresionGzip
	h[99] = tipoMVT
	h[100] = zMin
	h[101] = zMax
	i32(102, caja.MinLon)
	i32(106, caja.MinLat)
	i32(110, caja.MaxLon)
	i32(114, caja.MaxLat)
	h[118] = zMin
	i32(119, (caja.MinLon+caja.MaxLon)/2)
	i32(123, (caja.MinLat+caja.MaxLat)/2)

	for _, trozo := range [][]byte{h, raiz, meta, hojas} {
		if _, err := f.Write(trozo); err != nil {
			return err
		}
	}
	if _, err := io.Copy(f, e.datos); err != nil {
		return fmt.Errorf("volcando las teselas: %w", err)
	}
	return nil
}
