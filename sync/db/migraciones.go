// LAS MIGRACIONES QUE ESTE BINARIO ESPERA, incrustadas en el ejecutable.
//
// La gemela de `api/db/migraciones.go`, y por la misma razón: el 17/09/2026 se desplegó
// código que daba por aplicada una migración que no lo estaba, y el servicio arrancó tan
// tranquilo. Aquí duele igual o más — el sincronizador es lo único que tienen los aparatos
// sin señal para volver a estar al día, y si falla no hay ninguna pantalla que lo diga.
//
// Está copiado y no compartido porque `api/` y `sync/` son dos módulos de Go distintos y no
// se ven el uno al otro. Si un día se toca uno, hay que tocar el otro: lo vigila
// `db/migraciones_test.go` en cada lado.
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

// Migracion es un fichero de goose: su número y su nombre.
type Migracion struct {
	Version int64
	Nombre  string
}

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

// deNombre saca el número de `00001_sync.sql`. Un nombre que no cuadre es un ERROR y no un
// fichero que se salta en silencio: saltárselo daría por buena una base incompleta.
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

// Faltan devuelve las que el binario espera y la base todavía no tiene. Pura para poder
// probarla sin un Postgres delante. Sólo mira hacia atrás: una base más adelantada que el
// binario es lo que pasa al volver a una imagen anterior, y ahí hace falta que levante.
func Faltan(esperadas []Migracion, enLaBase int64) []Migracion {
	var salida []Migracion
	for _, m := range esperadas {
		if m.Version > enLaBase {
			salida = append(salida, m)
		}
	}
	return salida
}
