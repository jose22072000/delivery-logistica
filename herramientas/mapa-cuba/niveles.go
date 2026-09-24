// LOS NIVELES DE DETALLE, que son la respuesta a la pregunta de Jose:
//
// > «los varios metodos que se necesitan para el mapa: si quieres uno mas
// > detallado pues uno mas detallado, pero el necesario son tantos, y asi para
// > poder uno trabajar mas custom.»
//
// Cada nivel es un fichero suyo, con su tamano, y el tamano **se dice antes de
// bajarlo**. Nadie baja 88 MB sin saber que son 88 MB, y menos con los datos de
// Cuba.
//
// LO QUE DECIDE EL TAMANO no es el numero de capas: es **hasta que zoom** se
// generan y **a partir de que zoom entra cada clase de calle**. Una calle
// residencial metida desde el z10 multiplica el fichero sin que nadie la pueda
// leer a ese tamano.
package main

// Las capas. Con nombre y en un solo sitio porque el lector de Dart las busca
// por estas cadenas exactas: cambiarlas aqui y no alli deja el mapa en blanco
// sin un solo error.
const (
	capaCarretera = "carretera"
	capaAgua      = "agua"
	capaCosta     = "costa"
	capaPoblacion = "poblacion"
	// Las tres de 21/09/2026, de comparar la MISMA ruta en el telefono contra
	// la web con teselas de OSM. Lo que faltaba no eran calles: era **lo que
	// hay entre las calles**, que es lo que dice si uno ha llegado o no.
	capaSuelo    = "suelo"
	capaEdificio = "edificio"
	capaTren     = "tren"
)

// capasDeRelleno son las que se pintan como mancha y no como linea. Importa en
// dos sitios y en los dos rompe callado si se olvida: al extraer (un contorno
// sin cerrar no es un poligono) y al clonar (`orb` proyecta MUTANDO, y un
// poligono comparte sus anillos igual que una linea comparte sus puntos).
func esDeRelleno(capa string) bool {
	return capa == capaAgua || capa == capaSuelo || capa == capaEdificio
}

// clasesDeCarretera traduce el `highway=` de OSM a la clase con la que se pinta.
//
// LO QUE NO ESTA AQUI ES LO QUE MAS AHORRA. Un mapa de reparto no necesita
// senderos, escaleras, carriles bici, vias de construccion ni curvas de nivel:
// el camion no pasa por ahi. Cada una de esas capas son megas en el telefono
// del repartidor a cambio de nada.
var clasesDeCarretera = map[string]string{
	"motorway": "autopista", "motorway_link": "autopista",
	"trunk": "carretera", "trunk_link": "carretera",
	"primary": "principal", "primary_link": "principal",
	"secondary": "secundaria", "secondary_link": "secundaria",
	"tertiary": "terciaria", "tertiary_link": "terciaria",
	"unclassified": "calle", "residential": "calle", "living_street": "calle", "road": "calle",
	"service": "servicio",
	"track":   "camino",
}

// clasesDePoblacion: los nucleos que se rotulan. Sin ellos el mapa es una
// telarana de lineas sin un solo sitio reconocible.
var clasesDePoblacion = map[string]string{
	"city": "ciudad", "town": "pueblo", "village": "poblado",
	"suburb": "barrio", "hamlet": "caserio",
}

