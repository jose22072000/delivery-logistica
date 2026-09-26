package cotizar

import (
	"sort"
	"strings"
)

// EL ALMACÉN DE ORIGEN (§10 de reglas-negocio.md y la regla de selección de
// `/api/quote/home-delivery`).
//
// El almacén VIVE EN ACCESOS y no se copia aquí: un almacén copiado se separa del de
// verdad en cuanto alguien mueve unas coordenadas allá, y *con esas coordenadas se mide lo
// que se le cobra al cliente*.

// Almacen es lo que Accesos devuelve de cada almacén de una sucursal.
//
// `Codigo` ES LA IDENTIDAD, JUNTO CON LA SUCURSAL — y no el nombre. Comprobado en Ventra el
// 26/09/2026, y hacen falta las dos mitades:
//
//   - el NOMBRE no identifica: `Tiendas Parranda` existe en cinco sucursales con cinco ids,
//     `Parranda Oferta` en cuatro, y **`PV-STGO` está en Santiago Y en Palma Soriano**;
//   - el CÓDIGO solo tampoco: `objectCode: 2` es AURORA en Santiago, PV CAMAGÜEY en Camagüey
//     y PV GTMO en Guantánamo.
//
// La sucursal va implícita en la lista: aquí sólo llegan los almacenes de UNA, porque quien
// pregunta a Accesos pregunta por su código (`AlmacenesDeSucursal`). Por eso dentro de esta
// función basta con el código — y por eso NO se empareja por nombre ni como respaldo: un
// respaldo por nombre es exactamente el fallo que esto viene a cerrar, y encima uno que no
// falla nunca, sólo mide desde el sitio de otro.
type Almacen struct {
	ID        string   `json:"id"`
	Codigo    string   `json:"codigo"`
	Nombre    string   `json:"nombre"`
	Direccion *string  `json:"direccion"`
	Latitud   *float64 `json:"latitud"`
	Longitud  *float64 `json:"longitud"`
	Principal bool     `json:"principal"`
	Activo    bool     `json:"activo"`
}

// TieneCoordenadas: las dos, no una. Media coordenada no es un punto.
func (a Almacen) TieneCoordenadas() bool { return a.Latitud != nil && a.Longitud != nil }

// Punto del almacén. Sólo tiene sentido con TieneCoordenadas() == true.
func (a Almacen) Punto() Punto { return Punto{Lat: *a.Latitud, Lng: *a.Longitud} }

// SirveParaMedir: las TRES condiciones para que de este almacén pueda salir una distancia.
//
//   - **Activo.** Ver el bloque de `ElegirAlmacen`.
//   - **Con las dos coordenadas.** Media coordenada no es un punto.
//   - **Que no sea (0,0).** Es el golfo de Guinea, no Santiago: un almacén así no tiene
//     coordenadas, las tiene SIN PONER. Medir desde ahí da ~8.600 km y un orden de tarjetas
//     que parece bueno y no lo es. `internal/api` ya lo descartaba antes de llamar aquí
//     (`almacenesConPunto`, del tablero) y la cotización NO, que es otra forma del mismo
//     agujero: la condición vive aquí y una sola vez.
func (a Almacen) SirveParaMedir() bool {
	if !a.Activo || !a.TieneCoordenadas() {
		return false
	}
	return !(*a.Latitud == 0 && *a.Longitud == 0)
}

