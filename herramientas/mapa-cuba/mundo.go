// LA COSTA DEL MUNDO, para poder alejar el mapa sin que se acabe el mar.
//
// > «se puede traer otra parte de osm para tener el mundo completo asi podemos
// > alejar el mapa mas aun y tener la costa pero solo detallado tener cuba
// > entiendes»
// > — Jose, 22/09/2026
//
// ## De dónde viene el problema
//
// **El océano no es un polígono en OpenStreetMap, ni aquí ni en ningún sitio.**
// Lo único que hay es `natural=coastline`, una LÍNEA. Por eso el paquete nunca
// trajo el mar y el pintor lo deduce de la costa dentro de cada tesela
// (`marDeLaCosta`, en `app/lib/mapa/fondo_del_paquete.dart`), aprovechando que
// en OSM una línea de costa se camina SIEMPRE con la tierra a la izquierda.
//
// Eso funciona y tiene el límite que tenía que tener: **donde se acaba la costa
// cubana, se acaba el mar**. El extracto de Geofabrik es Cuba, así que al
// alejar aparece papel en blanco a partir de unos cientos de kilómetros de
// Cabo San Antonio y el mapa deja de parecer un mapa.
//
// ## Por qué Natural Earth y no `osmcoastline`
//
// Las dos vías razonables eran:
//
//   - **`osmcoastline`** sobre un extracto de OSM. Es lo que usa el propio
//     proyecto para armar sus polígonos de tierra, y da el mismo dato que ya
//     tenemos para Cuba. El precio es el extracto: para tener «el mundo» hace
//     falta el planeta entero (~80 GB comprimidos) o cosérselo de veinte
//     extractos continentales, más un binario de C++ con libosmium que aquí no
//     está instalado. Todo eso para un dato que a z0–z6 **no se puede
//     distinguir del de Natural Earth**: a z6 la simplificación de este
//     generador ya tira cualquier detalle por debajo de ~1,2 km (`tolerancia`,
//     en niveles.go).
//   - **Natural Earth**, que es lo que se eligió. Viene ya resuelto —polígonos
//     de tierra cerrados, con sus agujeros— en la escala exacta que hace falta
//     para los zooms de alejar, y es un fichero de 10 MB que se baja en
//     segundos.
//
// ## La licencia, que es parte de la decisión
//
//   - **Natural Earth es DOMINIO PÚBLICO.** Sus propias palabras: «no permission
//     is needed», y ni siquiera exige atribución. Aun así se anuncia en los
//     metadatos del `.pmtiles` (`AtribucionDelMundo`), porque un paquete que no
//     dice de dónde salen sus datos no se puede auditar desde fuera.
//   - **OpenStreetMap es ODbL**, y eso SÍ obliga: la atribución viaja dentro del
//     fichero y sale en la pantalla, y ahí no se toca nada. Lo de Cuba sigue
//     siendo de OSM.
//
// Mezclarlas no plantea ningún problema de licencia porque son dos capas que no
// se derivan la una de la otra: el mundo es de Natural Earth **hasta z6** y Cuba
// es de OSM **de z7 para arriba**. No hay ni un byte de OSM dentro de lo que
// sale de Natural Earth.
//
// ## Por qué los POLÍGONOS de tierra y no `ne_10m_coastline`
//
// Natural Earth publica también la costa como líneas (`ne_10m_coastline`), que
// parece lo obvio porque nuestra capa es de líneas. **No se usa, y es la
// decisión más importante de este fichero.**
//
// El pintor no dibuja una raya: deduce el mar de qué lado queda la tierra, y
// eso lo saca del SENTIDO en que está escrita la línea. La regla de OSM —tierra
// a la izquierda— es una regla del proyecto, con validadores que la vigilan.
// **Natural Earth no promete nada parecido para su capa de líneas**: no está
// escrito en su documentación, y una línea escrita al revés no da ningún error,
// no cambia el tamaño del fichero y no se ve en `-comprobar`. Lo único que hace
// es pintar el Atlántico del color de la tierra y Florida del color del agua.
//
// De un POLÍGONO, en cambio, el sentido se sabe: el anillo de fuera encierra
// tierra. Así que se toma `ne_10m_land`, se le miden los anillos y se escriben
// con el sentido que hace falta, sin fiarse de cómo vinieran (`enderezarAlMar`).
//
// Y el sentido que hace falta está MEDIDO, no supuesto: cosiendo los trozos de
// `natural=coastline` del `.pbf` de Cuba del 22/09/2026 salen 4.406 anillos
// cerrados y **los 4.406 giran CCW en lon/lat** —el mayor es la isla, 103.153
// puntos, caja -84,95/19,83 → -74,13/23,21—. Ésa es la referencia contra la que
// se enderezan los de Natural Earth, y está escrita como prueba en
// `TestLaCostaDelMundoGiraComoLaDeOsm`.
package main