// clasesDeSuelo traduce el uso del suelo de OSM a la clase con la que se pinta.
//
// POR QUE ESTA CAPA: sin ella el mapa es papel en blanco entre calles. Jose,
// 21/09/2026, comparando las dos vistas de la misma ruta: «nos faltan mas cosas
// q tiene el mapa con conexion q aqui no tenemos». Una mancha verde y una
// mancha gris de casas ubican mas que diez nombres de calle, porque se ven de
// un vistazo y desde lejos.
//
// La clave es `clave=valor` de la etiqueta de OSM, tal cual. Se busca por esa
// cadena y no por dos llamadas a `Find`, para que anadir un uso del suelo sea
// una linea aqui y nada mas.
//
// LO QUE NO ESTA, Y ES A PROPOSITO:
//
//   - `landuse=farmland` y `farmyard`. En Cuba es media isla. Pintarlo todo del
//     mismo color no distingue nada —si todo es campo, nada destaca— y multiplica
//     el fichero. Se cuenta en los descartes para que se vea lo que se dejo.
//   - Cementerios, campos deportivos y colegios: son manchas pequenas que no
//     cambian si uno ha llegado a un portal.
//
// Y UNA QUE SI ESTA DESDE EL 21/09/2026 POR LA TARDE: `natural=wetland`, el
// humedal. Estaba fuera con este motivo escrito aqui mismo —«casi todos estan
// mapeados como relacion, y las relaciones no entran»— y ese motivo se acabo:
// desde que se cosen los multipoligonos (relaciones.go) entran 363 humedales, y
// el mas grande de todos es **la Cienaga de Zapata**, que es el hueco que Jose
// senalo comparando su telefono con la web.
var clasesDeSuelo = map[string]string{
	"leisure=park":              "parque",
	"leisure=garden":            "parque",
	"landuse=recreation_ground": "parque",
	"landuse=village_green":     "parque",

	"natural=wood":   "bosque",
	"landuse=forest": "bosque",
	"natural=scrub":  "bosque",

	// El humedal es CLASE PROPIA y no «bosque de otro verde»: la Cienaga de
	// Zapata son 4.000 km2 y por ahi no se mete un camion, que es justo lo que
	// un mapa de reparto tiene que decir. `natural=marsh` es la forma vieja de
	// escribir lo mismo y sigue puesta en media Cuba.
	"natural=wetland": "humedal",
	"natural=marsh":   "humedal",

	"landuse=grass":     "hierba",
	"landuse=meadow":    "hierba",
	"natural=grassland": "hierba",

	"landuse=residential": "urbano",
	"landuse=commercial":  "urbano",
	"landuse=retail":      "urbano",

	"landuse=industrial": "industrial",
	"landuse=quarry":     "industrial",

	"landuse=port":    "portuario",
	"landuse=harbour": "portuario",
}

// clasesDeTren: las vias por las que pasa un tren de verdad.
//
// Fuera se quedan las de `disused`, `abandoned`, `razed`, `construction` y
// `proposed` —que no son una via, son el recuerdo de una— y los andenes, las
// agujas de patio y los monorrailes. Una via de patio dibujada es una telarana
// gris encima de un almacen.
var clasesDeTren = map[string]string{
	"rail":         "tren",
	"light_rail":   "tren",
	"narrow_gauge": "via_estrecha",
}

// claseDeEdificio es una sola, y esa es la decision: **todos los edificios se
// pintan igual**. Separar naves de viviendas pide etiquetas que en Cuba casi
// nadie pone, y lo que hace falta es la silueta de la manzana, no saber de que
// es cada bloque.
const claseEdificio = "edificio"

// edificiosNuncaPorDebajoDe es el techo del fichero escrito como numero.
//
// Un edificio mide 15 metros. A z13 la tesela entera son 5 km: los edificios de
// La Habana caben en un pixel y son una mancha sucia que tapa las calles. Lo
// que si hacen es **multiplicar el fichero**, porque son cientos de miles de
// poligonos y cada uno cae en todas las teselas de todos los niveles por debajo.
// Por eso no es una preferencia de dibujo: es LA decision de tamano de este
// fichero, y por eso hay una prueba que la vigila.
const edificiosNuncaPorDebajoDe = uint8(14)