// ElegirAlmacen aplica la regla de selección del origen, en este orden:
//
//  1. De los que SIRVEN PARA MEDIR (`SirveParaMedir`), el `principal`.
//  2. Si hay varios principales o ninguno, el primero por **nombre ascendente**.
//  3. Si no sirve ninguno, nil — y quien llama contesta
//     `409 «<Sucursal> no tiene ningún almacén con coordenadas»`.
//
// POR QUÉ EL 409 Y NO UN APAÑO: *es desde donde sale la mercancía, que es lo que mide la
// APK.* Sin almacén con coordenadas no se contesta un número aproximado —ni se usan las
// coordenadas de la sucursal, que no son el sitio del que sale la carga—: se dice que no
// se puede. Un número aproximado aquí se cobra igual que uno bueno.
//
// # POR QUÉ `activo` SÍ FILTRA — 24/09/2026
//
// AQUÍ PONÍA LO CONTRARIO, y estaba razonado: «`activo` NO filtra. La regla del pliego
// mira `principal` y las coordenadas, nada más; añadir aquí un filtro por activo cambiaría
// el almacén elegido en sucursales que tienen uno dado de baja con coordenadas buenas, y
// con él el importe». El aviso era cierto —cambia el importe— pero la conclusión era la
// mala: lo que había no era «no tocar esto», era que el servidor y el aparato elegían
// almacenes DISTINTOS, y ninguna prueba lo decía. `AlmacenDeReferencia` (el aparato) sí
// filtraba `activo`, y el Panel, el Tablero y Clientes con él: tres de los cuatro
// consumidores contra éste.
//
// LO QUE SE VEÍA. Una sucursal con dos almacenes, el principal dado de baja con
// coordenadas buenas y otro activo:
//
//   - el **Tablero** ordena las tarjetas midiendo desde el ACTIVO (lo resuelve en local);
//   - en la **web**, «Armar la ruta de esta zona» sale por `POST /board/columns/{id}/route`
//     y el servidor calculaba el origen aquí → el DE BAJA;
//   - en la **APK** esa misma acción se resuelve en local y escribe `origin_lat/lng` del
//     ACTIVO.
//
// El mismo botón, dos orígenes y **dos kilometrajes** según se pulse en el navegador o en
// el teléfono. Y esos km son los del cobro. Jose, 24/09/2026:
//
//	«no puede dar distinto, debe dar igual. ¿Cómo que distinto si es la misma API los
//	dos? No tienen que elegir distinto, eso debe dar igual en todos los datos. Es un
//	lugar distinto pero ya más nada.»
//
// Una sola regla, el mismo almacén elegido en todas partes, y la que gana es la de los
// tres: un almacén dado de baja NO cuenta. Es además el caso más caro que hay, porque sus
// coordenadas son buenas: la cuenta sale, el número es creíble y ninguna pantalla lo
// desmiente (`CLAUDE.md` §4, «el dato está y no se escribe» en su forma peor).
//
// LO QUE LO ATA, y no este comentario —un comentario no falla (`CLAUDE.md` §3-bis)—:
// `docs/almacen-de-origen.casos.json`, el MISMO fichero que leen
// `almacen_casos_compartidos_test.go` de aquí y
// `app/test/nucleo/almacenes/almacen_de_origen_casos_compartidos_test.dart` del aparato.
// Tocar un lado y no el otro pone en rojo la prueba del otro.
//
// # Y EL DESEMPATE POR NOMBRE, QUE TAMPOCO ERA EL MISMO
//
// Esto devolvía «el primero de la lista» y la lista la sirve Accesos por HTTP; el aparato
// lee la suya de SQLite con `ORDER BY principal DESC, nombre ASC`. Dos sucursales con dos
// almacenes buenos y ninguno principal elegían distinto sin que nada fallara, por el mismo
// motivo que el `activo`. El desempate va aquí dentro y no en quien llama: así no depende
// del orden en que a nadie se le ocurra servir la lista.
func ElegirAlmacen(almacenes []Almacen) *Almacen {
	todos := make([]int, len(almacenes))
	for i := range almacenes {
		todos[i] = i
	}
	return elegirEntre(almacenes, todos)
}

