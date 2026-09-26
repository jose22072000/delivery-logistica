package cotizar

import "testing"

// EL ALMACÉN DEL PEDIDO, no el principal de la sucursal.
//
// # QUÉ SE DEFIENDE AQUÍ, con los números del 26/09/2026
//
// La distancia del domicilio se mide DESDE EL ALMACÉN y de esos kilómetros sale el costo que
// alguien cobra. Mientras cada sucursal tuvo UN almacén, «el de la sucursal» y «el del pedido»
// eran la misma frase. Dejó de serlo, y la sesión de PEDIDO contó sus renglones:
//
//	SANTIAGO    2.185 líneas desde AURORA · 804 desde PV-STGO · 11 desde PTO MONEDERO
//	CAMAGÜEY    2.778 desde PV CAMAGÜEY   · 183 desde FLORIDA · 39 desde ALM CAMAGÜEY
//	GUANTÁNAMO  2.060 desde PV GTMO       · 940 desde ALM CENTRAL
//
// En Santiago **dos de cada tres pedidos salen de AURORA** y se medían todos desde PV-STGO.
//
// # LA FORMA DE ESTAS PRUEBAS, Y POR QUÉ VAN EN PAREJA
//
// Cada caso de «mide desde el almacén del pedido» lleva su gemelo de «y sigue midiendo desde
// el principal cuando no hay almacén del pedido». La segunda mitad es la que se olvida, y sin
// ella lo primero se cumple con un código que rompe los 5.480 pedidos que hoy hay en
// producción — todos sin almacén, porque PEDIDO todavía no mandaba el campo.
//
// Y SE COMPRUEBA CUÁL ALMACÉN SALE, no que «salga alguno»: `ElegirOrigenDelPedido` devolviendo
// siempre el principal pasaría cualquier prueba que sólo mirara que no es nil.

// almacenDePrueba: un almacén usable, con su código y su punto.
// elQueSalio dice QUÉ almacén salió, en palabras.
//
// Un `%v` sobre el `*Almacen` imprime la estructura entera con las coordenadas como direcciones
// —`&{1 1 PV-STGO <nil> 0xe2d052bf610 ...}`—, o sea que el mensaje del fallo no se puede leer sin
// abrir el fichero. Lo que hace falta saber es el nombre y el código, y nada más.
func elQueSalio(o OrigenDelPedido) string {
	if o.Almacen == nil {
		return "nada (no había desde dónde medir), motivo " + string(o.Motivo)
	}
	return o.Almacen.Nombre + " (código " + o.Almacen.Codigo + "), motivo " + string(o.Motivo)
}

func almacenDePrueba(codigo, nombre string, lat, lng float64, principal bool) Almacen {
	return Almacen{
		ID: codigo, Codigo: codigo, Nombre: nombre,
		Latitud: num(lat), Longitud: num(lng),
		Principal: principal, Activo: true,
	}
}

// losDeSantiago son los tres de verdad, con PV-STGO como principal: es la sucursal del caso.
func losDeSantiago() []Almacen {
	return []Almacen{
		almacenDePrueba("1", "PV-STGO", 20.0200, -75.8200, true),
		almacenDePrueba("2", "AURORA", 20.1500, -75.9500, false),
		almacenDePrueba("3", "ALM CENTRAL", 20.0500, -75.8000, false),
	}
}

// --------------------------------------------------------------------------- la pareja