import (
	"fmt"
	"math"

	"github.com/paulmach/orb"
	"github.com/paulmach/orb/geojson"
)

// CorteDelMundo es EL ÚLTIMO ZOOM que lleva la costa del mundo. De aquí para
// arriba manda la costa de OSM, que es la de Cuba y es la buena.
//
// ## Por qué z6 y no otro
//
// Los dos lados de la cuenta:
//
//   - **Por abajo no hay elección**: z0 es el mundo entero en una tesela y es
//     donde hay que llegar para que «alejar» no se acabe nunca.
//   - **Por arriba manda el detalle.** A z6 una tesela son 5,6° (~620 km) y la
//     simplificación de este generador usa tolerancia 8 sobre 4096 unidades, o
//     sea que ya tira todo lo que mida menos de ~1,2 km. Natural Earth 1:10M
//     tiene justo esa resolución: por debajo de z7 **no se le nota que no es
//     OSM**. De z7 para arriba sí se le notaría, y ahí es donde empieza Cuba.
//
// Y la otra mitad, que es la que evita pintar dos veces: **por debajo de z7 la
// costa de OSM NO viaja** (ver `Nivel.costaDesde`). Las dos costas a la vez en
// la misma tesela serían la misma orilla dibujada dos veces con geometrías
// parecidas pero no iguales, y el pintor cose los trozos por sus extremos
// EXACTOS: dos cadenas que no casan son dos cabos sueltos en mitad del cuadro,
// que es justo el caso en el que se rinde y deja la tesela sin mar.
//
// Lo que NO se pierde por cortar aquí: a partir de z7 el pintor, cuando una
// tesela no tiene costa, sube hasta cuatro niveles buscando un antepasado que
// sí la tenga (`saltosParaElMar`, en `fondo_del_paquete.dart`). Con el mundo
// hasta z6, un z10 en mitad del Golfo encuentra su antepasado z6 y se pinta de
// mar. Por eso esto no arregla sólo los zooms de alejar: arregla el mar hasta
// z10 en todo el planeta.
const CorteDelMundo = uint8(6)

// AtribucionDelMundo va en los metadatos del `.pmtiles` al lado de la de OSM.
//
// Natural Earth no la exige —es dominio público— pero se pone igual: lo que
// dice de dónde salen los datos no es un trámite de licencia, es lo que permite
// mirar un paquete dentro de dos años y saber qué se está viendo.
const AtribucionDelMundo = "Natural Earth 1:10m (dominio público)"

// latMaximaDeMercator es donde se corta el mundo en Mercator web.
//
// Mercator no llega a los polos: a 90° la proyección se va a infinito. Los
// puntos de la Antártida que bajan de aquí se recortan a esta latitud, que es
// exactamente lo que hace cualquier mapa de teselas. Se recorta ANTES de mirar
// el sentido de giro, porque recortar cambia el área del anillo y el sentido
// sale del signo del área.
//
// El valor es un pelo menos que el límite de verdad (85,05112878) a propósito:
// clavado en el límite, `aY` da exactamente `1<<z` y el reparto por teselas
// descarta esa fila por caer fuera del mundo.
const latMaximaDeMercator = 85.0