// elegirEntre aplica la regla sobre un SUBCONJUNTO de la lista, dado por sus índices.
//
// VA POR ÍNDICES Y NO POR UNA REBANADA NUEVA a propósito: `ElegirAlmacenDelPedido` tiene que
// elegir entre los que casan con un código, y si para eso copiara los candidatos a otra
// rebanada devolvería un puntero a la COPIA. Quien llama se guarda ese puntero y cree que
// apunta a la fila de su lista —`TestElegirAlmacenNoReordenaLaListaDeQuienLlama` fija que
// apunta a la de verdad—, así que una copia sería un puntero que parece bueno y no lo es.
func elegirEntre(almacenes []Almacen, candidatos []int) *Almacen {
	sirven := make([]int, 0, len(candidatos))
	for _, i := range candidatos {
		if almacenes[i].SirveParaMedir() {
			sirven = append(sirven, i)
		}
	}
	if len(sirven) == 0 {
		return nil
	}
	// Se ordenan los ÍNDICES: la lista de quien llama no se toca. `sort.SliceStable` sobre
	// un criterio total (principal y luego nombre) para que dos lecturas seguidas den
	// siempre el mismo — si los km de la misma tarjeta bailan, nadie se fía de ninguno.
	// El `Nombre` desempata al `Principal` y el `ID` al `Nombre`, que es lo único que queda
	// cuando dos almacenes se llaman igual. Es el mismo criterio, en el mismo orden, que
	// `AlmacenDeReferencia.elegir` del aparato.
	sort.SliceStable(sirven, func(x, y int) bool {
		a, b := almacenes[sirven[x]], almacenes[sirven[y]]
		if a.Principal != b.Principal {
			return a.Principal
		}
		if a.Nombre != b.Nombre {
			return a.Nombre < b.Nombre
		}
		return a.ID < b.ID
	})
	return &almacenes[sirven[0]]
}

// ---------------------------------------------------------------------------
// EL ALMACÉN DEL PEDIDO
// ---------------------------------------------------------------------------

// MotivoDelOrigen dice DESDE DÓNDE se midió y POR QUÉ. Se guarda en
// `orders.almacen_salida_motivo` (migración 00012) y viaja en la respuesta del lote.
//
// EXISTE PORQUE NADA SE DESCARTA EN SILENCIO (`CLAUDE.md` §4). Sin esto, un kilometraje
// medido desde el principal porque el almacén del pedido no estaba dado de alta es
// exactamente igual —mismo tipo, mismos decimales, misma tarjeta— que uno medido desde el
// almacén bueno. Y lo que no se distingue no se arregla: el caso del 26/09/2026 llevaba
// meses así y sólo se vio cuando la sesión de PEDIDO contó los renglones por almacén.
type MotivoDelOrigen string

