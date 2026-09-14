package cotizar

import "testing"

// `${lat.toFixed(5)}, ${lng.toFixed(5)}` — cinco decimales, coma Y ESPACIO. Es lo que se
// enseña cuando la geocodificación inversa no devuelve dirección; si el formato se mueve,
// la pantalla enseña dos cosas distintas para la misma coordenada.
func TestFormatCoords(t *testing.T) {
	casos := []struct {
		nombre   string
		lat, lng float64
		esperado string
	}{
		{"La Habana", 23.1136, -82.3666, "23.11360, -82.36660"},
		{"cero, cero", 0, 0, "0.00000, 0.00000"},
		{"se corta en el quinto decimal", 20.024699999, -75.82190001, "20.02470, -75.82190"},
		{"un negativo diminuto se enseña como -0", -0.000001, 180, "-0.00000, 180.00000"},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			if got := FormatCoords(c.lat, c.lng); got != c.esperado {
				t.Fatalf("%q, se esperaba %q", got, c.esperado)
			}
		})
	}
}

// `round(13 − log2(√área))`, acotado a [8, 16]. Área mayor, zoom menor.
func TestZoomDesdeArea(t *testing.T) {
	casos := []struct {
		nombre   string
		area     float64
		esperado float64
	}{
		// CASO LÍMITE: el `a = área > 0 ? área : 1` protege el logaritmo. Sin él, una
		// sucursal con el área sin poner daría −Infinity y el mapa saldría en blanco.
		{"área cero se trata como 1", 0, 13},
		{"área negativa se trata como 1", -5, 13},
		{"un kilómetro cuadrado", 1, 13},
		{"cuatro", 4, 12},
		{"dieciséis", 16, 11},
		{"cien", 100, 10},
		{"sesenta y cuatro", 64, 10},
		{"dos y medio", 2.5, 12},
		{"mil: toca el suelo de 8", 1000, 8},
		{"diez mil: sigue en 8", 10000, 8},
		{"un millón: sigue en 8", 1e6, 8},
		{"una centésima: toca el techo de 16", 0.01, 16},
		{"una diezmilésima: sigue en 16", 0.0001, 16},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			if got := ZoomDesdeArea(c.area); got != c.esperado {
				t.Fatalf("ZoomDesdeArea(%v) = %v, se esperaba %v", c.area, got, c.esperado)
			}
		})
	}
}

// Lo que alguien pega en la caja de la dirección. El recorte por rango es lo que separa
// una coordenada pegada de un número de teléfono pegado por error.
func TestParsearCoordenadas(t *testing.T) {
	casos := []struct {
		nombre   string
		texto    string
		lat, lng float64
		nulo     bool
	}{
		{"coma y espacio", "-23.5505, -46.6333", -23.5505, -46.6333, false},
		{"sólo un espacio", "23.55 -46.63", 23.55, -46.63, false},
		{"punto y coma", "20;-75", 20, -75, false},
		{"con espacios de sobra alrededor", "  20.5 , -75.5  ", 20.5, -75.5, false},
		{"sin separador de miles ni nada raro", "20.5,-75.5", 20.5, -75.5, false},
		// Los bordes del mundo SÍ valen.
		{"el borde de abajo", "-90,-180", -90, -180, false},
		{"el borde de arriba", "90,180", 90, 180, false},
		// Fuera del mundo, no.
		{"latitud de 91", "91,0", 0, 0, true},
		{"longitud de 200", "20,200", 0, 0, true},
		// Máximo TRES dígitos enteros: por eso "1000" no casa siquiera el regex.
		{"cuatro dígitos enteros no casan", "1000,20", 0, 0, true},
		{"texto suelto", "abc", 0, 0, true},
		{"un solo número", "20", 0, 0, true},
		{"separador sin segundo número", "20,", 0, 0, true},
		{"tres números", "20,-75,3", 0, 0, true},
		{"vacío", "", 0, 0, true},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			got := ParsearCoordenadas(c.texto)
			if c.nulo {
				if got != nil {
					t.Fatalf("se esperaba nil, salió %+v", *got)
				}
				return
			}
			if got == nil {
				t.Fatalf("salió nil, se esperaba {%v %v}", c.lat, c.lng)
			}
			if got.Lat != c.lat || got.Lng != c.lng {
				t.Fatalf("salió {%v %v}, se esperaba {%v %v}", got.Lat, got.Lng, c.lat, c.lng)
			}
		})
	}
}