func TestElOrigenEsElAlmacenDelPedidoYSiNoElPrincipal(t *testing.T) {
	casos := []struct {
		nombre string
		codigo string
		// `quiere` es el NOMBRE del almacén que tiene que salir; "" = ninguno. Se compara por
		// nombre y no por código A PROPÓSITO: uno de los casos es justo el de los almacenes
		// SIN código, y comparar por código lo haría imposible de escribir.
		quiere  string
		motivo  MotivoDelOrigen //
		porQue  string
		lista   []Almacen
		esperar bool // true = el elegido tiene que ser el del pedido
	}{
		// LA MITAD QUE SE PIDIÓ: el pedido sale de AURORA y se mide desde AURORA.
		{
			nombre: "el pedido trae AURORA y se mide desde AURORA", codigo: "2",
			quiere: "AURORA", motivo: MotivoAlmacenDelPedido, lista: losDeSantiago(),
			porQue: "es el caso del 26/09/2026: dos de cada tres pedidos de Santiago salen " +
				"de AURORA y se medían desde PV-STGO, que es el principal",
			esperar: true,
		},
		// LA OTRA MITAD, LA QUE SE OLVIDA: sin almacén se sigue midiendo desde el principal.
		// Son los 5.480 pedidos que hay hoy en producción, o sea el caso mayoritario.
		{
			nombre: "sin almacén en el pedido se mide desde el PRINCIPAL", codigo: "",
			quiere: "PV-STGO", motivo: MotivoPedidoSinAlmacen, lista: losDeSantiago(),
			porQue: "todo lo bajado antes de que PEDIDO mandara el campo, y todo pedido que " +
				"entra antes de facturarse, llega sin almacén",
		},
		// Y no es «el primero de la lista»: el principal se elige con la regla de siempre.
		{
			nombre: "sin almacén, el principal no es el primero de la lista", codigo: "",
			quiere: "PV-STGO", motivo: MotivoPedidoSinAlmacen,
			lista: []Almacen{
				almacenDePrueba("2", "AURORA", 20.15, -75.95, false),
				almacenDePrueba("1", "PV-STGO", 20.02, -75.82, true),
			},
			porQue: "el desempate es la regla de `ElegirAlmacen`, no el orden en que Accesos " +
				"sirva la lista",
		},

		// EL DESCONOCIDO. `28 · PTO MONEDERO` existe de verdad en Santiago con 11 líneas.
		{
			nombre: "un almacén que no está dado de alta NO se descarta: se mide desde el principal y se dice",
			codigo: "28", quiere: "PV-STGO", motivo: MotivoAlmacenNoDadoDeAlta, lista: losDeSantiago(),
			porQue: "`CLAUDE.md` §4: nada se descarta en silencio. Ni se tira el pedido ni se " +
				"cambia por el principal a escondidas",
		},

		// SIN COORDENADAS SE SALTA. Es el caso NORMAL de esta semana: los 6 almacenes nuevos
		// se dieron de alta SIN punto a propósito — los ponen los logísticos —, así que el
		// dato llega antes que las coordenadas.
		{
			nombre: "el almacén del pedido sin coordenadas cede al principal, y se dice",
			codigo: "2", quiere: "PV-STGO", motivo: MotivoAlmacenSinCoordenadas,
			lista: []Almacen{
				almacenDePrueba("1", "PV-STGO", 20.02, -75.82, true),
				{ID: "2", Codigo: "2", Nombre: "AURORA", Activo: true},
			},
			porQue: "los 6 almacenes nuevos están dados de alta sin punto A PROPÓSITO: esto " +
				"es lo normal unos días, no un fallo",
		},
		{
			nombre: "el almacén del pedido dado de baja cede al principal",
			codigo: "2", quiere: "PV-STGO", motivo: MotivoAlmacenSinCoordenadas,
			lista: []Almacen{
				almacenDePrueba("1", "PV-STGO", 20.02, -75.82, true),
				{ID: "2", Codigo: "2", Nombre: "AURORA", Latitud: num(20.15),
					Longitud: num(-75.95), Activo: false},
			},
			porQue: "un almacén de baja con coordenadas BUENAS es el caso más caro que hay: " +
				"la cuenta sale y el número es creíble (24/09/2026)",
		},
		{
			nombre: "el almacén del pedido en (0,0) cede al principal",
			codigo: "2", quiere: "PV-STGO", motivo: MotivoAlmacenSinCoordenadas,
			lista: []Almacen{
				almacenDePrueba("1", "PV-STGO", 20.02, -75.82, true),
				{ID: "2", Codigo: "2", Nombre: "AURORA", Latitud: num(0), Longitud: num(0),
					Activo: true},
			},
			porQue: "(0,0) es el golfo de Guinea, no Santiago: no tiene coordenadas, las " +
				"tiene sin poner",
		},

		// ACCESOS SIN CÓDIGOS es OTRA COSA que «no dado de alta», y por eso tiene su motivo:
		// no falta ningún almacén, faltan los códigos de los que ya están. Son dos arreglos
		// distintos y dos personas distintas.
		{
			nombre: "si NINGÚN almacén tiene código, el motivo lo dice y no acusa al almacén",
			codigo: "2", quiere: "PV-STGO", motivo: MotivoAccesosSinCodigos,
			lista: []Almacen{
				{ID: "a", Nombre: "PV-STGO", Latitud: num(20.02), Longitud: num(-75.82),
					Principal: true, Activo: true},
				{ID: "b", Nombre: "AURORA", Latitud: num(20.15), Longitud: num(-75.95),
					Activo: true},
			},
			porQue: "es el estado del día del despliegue: Accesos todavía no expone `codigo`. " +
				"Con «no dado de alta» se acusaría a catorce almacenes de no existir",
		},

		// NO HAY DESDE DÓNDE MEDIR. El motivo va COMPUESTO: son dos preguntas y las dos
		// tienen respuesta.
		{
			nombre: "sin ningún almacén con punto, el motivo dice las DOS cosas",
			codigo: "28", quiere: "",
			motivo: MotivoSucursalSinAlmacen + "+" + MotivoAlmacenNoDadoDeAlta,
			lista: []Almacen{
				{ID: "1", Codigo: "1", Nombre: "PV-STGO", Principal: true, Activo: true},
			},
			porQue: "si el motivo dijera sólo «la sucursal no tiene almacén», el `28` " +
				"desconocido no aparecería como desconocido en ninguna parte",
		},
		{
			nombre: "sin almacenes y sin almacén en el pedido, también compuesto",
			codigo: "", quiere: "",
			motivo:  MotivoSucursalSinAlmacen + "+" + MotivoPedidoSinAlmacen,
			lista:   nil,
			porQue:  "una sucursal sin almacenes dados de alta se mide desde su punto, y eso se dice",
			esperar: false,
		},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			o := ElegirOrigenDelPedido(c.lista, c.codigo)

			if o.Motivo != c.motivo {
				t.Errorf("motivo %q, se esperaba %q\n  por qué importa: %s",
					o.Motivo, c.motivo, c.porQue)
			}
			if c.quiere == "" {
				if o.Almacen != nil {
					t.Fatalf("se esperaba que NO hubiera desde dónde medir; salió %q",
						o.Almacen.Nombre)
				}
				if o.DelPedido() {
					t.Fatal("dice que midió desde el almacén del pedido y no midió desde ninguno")
				}
				return
			}
			if o.Almacen == nil {
				t.Fatalf("salió nil y se esperaba el almacén %q\n  por qué importa: %s",
					c.quiere, c.porQue)
			}
			if o.Almacen.Nombre != c.quiere {
				t.Fatalf("midió desde el almacén %q (código %q) y tenía que medir desde %q\n"+
					"  por qué importa: %s",
					o.Almacen.Nombre, o.Almacen.Codigo, c.quiere, c.porQue)
			}
			// Y `DelPedido()` tiene que contar la misma historia que el motivo: es lo que
			// mira quien decide si avisar, y dos respuestas distintas sobre lo mismo es el
			// §3-bis del `CLAUDE.md`.
			if o.DelPedido() != (c.motivo == MotivoAlmacenDelPedido) {
				t.Errorf("DelPedido() = %v con el motivo %q: no cuentan lo mismo",
					o.DelPedido(), o.Motivo)
			}
		})
	}
}