// Nivel es un paquete descargable.
type Nivel struct {
	// Clave es el nombre del fichero y lo que viaja en `GET /api/mapa`.
	Clave string
	// Titulo es lo que lee el logistico antes de decidir si lo baja.
	Titulo string
	// Explicacion es la linea de debajo: para que sirve y para que no.
	Explicacion string

	ZoomMax uint8

	// DesdeZoom dice, por clase, a partir de que zoom entra. Una clase que no
	// esta en el mapa no entra nunca en este nivel. **Un mapa vacio no es «desde
	// el z0»: es «este nivel no lo lleva»**, y eso es lo que apaga la capa
	// entera sin tocar una linea de codigo.
	Carreteras  map[string]uint8
	Poblaciones map[string]uint8
	Suelos      map[string]uint8
	Trenes      map[string]uint8
	// Edificios tiene una sola clave posible, `edificio`. Es un mapa y no un
	// numero suelto por lo mismo que los otros cuatro: para que «este nivel no
	// lleva edificios» se escriba quitando la entrada, y no poniendo un cero que
	// significa justo lo contrario.
	Edificios map[string]uint8

	// NombresDesde: por debajo de este zoom no viajan los nombres. Un nombre de
	// calle a z9 no se puede leer y ocupa lo mismo que a z14.
	NombresDesde uint8

	// SinRelaciones apaga los multipoligonos. **Solo para MEDIR**, como
	// `SinCapas`: lo que cuestan los bosques grandes, los humedales y la
	// Cienaga de Zapata es una decision de tamano, y una decision no se toma
	// con una estimacion. No se usa para generar lo que se cuelga.
	SinRelaciones bool

	// ConMundo dice que este paquete lleva la costa del mundo de Natural Earth
	// hasta `CorteDelMundo` (mundo.go). NO se pone a mano: lo pone
	// `ConLaCostaDelMundo`, que es la misma llamada que carga los rasgos, para
	// que no pueda quedar encendido sin ellos.
	ConMundo bool
}

// costaDesde dice DESDE QUE ZOOM viaja la costa de OpenStreetMap.
//
// Es el otro lado de `CorteDelMundo` y por eso sale de aqui y no de una
// constante suelta: con el mundo puesto, la costa de OSM empieza justo donde se
// acaba la del mundo. Ni un zoom antes —serian dos orillas casi iguales en la
// misma tesela, y el pintor cose los trozos por sus extremos EXACTOS: dos que no
// casan son dos cabos sueltos y se queda sin mar— ni un zoom despues, que
// dejaria un nivel entero sin una sola linea de costa.
//
// Sin mundo se queda como estaba desde el principio: **la costa es lo que hace
// que Cuba se reconozca** y viaja desde el z0.
func (n Nivel) costaDesde() uint8 {
	if n.ConMundo {
		return CorteDelMundo + 1
	}
	return 0
}

// aguaDesde es igual en todos los niveles y por eso no esta en `Nivel`: el agua
// interior es lo que explica por que una carretera da un rodeo, y no es
// negociable por tamano.
//
// La costa tenia aqui su gemela `costaDesde` y se la llevo la costa del mundo:
// ahora depende de si el paquete la lleva, asi que es un metodo de `Nivel`.
const aguaDesde = uint8(7)

