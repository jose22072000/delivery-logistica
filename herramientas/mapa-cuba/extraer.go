// DE LOS 62 MB DE OSM A LO QUE HACE FALTA PARA REPARTIR.
//
// El `.osm.pbf` de Cuba trae el pais entero: cada banco, cada arbol, cada
// sendero y cada curva de nivel. De todo eso, un mapa de reparto necesita
// cuatro cosas:
//
//	carretera  las vias por las que pasa un camion, con su clase y su nombre
//	costa      la linea del mar. Cuba es una isla: sin costa el mapa no se
//	           reconoce, y entonces no sirve para orientarse
//	agua       embalses, lagunas y rios anchos, que es lo que explica por que
//	           una carretera da un rodeo
//	poblacion  los nucleos con su nombre
//
// Y desde el 21/09/2026, tres mas, de comparar la misma ruta en el telefono
// contra la web con teselas de OSM:
//
//	suelo      parques, vegetacion, zona urbana, industrial y portuaria. Sin
//	           esto el mapa es papel en blanco entre calles y no se ubica uno
//	edificio   la silueta de las manzanas. Es lo que mas se nota al llegar a
//	           una direccion, y lo que mas pesa: por eso entra tarde (z14/z15)
//	tren       las vias de tren
//
// Y nada mas. Cada capa que sobra son megas en el telefono del repartidor, y
// **lo que decide el peso no es la capa: es desde que zoom entra** (niveles.go).
//
// ## Por que se guardan TODOS los nodos en memoria
//
// En un `.pbf` los nodos vienen antes que las vias, asi que al leer un nodo
// todavia no se sabe si alguna via lo va a usar. O se lee el fichero dos veces,
// o se guardan las coordenadas. Con Cuba son ~7 millones de nodos a 16 bytes:
// cabe de sobra en cualquier equipo de los de aqui, y leer 62 MB dos veces
// cuesta mas que la memoria que ahorra.
package main

import (
	"context"
	"fmt"
	"io"
	"runtime"

	"github.com/paulmach/orb"
	"github.com/paulmach/osm"
	"github.com/paulmach/osm/osmpbf"
)

// Rasgo es una cosa dibujable ya lista: su geometria en lon/lat, en que capa va,
// con que clase se pinta, como se llama y desde que zoom aparece.
type Rasgo struct {
	Geo    orb.Geometry
	Capa   string
	Clase  string
	Nombre string
	Desde  uint8
	Caja   orb.Bound
}

// Extraido es lo que sale de una pasada por el fichero.
type Extraido struct {
	Rasgos []Rasgo
	Caja   orb.Bound
	// Descartes cuenta lo que se dejo fuera, por motivo. NO es adorno: si un
	// dia el fichero sale la mitad de pequeno, esto es lo que dice por que.
	Descartes map[string]int
}