// --------------------------------------------------------------------------- la identidad

// LA IDENTIDAD ES (SUCURSAL, CÓDIGO), Y EL NOMBRE NO IDENTIFICA NADA.
//
// Comprobado en Ventra el 26/09/2026, y hacen falta las dos mitades:
//
//   - el NOMBRE no identifica: `Tiendas Parranda` existe en cinco sucursales con cinco ids,
//     `Parranda Oferta` en cuatro, y **`PV-STGO` está en Santiago Y en Palma Soriano**;
//   - el CÓDIGO solo tampoco: `objectCode: 2` es AURORA en Santiago, PV CAMAGÜEY en Camagüey
//     y PV GTMO en Guantánamo.
//
// La sucursal va implícita en la lista —a `ElegirOrigenDelPedido` sólo llegan los almacenes de
// UNA—, así que lo que esta prueba defiende es que **el mismo código en dos sucursales no se
// cruza** y que **el nombre no se usa como respaldo**. Un respaldo por nombre no falla nunca:
// sólo mide desde el almacén de otro sitio, con sus decimales y sin que nada chirríe.
func TestLaIdentidadEsElCodigoYNuncaElNombre(t *testing.T) {
	// `2` es AURORA en Santiago y PV CAMAGÜEY en Camagüey: dos almacenes distintos, el mismo
	// código, y a 500 km uno del otro.
	santiago := losDeSantiago()
	camaguey := []Almacen{
		almacenDePrueba("1", "ALM CAMAGUEY", 21.3800, -77.9200, true),
		almacenDePrueba("2", "PV CAMAGUEY", 21.3900, -77.9100, false),
	}

	enStg := ElegirOrigenDelPedido(santiago, "2")
	enCam := ElegirOrigenDelPedido(camaguey, "2")

	if enStg.Almacen == nil || enStg.Almacen.Nombre != "AURORA" {
		t.Fatalf("el código 2 de Santiago tenía que ser AURORA; salió %s", elQueSalio(enStg))
	}
	if enCam.Almacen == nil || enCam.Almacen.Nombre != "PV CAMAGUEY" {
		t.Fatalf("el código 2 de Camagüey tenía que ser PV CAMAGUEY; salió %s", elQueSalio(enCam))
	}
	// Y no son el mismo punto, que es lo que de verdad se cobra distinto.
	if *enStg.Almacen.Latitud == *enCam.Almacen.Latitud {
		t.Fatal("los dos «2» acabaron en el mismo punto: se cruzaron las sucursales")
	}

	// EL NOMBRE NO VALE NI COMO RESPALDO. Un pedido que trae el código `9` —que no existe—
	// no puede acabar midiendo desde «PV-STGO» porque el nombre le suene a nadie.
	porNombre := ElegirOrigenDelPedido([]Almacen{
		almacenDePrueba("1", "AURORA", 20.15, -75.95, false),
		almacenDePrueba("7", "PV-STGO", 20.02, -75.82, true),
	}, "AURORA")
	if porNombre.DelPedido() {
		t.Fatalf("emparejó por NOMBRE: midió desde %q como si fuera el del pedido. "+
			"`PV-STGO` está en Santiago Y en Palma Soriano; un respaldo por nombre no falla "+
			"nunca, sólo mide desde el almacén de otra sucursal", porNombre.Almacen.Nombre)
	}
	if porNombre.Motivo != MotivoAlmacenNoDadoDeAlta {
		t.Errorf("motivo %q: un código que no casa es «no dado de alta», y así se arregla "+
			"dándolo de alta", porNombre.Motivo)
	}
}

