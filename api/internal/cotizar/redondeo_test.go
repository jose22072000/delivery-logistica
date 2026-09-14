package cotizar

import (
	"encoding/json"
	"math"
	"testing"
)

// Los esperados salen de correr `Math.round((v + Number.EPSILON) * 10^d) / 10^d` en Node.
// Aquí NO hay holgura: un redondeo que se separa en el último céntimo es exactamente el
// fallo que este fichero existe para impedir.
func TestRedondear(t *testing.T) {
	casos := []struct {
		nombre    string
		valor     float64
		decimales int
		esperado  float64
	}{
		// EL CASO QUE JUSTIFICA EL `+ Number.EPSILON`: 1.005 en binario es
		// 1.00499999999999989..., así que sin el epsilon el redondeo da 1.00.
		{"1.005 sube gracias al epsilon", 1.005, 2, 1.01},
		{"2.675 sube gracias al epsilon", 2.675, 2, 2.68},
		// …y el epsilon NO arrastra lo que de verdad está por debajo del medio.
		{"1.0049999 no llega al medio", 1.0049999, 2, 1},
		{"cero", 0, 2, 0},
		{"medio exacto sube", 0.5, 0, 1},
		{"uno y medio sube", 1.5, 0, 2},
		{"dos y medio sube (no es half-to-even)", 2.5, 0, 3},
		// Los negativos con medio exacto: el epsilon deshace el empate y Go coincide con
		// JavaScript. Aquí no hay importes negativos, pero queda fijado por si aparecen.
		{"menos medio", -0.5, 0, 0},
		{"menos uno y medio", -1.5, 0, -1},
		{"tres decimales de los que sólo informan", 12.3456789, 3, 12.346},
		{"tres decimales, medio exacto", 1.2345, 3, 1.235},
		{"por debajo de la milésima desaparece", 0.0001, 3, 0},
		{"negativo normal", -3.14159, 2, -3.14},
		{"un número diminuto es cero", 1e-20, 2, 0},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			got := Redondear(c.valor, c.decimales)
			// +0 y -0 son iguales con `==` y es lo que queremos: JavaScript devuelve -0
			// en `redondear(-0.5, 0)` y eso se enseña como "0".
			if got != c.esperado {
				t.Fatalf("Redondear(%v, %d) = %.17g, se esperaba %.17g", c.valor, c.decimales, got, c.esperado)
			}
		})
	}
}

func TestFinito(t *testing.T) {
	casos := []struct {
		nombre   string
		v        float64
		esperado bool
	}{
		{"cero es finito", 0, true},
		{"un número normal", 12.5, true},
		{"un negativo", -3, true},
		{"NaN no", math.NaN(), false},
		{"+Infinity no", math.Inf(1), false},
		{"-Infinity no", math.Inf(-1), false},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			if got := Finito(c.v); got != c.esperado {
				t.Fatalf("Finito(%v) = %v, se esperaba %v", c.v, got, c.esperado)
			}
		})
	}
}

// Number() de JavaScript, campo a campo. Es la tabla que decide qué cuerpos dan 400 y
// cuáles pasan; las rarezas de aquí (null -> 0) están copiadas a propósito.
func TestNumeroDesdeJSON(t *testing.T) {
	casos := []struct {
		nombre   string
		json     string // el cuerpo entero
		esperado float64
		esNaN    bool
	}{
		{"número", `{"v": 12.5}`, 12.5, false},
		{"cero", `{"v": 0}`, 0, false},
		{"negativo", `{"v": -75.8219}`, -75.8219, false},
		// Number(null) === 0, que es FINITO y por tanto pasa la validación de lat/lng.
		// Es una rareza de la de Next, no una mejora pendiente.
		{"null vale cero", `{"v": null}`, 0, false},
		{"cadena numérica", `{"v": "12.5"}`, 12.5, false},
		{"cadena vacía vale cero", `{"v": ""}`, 0, false},
		{"cadena con espacios vale cero", `{"v": "   "}`, 0, false},
		{"cadena no numérica es NaN", `{"v": "abc"}`, 0, true},
		{"true vale uno", `{"v": true}`, 1, false},
		{"false vale cero", `{"v": false}`, 0, false},
		{"un objeto es NaN", `{"v": {"a":1}}`, 0, true},
		{"notación científica", `{"v": 1e3}`, 1000, false},
		// EL CAMPO AUSENTE es el caso importante: tiene que quedar en NaN, no en 0, o un
		// `lat` que no viene pasaría la validación en vez de dar el 400.
		{"campo ausente es NaN", `{}`, 0, true},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			cuerpo := struct {
				V Numero `json:"v"`
			}{V: NoVino()} // así se leen los cuerpos: inicializados a «no vino»
			if err := json.Unmarshal([]byte(c.json), &cuerpo); err != nil {
				t.Fatalf("no debería fallar la decodificación: %v", err)
			}
			if c.esNaN {
				if !math.IsNaN(cuerpo.V.Valor) {
					t.Fatalf("se esperaba NaN, salió %v", cuerpo.V.Valor)
				}
				if cuerpo.V.Finito() {
					t.Fatalf("NaN no puede ser finito")
				}
				return
			}
			if cuerpo.V.Valor != c.esperado {
				t.Fatalf("%v, se esperaba %v", cuerpo.V.Valor, c.esperado)
			}
		})
	}
}

// `Number(x) || porDefecto`: el cero y el NaN son falsy, así que ceden al respaldo.
func TestNumeroO(t *testing.T) {
	casos := []struct {
		nombre     string
		n          Numero
		porDefecto float64
		esperado   float64
	}{
		{"un valor normal se queda", De(7), 1, 7},
		{"el cero cede (es falsy)", De(0), 1, 1},
		{"el cero cede a 0 también", De(0), 0, 0},
		{"NaN cede", NoVino(), 1, 1},
		{"un negativo NO cede: es truthy", De(-2), 1, -2},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			if got := c.n.O(c.porDefecto); got != c.esperado {
				t.Fatalf("%v, se esperaba %v", got, c.esperado)
			}
		})
	}
}
