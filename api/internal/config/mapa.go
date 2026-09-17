// EL ANUNCIO DEL PAQUETE DE MAPA, que es el hermano de `leerPublicada`.
//
// Es exactamente el mismo problema que el anuncio de versión de la aplicación
// (`docs/actualizaciones.md`), y por eso se parece letra a letra:
//
//   - el servidor NO sirve el fichero, sólo dice dónde está y cuánto pesa;
//   - **a medias no arranca**: una URL sin versión no se anunciaría nunca, y una
//     versión sin URL avisaría sin decir de dónde bajarla;
//   - vacío es el estado seguro: mientras no haya un `.pmtiles` colgado de
//     verdad, no se anuncia nada y ningún aparato ofrece descargar nada.
//
// LA DIFERENCIA con `Publicada` es que aquí hay **varios niveles de detalle** y
// la lista no está cerrada en el código. Jose los pidió así: «si quieres uno más
// detallado pues uno más detallado, pero el necesario son tantos». Los niveles
// se DESCUBREN del entorno, y por una razón concreta: una lista cerrada aquí
// obliga a desplegar la api para publicar un nivel nuevo, y —peor— una errata
// (`MAPA_COMPLTO_URL`) se ignoraría en silencio. Descubriéndolos, la errata
// aparece en la pantalla del logístico como un nivel llamado «complto», que es
// feo y **se ve**, en vez de un nivel que falta y no se ve.
package config

import (
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
)

// PaqueteDeMapa es un nivel de detalle colgado para descargar.
type PaqueteDeMapa struct {
	// Nivel es la clave: `basico`, `completo`, `detallado`. La misma que usa el
	// generador para nombrar el fichero, y la que el aparato guarda para saber
	// cuál tiene puesto.
	Nivel string
	// Version es la del ORIGEN de los datos, no la de la api ni la de la
	// aplicación: el sello del `.osm.pbf` del que salió (`260916`).
	Version string
	// Fecha, normalizada a RFC3339. Opcional.
	Fecha string
	// Bytes es lo que pesa, y se dice ANTES de bajar nada. Nadie baja 26 MB sin
	// saber que son 26 MB, y menos con los datos de Cuba.
	Bytes int64
	// SHA256 es lo que separa «bajado» de «bajado entero». No es adorno: una
	// descarga que se corta al 60 % y se da por buena es el fallo de los 2.000
	// clientes otra vez (`CLAUDE.md` §3).
	SHA256 string
	URL    string
}

// Mapa es todo lo anunciado, de menor a mayor tamaño.
type Mapa struct {
	Paquetes []PaqueteDeMapa
}

// HayAlguno dice si se anunció algo.
func (m *Mapa) HayAlguno() bool { return m != nil && len(m.Paquetes) > 0 }

// sufijos es lo que se busca en el entorno para descubrir un nivel.
var sufijosDeMapa = []string{"URL", "BYTES", "SHA256"}

// leerMapa arma el anuncio, o devuelve nil si no se anunció ninguno.
func leerMapa() (*Mapa, []error) {
	version := valor("MAPA_VERSION", "")
	crudaFecha := valor("MAPA_FECHA", "")

	// Qué niveles se nombraron en el entorno, con qué trozos de cada uno.
	trozos := map[string]map[string]string{}
	for _, linea := range os.Environ() {
		nombre, v, _ := strings.Cut(linea, "=")
		if !strings.HasPrefix(nombre, "MAPA_") {
			continue
		}
		for _, sufijo := range sufijosDeMapa {
			if !strings.HasSuffix(nombre, "_"+sufijo) {
				continue
			}
			clave := strings.ToLower(strings.TrimSuffix(strings.TrimPrefix(nombre, "MAPA_"), "_"+sufijo))
			if clave == "" {
				continue
			}
			if v = strings.TrimSpace(v); v == "" {
				// Vacía cuenta como no puesta: es como las deja `docker-compose`
				// cuando no hay nada en el `.env`, y tratarlas como puestas
				// haría que el servicio no arrancase nunca sin configurar el
				// mapa.
				continue
			}
			if trozos[clave] == nil {
				trozos[clave] = map[string]string{}
			}
			trozos[clave][sufijo] = v
		}
	}

	if len(trozos) == 0 {
		if version != "" || crudaFecha != "" {
			return nil, []error{errors.New(
				"MAPA_VERSION (o MAPA_FECHA) está puesta pero no hay ni un MAPA_<NIVEL>_URL: " +
					"se anunciaría que hay mapa sin decir de dónde bajarlo")}
		}
		// Nada anunciado, que es lo normal hasta que haya un .pmtiles colgado.
		return nil, nil
	}

	var errs []error
	if version == "" {
		nombres := make([]string, 0, len(trozos))
		for clave := range trozos {
			nombres = append(nombres, "MAPA_"+strings.ToUpper(clave)+"_*")
		}
		sort.Strings(nombres)
		errs = append(errs, fmt.Errorf(
			"%s está puesta pero MAPA_VERSION no: sin versión el aparato no puede saber si "+
				"lo que tiene guardado se quedó viejo, así que no se anunciaría nunca",
			strings.Join(nombres, ", ")))
	}

	fecha := ""
	if crudaFecha != "" {
		n, err := fechaDeMapa(crudaFecha)
		if err != nil {
			errs = append(errs, err)
		} else {
			fecha = n
		}
	}

	claves := make([]string, 0, len(trozos))
	for clave := range trozos {
		claves = append(claves, clave)
	}
	sort.Strings(claves)

	var paquetes []PaqueteDeMapa
	for _, clave := range claves {
		p, errsNivel := unPaquete(clave, trozos[clave], version, fecha)
		errs = append(errs, errsNivel...)
		if p != nil {
			paquetes = append(paquetes, *p)
		}
	}
	if len(errs) > 0 {
		return nil, errs
	}
	// De menor a mayor: es el orden en que se le ofrecen a la persona, y el que
	// hace que lo primero que vea sea lo más barato de bajar.
	sort.Slice(paquetes, func(i, j int) bool { return paquetes[i].Bytes < paquetes[j].Bytes })
	return &Mapa{Paquetes: paquetes}, nil
}