// Extraer lee el `.pbf` y devuelve los rasgos del [nivel] pedido.
//
// Pide un `io.ReadSeeker` y no un `io.Reader` porque **el fichero se lee dos
// veces**: la primera, solo las relaciones, para saber que vias hacen falta
// (relaciones.go); la segunda, la de siempre. La primera cuesta 0,2 s porque el
// lector ni descomprime los bloques de nodos y vias.
func Extraer(r io.ReadSeeker, nivel Nivel) (*Extraido, error) {
	salida := &Extraido{Caja: orb.Bound{Min: orb.Point{180, 90}, Max: orb.Point{-180, -90}}, Descartes: map[string]int{}}

	var planes []planDeRelacion
	faltanVias := map[osm.WayID]enQuePlan{}
	if !nivel.SinRelaciones {
		var err error
		planes, faltanVias, err = leerRelaciones(r, nivel, salida.Descartes)
		if err != nil {
			return nil, fmt.Errorf("leyendo las relaciones del .pbf: %w", err)
		}
		if _, err := r.Seek(0, io.SeekStart); err != nil {
			return nil, fmt.Errorf("rebobinando el .pbf para la segunda pasada: %w", err)
		}
	}

	ctx := context.Background()
	escaner := osmpbf.New(ctx, r, runtime.NumCPU())
	defer escaner.Close()

	donde := make(map[osm.NodeID]orb.Point, 8<<20)
	// Solo los nodos de las vias que alguna relacion aceptada usa. Guardar
	// todas las vias serian millones para usar 26.358.
	nodosDeVia := make(map[osm.WayID][]osm.NodeID, len(faltanVias))
	// Las vias que pintan lo mismo que la relacion a la que pertenecen. Ver el
	// comentario de `tapada`.
	var tapadas []tapada

	anotar := func(g orb.Geometry, capa, clase, nombre string, desde uint8) {
		caja := g.Bound()
		salida.Caja = salida.Caja.Union(caja)
		salida.Rasgos = append(salida.Rasgos, Rasgo{
			Geo: g, Capa: capa, Clase: clase, Nombre: nombre, Desde: desde, Caja: caja,
		})
	}

	for escaner.Scan() {
		switch o := escaner.Object().(type) {
		case *osm.Node:
			donde[o.ID] = orb.Point{o.Lon, o.Lat}
			if len(o.Tags) == 0 {
				continue
			}
			clase, hay := clasesDePoblacion[o.Tags.Find("place")]
			if !hay {
				continue
			}
			nombre := o.Tags.Find("name")
			if nombre == "" {
				// Un nucleo sin nombre es un punto sin informacion: ocupa y no
				// dice nada. Se cuenta para que el descarte no sea silencioso.
				salida.Descartes["población sin nombre"]++
				continue
			}
			desde, entra := nivel.Poblaciones[clase]
			if !entra {
				salida.Descartes["población de clase que este nivel no lleva"]++
				continue
			}
			anotar(orb.Point{o.Lon, o.Lat}, capaPoblacion, clase, nombre, desde)

		case *osm.Way:
			if len(o.Nodes) < 2 {
				continue
			}
			enUnaRelacion, esMiembro := faltanVias[o.ID]
			if esMiembro {
				ids := make([]osm.NodeID, len(o.Nodes))
				for i, n := range o.Nodes {
					ids[i] = n.ID
				}
				nodosDeVia[o.ID] = ids
			}
			capa, clase, desde, nombre, sirve := queEsLaVia(o, nivel, salida.Descartes)
			if !sirve {
				continue
			}
			linea := make(orb.LineString, 0, len(o.Nodes))
			completa := true
			for _, n := range o.Nodes {
				p, hay := donde[n.ID]
				if !hay {
					// Una via cortada por el borde del extracto. No se dibuja a
					// medias: media carretera dibujada miente sobre por donde
					// se va.
					completa = false
					break
				}
				linea = append(linea, p)
			}
			if !completa || len(linea) < 2 {
				salida.Descartes["vía con nodos fuera del extracto"]++
				continue
			}
			geo, vale := geometriaDe(capa, linea)
			if !vale {
				salida.Descartes["relleno con contorno sin cerrar"]++
				continue
			}
			anotar(geo, capa, clase, nombre, desde)
			// LA MISMA MANCHA DOS VECES NO SE PINTA DOS VECES. Hay vias que
			// llevan sus propias etiquetas **y ademas** son miembro de una
			// relacion con esas mismas etiquetas: el bosque entero y uno de sus
			// trozos, del mismo verde, uno encima del otro. No se ve, pero se
			// paga en bytes en todas las teselas de todos los zooms.
			//
			// No se descarta aqui, que seria lo facil: se apunta y se quita al
			// final, **solo si la relacion se pudo coser**. Descartarla ahora
			// dejaria sin mancha a la relacion rota, que es cambiar unos bytes
			// de mas por un hueco de menos.
			if esMiembro && enUnaRelacion.Pinta == capa+"|"+clase {
				tapadas = append(tapadas, tapada{Rasgo: len(salida.Rasgos) - 1, Plan: enUnaRelacion.Plan})
			}

		case *osm.Relation:
			// Ya se leyeron en la primera pasada, con sus etiquetas y sus
			// miembros. Aqui no hay nada que hacer con ellas.
		}
	}
	if err := escaner.Err(); err != nil {
		return nil, fmt.Errorf("leyendo el .pbf: %w", err)
	}

	// Y AHORA SI: los multipoligonos, que necesitaban tener delante los nodos de
	// sus vias miembro. Van al final y no dentro del bucle por eso mismo.
	cosidos := make([]bool, len(planes))
	for i, plan := range planes {
		poligonos := armarRelacion(plan, nodosDeVia, donde, salida.Descartes)
		cosidos[i] = len(poligonos) > 0
		for _, poligono := range poligonos {
			anotar(poligono, plan.Capa, plan.Clase, plan.Nombre, plan.Desde)
		}
	}
	quitarLasTapadas(salida, tapadas, cosidos)

	if len(salida.Rasgos) == 0 {
		// Una salida vacia NO es una salida buena (`CLAUDE.md` §3): un `.pbf`
		// truncado o de otro sitio se lee sin un solo error y deja cero rasgos.
		return nil, fmt.Errorf("el .pbf no dejó ni un rasgo dibujable: ¿es el fichero correcto?")
	}
	return salida, nil
}