const (
	// MotivoAlmacenDelPedido: se midió desde el almacén que trae el pedido. Lo normal.
	MotivoAlmacenDelPedido MotivoDelOrigen = "almacen-del-pedido"
	// MotivoPedidoSinAlmacen: el pedido no trae almacén. Pasa con todo lo bajado antes de
	// que PEDIDO empezara a mandar el campo, y con lo que entra antes de facturarse.
	MotivoPedidoSinAlmacen MotivoDelOrigen = "el-pedido-no-trae-almacen"
	// MotivoAlmacenNoDadoDeAlta: lo trae y no está en Accesos. VA A PASAR: el 26/09/2026
	// había un `28 · PTO MONEDERO` en Santiago con 11 líneas. Se arregla dándolo de alta.
	MotivoAlmacenNoDadoDeAlta MotivoDelOrigen = "almacen-no-dado-de-alta"
	// MotivoAlmacenSinCoordenadas: está dado de alta y sin punto. ES EL CASO NORMAL DE ESTA
	// SEMANA y no un fallo: los 6 almacenes nuevos se dieron de alta SIN punto a propósito
	// —los ponen los logísticos— así que el dato llega antes que las coordenadas.
	MotivoAlmacenSinCoordenadas MotivoDelOrigen = "almacen-sin-coordenadas"
	// MotivoAccesosSinCodigos: NINGÚN almacén de esa sucursal tiene código en Accesos, así
	// que no había con qué emparejar.
	//
	// ES UN MOTIVO APARTE Y NO «no dado de alta», aunque el resultado sea el mismo, porque
	// SE ARREGLA EN OTRO SITIO Y POR OTRA PERSONA: aquí no falta ningún almacén, faltan los
	// códigos de los que ya están. Con un solo motivo las dos tareas se leen igual y la que
	// toca de verdad —abrir la pantalla de Almacenes y rellenar 14 códigos— no se ve.
	MotivoAccesosSinCodigos MotivoDelOrigen = "accesos-sin-codigos"
	// MotivoSucursalSinAlmacen: no había NI UN almacén con punto, así que se midió desde las
	// coordenadas de la SUCURSAL.
	//
	// VA SIEMPRE COMPUESTO con el motivo del almacén del pedido, separados por `+`:
	// `sucursal-sin-almacen-con-punto+almacen-no-dado-de-alta`. Nunca sale solo, y eso es a
	// propósito: son DOS preguntas —desde dónde se midió, y qué pasó con el almacén que traía
	// el pedido— y con un solo valor se perdía la segunda. En una sucursal cuyos almacenes
	// están todos sin coordenadas —el estado de los 6 nuevos— un `28 · PTO MONEDERO` que
	// llega sin dar de alta quedaba apuntado sólo como «la sucursal no tiene almacén», y
	// entonces el almacén desconocido no aparecía como desconocido en ningún sitio: la
	// confesión perdía justo el dato por el que existe.
	//
	// ES EL PEOR DE LOS SEIS y por eso tiene sus propias palabras. El punto de la sucursal
	// **no es el sitio del que sale la carga** —está escrito arriba, y es la razón de que
	// `/api/quote/home-delivery` conteste 409 en vez de aproximar—. En la puerta del lote no
	// se puede contestar 409: `/api/quote/batch` es LA PUERTA de los pedidos y rechazar uno
	// es perderlo. Así que se mide con lo único que hay y se dice con otras palabras: si
	// compartiera confesión con «desde el principal», el caso peor sería el único invisible.
	MotivoSucursalSinAlmacen MotivoDelOrigen = "sucursal-sin-almacen-con-punto"
)

// OrigenDelPedido es desde dónde se mide ESE pedido, y por qué.
//
// `Almacen` nil significa que no hay ningún almacén del que salga una distancia; entonces el
// motivo es `MotivoSucursalSinAlmacen` y quien llama decide: el lote mide desde la sucursal
// —no puede rechazar un pedido— y `/api/quote/home-delivery` contesta 409, porque un importe
// aproximado se cobra igual que uno bueno.
type OrigenDelPedido struct {
	Almacen *Almacen
	Motivo  MotivoDelOrigen
}

// DelPedido: si de verdad se midió desde el almacén que trae el pedido.
func (o OrigenDelPedido) DelPedido() bool { return o.Motivo == MotivoAlmacenDelPedido }

