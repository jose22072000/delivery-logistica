package espejo

import "time"

// TRAMOS, MARCA DE AGUA Y BARRIDO: la parte que decide QUÉ se pide, sin pedir nada.
//
// Está separada de todo lo que habla por la red a propósito: son funciones puras —mismas
// entradas, mismo resultado— y se prueban con una tabla, sin PEDIDO, sin base y sin reloj
// de verdad. Un fallo aquí no revienta nada: el espejo sigue vivo, trayendo los días que no
// son, y eso no se ve hasta que alguien busca un pedido de la semana pasada y no está.
//
// AQUÍ HA HABIDO DOS ERRORES SEGUIDOS, OPUESTOS Y LOS DOS MALOS.
//
// El primero: pedir sólo los pendientes, de cuando el reparto era quien cotizaba. Con el
// precio puesto por la APK, ese filtro se lleva justo los pedidos ya cotizados —la mayoría,
// y los que hacen falta para armar una ruta—.
//
// El segundo: quitar el filtro y traerlo todo en UNA llamada. Son 56.000 pedidos con sus
// líneas, y montar esa respuesta agotó la memoria del proceso. De ahí salió un recorte a
// quince días... que dejó fuera el catálogo entero. Una ruta se arma también con pedidos ya
// completados, y la mitad del trabajo es mirar lo de la semana pasada.
//
// Lo que arregla las dos cosas no es elegir cuántos días, es NO TRAERLOS DOS VECES:
//
//   - La primera vez se recorre el histórico por TRAMOS de días, de lo nuevo a lo viejo.
//     Tarda, y pasa una sola vez.
//   - A partir de ahí se pide `since = <lo más nuevo que ya tengo>`: lo que se movió desde
//     entonces. Suele ser nada o cuatro filas.

// Tramo es un trozo de días, ya en el formato de fecha que entiende PEDIDO (aaaa-mm-dd).
type Tramo struct {
	Desde string
	Hasta string
}

// FormatoDeFecha es el que espera `/integration/orders` en `desde` y `hasta`.
const FormatoDeFecha = "2006-01-02"

// Tramos parte un intervalo de «días hacia atrás» en trozos de `tramoDias`.
//
// DE LO NUEVO A LO VIEJO, y eso importa: si el proceso se para a mitad del recorrido, lo
// que ya está traído es lo RECIENTE, que es con lo que se trabaja hoy. Al revés, se
// tendría el año pasado entero y nada de esta semana.
//
// `hastaDias` es el borde más cercano a hoy (0 = hoy) y `desdeDias` el más lejano. Un
// intervalo al revés no devuelve nada en vez de dar la vuelta al año sin querer.
func Tramos(ahora time.Time, desdeDias, hastaDias, tramoDias int) []Tramo {
	if tramoDias <= 0 || hastaDias > desdeDias {
		return nil
	}
	dia := func(n int) string {
		return ahora.AddDate(0, 0, -n).Format(FormatoDeFecha)
	}
	var salida []Tramo
	for d := hastaDias; d <= desdeDias; d += tramoDias {
		// `hasta` es el borde nuevo del trozo y `desde` el viejo, pero el último trozo se
		// recorta en `desdeDias`: sin ese recorte, el barrido se pasaría del histórico
		// pedido y traería días que nadie quiso.
		lejano := d + tramoDias - 1
		if lejano > desdeDias {
			lejano = desdeDias
		}
		salida = append(salida, Tramo{Desde: dia(lejano), Hasta: dia(d)})
	}
	return salida
}

// SiguienteBarrido dice qué trozo del histórico toca en este ciclo.
//
// El barrido arranca donde lo dejó la vez anterior —la POSICIÓN GUARDADA— y estira
// `porCiclo` días más hacia atrás. Nunca empieza más cerca de hoy que el repaso corto, que
// ya cubre esos días en cada vuelta.
func SiguienteBarrido(posicion, repasoDias, porCiclo, historicoDias int) (desde, hasta int) {
	desde = posicion
	if desde < repasoDias {
		desde = repasoDias
	}
	hasta = desde + porCiclo
	if hasta > historicoDias {
		hasta = historicoDias
	}
	return desde, hasta
}

// AvanzarBarrido es dónde queda la posición después de barrer hasta `hasta`.
//
// AL LLEGAR AL FINAL SE VUELVE A EMPEZAR: el histórico se repasa EN BUCLE, así que
// cualquier hueco —un tramo que falló, un día que PEDIDO tocó sin avisar— se acaba tapando
// solo sin que nadie tenga que darse cuenta.
func AvanzarBarrido(hasta, historicoDias int) int {
	if hasta >= historicoDias {
		return 0
	}
	return hasta
}

// MasNuevo devuelve el `updatedAt` más nuevo de una tanda, y si alguno se pudo leer.
//
// Con esto se PAGINA el sincronizado incremental: se pide `since`, se procesa, y la
// siguiente petición arranca del más nuevo que acaba de llegar. Sin eso, una tanda de más
// de `limit` pedidos devolvería siempre los mismos y el bucle no avanzaría nunca.
func MasNuevo(pedidos []PedidoDeFuera) (time.Time, bool) {
	var tope time.Time
	hay := false
	for _, p := range pedidos {
		t, err := time.Parse(time.RFC3339, p.UpdatedAt)
		if err != nil {
			// Un pedido sin `updatedAt` legible no mueve la marca. No es un fallo del
			// recorrido: el pedido se guarda igual, y la marca la moverá otro.
			continue
		}
		if !hay || t.After(tope) {
			tope, hay = t, true
		}
	}
	return tope, hay
}

// Trozos parte una tanda en lotes de `tamano`.
//
// Se trocea porque el reparto de carga se calcula POR ENVÍO y 200 es un tamaño realista de
// camión — y porque mandar miles de pedidos en un solo POST es lo que reventó la memoria la
// vez anterior.
func Trozos[T any](todos []T, tamano int) [][]T {
	if tamano <= 0 || len(todos) == 0 {
		return nil
	}
	var salida [][]T
	for i := 0; i < len(todos); i += tamano {
		fin := i + tamano
		if fin > len(todos) {
			fin = len(todos)
		}
		salida = append(salida, todos[i:fin])
	}
	return salida
}
