// LEER DE VUELTA LO QUE SE ESCRIBIO.
//
// Un generador que solo escribe no se puede comprobar: el fichero sale, pesa lo
// que sea, y si la curva de Hilbert esta al reves o un varint se escribio de mas
// **no se entera nadie hasta que el mapa sale en blanco en el telefono de un
// repartidor**. Por eso el mismo programa lo abre:
//
//	go run ./herramientas/mapa-cuba -comprobar cuba-completo.pmtiles
//
// Y por eso el lector vive aqui y no solo en Dart: el de Dart
// (`app/lib/mapa/pmtiles.dart`) tiene que dar exactamente lo mismo sobre el
// mismo fichero, y esa comparacion es la unica prueba que vale de los dos.
package main

import (
	"bytes"
	"compress/gzip"
	"encoding/binary"
	"fmt"
	"io"
	"os"

	"github.com/paulmach/orb/encoding/mvt"
)

// Cabecera es lo que dice el fichero de si mismo.
type Cabecera struct {
	RaizDesde, RaizLargo   uint64
	MetaDesde, MetaLargo   uint64
	HojasDesde, HojasLargo uint64
	DatosDesde, DatosLargo uint64
	Direcciones            uint64
	Entradas               uint64
	Contenidos             uint64
	ZMin, ZMax             uint8
	Caja                   Caja
}

// LeerCabecera comprueba la magia y saca los 127 bytes. **No se fia de nada**:
// un fichero a medio bajar tiene los primeros bytes buenos y el resto no.
func LeerCabecera(r io.ReaderAt) (*Cabecera, error) {
	b := make([]byte, 127)
	if _, err := r.ReadAt(b, 0); err != nil {
		return nil, fmt.Errorf("no se pudieron leer los 127 bytes de cabecera: %w", err)
	}
	if !bytes.Equal(b[:7], []byte("PMTiles")) {
		return nil, fmt.Errorf("esto no es un .pmtiles: empieza por %q", b[:7])
	}
	if b[7] != 3 {
		return nil, fmt.Errorf("versión %d de PMTiles; sólo se lee la 3", b[7])
	}
	if b[97] != compresionGzip || b[98] != compresionGzip {
		return nil, fmt.Errorf("compresión %d/%d; este lector sólo entiende gzip (2)", b[97], b[98])
	}
	if b[99] != tipoMVT {
		return nil, fmt.Errorf("tipo de tesela %d; se esperaba MVT (1)", b[99])
	}
	u := func(pos int) uint64 { return binary.LittleEndian.Uint64(b[pos:]) }
	g := func(pos int) float64 {
		return float64(int32(binary.LittleEndian.Uint32(b[pos:]))) / 1e7
	}
	return &Cabecera{
		RaizDesde: u(8), RaizLargo: u(16),
		MetaDesde: u(24), MetaLargo: u(32),
		HojasDesde: u(40), HojasLargo: u(48),
		DatosDesde: u(56), DatosLargo: u(64),
		Direcciones: u(72), Entradas: u(80), Contenidos: u(88),
		ZMin: b[100], ZMax: b[101],
		Caja: Caja{MinLon: g(102), MinLat: g(106), MaxLon: g(110), MaxLat: g(114)},
	}, nil
}

func descomprimir(datos []byte) ([]byte, error) {
	zr, err := gzip.NewReader(bytes.NewReader(datos))
	if err != nil {
		return nil, err
	}
	defer zr.Close()
	return io.ReadAll(zr)
}

// leerDirectorio deshace `serializarDirectorio`.
func leerDirectorio(crudo []byte) ([]entrada, error) {
	datos, err := descomprimir(crudo)
	if err != nil {
		return nil, fmt.Errorf("el directorio no es gzip: %w", err)
	}
	b := bytes.NewReader(datos)
	n, err := binary.ReadUvarint(b)
	if err != nil {
		return nil, err
	}
	if n > 1<<24 {
		// Un numero absurdo aqui es un fichero corrupto, no un fichero grande.
		// Sin este techo, `make` con ese numero tumba el proceso.
		return nil, fmt.Errorf("el directorio dice tener %d entradas", n)
	}
	es := make([]entrada, n)
	var ultimo uint64
	for i := range es {
		d, err := binary.ReadUvarint(b)
		if err != nil {
			return nil, err
		}
		ultimo += d
		es[i].ID = ultimo
	}
	for i := range es {
		v, err := binary.ReadUvarint(b)
		if err != nil {
			return nil, err
		}
		es[i].Repetida = uint32(v)
	}
	for i := range es {
		v, err := binary.ReadUvarint(b)
		if err != nil {
			return nil, err
		}
		es[i].Largo = uint32(v)
	}
	for i := range es {
		v, err := binary.ReadUvarint(b)
		if err != nil {
			return nil, err
		}
		if v == 0 && i > 0 {
			es[i].Desde = es[i-1].Desde + uint64(es[i-1].Largo)
		} else {
			es[i].Desde = v - 1
		}
	}
	return es, nil
}