// unPaquete comprueba UN nivel. Las tres variables o ninguna: con dos de tres,
// el aparato o no sabe cuánto pesa (y lo baja a ciegas) o no puede comprobar que
// llegó entero (y se queda con medio fichero creyéndolo bueno).
func unPaquete(clave string, tiene map[string]string, version, fecha string) (*PaqueteDeMapa, []error) {
	prefijo := "MAPA_" + strings.ToUpper(clave) + "_"

	var faltan []string
	for _, sufijo := range sufijosDeMapa {
		if tiene[sufijo] == "" {
			faltan = append(faltan, prefijo+sufijo)
		}
	}
	if len(faltan) > 0 {
		return nil, []error{fmt.Errorf(
			"al nivel de mapa %q le falta %s: o están las tres (URL, BYTES y SHA256) o no está "+
				"ninguna — sin BYTES se baja a ciegas y sin SHA256 no hay forma de saber si "+
				"llegó entero", clave, strings.Join(faltan, " y "))}
	}

	var errs []error
	url := tiene["URL"]
	if !strings.HasPrefix(url, "http://") && !strings.HasPrefix(url, "https://") {
		errs = append(errs, fmt.Errorf(
			"%sURL vale %q: tiene que empezar por http:// o https://", prefijo, url))
	}

	bytes, err := strconv.ParseInt(tiene["BYTES"], 10, 64)
	switch {
	case err != nil:
		errs = append(errs, fmt.Errorf(
			"%sBYTES vale %q y no es un número: es lo que dice `ls -l` del .pmtiles",
			prefijo, tiene["BYTES"]))
	case bytes <= 0:
		errs = append(errs, fmt.Errorf("%sBYTES vale %d: tiene que ser mayor que cero", prefijo, bytes))
	}

	// EL SHA256 SE COMPRUEBA AQUÍ, y es la validación que más cara sale si falta.
	// Un hash con un carácter de menos hace que TODAS las descargas se rechacen,
	// para siempre, y desde fuera se ve como «el mapa no se descarga nunca» — que
	// no se parece en nada a un error de configuración.
	huella := strings.ToLower(strings.TrimSpace(tiene["SHA256"]))
	if len(huella) != 64 {
		errs = append(errs, fmt.Errorf(
			"%sSHA256 tiene %d caracteres y un sha256 son 64: lo imprime el generador y "+
				"también `sha256sum el-fichero.pmtiles`", prefijo, len(huella)))
	} else if _, err := hex.DecodeString(huella); err != nil {
		errs = append(errs, fmt.Errorf(
			"%sSHA256 vale %q y no es hexadecimal", prefijo, tiene["SHA256"]))
	}

	if len(errs) > 0 {
		return nil, errs
	}
	return &PaqueteDeMapa{
		Nivel: clave, Version: version, Fecha: fecha,
		Bytes: bytes, SHA256: huella, URL: url,
	}, nil
}

func fechaDeMapa(crudo string) (string, error) {
	for _, formato := range []string{time.RFC3339, "2006-01-02"} {
		if t, err := time.Parse(formato, crudo); err == nil {
			return t.UTC().Format(time.RFC3339), nil
		}
	}
	return "", fmt.Errorf(
		"MAPA_FECHA vale %q: se espera 2026-09-16 o 2026-09-16T00:00:00Z (es la fecha del "+
			".osm.pbf del que salió el paquete)", crudo)
}
