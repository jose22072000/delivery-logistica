package cotizar

// EL ALMACÉN DE ORIGEN SE ELIGE DOS VECES, Y TIENE QUE SALIR EL MISMO.
//
// Aquí (`ElegirAlmacen`) y en el aparato (`AlmacenDeReferencia.elegir`,
// `app/lib/nucleo/almacenes/almacen_de_referencia.dart`), porque la ruta se arma también en
// el patio del almacén sin señal. Si los dos no eligen EXACTAMENTE el mismo almacén no
// falla nada: sale un kilometraje en la web y otro en el teléfono, los dos creíbles, y de
// esos km sale lo que se le cobra al cliente.
//
// Pasó, y es lo que arregló el 24/09/2026: este lado no filtraba `activo` y el otro sí, así
// que en una sucursal con el almacén principal dado de baja —con coordenadas buenas— el
// mismo botón «Armar la ruta de esta zona» medía desde dos sitios distintos. Había dos
// pruebas verdes afirmando lo contrario la una de la otra, y ninguna las comparaba.
//
// POR QUÉ UN FICHERO COMPARTIDO Y NO UNA TABLA AQUÍ (CLAUDE.md §3-bis): una tabla escrita
// aquí sólo comprueba que este lado hace lo que esta prueba cree; se puede cambiar la regla
// en los dos sitios de ESTE fichero y salir verde con el aparato ya separado. El fichero es
// el MISMO —`docs/almacen-de-origen.casos.json`, no una copia— y lo leen las pruebas de los
// dos lenguajes: cambiar la regla en un solo lado pone en rojo la prueba del otro.
//
// Precedente idéntico: `internal/api/orden_de_paradas_test.go` con
// `docs/orden-de-paradas.casos.json`.

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// rutaDeLosCasosDeAlmacen: el MISMO fichero que lee la prueba del aparato. Una copia se
// desincroniza y entonces las dos pruebas salen verdes diciendo cosas distintas, que es
// justo el fallo que esto cierra.
const rutaDeLosCasosDeAlmacen = "../../../docs/almacen-de-origen.casos.json"

type almacenDeCaso struct {
	ID        string   `json:"id"`
	Nombre    string   `json:"nombre"`
	Principal bool     `json:"principal"`
	Activo    bool     `json:"activo"`
	Lat       *float64 `json:"lat"`
	Lng       *float64 `json:"lng"`
}

type casoDeAlmacen struct {
	Nombre    string          `json:"nombre"`
	Nota      string          `json:"nota"`
	Almacenes []almacenDeCaso `json:"almacenes"`
	Elegido   *string         `json:"elegido"`
}

type ficheroDeCasosDeAlmacen struct {
	Casos []casoDeAlmacen `json:"casos"`
}

