package cotizar

import "math"

// GEOMETRÍA DEL RECORRIDO (§1 de reglas-negocio.md).
//
// De `pricing.ts` sólo sobrevive esto. Las cuatro fórmulas de PRECIO que tenía se
// borraron: tres no las llamaba nadie y la cuarta era una SEGUNDA forma de cobrar el
// domicilio —el mismo pedido costaba una cosa entrando por el espejo y otra a mano—.
// El precio del domicilio lo pone la APK de Entrega y nadie más; aquí se muestra.

// Punto es una coordenada. `lat`/`lng` como en el contrato.
type Punto struct {
	Lat float64
	Lng float64
}

// Parada es un punto con identidad, que es lo que devuelve el orden de visita.
type Parada struct {
	ID  string
	Lat float64
	Lng float64
}

// DistanciaHaversineKm es la distancia en línea recta, en km.
//
// SIN REDONDEAR, a propósito. Es la misma fórmula que `domicilioEntrega.distanciaHaversineKm`;
// lo que cambia entre las dos es el redondeo de SALIDA, que allí se aplica al informarla
// (3 decimales) y aquí no se aplica nunca. El cálculo del importe usa la cruda.
func DistanciaHaversineKm(lat1, lon1, lat2, lon2 float64) float64 {
	dLat := (lat2 - lat1) * math.Pi / 180
	dLon := (lon2 - lon1) * math.Pi / 180
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*math.Pi/180)*math.Cos(lat2*math.Pi/180)*
			math.Sin(dLon/2)*math.Sin(dLon/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
	return RadioTierraKm * c
}

// DistanciaEntre es lo mismo con dos puntos.
func DistanciaEntre(a, b Punto) float64 {
	return DistanciaHaversineKm(a.Lat, a.Lng, b.Lat, b.Lng)
}

// OrdenPorCercania es el `greedyRouteOptimization`: vecino más próximo, sin 2-opt ni nada
// posterior. Devuelve los ids en orden de visita.
//
// DOS DETALLES QUE HAY QUE CONSERVAR TAL CUAL:
//
//  1. El desempate lo gana el PRIMERO de la lista. La comparación es estricta (`dist <
//     mejor`, arrancando en +∞), no `<=`. Con dos clientes a la misma distancia —la misma
//     cuadra, dos pedidos del mismo edificio— un `<=` daría el orden contrario, y el orden
//     de paradas es lo que el chofer lleva en la mano.
//  2. NO se cierra el circuito: el regreso al almacén no forma parte del orden. Lo suma
//     quien llame, si lo necesita.
func OrdenPorCercania(origen Punto, paradas []Parada) []string {
	// Casos límite explícitos del pliego. El de 1 evita recorrer la lista para nada, y
	// el de 0 tiene que devolver una lista VACÍA, no nil: es un JSON `[]`, no `null`.
	if len(paradas) == 0 {
		return []string{}
	}
	if len(paradas) == 1 {
		return []string{paradas[0].ID}
	}

	// Copia propia: el original es de quien llama y aquí se va vaciando (el `splice`).
	quedan := make([]Parada, len(paradas))
	copy(quedan, paradas)

	orden := make([]string, 0, len(paradas))
	actual := origen
	for len(quedan) > 0 {
		mejor := math.Inf(1)
		idx := 0 // `nearestIdx = 0`: si ninguna mejora (distancias NaN), gana la primera
		for i, p := range quedan {
			d := DistanciaHaversineKm(actual.Lat, actual.Lng, p.Lat, p.Lng)
			if d < mejor { // ESTRICTO: el empate lo gana quien llegó antes
				mejor = d
				idx = i
			}
		}
		elegida := quedan[idx]
		orden = append(orden, elegida.ID)
		quedan = append(quedan[:idx], quedan[idx+1:]...)
		actual = Punto{Lat: elegida.Lat, Lng: elegida.Lng}
	}
	return orden
}

// TramosDeRuta es el `calculateRouteSegments`: las distancias CONSECUTIVAS
// origen→p1, p1→p2, p2→p3… una por parada, en el orden dado.
//
// Sirve para los kilómetros REALES del camión (`totalDistance` de la ruta). Con esto no
// se cobra nada: el domicilio se mide del almacén al cliente en línea recta, que es otra
// medida y no hay que confundirlas (§15.8 del pliego).
func TramosDeRuta(origen Punto, paradas []Parada) []float64 {
	tramos := make([]float64, 0, len(paradas))
	actual := origen
	for _, p := range paradas {
		tramos = append(tramos, DistanciaHaversineKm(actual.Lat, actual.Lng, p.Lat, p.Lng))
		actual = Punto{Lat: p.Lat, Lng: p.Lng}
	}
	return tramos
}