// LOS ESPACIOS Y LAS MAYÚSCULAS NO PARTEN EL EMPAREJAMIENTO. Los códigos viajan por dos JSON
// y una base de datos antes de llegar aquí; un « 2» con un espacio delante mediría desde el
// principal y lo apuntaría como «almacén no dado de alta», que manda a alguien a dar de alta
// un almacén que ya está.
func TestElCodigoSeEmparejaSinEspaciosNiMayusculas(t *testing.T) {
	lista := []Almacen{
		almacenDePrueba("PV-STGO", "PV-STGO", 20.02, -75.82, true),
		almacenDePrueba("aurora", "AURORA", 20.15, -75.95, false),
	}
	for _, pide := range []string{"AURORA", " aurora ", "Aurora"} {
		o := ElegirOrigenDelPedido(lista, pide)
		if !o.DelPedido() || o.Almacen.Nombre != "AURORA" {
			t.Errorf("con %q no encontró su almacén: motivo %q", pide, o.Motivo)
		}
	}
}

// LA LISTA DE QUIEN LLAMA NO SE TOCA, y el puntero apunta a la fila DE VERDAD.
//
// `ElegirOrigenDelPedido` elige entre un subconjunto —los que casan con el código— y la
// tentación es copiar esos a otra rebanada. Entonces el puntero devuelto apunta a la COPIA:
// parece bueno, mide bien, y cualquiera que se fíe de la dirección para escribir algo al lado
// lo escribe en una fila que no existe. Es la misma guarda que
// `TestElegirAlmacenNoReordenaLaListaDeQuienLlama` pone para la otra función.
func TestElOrigenDelPedidoApuntaALaFilaDeVerdad(t *testing.T) {
	lista := losDeSantiago()
	o := ElegirOrigenDelPedido(lista, "2")

	if o.Almacen != &lista[1] {
		t.Fatal("el puntero no es el de la fila elegida dentro de la lista original")
	}
	if lista[0].Codigo != "1" || lista[1].Codigo != "2" || lista[2].Codigo != "3" {
		t.Fatalf("la lista de quien llama salió reordenada: %q, %q, %q",
			lista[0].Codigo, lista[1].Codigo, lista[2].Codigo)
	}
}

// --------------------------------------------------------------------------- la distancia

// Y LO QUE DE VERDAD IMPORTA: QUE LA DISTANCIA SALGA DISTINTA.
//
// Todo lo de arriba comprueba QUÉ almacén se elige. Esto comprueba que de esa elección sale
// **otro número de kilómetros**, que es lo que se cobra. Sin esta prueba, un
// `ElegirOrigenDelPedido` que devolviera el principal con el motivo bueno pasaría media suite.
func TestDesdeDosAlmacenesLaDistanciaEsDistinta(t *testing.T) {
	cliente := Punto{Lat: 20.0250, Lng: -75.8150} // a un par de km de PV-STGO
	lista := losDeSantiago()

	desdePrincipal := ElegirOrigenDelPedido(lista, "")
	desdeAurora := ElegirOrigenDelPedido(lista, "2")

	kmPrincipal := DistanciaEntre(desdePrincipal.Almacen.Punto(), cliente)
	kmAurora := DistanciaEntre(desdeAurora.Almacen.Punto(), cliente)

	// AURORA está a ~20 km del centro de Santiago; PV-STGO, a menos de uno. Si estos dos
	// números salieran iguales, es que se midió las dos veces desde el mismo sitio.
	if kmPrincipal >= kmAurora {
		t.Fatalf("desde el principal %.3f km y desde AURORA %.3f km: se midió desde el "+
			"mismo punto las dos veces", kmPrincipal, kmAurora)
	}
	if kmAurora-kmPrincipal < 5 {
		t.Fatalf("la diferencia es de %.3f km y los dos almacenes están a más de 15 km: "+
			"el origen no se movió", kmAurora-kmPrincipal)
	}
}
