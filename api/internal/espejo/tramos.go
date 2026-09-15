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

// TopeDePagina es lo que se le pide a PEDIDO en CADA peticion de pedidos, y el numero no
// es un numero cualquiera: es EL SUYO.
//
// `/integration/orders` recorta la respuesta por su cuenta y no lo anuncia — contesta 200
// con los primeros y ni una palabra de que falten—. Pidiendole de mas, una pagina recortada
// es indistinguible de una pagina corta: de un `limit=5000` vuelven 2.000 clavados, que
// leidos desde aqui parecen «ya no habia mas». Ese es exactamente el fallo que dejaba
// tramos enteros a medias sin un solo aviso, y el mismo que se llevo 6.000 clientes.
//
// Pidiendole SU tope, «vinieron tantos como pedi» significa «hay mas», que es lo unico que
// hace falta saber para seguir pidiendo. Si algun dia PEDIDO sirve mas, pedir de menos no
// rompe nada: se encadena una vuelta de mas y ya.
const TopeDePagina = 2000

// TopeDeVueltas es cuantas peticiones encadenadas se permiten en un mismo paso, tanto en el
// incremental como en un tramo. Un bucle sin tope es un proceso que se queda toda la noche
// en el mismo sitio y no llega nunca al resto del ciclo; lo que no entre en estas vueltas
// entra en la pasada siguiente, que para eso el historico se repasa en bucle.
const TopeDeVueltas = 200

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

// DiaMasViejo devuelve el dia (aaaa-mm-dd) del pedido mas antiguo de una tanda, y si se
// pudo leer alguno.
//
// Con esto se encadenan los TRAMOS, igual que `MasNuevo` encadena el incremental. La
// diferencia es de donde sale el avance: el incremental lo saca de `updatedAt` porque
// filtra por `since`; un tramo filtra por `desde`/`hasta`, que van por la FECHA DEL PEDIDO,
// asi que su borde es esa fecha y no la marca de agua. `/integration/orders` ordena por
// fecha descendente y recorta por arriba, o sea que el mas viejo de lo que llego es justo
// el punto por el que hay que seguir pidiendo.
//
// EL DIA SE SACA EN UTC, que es como PEDIDO serializa la fecha; su filtro `hasta` corta por
// el final de ese dia en la hora de SU servidor. Mientras ese servidor no este al este de
// UTC —y no lo esta: Cuba es UTC-4/-5 y los contenedores van en UTC— el corte cae igual o
// mas tarde que el pedido mas viejo que llego, que es lo que garantiza que por el medio no
// se quede ninguno.
//
// Un pedido sin fecha legible no cuenta: no mueve el borde y no estorba a los que si.
func DiaMasViejo(pedidos []PedidoDeFuera) (string, bool) {
	var suelo time.Time
	hay := false
	for _, p := range pedidos {
		t, err := time.Parse(time.RFC3339, p.Fecha)
		if err != nil {
			continue
		}
		if !hay || t.Before(suelo) {
			suelo, hay = t, true
		}
	}
	if !hay {
		return "", false
	}
	return suelo.UTC().Format(FormatoDeFecha), true
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
