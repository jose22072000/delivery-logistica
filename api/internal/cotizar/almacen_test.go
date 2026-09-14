package cotizar

import "testing"

func num(v float64) *float64 { return &v }

// La regla de selección del origen. Es de dónde sale la mercancía y por tanto de dónde se
// mide lo que se cobra: elegir mal el almacén cambia el importe de todos los domicilios de
// esa sucursal sin que nada falle.
func TestElegirAlmacen(t *testing.T) {
	conCoords := func(id string, principal bool) Almacen {
		return Almacen{ID: id, Nombre: id, Latitud: num(20.02), Longitud: num(-75.82), Principal: principal, Activo: true}
	}
	sinCoords := func(id string, principal bool) Almacen {
		return Almacen{ID: id, Nombre: id, Principal: principal, Activo: true}
	}

	casos := []struct {
		nombre    string
		almacenes []Almacen
		esperado  string // "" = nil
	}{
		// CASO LÍMITE: sin almacenes. nil, y quien llama contesta el 409. No se usan las
		// coordenadas de la sucursal como apaño: no son el sitio del que sale la carga.
		{"sin almacenes", nil, ""},
		{"lista vacía", []Almacen{}, ""},
		// CASO LÍMITE: hay almacenes pero ninguno tiene coordenadas.
		{"ninguno con coordenadas", []Almacen{sinCoords("A", true), sinCoords("B", false)}, ""},
		{"1) el principal con coordenadas gana", []Almacen{conCoords("A", false), conCoords("B", true)}, "B"},
		{"1) el primer principal con coordenadas, si hay dos", []Almacen{conCoords("A", true), conCoords("B", true)}, "A"},
		// El principal SIN coordenadas no sirve: se pasa al primero que las tenga.
		{"2) el principal sin coordenadas cede al primero que las tenga", []Almacen{sinCoords("P", true), conCoords("A", false), conCoords("B", false)}, "A"},
		{"2) ninguno principal: el primero con coordenadas", []Almacen{sinCoords("X", false), conCoords("A", false)}, "A"},
		// Media coordenada no es un punto: hace falta latitud Y longitud.
		{"media coordenada no cuenta", []Almacen{{ID: "M", Latitud: num(20), Principal: true}, conCoords("A", false)}, "A"},
		// `activo` NO filtra: la regla del pliego mira principal y coordenadas, nada más.
		// Filtrar por activo cambiaría el almacén elegido —y el importe— en las sucursales
		// que tienen uno dado de baja con coordenadas buenas.
		{"un almacén inactivo con coordenadas sigue sirviendo",
			[]Almacen{{ID: "I", Latitud: num(20), Longitud: num(-75), Principal: true, Activo: false}}, "I"},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			got := ElegirAlmacen(c.almacenes)
			if c.esperado == "" {
				if got != nil {
					t.Fatalf("se esperaba nil, salió %q", got.ID)
				}
				return
			}
			if got == nil {
				t.Fatalf("salió nil, se esperaba %q", c.esperado)
			}
			if got.ID != c.esperado {
				t.Fatalf("salió %q, se esperaba %q", got.ID, c.esperado)
			}
		})
	}
}