// geometriaDe dice CON QUE FORMA viaja una via de esa capa: mancha o linea.
//
// No es un detalle de tipos. Lo que llega al otro lado como linea lo pinta el
// aparato como linea: un barrio saldria como un contorno fino en vez de una
// mancha, y una mancha es lo que ubica de un vistazo. Al reves tambien rompe:
// una carretera convertida en poligono se pintaria rellena de gris.
func geometriaDe(capa string, linea orb.LineString) (orb.Geometry, bool) {
	if !esDeRelleno(capa) {
		return linea, true
	}
	p, vale := rellenoDe(linea)
	if !vale {
		return nil, false
	}
	return p, true
}

// rellenoDe convierte un contorno en poligono, o dice que no vale.
//
// Agua, suelo y edificios se pintan RELLENOS, asi que solo sirven **cerrados**.
// Un contorno abierto no es un poligono: al dibujarlo se cierra solo con una
// cuerda recta por donde falta, y esa cuerda no esta en el suelo — sale una
// manzana con un tajo diagonal, o media laguna. Se tira y se cuenta; a medias
// no se dibuja nada, que es la regla de las vias cortadas por el borde.
//
// Cuatro puntos es el minimo de verdad: tres esquinas mas la repetida del
// cierre. Con menos no hay area que pintar.
func rellenoDe(linea orb.LineString) (orb.Polygon, bool) {
	if len(linea) < 4 || linea[0] != linea[len(linea)-1] {
		return nil, false
	}
	return orb.Polygon{orb.Ring(linea)}, true
}

// queEsLaVia decide en que capa cae una via, o dice que no cae en ninguna.
func queEsLaVia(v *osm.Way, nivel Nivel, descartes map[string]int) (capa, clase string, desde uint8, nombre string, sirve bool) {
	return enQueCapaCae(v.Tags, nivel, descartes)
}

// enQueCapaCae es la clasificacion, y esta separada de `queEsLaVia` por una
// razon concreta: **una relacion se clasifica EXACTAMENTE igual que una via**.
// Un `natural=wood` es un bosque venga en una via cerrada o en un multipoligono
// de cuarenta trozos, y si fueran dos tablas distintas acabarian diciendo cosas
// distintas sin que nadie se entere. Lo unico que cambia entre las dos es de
// donde salen las etiquetas.
func enQueCapaCae(t osm.Tags, nivel Nivel, descartes map[string]int) (capa, clase string, desde uint8, nombre string, sirve bool) {
	nombre = t.Find("name")

	if t.Find("natural") == "coastline" {
		return capaCosta, "costa", costaDesde, "", true
	}
	if esAgua(t) {
		return capaAgua, "agua", aguaDesde, nombre, true
	}
	if h := t.Find("highway"); h != "" {
		c, conocida := clasesDeCarretera[h]
		if !conocida {
			// Senderos, escaleras, carriles bici, aceras: por ahi no pasa un
			// camion. Es el descarte que mas megas ahorra de todos.
			descartes["vía por la que no pasa un camión"]++
			return "", "", 0, "", false
		}
		d, entra := nivel.Carreteras[c]
		if !entra {
			descartes["calle que este nivel no lleva"]++
			return "", "", 0, "", false
		}
		return capaCarretera, c, d, nombre, true
	}

	// EL EDIFICIO VA ANTES QUE EL SUELO, y no es casual: un bloque puede llevar
	// `building=yes` y ademas un `landuse` heredado del poligono que lo rodea.
	// Si ganara el suelo, la manzana se pintaria de color de barrio y no habria
	// silueta que es lo que se busca.
	if b := t.Find("building"); b == "no" {
		// `building=no` significa **que ahi NO hay un edificio**: es la forma de
		// tapar un dato malo de otra fuente. Se cuenta como cualquier otro
		// descarte, porque alguien se molesto en ponerlo.
		descartes["building=no (ahí NO hay un edificio)"]++
		return "", "", 0, "", false
	}
	if esEdificio(t) {
		d, entra := nivel.Edificios[claseEdificio]
		if !entra {
			descartes["edificio (este nivel no los lleva)"]++
			return "", "", 0, "", false
		}
		// EL EDIFICIO NO LLEVA NOMBRE, a proposito. Son cientos de miles y casi
		// ninguno tiene uno que sirva para orientarse; los que lo tienen traen
		// el del negocio, que cambia cada temporada. Lo que hace falta es la
		// silueta.
		return capaEdificio, claseEdificio, d, "", true
	}

	if r := t.Find("railway"); r != "" {
		c, conocida := clasesDeTren[r]
		if !conocida {
			descartes["vía de tren que no es una vía (en desuso, andén…)"]++
			return "", "", 0, "", false
		}
		if t.Find("service") != "" {
			// Agujas, apartaderos y vias de patio. Son una telarana gris encima
			// de un almacen y no llevan a ningun sitio.
			descartes["vía de tren de patio o apartadero"]++
			return "", "", 0, "", false
		}
		d, entra := nivel.Trenes[c]
		if !entra {
			descartes["vía de tren que este nivel no lleva"]++
			return "", "", 0, "", false
		}
		// El tren tampoco lleva nombre: la linea se reconoce por donde va, no
		// por como se llama, y los nombres de via en Cuba estan a medias.
		return capaTren, c, d, "", true
	}

	if c, hay := queSueloEs(t); hay {
		d, entra := nivel.Suelos[c]
		if !entra {
			descartes["suelo de clase que este nivel no lleva"]++
			return "", "", 0, "", false
		}
		// Sin nombre tambien. «Parque Central» rotulado ayudaria, pero hoy el
		// pintor solo rotula nucleos (docs/mapa-sin-conexion.md §9) y un nombre
		// que nadie dibuja son bytes que nadie lee.
		return capaSuelo, c, d, "", true
	}
	if esSueloDescartado(t) {
		// Media Cuba es campo. Pintarlo todo del mismo color no distingue nada
		// y multiplica el fichero. Se cuenta para que el dia que alguien se
		// pregunte por que no sale, lo vea en la salida del generador.
		descartes["campo de cultivo (a propósito fuera)"]++
		return "", "", 0, "", false
	}
	if tieneUsoDelSuelo(t) {
		// Llevaba `landuse`, `leisure` o `natural` y ninguno de los tres esta en
		// la tabla: campos de futbol, colegios, cementerios, zona militar. **Se
		// cuenta.** Lo que NO se cuenta es la via que no traia ninguna de esas
		// etiquetas —una valla, un muro, el contorno de una parcela—, porque esa
		// nunca fue candidata a nada y contarla ahogaria la lista de descartes
		// con un millon de vias que no significan nada.
		descartes["uso del suelo que no está en la tabla"]++
		return "", "", 0, "", false
	}
	return "", "", 0, "", false
}