// Comprobar abre un `.pmtiles` y cuenta lo que hay dentro, decodificando de
// verdad una tesela de cada nivel. Devuelve un resumen legible.
func Comprobar(ruta string) (string, error) {
	f, err := os.Open(ruta)
	if err != nil {
		return "", err
	}
	defer f.Close()

	c, err := LeerCabecera(f)
	if err != nil {
		return "", err
	}

	leer := func(desde, largo uint64) ([]byte, error) {
		b := make([]byte, largo)
		_, err := f.ReadAt(b, int64(desde))
		return b, err
	}

	raizCruda, err := leer(c.RaizDesde, c.RaizLargo)
	if err != nil {
		return "", err
	}
	raiz, err := leerDirectorio(raizCruda)
	if err != nil {
		return "", err
	}

	// Se recorren raiz y hojas y se juntan TODAS las entradas de tesela.
	var todas []entrada
	for _, e := range raiz {
		if e.Repetida != 0 {
			todas = append(todas, e)
			continue
		}
		hojaCruda, err := leer(c.HojasDesde+e.Desde, uint64(e.Largo))
		if err != nil {
			return "", err
		}
		hoja, err := leerDirectorio(hojaCruda)
		if err != nil {
			return "", fmt.Errorf("hoja en %d: %w", e.Desde, err)
		}
		todas = append(todas, hoja...)
	}

	if uint64(len(todas)) != c.Entradas {
		return "", fmt.Errorf(
			"la cabecera anuncia %d entradas y los directorios dan %d: el fichero no cuadra consigo mismo",
			c.Entradas, len(todas))
	}

	// Una tesela de cada nivel, decodificada de verdad. Contar entradas no
	// comprueba nada: un directorio perfecto puede apuntar a bytes que no son
	// una tesela.
	porZoom := map[uint8]int{}
	muestra := map[uint8]string{}
	for _, e := range todas {
		z := nivelDe(e.ID)
		porZoom[z]++
		if _, ya := muestra[z]; ya {
			continue
		}
		crudo, err := leer(c.DatosDesde+e.Desde, uint64(e.Largo))
		if err != nil {
			return "", err
		}
		capas, err := mvt.UnmarshalGzipped(crudo)
		if err != nil {
			return "", fmt.Errorf("la tesela de id %d (z%d) no es MVT: %w", e.ID, z, err)
		}
		resumen := ""
		for _, capa := range capas {
			resumen += fmt.Sprintf(" %s=%d", capa.Name, len(capa.Features))
		}
		if resumen == "" {
			return "", fmt.Errorf("la tesela de id %d (z%d) no trae ni una capa", e.ID, z)
		}
		muestra[z] = resumen
	}

	meta, err := leer(c.MetaDesde, c.MetaLargo)
	if err != nil {
		return "", err
	}
	metaJSON, err := descomprimir(meta)
	if err != nil {
		return "", err
	}
	if !bytes.Contains(metaJSON, []byte("OpenStreetMap")) {
		// LA ATRIBUCION NO ES ADORNO: la licencia la exige, también sin
		// conexión. Un paquete sin ella no se cuelga.
		return "", fmt.Errorf("los metadatos no llevan la atribución de OpenStreetMap")
	}

	salida := fmt.Sprintf("%s\n  z%d–z%d · %.4f,%.4f → %.4f,%.4f\n  %d entradas · %d contenidos distintos · %d direcciones\n",
		ruta, c.ZMin, c.ZMax, c.Caja.MinLon, c.Caja.MinLat, c.Caja.MaxLon, c.Caja.MaxLat,
		c.Entradas, c.Contenidos, c.Direcciones)
	for z := c.ZMin; z <= c.ZMax; z++ {
		if porZoom[z] == 0 {
			continue
		}
		salida += fmt.Sprintf("  z%-2d %7d teselas · una de ellas:%s\n", z, porZoom[z], muestra[z])
	}
	return salida, nil
}

// nivelDe deshace el desplazamiento por nivel del identificador.
func nivelDe(id uint64) uint8 {
	for z := uint8(0); z < 32; z++ {
		acumulado := (uint64(1)<<(2*uint64(z)) - 1) / 3
		siguiente := (uint64(1)<<(2*uint64(z+1)) - 1) / 3
		if id >= acumulado && id < siguiente {
			return z
		}
	}
	return 0
}

// TeselaDe saca la tesela `z/x/y` de un fichero ya abierto, o `nil` si no está.
// Es el camino que recorre el aparato, escrito aqui para poder compararlo con el
// de Dart sobre el mismo fichero.
func TeselaDe(f io.ReaderAt, c *Cabecera, z uint8, x, y uint32) ([]byte, error) {
	buscado := idDeTesela(z, x, y)
	desde, largo := c.RaizDesde, c.RaizLargo
	for vuelta := 0; vuelta < 4; vuelta++ {
		crudo := make([]byte, largo)
		if _, err := f.ReadAt(crudo, int64(desde)); err != nil {
			return nil, err
		}
		es, err := leerDirectorio(crudo)
		if err != nil {
			return nil, err
		}
		e, hay := buscarEntrada(es, buscado)
		if !hay {
			return nil, nil
		}
		if e.Repetida != 0 {
			tesela := make([]byte, e.Largo)
			if _, err := f.ReadAt(tesela, int64(c.DatosDesde+e.Desde)); err != nil {
				return nil, err
			}
			return tesela, nil
		}
		desde, largo = c.HojasDesde+e.Desde, uint64(e.Largo)
	}
	return nil, fmt.Errorf("más de cuatro saltos de directorio buscando %d/%d/%d", z, x, y)
}

// buscarEntrada hace la busqueda binaria del formato: la ultima entrada con
// `ID <= buscado`. No es «la que tenga ese id exacto», y esa diferencia es la
// que permite que una entrada de hoja cubra un rango.
func buscarEntrada(es []entrada, buscado uint64) (entrada, bool) {
	lo, hi := 0, len(es)-1
	for lo <= hi {
		medio := (lo + hi) / 2
		switch {
		case es[medio].ID > buscado:
			hi = medio - 1
		case es[medio].ID < buscado:
			lo = medio + 1
		default:
			return es[medio], true
		}
	}
	if hi < 0 {
		return entrada{}, false
	}
	e := es[hi]
	if e.Repetida == 0 {
		return e, true // una hoja: cubre todo lo que venga detras
	}
	if e.Repetida > 0 && buscado-e.ID < uint64(e.Repetida) {
		return e, true
	}
	return entrada{}, false
}
