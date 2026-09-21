// LAS MIGRACIONES QUE ESTE BINARIO ESPERA.
//
// Van incrustadas en el ejecutable a propósito: lo que hay que comparar no es «qué
// ficheros hay en el disco del servidor» —ahí puede haber cualquier cosa, o nada, porque
// la imagen de la API no lleva la carpeta de migraciones— sino **qué esquema da por
// supuesto el código que se acaba de desplegar**.
//
// De qué se protege esto, con nombre y fecha: el 17/09/2026 la migración 00006 pasó un día
// entero sin aplicarse con el código que la necesitaba ya desplegado. El fallo tiene una
// forma que engaña y por eso nadie lo vio: la bajada por diferencias contesta 500, pero la
// carga inicial contesta 200. O sea que **una instalación nueva funciona** —quien pruebe
// con un teléfono recién instalado lo ve todo bien— y **todo aparato que ya está en la
// calle se queda congelado para siempre**. La web ni se entera, porque su base nace vacía
// en cada carga y siempre pide carga inicial: todo verde en el navegador con la flota
// parada.
//
// Por eso la API se NIEGA a arrancar con la base atrasada. Un contenedor que no levanta se
// ve en el despliegue, en el minuto uno, y lo ve quien está desplegando. Un 500 en la
// bajada de un teléfono que está a 400 km no lo ve nadie.
package db

import (
	"embed"
	"fmt"
	"path"
	"sort"
	"strconv"
	"strings"
)

//go:embed migrations/*.sql
var ficheros embed.FS

// Esperadas devuelve las migraciones que este binario da por aplicadas, de la más vieja a
// la más nueva.
func Esperadas() ([]Migracion, error) {
	entradas, err := ficheros.ReadDir("migrations")
	if err != nil {
		return nil, fmt.Errorf("no se pudieron leer las migraciones incrustadas: %w", err)
	}
	salida := make([]Migracion, 0, len(entradas))
	for _, e := range entradas {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".sql") {
			continue
		}
		m, err := deNombre(e.Name())
		if err != nil {
			return nil, err
		}
		salida = append(salida, m)
	}
	sort.Slice(salida, func(i, j int) bool { return salida[i].Version < salida[j].Version })
	return salida, nil
}

// Migracion es un fichero de goose: su número y su nombre.
type Migracion struct {
	Version int64
	Nombre  string
}

// deNombre saca el número de `00006_bajas_de_la_bajada.sql`.
//
// Un nombre que no cuadre es un ERROR y no un fichero que se salta en silencio: saltárselo
// haría que la comprobación diera por buena una base a la que le falta justo esa.
func deNombre(nombre string) (Migracion, error) {
	base := path.Base(nombre)
	corte := strings.IndexByte(base, '_')
	if corte <= 0 {
		return Migracion{}, fmt.Errorf("migración con nombre raro, no se puede comprobar: %q", base)
	}
	version, err := strconv.ParseInt(base[:corte], 10, 64)
	if err != nil {
		return Migracion{}, fmt.Errorf("migración con nombre raro, no se puede comprobar: %q", base)
	}
	return Migracion{Version: version, Nombre: base}, nil
}

// Faltan devuelve las migraciones que el binario espera y la base todavía no tiene.
//
// **Aparte y pura para poder probarla**: es la cuenta que decide si un despliegue levanta
// o no, y no puede depender de que haya un Postgres delante.
//
// Sólo mira hacia atrás. Una base MÁS ADELANTADA que el binario no es un fallo que deba
// impedir arrancar: es lo que pasa al volver a una imagen anterior, y ahí lo que hace
// falta es que el servicio levante, no que se muera dos veces.
func Faltan(esperadas []Migracion, enLaBase int64) []Migracion {
	var salida []Migracion
	for _, m := range esperadas {
		if m.Version > enLaBase {
			salida = append(salida, m)
		}
	}
	return salida
}