// Niveles, en el orden en que se le ofrecen a la persona: de menos a mas.
var Niveles = []Nivel{
	{
		Clave:  "basico",
		Titulo: "Sólo carreteras",
		Explicacion: "Las carreteras que unen los pueblos, la costa y los núcleos con su " +
			"nombre. Sirve para ver dónde cae cada parada y por dónde se va; no trae " +
			"las calles de dentro de la ciudad.",
		ZoomMax: 11,
		Carreteras: map[string]uint8{
			"autopista": 5, "carretera": 6, "principal": 8,
			"secundaria": 10, "terciaria": 11,
		},
		Poblaciones: map[string]uint8{"ciudad": 5, "pueblo": 8, "poblado": 10},
		// El verde y la mancha de ciudad entran ya aqui: a z9 una carretera
		// sola no dice si va por dentro de un pueblo o por el monte, y eso es
		// justo lo que se mira en este nivel. La hierba no, que a z11 son
		// motas.
		Suelos: map[string]uint8{
			"bosque": 9, "humedal": 9, "urbano": 9, "industrial": 10, "portuario": 10, "parque": 11,
		},
		Trenes: map[string]uint8{"tren": 9},
		// Sin edificios: este nivel llega a z11 y un edificio a z11 no existe.
		NombresDesde: 9,
	},
	{
		Clave:  "completo",
		Titulo: "Completo, con calles",
		Explicacion: "Todo lo del básico más las calles de las ciudades con su nombre. Es " +
			"el que hace falta para llegar a un domicilio.",
		ZoomMax: 14,
		Carreteras: map[string]uint8{
			"autopista": 5, "carretera": 6, "principal": 8,
			"secundaria": 10, "terciaria": 11, "calle": 13, "servicio": 14,
		},
		Poblaciones: map[string]uint8{
			"ciudad": 5, "pueblo": 8, "poblado": 10, "barrio": 12, "caserio": 12,
		},
		Suelos: map[string]uint8{
			"bosque": 9, "humedal": 9, "urbano": 9, "industrial": 10, "portuario": 10,
			"parque": 11, "hierba": 13,
		},
		Trenes: map[string]uint8{"tren": 9, "via_estrecha": 12},
		// Y AQUI SI, edificios, aunque el nivel se quede en z14. Es la capa que
		// Jose echo de menos primero —«es lo que mas se nota al llegar a una
		// direccion»— y este es el nivel que se ofrece por defecto: dejarla solo
		// en el detallado seria contestar a otra pregunta. Entra en el ultimo
		// zoom del nivel y en ninguno mas; lo que cuesta esta medido en
		// docs/mapa-sin-conexion.md.
		Edificios:    map[string]uint8{"edificio": 14},
		NombresDesde: 9,
	},
	{
		Clave:  "detallado",
		Titulo: "Detallado, con caminos",
		Explicacion: "Todo lo del completo, un nivel de acercamiento más y los caminos de " +
			"tierra. Sólo hace falta si se reparte fuera de la ciudad; ocupa el doble " +
			"que el completo y no añade una sola calle nueva.",
		ZoomMax: 15,
		Carreteras: map[string]uint8{
			"autopista": 5, "carretera": 6, "principal": 8,
			"secundaria": 10, "terciaria": 11, "calle": 13, "servicio": 14, "camino": 14,
		},
		Poblaciones: map[string]uint8{
			"ciudad": 5, "pueblo": 8, "poblado": 10, "barrio": 12, "caserio": 12,
		},
		Suelos: map[string]uint8{
			"bosque": 9, "humedal": 9, "urbano": 9, "industrial": 10, "portuario": 10,
			"parque": 11, "hierba": 13,
		},
		Trenes: map[string]uint8{"tren": 9, "via_estrecha": 12},
		// Los edificios, desde el MISMO z14 que el completo, no desde el z15.
		// El primer intento fue z15 «para no pagar dos veces el z14», y esa
		// cuenta esta mal: **son dos descargas distintas y nadie tiene las
		// dos**. Quien baja el detallado veria a z14 menos manzana que quien
		// bajo el completo, que es justo lo contrario de lo que promete el
		// nivel. Lo caza `TestCadaNivelLlevaTodoLoDelAnterior`.
		Edificios:    map[string]uint8{"edificio": 14},
		NombresDesde: 9,
	},
}

// SinCapas devuelve el mismo nivel con esas capas apagadas.
//
// **Solo para MEDIR.** El tamano de este fichero es una decision, y una decision
// no se toma con una estimacion: se genera con la capa y sin ella y se restan
// los bytes. Eso es lo que hay en la tabla de `docs/mapa-sin-conexion.md`, y esto
// es lo que permite repetirla sin editar el codigo:
//
//	go run . -pbf cuba.osm.pbf -nivel completo -sin edificio,suelo,tren
//
// No se usa para generar lo que se cuelga.
func (n Nivel) SinCapas(capas []string) Nivel {
	for _, c := range capas {
		switch c {
		case capaSuelo:
			n.Suelos = nil
		case capaTren:
			n.Trenes = nil
		case capaEdificio:
			n.Edificios = nil
		case capaPoblacion:
			n.Poblaciones = nil
		case capaCarretera:
			n.Carreteras = nil
		}
	}
	return n
}

