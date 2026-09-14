package cotizar

import (
	"encoding/json"
	"math"
	"strconv"
	"strings"
)

// Redondear es el `redondear(valor, decimales = 2)` de `domicilioEntrega.ts`:
//
//	Math.round((valor + Number.EPSILON) * 10^decimales) / 10^decimales
//
// SE COPIA TAL CUAL, con el `+ Number.EPSILON` incluido. El pliego lo pide literal
// (§7, «Constantes y helpers») y lo pide por algo: es el redondeo con el que Entrega
// calcula lo que cobra la APK. Un redondeo «mejor» aquí significa que el mismo reparto
// vale una cosa en el teléfono y otra en la pantalla del logístico.
//
// DIVERGENCIA CONOCIDA, anotada a propósito: `Math.round` de JavaScript rompe los empates
// hacia +∞ (`-0.5 → -0`), y `math.Round` de Go los rompe alejándose del cero (`-0.5 → -1`).
// El `+ EpsilonJS` deshace el empate en casi todos los casos reales —después de sumarlo ya
// no hay medio exacto—, así que las dos implementaciones coinciden. Sólo se separarían con
// un valor NEGATIVO cuyo `(v+ε)*10^d` cayera exactamente en .5, y aquí no hay importes
// negativos: la tarifa, la distancia y el peso son todos positivos.
func Redondear(valor float64, decimales int) float64 {
	f := math.Pow(10, float64(decimales))
	return math.Round((valor+EpsilonJS)*f) / f
}

// Redondear2 y Redondear3 son los dos únicos usos que hay (§7): 2 decimales para los
// importes que se cobran, 3 para los kilómetros y los kilos que sólo se INFORMAN.
//
// Los 3 decimales no entran en la cuenta: el `usd` se calcula con la distancia y el peso
// CRUDOS, y sólo después se redondean para enseñarlos. Redondear antes y multiplicar
// después da otro número.
func Redondear2(v float64) float64 { return Redondear(v, 2) }
func Redondear3(v float64) float64 { return Redondear(v, 3) }

// Finito es el `Number.isFinite(x)` de JavaScript: ni NaN ni ±Infinity.
func Finito(v float64) bool { return !math.IsNaN(v) && !math.IsInf(v, 0) }

// ---------------------------------------------------------------------------
// Number() de JavaScript
// ---------------------------------------------------------------------------

// Numero es un campo numérico leído con las reglas de `Number(...)` de JavaScript, que es
// como los lee la ruta de Next.
//
// POR QUÉ NO BASTA UN `*float64`: las validaciones del contrato son «`lat` o `lng` no
// finitos» y «`pesoKg` no finito o <= 0», y en JavaScript eso NO significa lo mismo para
// un campo ausente que para uno que llega en `null`:
//
//	ausente        Number(undefined) = NaN   -> NO finito  -> se rechaza
//	null           Number(null)      = 0     -> SÍ finito  -> PASA (y cotiza en lat 0)
//	""             Number("")        = 0     -> SÍ finito  -> PASA
//	"12.5"         Number("12.5")    = 12.5  -> pasa con su valor
//	"abc"          Number("abc")     = NaN   -> se rechaza
//	true / false   1 / 0
//
// Que un `lat: null` cotice desde el golfo de Guinea es una rareza de la de Next, no una
// mejora pendiente: se copia igual, porque el criterio es dar el MISMO número. Queda
// anotada para que quien la vea sepa que está puesta a mano y no por descuido.
type Numero struct {
	Valor float64 // NaN cuando el campo no vino o no se pudo convertir
}

// NoVino devuelve el Numero de un campo ausente: NaN, como `Number(undefined)`.
func NoVino() Numero { return Numero{Valor: math.NaN()} }

// De construye un Numero con un valor ya conocido. Para las pruebas y para quien ya tiene
// el float.
func De(v float64) Numero { return Numero{Valor: v} }

// Finito dice si el valor pasa el `Number.isFinite` del contrato.
func (n Numero) Finito() bool { return Finito(n.Valor) }

// Positivo es el `> 0` de las validaciones. NaN devuelve false, como en JavaScript.
func (n Numero) Positivo() bool { return n.Finito() && n.Valor > 0 }

// O devuelve el valor, o `porDefecto` cuando el valor es «falsy» en JavaScript (NaN o 0).
// Es el `Number(x) || 0` y el `quantity || 1` del pliego (§2.1).
func (n Numero) O(porDefecto float64) float64 {
	if math.IsNaN(n.Valor) || n.Valor == 0 {
		return porDefecto
	}
	return n.Valor
}

// UnmarshalJSON aplica las reglas de `Number(...)` al decodificar.
//
// El campo ausente NO pasa por aquí: el valor cero de `Numero` es `Valor = 0`, no NaN, así
// que los cuerpos se leen SIEMPRE con `NumerosNoVinieron` (o inicializando los campos con
// `NoVino()`) antes de decodificar. Sin eso, un `lat` que no viene se leería como 0 —que
// es finito— en vez de como NaN, y la petición pasaría la validación en lugar de dar el
// 400 del contrato.
func (n *Numero) UnmarshalJSON(b []byte) error {
	s := strings.TrimSpace(string(b))
	switch s {
	case "null": // Number(null) === 0
		n.Valor = 0
		return nil
	case "true":
		n.Valor = 1
		return nil
	case "false":
		n.Valor = 0
		return nil
	}
	// Cadena: Number("12.5") = 12.5, Number("") = 0, Number("abc") = NaN.
	if len(s) > 0 && s[0] == '"' {
		var texto string
		if err := json.Unmarshal(b, &texto); err != nil {
			n.Valor = math.NaN()
			return nil
		}
		texto = strings.TrimSpace(texto)
		if texto == "" {
			n.Valor = 0
			return nil
		}
		v, err := strconv.ParseFloat(texto, 64)
		if err != nil {
			n.Valor = math.NaN()
			return nil
		}
		n.Valor = v
		return nil
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		// Un objeto o un array: Number({}) y Number([1,2]) son NaN. Nunca un error de
		// decodificación, porque en Next el cuerpo entero se acepta igual y el fallo sale
		// como «falta la ubicación», no como «cuerpo no válido».
		n.Valor = math.NaN()
		return nil
	}
	n.Valor = v
	return nil
}