// LeerElMundo saca de `ne_10m_land.geojson` los rasgos de costa del mundo.
//
// Devuelve LÍNEAS en la capa `costa`, no polígonos, porque es la capa que ya
// existe y la que el pintor sabe leer: **no hace falta tocar el aparato para
// que esto se vea**. Cada anillo de tierra sale como una línea cerrada con el
// sentido de OSM.
//
// `descartes` se rellena igual que en el extractor: lo que se queda fuera se
// dice, con su motivo y su número.
func LeerElMundo(datos []byte, descartes map[string]int) ([]Rasgo, error) {
	fc, err := geojson.UnmarshalFeatureCollection(datos)
	if err != nil {
		return nil, fmt.Errorf("el fichero del mundo no es un GeoJSON legible: %w", err)
	}

	var rasgos []Rasgo
	anillos := func(p orb.Polygon, desde uint8) {
		for i, anillo := range p {
			recortado := recortarAMercator(anillo)
			// Cuatro puntos es el mínimo de un anillo de verdad: tres esquinas
			// más la repetida del cierre. Con menos no encierra nada y el
			// pintor no puede coserlo contra ningún borde.
			if len(recortado) < 4 {
				descartes["anillo del mundo sin área"]++
				continue
			}
			// EL DE FUERA ENCIERRA TIERRA; los de dentro encierran agua (el mar
			// Caspio dentro de Asia). Por eso el sentido que se les pide es el
			// contrario, igual que un agujero de un multipolígono.
			quiere := orb.CCW
			if i > 0 {
				quiere = orb.CW
			}
			enderezarAlMar(recortado, quiere)
			linea := orb.LineString(recortado)
			rasgos = append(rasgos, Rasgo{
				Geo:  linea,
				Capa: capaCosta,
				// Desde sale de la propia Natural Earth. Ver `desdeQueZoom`.
				// La MISMA clase que la costa de OSM, a propósito: el pintor
				// busca por esa cadena y el mar se deduce de las dos juntas.
				// Una clase propia («mundo») dejaría la costa del mundo sin
				// color y sin mar, sin un solo error.
				Clase:    "costa",
				Desde:    desde,
				DelMundo: true,
				Caja:     linea.Bound(),
			})
		}
	}

	for _, f := range fc.Features {
		desde, entra := desdeQueZoom(f)
		if !entra {
			// Lo que Natural Earth no ensena hasta un zoom al que este paquete
			// no llega. Ahi dentro va, entre otras cosas, la «Null island» que
			// el proyecto pone a proposito en 0,0: un cuadradito de cinco
			// puntos que no es tierra de nadie y que se pintaria como una isla.
			descartes["tierra que Natural Earth no enseña hasta pasado el corte"]++
			continue
		}
		switch g := f.Geometry.(type) {
		case orb.Polygon:
			anillos(g, desde)
		case orb.MultiPolygon:
			for _, p := range g {
				anillos(p, desde)
			}
		default:
			// Una capa de LÍNEAS aquí sería `ne_10m_coastline`, que es
			// exactamente el fichero que no se puede usar: de una línea no se
			// sabe de qué lado queda la tierra. Ver la cabecera del fichero.
			return nil, fmt.Errorf(
				"el fichero del mundo trae geometrías %T; hacen falta polígonos de tierra "+
					"(ne_10m_land.geojson), no líneas de costa", g)
		}
	}
	if len(rasgos) == 0 {
		// Una respuesta vacía no es una respuesta buena (`CLAUDE.md` §3). Un
		// GeoJSON de otra cosa, o bajado a medias, se lee sin un solo error y
		// deja cero anillos — y entonces el paquete sale sin mundo, pesando
		// menos, sin que nadie se entere.
		return nil, fmt.Errorf("el fichero del mundo no dejó ni un anillo de tierra: ¿es ne_10m_land.geojson?")
	}
	return rasgos, nil
}

