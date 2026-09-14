package cotizar

import "math"

// EL COSTO DEL DOMICILIO (§7 de reglas-negocio.md) — la fórmula de Entrega, calcada.
//
//	tarifa base (USD por km·kg) × distancia (km) × peso (kg)
//
// La distancia es en línea recta (Haversine) del ALMACÉN al cliente, y el redondeo es a
// dos decimales. La tarifa se guarda en Entrega en CUP, así que se pasa a USD dividiendo
// por la tasa DE ESA SUCURSAL — exactamente lo que hace la APK antes de multiplicar.
//
// REGLA DE FONDO: un pedido metido a mano en delivery tiene que salir por el MISMO número
// que uno hecho desde el teléfono. Una fórmula «parecida» aquí hace que el mismo reparto
// valga una cosa en un sitio y otra en el otro, y nadie sabe cuál cobrar.
//
// Nada de esto se configura aquí: tarifa y tasa vienen de Entrega a través de Accesos.

// CostoDomicilio es lo que sale del cálculo.
//
// `DistanciaKm` y `PesoKg` vienen YA REDONDEADOS a 3 decimales y son sólo para informar;
// los que entraron en la multiplicación son los crudos.
type CostoDomicilio struct {
	DistanciaKm float64 `json:"distanciaKm"`
	PesoKg      float64 `json:"pesoKg"`
	USD         float64 `json:"usd"`
	CUP         float64 `json:"cup"`
	TarifaUsd   float64 `json:"tarifaUsd"`
}

// CostoDomicilioEntrega devuelve el costo, o nil.
//
// NIL NO ES CERO, Y ÉSTA ES LA REGLA MÁS IMPORTANTE DEL FICHERO. Un cero es un precio: se
// suma, se ordena y se lee como «este domicilio es gratis», que es peor que decir que no
// se sabe. Por eso los rechazos devuelven nil y nunca 0.
//
// Rechazos, en el orden del pliego:
//
//   - `!tarifaBaseCup` — falsy de JavaScript, así que incluye el CERO y el NaN (que es
//     como llega un `tarifaBase: null` de Accesos). Una tarifa de 0 no es «gratis»: es
//     «Entrega todavía no la puso».
//   - `!cupPorUsd || cupPorUsd <= 0` — sin tasa no hay conversión posible.
//   - `distanciaKm` o `pesoKg` no finitos (NaN, ±Infinity).
//
// OJO CON LO QUE NO SE RECHAZA: una distancia de 0 km y un peso de 0 kg SÍ son finitos,
// así que pasan y dan `usd = 0`, `cup = 0`. Es correcto y es distinto de nil: ahí sí se
// sabe cuánto cuesta —nada— porque el cliente está en la puerta del almacén o no lleva
// carga. El que no se sabe es el nil.
func CostoDomicilioEntrega(tarifaBaseCup, cupPorUsd, distanciaKm, pesoKg float64) *CostoDomicilio {
	// `!tarifaBaseCup` es el falsy de JavaScript, ni más ni menos: rechaza el 0 y el NaN
	// (que es como llega un `tarifaBase: null` de Accesos). Lo que NO rechaza —y aquí
	// tampoco— es un negativo ni un ±Infinity, que en JavaScript son truthy. No deberían
	// llegar nunca; si llegan, salen por el mismo sitio que allí y se ven.
	if tarifaBaseCup == 0 || math.IsNaN(tarifaBaseCup) {
		return nil
	}
	if !(cupPorUsd > 0) { // cubre a la vez el `!cupPorUsd` (0, NaN) y el `<= 0`
		return nil
	}
	if !Finito(distanciaKm) || !Finito(pesoKg) {
		return nil
	}

	// SIN REDONDEAR: se devuelve tal cual. Es el número con el que multiplica la APK.
	tarifaUsd := tarifaBaseCup / cupPorUsd

	// El orden de la multiplicación es el de la APK, izquierda a derecha:
	// (tarifaUsd × distancia) × peso. Con coma flotante, reordenar cambia el último bit,
	// y el último bit es justo lo que decide de qué lado del medio céntimo cae el redondeo.
	usd := Redondear2(tarifaUsd * distanciaKm * pesoKg)

	// EL CUP SE CALCULA SOBRE EL USD YA REDONDEADO, no sobre el valor crudo. Hacerlo al
	// revés da otro número, y el que cobra la APK es éste.
	cup := Redondear2(usd * cupPorUsd)

	return &CostoDomicilio{
		DistanciaKm: Redondear3(distanciaKm),
		PesoKg:      Redondear3(pesoKg),
		USD:         usd,
		CUP:         cup,
		TarifaUsd:   tarifaUsd,
	}
}
