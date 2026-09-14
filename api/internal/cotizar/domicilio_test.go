package cotizar

import (
	"math"
	"testing"
)

// LA TABLA MÁS IMPORTANTE DEL PAQUETE. Cada fila es un importe que alguien cobra.
//
// Los esperados salen de correr `costoDomicilioEntrega` del pliego (§7) en Node, con la
// misma cadena de operaciones y el mismo redondeo. Se comparan EXACTOS, sin holgura: el
// resultado ya viene redondeado a dos decimales, así que una diferencia aquí no es ruido
// de coma flotante, es un céntimo de diferencia con lo que cobra la APK.
func TestCostoDomicilioEntrega(t *testing.T) {
	casos := []struct {
		nombre                                        string
		tarifaBaseCup, cupPorUsd, distanciaKm, pesoKg float64
		esperado                                      *CostoDomicilio // nil = se rechaza
	}{
		{
			"caso redondo: 120 CUP/km·kg a 400 CUP/USD, 10 km, 25 kg",
			120, 400, 10, 25,
			&CostoDomicilio{DistanciaKm: 10, PesoKg: 25, USD: 75, CUP: 30000, TarifaUsd: 0.3},
		},
		{
			// CASO LÍMITE: 0 km. El cliente está en la puerta del almacén. Devuelve CERO,
			// que es un precio, y NO nil. Aquí sí se sabe cuánto cuesta: nada.
			"cero kilómetros da cero, no nil",
			120, 400, 0, 25,
			&CostoDomicilio{DistanciaKm: 0, PesoKg: 25, USD: 0, CUP: 0, TarifaUsd: 0.3},
		},
		{
			// Lo mismo con el peso: un pedido sin peso resuelto entra con 0 y sale con 0.
			"cero kilos da cero, no nil",
			120, 400, 10, 0,
			&CostoDomicilio{DistanciaKm: 10, PesoKg: 0, USD: 0, CUP: 0, TarifaUsd: 0.3},
		},
		{
			// CASO LÍMITE: tarifa cero. `!tarifaBaseCup` es falsy con el 0, así que se
			// RECHAZA. Una tarifa de 0 no es «el domicilio es gratis»: es «Entrega
			// todavía no la puso», y un cero ahí se suma y se lee como gratis.
			"tarifa base cero: nil, nunca cero",
			0, 400, 10, 25, nil,
		},
		{
			// CASO LÍMITE: tasa cero. Sin tasa no hay conversión: nil.
			"tasa cero: nil",
			120, 0, 10, 25, nil,
		},
		{"tasa negativa: nil", 120, -5, 10, 25, nil},
		{"distancia NaN: nil", 120, 400, math.NaN(), 25, nil},
		{"peso infinito: nil", 120, 400, 10, math.Inf(1), nil},
		{"tarifa NaN (así llega un tarifaBase null de Accesos): nil", math.NaN(), 400, 10, 25, nil},
		{"tasa NaN: nil", 120, math.NaN(), 10, 25, nil},
		{
			// Los tres decimales de km y kg son SÓLO para informar: 12.3456789 se enseña
			// como 12.346 pero el importe se calculó con el crudo. Redondear antes daría
			// otro número.
			"decimales de sobra: se informan a 3, se calcula con los crudos",
			350, 425, 12.3456789, 7.7777,
			&CostoDomicilio{DistanciaKm: 12.346, PesoKg: 7.778, USD: 79.08, CUP: 33609, TarifaUsd: 0.8235294117647058},
		},
		{
			"todo a uno",
			1, 1, 1, 1,
			&CostoDomicilio{DistanciaKm: 1, PesoKg: 1, USD: 1, CUP: 1, TarifaUsd: 1},
		},
		{
			"distancia con muchos decimales",
			120, 400, 8.123456789, 13.5,
			&CostoDomicilio{DistanciaKm: 8.123, PesoKg: 13.5, USD: 32.9, CUP: 13160, TarifaUsd: 0.3},
		},
		{
			// Una tasa con céntimos y un peso pequeño: aquí es donde se ve que el CUP se
			// saca del USD YA REDONDEADO. Con el crudo saldría 150.98, no 151.03.
			"el CUP sale del USD ya redondeado",
			95.5, 387.25, 3.14159265, 0.5,
			&CostoDomicilio{DistanciaKm: 3.142, PesoKg: 0.5, USD: 0.39, CUP: 151.03, TarifaUsd: 0.24661071659134925},
		},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			got := CostoDomicilioEntrega(c.tarifaBaseCup, c.cupPorUsd, c.distanciaKm, c.pesoKg)
			if c.esperado == nil {
				if got != nil {
					t.Fatalf("se esperaba nil (no cero), salió %+v", got)
				}
				return
			}
			if got == nil {
				t.Fatalf("salió nil, se esperaba %+v", *c.esperado)
			}
			if *got != *c.esperado {
				t.Fatalf("\n salió     %+v\n se esperaba %+v", *got, *c.esperado)
			}
		})
	}
}

// El CUP se calcula sobre el USD YA REDONDEADO. Esta prueba lo fija aparte porque es el
// detalle que el pliego marca como «reimplementarlo al revés da otro número».
func TestCUPSaleDelUSDRedondeado(t *testing.T) {
	const tarifa, tasa, km, kg = 95.5, 387.25, 3.14159265, 0.5

	got := CostoDomicilioEntrega(tarifa, tasa, km, kg)
	if got == nil {
		t.Fatal("no debería rechazar")
	}

	crudo := Redondear2((tarifa / tasa) * km * kg * tasa) // la forma INCORRECTA
	if got.CUP == crudo {
		t.Fatalf("el caso de prueba ya no distingue las dos formas (ambas dan %v)", crudo)
	}
	if got.CUP != Redondear2(got.USD*tasa) {
		t.Fatalf("CUP = %v; se esperaba redondear(usd × tasa) = %v", got.CUP, Redondear2(got.USD*tasa))
	}
}