// NivelPorClave, para el `-nivel` de la linea de ordenes.
func NivelPorClave(clave string) (Nivel, bool) {
	for _, n := range Niveles {
		if n.Clave == clave {
			return n, true
		}
	}
	return Nivel{}, false
}

// tolerancia es cuanto se simplifica la geometria, en unidades de tesela (la
// tesela mide 4096). Mas alto = menos puntos = menos megas y mas esquinas.
//
// Se afloja en los zooms bajos porque ahi **no se nota**: a z6 la tesela entera
// son 600 km, y dos puntos a 4 unidades de distancia caen en el mismo pixel de
// la pantalla. Es donde esta la mitad del ahorro y no cuesta nada visible.
//
// SE MIRO AFLOJARLA SOLO PARA LAS MANCHAS al coser los multipoligonos, y se
// dejo como estaba: medido sobre el `.pbf` del 21/09/2026, subirla a 8 para
// `suelo` y `agua` por encima del z11 ahorra 2,4 MB en el `completo` y unos 5 en
// el `detallado`, y ninguno de los dos hace falta —el recorte por capa
// (`recorteDe`, en teselar.go) ya los dejo por debajo del techo—. Queda apuntado
// por si un dia el `.pbf` crece y hay que apretar: es lo siguiente que hay que
// tirar, y son cinco lineas.
func tolerancia(z uint8) float64 {
	switch {
	case z <= 8:
		return 8
	case z <= 11:
		return 4
	default:
		return 1.5
	}
}

// toleranciaDelMundo es lo que se simplifica la costa de Natural Earth, que
// viaja sola en la capa `costa` por debajo de z`CorteDelMundo+1`.
//
// SE SIMPLIFICA MAS QUE TODO LO DEMAS, y esto es una decision de tamano MEDIDA,
// no una preferencia. Cada fila es un fichero que se genero y se peso, sobre el
// `.pbf` de Cuba del 22/09/2026 y `ne_10m_land` de esa misma fecha. Lo que anade
// al `basico`, que sin mundo son 5.996.612 bytes:
//
//	tolerancia  8 (la de las demas capas)  10.863.851   +4,87 MB
//	tolerancia 16                           9.452.410   +3,46 MB
//	tolerancia 24 (esta)                    8.783.791   +2,79 MB
//	tolerancia 48                           7.837.583   +1,84 MB
//
// Los otros dos niveles pagan lo MISMO en bytes —el mundo solo esta en z0–z6 y
// es identico en los tres—, asi que el que decide es el `basico`, que es el que
// se baja quien tiene la conexion justa.
//
// Y lo que se pierde a cambio se puede decir en pixeles, que es lo que se ve:
// la tolerancia va en unidades de tesela y una tesela de 4.096 unidades se
// dibuja en 256 pixeles, asi que **24 unidades son 1,5 pixeles de pantalla, en
// cualquier zoom**. Una orilla movida pixel y medio a z6, donde la pantalla
// entera son ~2.500 km. Lo que esta capa tiene que contestar es «donde cae Cuba
// en el Caribe» y «hasta donde llega el mar»; por donde entra un camion lo
// contesta la costa de OSM, que empieza en el zoom siguiente y no se toca.
//
// La comparacion honesta no es contra OSM: es contra el papel en blanco que
// habia antes.
const toleranciaDelMundo = 24.0

// toleranciaDe escoge cuanto se simplifica CADA capa en ese zoom.
//
// Solo hay un caso especial y es la costa del mundo. Se reconoce por donde esta
// —la capa `costa` por debajo de `CorteDelMundo+1`, donde la de OSM no viaja
// (`Nivel.costaDesde`)— y no por una marca en la capa, porque en el formato una
// capa no lleva mas que su nombre.
func toleranciaDe(z uint8, capa string, n Nivel) float64 {
	if n.ConMundo && capa == capaCosta && z <= CorteDelMundo {
		return toleranciaDelMundo
	}
	return tolerancia(z)
}
