package api

import (
	"testing"

	"procovar/reparto-api/internal/cotizar"
	"procovar/reparto-api/internal/store/sqlc"
)

// DE DÓNDE SON LOS RENGLONES, DE PEDIDO A LA BASE.
//
// Cuando un pedido se factura distinto de como se tomó, PEDIDO manda **las líneas de la
// factura** en `items` —descartando las que se pidieron y no se facturaron, para que nadie
// cargue un hueco—. O sea que los kg y las unidades que este reparto tiene ya son los que
// suben al camión. Comprobado contra producción el 26/09/2026:
//
//	PAT26-260923-1246 · el vendedor tomó MALTA 1.5L ×15 y MALTA 0.33L ×10;
//	                    la factura dice SÓLO 10 blísters de 330 ml;
//	                    aquí hay 1 renglón, 60 uds y 24,194 kg — los de la factura.
//
// Lo que faltaba era DECIRLO: en pantalla salía «Cambió en la factura» y nada más, así que
// quien mira un número no sabe cuál de los dos tiene delante.
//
// Jose, 26/09/2026: «se facturó otra cosa, ese pedido ya no representa la cantidad total»,
// y cómo se resuelve, con sus palabras: «mantenemos el pedido y sólo le añadimos una
// factura a ese pedido para saber si cambió o no».
//
// LOS DOS TRAMOS se rompen por separado y por eso van separados: que el dato SE LEE del
// lote de PEDIDO, y que LLEGA a la fila que se escribe. El tercero —que sale hacia la
// aplicación— lo sujeta `la_bajada_no_pierde_campos_test`, que es donde vive esa guarda.

// armadoConOrigen pasa un pedido del lote por el mismo camino que la bajada de verdad.
func armadoConOrigen(origen *string) PedidoParaGuardar {
	return armarPedidoDelLote(
		conOrigen(origen), sqlc.ListarSucursalesRow{}, cotizar.PesosResueltos{}, 0, 0,
	)
}

// Un pedido del lote con lo mínimo para que se pueda armar: las coordenadas del cliente
// son obligatorias río arriba —`armarPedidoDelLote` las da por comprobadas— y sin ellas
// esto revienta por donde no toca.
func conOrigen(origen *string) pedidoDelLote {
	lat, lng := 20.02, -75.82
	return pedidoDelLote{
		ExternalID:   "ped-1",
		CustomerName: "Bodega La Esquina",
		Address:      "Calle 4",
		Lat:          &lat,
		Lng:          &lng,
		ItemsOrigen:  origen,
	}
}

func TestElOrigenDeLosRenglonesSeLeeDelLote(t *testing.T) {
	factura := "factura"

	armado := armadoConOrigen(&factura)

	if armado.ItemsOrigen == nil || *armado.ItemsOrigen != "factura" {
		t.Fatalf("se perdió de dónde son los renglones: %v", armado.ItemsOrigen)
	}
}

func TestElOrigenDeLosRenglonesLlegaALaFilaQueSeEscribe(t *testing.T) {
	pedido := "pedido"

	arg := paraLaBase(armadoConOrigen(&pedido))

	if arg.ItemsOrigen == nil || *arg.ItemsOrigen != "pedido" {
		t.Fatalf("no llegó a la fila: %v", arg.ItemsOrigen)
	}
}

// LA OTRA MITAD: sin esto, «llega» se cumple poniendo `factura` siempre.
//
// Un pedido que PEDIDO no cotejó, o cuyo cotejo no pudo atar la factura a ESTE pedido, se
// queda con las líneas del pedido. Afirmar «factura» ahí se lee igual de bien que la
// verdad, y es justo el número por el que alguien cargaría el camión de más.
func TestSinOrigenNoSeInventaNinguno(t *testing.T) {
	arg := paraLaBase(armadoConOrigen(nil))

	if arg.ItemsOrigen != nil {
		t.Fatalf(
			"se inventó de dónde son los renglones cuando PEDIDO no lo dijo: %q",
			*arg.ItemsOrigen,
		)
	}
}

// NO SE DEDUCE DE `facturaEstado`, que es otra pregunta.
//
// `cambiado` dice que la factura difiere; `itemsOrigen` dice qué estoy mirando yo. Un
// `igual` también trae las líneas de la factura, y un `cambiado` sin factura atada se
// queda con las del pedido. Deducir uno del otro es adivinar.
func TestElOrigenNoSaleDelEstadoDeLaFactura(t *testing.T) {
	cambiado, pedido := "cambiado", "pedido"
	p := conOrigen(&pedido)
	p.FacturaEstado = &cambiado

	arg := paraLaBase(
		armarPedidoDelLote(p, sqlc.ListarSucursalesRow{}, cotizar.PesosResueltos{}, 0, 0),
	)

	if arg.ItemsOrigen == nil || *arg.ItemsOrigen != "pedido" {
		t.Fatalf(
			"con la factura «cambiado» se dio por hecho que los renglones eran suyos: %v",
			arg.ItemsOrigen,
		)
	}
}