func TestElAlmacenDeOrigenEsElMismoQueEnElAparato(t *testing.T) {
	crudo, err := os.ReadFile(filepath.Clean(rutaDeLosCasosDeAlmacen))
	if err != nil {
		t.Fatalf(
			"no se pudo leer %s: %v\n"+
				"  Sin ese fichero no hay NADA que ate este lado con el aparato: los dos vuelven a\n"+
				"  poder elegir almacenes distintos sin que salte nada, y de ese almacén sale el\n"+
				"  kilometraje que se cobra.\n"+
				"  Si esto salta dentro de una imagen, es que al Dockerfile le falta\n"+
				"  `COPY docs/almacen-de-origen.casos.json /docs/almacen-de-origen.casos.json`\n"+
				"  (ver deploy/Dockerfile.api, que ya lo hace con docs/orden-de-paradas.casos.json).",
			rutaDeLosCasosDeAlmacen, err,
		)
	}

	var doc ficheroDeCasosDeAlmacen
	if err := json.Unmarshal(crudo, &doc); err != nil {
		t.Fatalf("%s no se entiende: %v", rutaDeLosCasosDeAlmacen, err)
	}
	if len(doc.Casos) == 0 {
		t.Fatalf("%s no trae ni un caso: una prueba sin casos no prueba nada", rutaDeLosCasosDeAlmacen)
	}

	// Los casos que son EL motivo de que esto exista. Si alguien los quita del fichero, el
	// contrato se queda sin la parte que costó dinero, y eso también tiene que ponerse rojo.
	imprescindibles := map[string]bool{
		"EL CASO DE JOSE: el principal dado de baja con coordenadas buenas": false,
		"el único que hay está de baja":                                     false,
		"el (0,0) no cuenta, aunque sea el principal":                       false,
		"sin principal manda el NOMBRE, no el orden de la lista":            false,
	}

	for _, c := range doc.Casos {
		if _, hay := imprescindibles[c.Nombre]; hay {
			imprescindibles[c.Nombre] = true
		}

		t.Run(c.Nombre, func(t *testing.T) {
			salio := ElegirAlmacen(deLosCasos(c.Almacenes))

			switch {
			case c.Elegido == nil && salio != nil:
				t.Fatalf(
					"«%s»: se eligió %q (%s) y no tendría que servir ninguno.\n"+
						"  %s\n"+
						"  El aparato contesta «no hay desde donde medir» para estos mismos datos, así que\n"+
						"  aquí sale un importe y allí un cartel: el mismo domicilio, dos respuestas.\n"+
						"  Si el cambio es a propósito hay que cambiar %s, ESTE lado Y\n"+
						"  app/lib/nucleo/almacenes/almacen_de_referencia.dart a la vez.",
					c.Nombre, salio.ID, salio.Nombre, c.Nota, rutaDeLosCasosDeAlmacen,
				)
			case c.Elegido != nil && salio == nil:
				t.Fatalf(
					"«%s»: no se eligió ninguno y tenía que salir %q.\n"+
						"  %s\n"+
						"  Esto es un 409 «<Sucursal> no tiene ningún almacén con coordenadas» en la web\n"+
						"  sobre una sucursal a la que el teléfono sí le arma la ruta.\n"+
						"  Si el cambio es a propósito hay que cambiar %s, ESTE lado Y\n"+
						"  app/lib/nucleo/almacenes/almacen_de_referencia.dart a la vez.",
					c.Nombre, *c.Elegido, c.Nota, rutaDeLosCasosDeAlmacen,
				)
			case c.Elegido != nil && salio.ID != *c.Elegido:
				t.Fatalf(
					"«%s»: se midió desde %q (%s) y el aparato mide desde %q.\n"+
						"  %s\n"+
						"  Dos orígenes son DOS KILOMETRAJES para el mismo botón, los dos creíbles, y de\n"+
						"  esos km sale el cobro. No falla nada y no lo enseña ninguna pantalla.\n"+
						"  Si el cambio es a propósito hay que cambiar %s, ESTE lado Y\n"+
						"  app/lib/nucleo/almacenes/almacen_de_referencia.dart a la vez.",
					c.Nombre, salio.ID, salio.Nombre, *c.Elegido, c.Nota, rutaDeLosCasosDeAlmacen,
				)
			}
		})
	}

	for nombre, estaba := range imprescindibles {
		if !estaba {
			t.Errorf(
				"el caso «%s» ya no está en %s.\n"+
					"  Es uno de los que separaban el servidor del aparato el 24/09/2026: quitarlo deja\n"+
					"  el contrato verde y sin vigilar justo por donde se rompió.",
				nombre, rutaDeLosCasosDeAlmacen,
			)
		}
	}
}

func deLosCasos(filas []almacenDeCaso) []Almacen {
	salida := make([]Almacen, 0, len(filas))
	for _, f := range filas {
		salida = append(salida, Almacen{
			ID: f.ID, Nombre: f.Nombre,
			Latitud: f.Lat, Longitud: f.Lng,
			Principal: f.Principal, Activo: f.Activo,
		})
	}
	return salida
}
