// LOS MULTIPOLIGONOS: LO QUE NO CABE EN UNA SOLA VIA.
//
// Hasta el 21/09/2026 este generador tiraba las 13.483 relaciones del `.pbf` de
// Cuba con un motivo escrito a mano: «relación (multipolígono) no soportada».
// Mientras solo hubo carreteras se notaba poco. En cuanto entraron las capas de
// relleno se noto mucho, porque **lo grande de Cuba esta mapeado asi**: los
// bosques de verdad, los humedales y la Cienaga de Zapata no son una via
// cerrada, son una relacion con decenas de trozos de contorno y sus lagunas
// dentro. Fuera de la ciudad quedaban huecos verdes que en el mapa con conexion
// si estan.
//
// ## Que es un multipoligono de OSM, en dos lineas
//
// Una relacion `type=multipolygon` lista vias miembro con un papel: `outer` es
// contorno y `inner` es agujero. **Ninguna de esas vias tiene por que estar
// cerrada**: un contorno de 40 km viene partido en trozos que hay que coser por
// los extremos, y el orden en el que vienen no es el orden en el que encajan.
// Las etiquetas —`natural=wood`, `landuse=residential`— van en la relacion, no
// en las vias, y por eso las vias sueltas no entraban por su cuenta.
//
// ## Dos pasadas, y por que no se puede hacer en una
//
// En un `.pbf` el orden es nodos, vias y relaciones. Al leer una relacion **las
// vias ya pasaron**, asi que o se guardan TODAS las vias en memoria —millones,
// para usar 26.358— o se lee el fichero dos veces. Se lee dos veces, y la
// primera es barata de verdad: `SkipNodes` y `SkipWays` le dicen al lector que
// ni descomprima esos bloques, y la pasada entera son **0,2 segundos**. Lo que
// sale de ahi es la lista de que vias hacen falta; la segunda pasada, la de
// siempre, se guarda solo esas.
//
// ## Lo que se deja fuera a proposito, MEDIDO sobre el `.pbf` del 21/09/2026
//
//   - `type=boundary` (624 relaciones): son limites administrativos. Se miraron
//     una a una: 612 son `boundary=administrative` y el resto husos horarios,
//     codigos postales y cuatro areas protegidas. **Ni una sola cae en una capa
//     de las que hay hoy**, asi que no aportan nada y no entran. Se cuentan con
//     su propio motivo para que el dia que alguien anada una capa de areas
//     protegidas vea que estan ahi.
//   - `type=building` (14), `type=site`, `type=waterway`: son esquemas de
//     agrupacion, no contornos. Su silueta ya viene en vias sueltas.
//   - Las relaciones anidadas (una relacion como miembro de otra). Son cuatro
//     gatos y coserlas pide recursion y un guardia de ciclos; se cuentan.
package main

import (
	"context"
	"io"
	"runtime"

	"github.com/paulmach/orb"
	"github.com/paulmach/orb/planar"
	"github.com/paulmach/osm"
	"github.com/paulmach/osm/osmpbf"
)

// enQuePlan dice, para una via miembro, en que multipoligono va y de que color
// se pinta ese multipoligono. Lo segundo es para no dibujar la misma mancha dos
// veces: ver `Extraer`.
type enQuePlan struct {
	Plan  int
	Pinta string
}

// planDeRelacion es un multipoligono ya clasificado al que **todavia le falta la
// geometria**: la primera pasada sabe de que color se pinta y que vias lo forman,
// pero las coordenadas no llegan hasta la segunda.
type planDeRelacion struct {
	ID     osm.RelationID
	Capa   string
	Clase  string
	Desde  uint8
	Nombre string
	Fuera  []osm.WayID
	Dentro []osm.WayID
}

// Los motivos de descarte, en constantes y no repartidos por el codigo: la lista
// que imprime el generador es lo unico que explica por que un fichero adelgaza,
// y dos motivos escritos casi igual se leen como dos cosas distintas.
const (
	fueraBoundary   = "relación type=boundary (no aporta a ninguna capa de hoy)"
	fueraOtroTipo   = "relación que no es un multipolígono"
	fueraNoRelleno  = "multipolígono que no se pinta relleno"
	fueraAnidada    = "multipolígono con otra relación dentro"
	fueraSinFuera   = "multipolígono sin ningún contorno exterior"
	fueraSinCoser   = "multipolígono con el contorno sin coser (trozos que faltan)"
	fueraHuerfano   = "agujero de multipolígono sin contorno que lo rodee"
	fueraYaEnUnaRel = "vía que ya va dentro de una relación (se dibujaría dos veces)"
)

