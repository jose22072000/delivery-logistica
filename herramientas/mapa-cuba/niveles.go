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
)

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
	// esta en el mapa no entra nunca en este nivel.
	Carreteras  map[string]uint8
	Poblaciones map[string]uint8

	// NombresDesde: por debajo de este zoom no viajan los nombres. Un nombre de
	// calle a z9 no se puede leer y ocupa lo mismo que a z14.
	NombresDesde uint8
}

// aguaDesde y costaDesde son iguales en todos los niveles y por eso no estan en
// `Nivel`: **la costa es lo que hace que Cuba se reconozca** —es una isla— y el
// agua interior es lo que explica por que una carretera da un rodeo. Ninguna de
// las dos es negociable por tamano; las dos juntas son una fraccion del
// fichero.
const (
	costaDesde = uint8(0)
	aguaDesde  = uint8(7)
)

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
		Poblaciones:  map[string]uint8{"ciudad": 5, "pueblo": 8, "poblado": 10},
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
		NombresDesde: 9,
	},
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