// ElegirOrigenDelPedido elige el almacén DE ESE PEDIDO, no el principal de la sucursal.
//
// # QUÉ SE ARREGLA AQUÍ, con los números delante (26/09/2026)
//
// Mientras cada sucursal tuvo un solo almacén, «el almacén de la sucursal» y «el almacén del
// pedido» eran la misma frase. Dejó de serlo. La sesión de PEDIDO contó sus renglones:
//
//	SANTIAGO      2.185 líneas desde AURORA · 804 desde PV-STGO · 11 desde PTO MONEDERO
//	CAMAGÜEY      2.778 desde PV CAMAGÜEY   · 183 desde FLORIDA · 39 desde ALM CAMAGÜEY
//	GUANTÁNAMO    2.060 desde PV GTMO       · 940 desde ALM CENTRAL
//
// En Santiago **dos de cada tres pedidos salen de AURORA** y se medían todos desde PV-STGO,
// que es el principal. De esos kilómetros sale el costo del domicilio: no es una pantalla
// torcida, es un número con decimales que nadie puede desmentir mirándolo.
//
// # LA IDENTIDAD ES EL CÓDIGO, NUNCA EL NOMBRE
//
// Ver el bloque de `Almacen`. Y no hay respaldo por nombre ni «por si acaso»: un respaldo por
// nombre no falla nunca, sólo mide desde el almacén de otra sucursal.
//
// # LA CASCADA, Y POR QUÉ CADA ESCALÓN CONFIESA
//
//  1. El pedido trae código y casa con uno que SIRVE PARA MEDIR → ése. Lo normal.
//  2. El pedido no trae código → el principal, y se dice.
//  3. Trae uno que no casa con ninguno → el principal, y se dice CUÁL de las dos cosas pasa:
//     que ese almacén no está dado de alta, o que en esa sucursal NINGUNO tiene código en
//     Accesos todavía (dos arreglos distintos, ver `MotivoAccesosSinCodigos`).
//  4. Casa pero ninguno de los que casan tiene punto → el principal, y se dice. **Esto es lo
//     normal estos días y no un fallo**: los 6 almacenes nuevos se dieron de alta sin punto a
//     propósito, así que el dato llega antes que las coordenadas.
//  5. No hay NI UN almacén con punto en la sucursal → nil, y quien llama decide.
//
// Nunca se devuelve nil por culpa del almacén del pedido: un almacén que no se pudo usar
// degrada al principal, no tira el pedido. Rechazar un pedido en la puerta es perderlo, y
// perder un pedido no es proteger un número.
func ElegirOrigenDelPedido(almacenes []Almacen, codigoDelPedido string) OrigenDelPedido {
	principal := ElegirAlmacen(almacenes)
	// `principal` nil se contesta con el motivo del peor caso COMPUESTO con el del pedido:
	// son dos preguntas —desde dónde se midió, y qué pasó con el almacén que traía el
	// pedido— y quedarse con una sola pierde la otra. Ver `MotivoSucursalSinAlmacen`.
	conPrincipal := func(m MotivoDelOrigen) OrigenDelPedido {
		if principal == nil {
			return OrigenDelPedido{Motivo: motivoSinNingunAlmacen(m)}
		}
		return OrigenDelPedido{Almacen: principal, Motivo: m}
	}

	cod := codigoNormalizado(codigoDelPedido)
	if cod == "" {
		return conPrincipal(MotivoPedidoSinAlmacen)
	}

	casan := make([]int, 0, 2)
	algunoConCodigo := false
	for i := range almacenes {
		suyo := codigoNormalizado(almacenes[i].Codigo)
		if suyo != "" {
			algunoConCodigo = true
		}
		if suyo != "" && suyo == cod {
			casan = append(casan, i)
		}
	}
	if len(casan) == 0 {
		// DOS COSAS DISTINTAS CON EL MISMO RESULTADO, separadas a propósito. Si ningún
		// almacén de la sucursal tiene código, el que falta no es un almacén: son los
		// códigos. Mientras Accesos no los exponga, TODOS los pedidos caen aquí — y lo que
		// hay que ver entonces es eso, no catorce almacenes acusados de no existir.
		if !algunoConCodigo {
			return conPrincipal(MotivoAccesosSinCodigos)
		}
		return conPrincipal(MotivoAlmacenNoDadoDeAlta)
	}
	// Entre varios con el mismo código —no debería haberlos, (sucursal, código) es único—
	// gana la misma regla de siempre, para que dos lecturas seguidas no midan distinto.
	if elegido := elegirEntre(almacenes, casan); elegido != nil {
		return OrigenDelPedido{Almacen: elegido, Motivo: MotivoAlmacenDelPedido}
	}
	return conPrincipal(MotivoAlmacenSinCoordenadas)
}

// motivoSinNingunAlmacen compone los dos hechos. Ver `MotivoSucursalSinAlmacen`.
func motivoSinNingunAlmacen(delPedido MotivoDelOrigen) MotivoDelOrigen {
	return MotivoSucursalSinAlmacen + "+" + delPedido
}

// codigoNormalizado: sin espacios y en mayúsculas, el mismo criterio con el que se indexan
// los códigos de sucursal (`AlmacenesDeSucursal`). Los de Ventra son números («2», «28»),
// pero normalizar cuesta nada y el día que sean letras no hay que acordarse.
func codigoNormalizado(s string) string { return strings.ToUpper(strings.TrimSpace(s)) }