// leerRelaciones es la PRIMERA pasada: solo relaciones, sin tocar nodos ni vias.
//
// Devuelve los planes y, para cada via que hace falta, en que plan va. Ese
// segundo mapa es lo que la segunda pasada usa para guardar **solo** los 26.358
// nodos de via que importan en vez de los millones que hay.
func leerRelaciones(r io.Reader, nivel Nivel, descartes map[string]int) ([]planDeRelacion, map[osm.WayID]enQuePlan, error) {
	esc := osmpbf.New(context.Background(), r, runtime.NumCPU())
	// AQUI ESTA LO QUE HACE QUE LA PASADA DE MAS NO CUESTE NADA: sin esto son
	// 62 MB descomprimidos y decodificados para tirarlos; con esto, 0,2 s.
	esc.SkipNodes = true
	esc.SkipWays = true
	defer esc.Close()

	var planes []planDeRelacion
	falta := map[osm.WayID]enQuePlan{}

	for esc.Scan() {
		rel, es := esc.Object().(*osm.Relation)
		if !es {
			continue
		}
		switch rel.Tags.Find("type") {
		case "multipolygon":
		case "boundary":
			descartes[fueraBoundary]++
			continue
		default:
			descartes[fueraOtroTipo]++
			continue
		}

		// LA MISMA CLASIFICACION QUE UNA VIA, sin una tabla aparte. Un
		// `natural=wood` es un bosque venga como quiera venir, y los motivos de
		// descarte —«campo de cultivo (a propósito fuera)»— salen ya contados.
		capa, clase, desde, nombre, sirve := enQueCapaCae(rel.Tags, nivel, descartes)
		if !sirve {
			continue
		}
		if !esDeRelleno(capa) {
			// Una relacion es un AREA por definicion. Si cayera en `carretera`
			// o en `tren` seria una via etiquetada de una forma que aqui no se
			// entiende, y dibujarla como linea pinta una telarana.
			descartes[fueraNoRelleno]++
			continue
		}

		plan := planDeRelacion{ID: rel.ID, Capa: capa, Clase: clase, Desde: desde, Nombre: nombre}
		anidada := false
		for _, m := range rel.Members {
			switch m.Type {
			case osm.TypeWay:
				id := osm.WayID(m.Ref)
				// El papel vacio es `outer`. Lo dice la especificacion de OSM y
				// hay miles de relaciones viejas asi: tomarlo por agujero
				// convierte un bosque entero en un hueco.
				if m.Role == "inner" {
					plan.Dentro = append(plan.Dentro, id)
				} else {
					plan.Fuera = append(plan.Fuera, id)
				}
			case osm.TypeRelation:
				anidada = true
			}
		}
		if anidada {
			descartes[fueraAnidada]++
			continue
		}
		if len(plan.Fuera) == 0 {
			descartes[fueraSinFuera]++
			continue
		}
		// Las vias se apuntan AQUI y no arriba: una relacion que se descarta
		// despues dejaria a sus vias apuntando al plan siguiente, que es otro
		// bosque en otra punta de Cuba.
		donde := enQuePlan{Plan: len(planes), Pinta: capa + "|" + clase}
		for _, id := range plan.Fuera {
			falta[id] = donde
		}
		for _, id := range plan.Dentro {
			falta[id] = donde
		}
		planes = append(planes, plan)
	}
	if err := esc.Err(); err != nil {
		return nil, nil, err
	}
	return planes, falta, nil
}

// coser junta los trozos de contorno en anillos cerrados.
//
// **Esto es el problema de verdad de los multipoligonos.** Los trozos vienen en
// el orden en que alguien los metio en la relacion, no en el orden en el que
// encajan, y cada uno puede venir del reves. Se cose por IDENTIFICADOR de nodo y
// no por coordenada: dos nodos distintos pueden caer en el mismo punto con los
// decimales que guarda el `.pbf`, y coser por ahi une dos contornos que no se
// tocan.
//
// Si un anillo no cierra **no se dibuja nada de esa relación**: media Cienaga de
// Zapata se cierra sola con una cuerda recta que no esta en el suelo, que es la
// misma regla de `rellenoDe` para las vias abiertas.
func coser(trozos [][]osm.NodeID) ([][]osm.NodeID, bool) {
	// Donde empieza o acaba cada trozo. Sin este indice, coser un contorno de
	// 300 trozos es cuadratico y se nota en los 5.582 multipoligonos.
	extremos := map[osm.NodeID][]int{}
	for i, t := range trozos {
		if len(t) < 2 {
			return nil, false
		}
		extremos[t[0]] = append(extremos[t[0]], i)
		if t[len(t)-1] != t[0] {
			extremos[t[len(t)-1]] = append(extremos[t[len(t)-1]], i)
		}
	}

	usado := make([]bool, len(trozos))
	var anillos [][]osm.NodeID
	for i := range trozos {
		if usado[i] {
			continue
		}
		usado[i] = true
		cadena := append([]osm.NodeID(nil), trozos[i]...)
		for cadena[0] != cadena[len(cadena)-1] {
			punta := cadena[len(cadena)-1]
			siguiente := -1
			for _, j := range extremos[punta] {
				if !usado[j] {
					siguiente = j
					break
				}
			}
			if siguiente == -1 {
				// Falta un trozo: o la relacion esta rota en OSM, o el trozo
				// cae fuera del extracto de Cuba.
				return nil, false
			}
			usado[siguiente] = true
			t := trozos[siguiente]
			if t[len(t)-1] == punta {
				// Viene del reves. Se le da la vuelta y encaja.
				t = alReves(t)
			}
			cadena = append(cadena, t[1:]...)
		}
		if len(cadena) < 4 {
			// Tres puntos mas el cierre es el minimo de verdad: con menos no
			// hay area que pintar.
			return nil, false
		}
		anillos = append(anillos, cadena)
	}
	return anillos, true
}

