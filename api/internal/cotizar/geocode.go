package cotizar

import (
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"
)

// GEOCODIFICACIÓN (§9 de reglas-negocio.md) — sólo la parte que es cuenta.
//
// `forwardGeocode` y `reverseGeocode` salen a Nominatim y no viven aquí: este paquete es
// de funciones puras, para poder probarlo sin red. Lo que sí es cuenta —el formato de las
// coordenadas, el zoom del mapa y el parseo de lo que alguien pega en una caja de texto—
// está abajo, con sus constantes literales.

// DecimalesDeCoordenadas: 5 (apéndice de constantes). No es estética: con 5 decimales se
// distingue un portal de otro (~1 m); con 4 ya no.
const DecimalesDeCoordenadas = 5

// FormatCoords es `${lat.toFixed(5)}, ${lng.toFixed(5)}` — coma Y ESPACIO.
// Es lo que se enseña cuando la geocodificación inversa no devuelve dirección, así que el
// formato tiene que ser el mismo o la pantalla enseña dos cosas distintas para lo mismo.
func FormatCoords(lat, lng float64) string {
	return fmt.Sprintf("%.*f, %.*f", DecimalesDeCoordenadas, lat, DecimalesDeCoordenadas, lng)
}

// ZoomDesdeArea es `zoomFromArea(areaKm2)`: `round(13 − log2(√área))`, acotado a [8, 16].
// Área mayor, zoom menor.
func ZoomDesdeArea(areaKm2 float64) float64 {
	// El `a = área > 0 ? área : 1` protege el logaritmo del 0 y de los negativos: sin él,
	// una sucursal con el área sin poner daría −Infinity y el mapa saldría en blanco.
	a := areaKm2
	if !(a > 0) {
		a = 1
	}
	z := math.Round(13 - math.Log2(math.Sqrt(a)))
	return math.Max(8, math.Min(16, z))
}

// Un máximo de TRES dígitos enteros, `.` decimal opcional, y `,`, `;` o espacio como
// separador. Es el mismo literal de `geocode.ts`.
var reCoordenadas = regexp.MustCompile(`^(-?\d{1,3}(?:\.\d+)?)\s*[,;\s]\s*(-?\d{1,3}(?:\.\d+)?)$`)

// ParsearCoordenadas es `parseCoordInput(text)`: acepta "-23.5505, -46.6333",
// "23.55 -46.63" y el `;` como separador. Devuelve nil si no casa o si se sale del mundo.
//
// El recorte por rango (lat ∈ [−90, 90], lng ∈ [−180, 180]) es lo que separa una
// coordenada pegada de un número de teléfono pegado por error.
func ParsearCoordenadas(texto string) *Punto {
	// El `trim()` va antes del regex, igual que allá: el texto llega pegado de una caja y
	// casi siempre trae un espacio de más al final.
	t := strings.TrimSpace(texto)
	m := reCoordenadas.FindStringSubmatch(t)
	if m == nil {
		return nil
	}
	lat, err1 := strconv.ParseFloat(m[1], 64)
	lng, err2 := strconv.ParseFloat(m[2], 64)
	if err1 != nil || err2 != nil {
		return nil
	}
	if lat < -90 || lat > 90 || lng < -180 || lng > 180 {
		return nil
	}
	return &Punto{Lat: lat, Lng: lng}
}