// ConLaCostaDelMundo carga el mundo y devuelve el nivel YA AJUSTADO.
//
// **Las dos cosas van juntas en una sola llamada a propósito.** Encender el
// mundo mueve la costa de OSM de z0 a z7 (`Nivel.costaDesde`), y si una de las
// dos se hiciera sin la otra el fallo sería mudo en los dos sentidos: con el
// nivel ajustado y sin rasgos, **z0–z6 se quedan sin una sola línea de costa y
// sin mar en todo el planeta**; con los rasgos y sin ajustar el nivel, la misma
// orilla de Cuba viajaría dos veces y el pintor no sabría coserla.
//
// Con la ruta vacía no pasa nada de eso: se devuelve el nivel tal cual y el
// paquete sale como salía antes.
func ConLaCostaDelMundo(datos []byte, n Nivel, descartes map[string]int) (Nivel, []Rasgo, error) {
	if len(datos) == 0 {
		return n, nil, nil
	}
	rasgos, err := LeerElMundo(datos, descartes)
	if err != nil {
		return n, nil, err
	}
	n.ConMundo = true
	return n, rasgos, nil
}

// recortarAMercator corta el anillo a las latitudes que Mercator sabe pintar.
//
// Se hace copiando y no en sitio porque el anillo viene del GeoJSON y se mira
// dos veces (aquí y al calcular la caja): mutar lo que otro lee es el mismo
// fallo que arreglaba `clonar` en teselar.go.
func recortarAMercator(a orb.Ring) orb.Ring {
	fuera := false
	for _, p := range a {
		if p[1] > latMaximaDeMercator || p[1] < -latMaximaDeMercator {
			fuera = true
			break
		}
	}
	if !fuera {
		return append(orb.Ring(nil), a...)
	}
	copia := make(orb.Ring, len(a))
	for i, p := range a {
		if p[1] > latMaximaDeMercator {
			p[1] = latMaximaDeMercator
		} else if p[1] < -latMaximaDeMercator {
			p[1] = -latMaximaDeMercator
		}
		copia[i] = p
	}
	return copia
}

// enderezarAlMar pone el anillo a girar como lo hace la costa de OSM.
//
// OJO CON EL SISTEMA DE COORDENADAS, que es donde esto se rompe callado: aquí
// se mide en **lon/lat**, con la Y hacia el NORTE, y ahí «tierra a la
// izquierda» es CCW. Su primo `enderezarAnillo` (teselar.go) mide en
// coordenadas de TESELA, con la Y hacia abajo, y por eso pide lo contrario para
// lo que es lo mismo. Las dos funciones dicen `orb.CCW` y no significan lo
// mismo; son dos espejos distintos y por eso no se comparten.
func enderezarAlMar(a orb.Ring, quiere orb.Orientation) {
	if len(a) < 4 {
		return
	}
	if a.Orientation() != quiere {
		a.Reverse()
	}
}

// desdeQueZoom saca de Natural Earth **su propia** recomendacion de desde que
// zoom se ensena cada grupo de tierra, y dice si llega a entrar.
//
// No es un invento nuestro: el fichero trae un `min_zoom` por grupo —0 para los
// continentes, 5 y 6 para los 2.349 islotes— y es exactamente la misma pregunta
// que este generador le hace a cada clase de calle o de suelo.
//
// **Lo que ahorra es poco y esta medido**: 24.554 bytes del `basico` (8.808.345
// con todo desde el z0 contra 8.783.791 con esto). No se queda por los bytes,
// se queda por la «Null island»: el simplificador ya tira sola la isla que no
// tiene tamano, pero un cuadradito de cinco puntos en 0,0 no se cae por
// pequeno, se cae porque no es tierra.
//
// Se redondea HACIA ABAJO: un `min_zoom` de 1,5 significa que a z1 ya se
// empieza a ver, y esconder tierra que existe es peor que dibujarla un zoom
// antes de tiempo — el simplificador ya tira sola la que no tiene tamano.
//
// Sin `min_zoom` se ensena desde el z0. **Es a proposito**: no saber cuando se
// ensena una isla no es una razon para no ensenarla, y una isla sin tamano se
// cae sola al simplificar.
func desdeQueZoom(f *geojson.Feature) (uint8, bool) {
	valor, hay := f.Properties["min_zoom"]
	if !hay || valor == nil {
		return 0, true
	}
	n, es := valor.(float64)
	if !es {
		return 0, true
	}
	if n < 0 {
		return 0, true
	}
	if n > float64(CorteDelMundo) {
		return 0, false
	}
	return uint8(math.Floor(n)), true
}