func alReves(t []osm.NodeID) []osm.NodeID {
	r := make([]osm.NodeID, len(t))
	for i, v := range t {
		r[len(t)-1-i] = v
	}
	return r
}

// enPuntos cambia los identificadores por coordenadas, o dice que no puede.
//
// Un nodo que no esta es un trozo de contorno que cae fuera del extracto, y la
// regla de esta casa para eso ya estaba escrita para las vias: **a medias no se
// dibuja nada**.
func enPuntos(ids []osm.NodeID, donde map[osm.NodeID]orb.Point) (orb.Ring, bool) {
	anillo := make(orb.Ring, 0, len(ids))
	for _, id := range ids {
		p, hay := donde[id]
		if !hay {
			return nil, false
		}
		anillo = append(anillo, p)
	}
	return anillo, true
}

// repartirAgujeros dice a QUE contorno pertenece cada agujero.
//
// Con un solo contorno —que es el caso de casi todos— no hay nada que decidir.
// Con varios, un agujero va en el contorno mas pequeno que lo contenga: en una
// relacion con dos bosques y una laguna, la laguna es hueco de UNO de los dos, y
// metida en el otro pintaria un agujero donde no lo hay.
//
// El agujero que no cae dentro de ningun contorno **no se dibuja**: un hueco sin
// nada alrededor no es un hueco, es un dato malo, y pintarlo como mancha pondria
// verde encima de una laguna, que es justo lo que se viene a arreglar.
func repartirAgujeros(fuera, dentro []orb.Ring) ([]orb.Polygon, int) {
	poligonos := make([]orb.Polygon, len(fuera))
	for i, f := range fuera {
		poligonos[i] = orb.Polygon{f}
	}
	huerfanos := 0
	for _, d := range dentro {
		if len(d) == 0 {
			continue
		}
		elegido, mejor := -1, 0.0
		for i, f := range fuera {
			if !planar.RingContains(f, d[0]) {
				continue
			}
			area := abs(planar.Area(orb.Polygon{f}))
			if elegido == -1 || area < mejor {
				elegido, mejor = i, area
			}
		}
		if elegido == -1 {
			huerfanos++
			continue
		}
		poligonos[elegido] = append(poligonos[elegido], d)
	}
	return poligonos, huerfanos
}

func abs(v float64) float64 {
	if v < 0 {
		return -v
	}
	return v
}

// armarRelacion pasa de un plan y los nodos de sus vias a los poligonos que se
// dibujan. Devuelve `nil` si la relacion no se pudo coser, y cuenta el motivo.
func armarRelacion(p planDeRelacion, nodosDe map[osm.WayID][]osm.NodeID,
	donde map[osm.NodeID]orb.Point, descartes map[string]int) []orb.Polygon {

	trozosDe := func(ids []osm.WayID) ([][]osm.NodeID, bool) {
		var trozos [][]osm.NodeID
		for _, id := range ids {
			nodos, hay := nodosDe[id]
			if !hay || len(nodos) < 2 {
				return nil, false
			}
			trozos = append(trozos, nodos)
		}
		return trozos, true
	}

	trozosFuera, completo := trozosDe(p.Fuera)
	if !completo {
		descartes[fueraSinCoser]++
		return nil
	}
	anillosFuera, cosido := coser(trozosFuera)
	if !cosido {
		descartes[fueraSinCoser]++
		return nil
	}
	fuera := make([]orb.Ring, 0, len(anillosFuera))
	for _, ids := range anillosFuera {
		anillo, todos := enPuntos(ids, donde)
		if !todos {
			descartes[fueraSinCoser]++
			return nil
		}
		fuera = append(fuera, anillo)
	}
	if len(fuera) == 0 {
		descartes[fueraSinFuera]++
		return nil
	}

	// LOS AGUJEROS NO TUMBAN LA RELACION. Si el contorno se cosio y una laguna
	// de dentro no, lo que hay que dibujar es el bosque sin ese hueco, no
	// quedarse sin bosque: perder la mancha entera por un agujero roto es
	// cambiar un fallo pequeno por uno grande.
	var dentro []orb.Ring
	if trozosDentro, completo := trozosDe(p.Dentro); completo {
		if anillosDentro, cosido := coser(trozosDentro); cosido {
			for _, ids := range anillosDentro {
				if anillo, todos := enPuntos(ids, donde); todos {
					dentro = append(dentro, anillo)
				}
			}
		}
	}

	poligonos, huerfanos := repartirAgujeros(fuera, dentro)
	if huerfanos > 0 {
		// Sumar un cero dejaria el motivo en la lista con un 0 al lado, y un
		// descarte que sale siempre deja de leerse.
		descartes[fueraHuerfano] += huerfanos
	}
	return poligonos
}