// tieneUsoDelSuelo dice si la via al menos SE PARECIA a un uso del suelo.
func tieneUsoDelSuelo(t osm.Tags) bool {
	return t.Find("landuse") != "" || t.Find("leisure") != "" || t.Find("natural") != ""
}

// esEdificio. Sigue rechazando `building=no` aunque `queEsLaVia` ya lo haya
// apartado antes: una funcion que contesta bien sola es la que no se rompe
// cuando alguien mueve el orden de las comprobaciones de arriba.
func esEdificio(t osm.Tags) bool {
	b := t.Find("building")
	if b != "" && b != "no" {
		return true
	}
	// Una parte de edificio (`building:part`) sin `building` es un trozo de un
	// bloque que ya esta dibujado entero: no se anade, se solaparia.
	return false
}

// queSueloEs busca la etiqueta tal cual, `clave=valor`, en una sola tabla.
func queSueloEs(t osm.Tags) (string, bool) {
	for _, clave := range []string{"leisure", "landuse", "natural"} {
		valor := t.Find(clave)
		if valor == "" {
			continue
		}
		if c, hay := clasesDeSuelo[clave+"="+valor]; hay {
			return c, true
		}
	}
	return "", false
}

func esSueloDescartado(t osm.Tags) bool {
	lu := t.Find("landuse")
	return lu == "farmland" || lu == "farmyard" || lu == "orchard" ||
		lu == "vineyard" || lu == "greenhouse_horticulture"
}

func esAgua(t osm.Tags) bool {
	return t.Find("natural") == "water" ||
		t.Find("landuse") == "reservoir" ||
		t.Find("waterway") == "riverbank" ||
		t.Find("waterway") == "dock"
}

// tapada es una via que se dibujo Y ADEMAS va dentro de una relacion del mismo
// color. Si la relacion se cose, la via sobra: es el mismo trozo de bosque
// pintado del mismo verde, dos veces, en todas las teselas de todos los zooms.
type tapada struct {
	Rasgo int // indice en salida.Rasgos
	Plan  int // indice en planes
}

// quitarLasTapadas borra las vias que la relacion ya dibuja, y **solo esas**.
//
// Se hace al final, con los multipoligonos ya cosidos, porque la pregunta que
// decide no es «esta via es miembro de una relacion» sino «esa relacion llego a
// dibujarse». Una relacion rota deja a sus vias siendo lo unico que hay.
func quitarLasTapadas(salida *Extraido, tapadas []tapada, cosidos []bool) {
	fuera := map[int]bool{}
	for _, t := range tapadas {
		if t.Plan < len(cosidos) && cosidos[t.Plan] {
			fuera[t.Rasgo] = true
		}
	}
	if len(fuera) == 0 {
		return
	}
	salida.Descartes[fueraYaEnUnaRel] += len(fuera)
	vivos := salida.Rasgos[:0]
	for i, r := range salida.Rasgos {
		if fuera[i] {
			continue
		}
		vivos = append(vivos, r)
	}
	salida.Rasgos = vivos
}
