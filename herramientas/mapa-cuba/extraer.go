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
// Y nada mas. Cada capa que sobra son megas en el telefono del repartidor.
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
func Extraer(r io.Reader, nivel Nivel) (*Extraido, error) {
	ctx := context.Background()
	escaner := osmpbf.New(ctx, r, runtime.NumCPU())
	defer escaner.Close()

	donde := make(map[osm.NodeID]orb.Point, 8<<20)
	salida := &Extraido{Caja: orb.Bound{Min: orb.Point{180, 90}, Max: orb.Point{-180, -90}}, Descartes: map[string]int{}}

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
			if capa == capaAgua {
				// El agua se pinta rellena, asi que solo sirve cerrada.
				if linea[0] != linea[len(linea)-1] || len(linea) < 4 {
					salida.Descartes["agua con contorno sin cerrar"]++
					continue
				}
				anotar(orb.Polygon{orb.Ring(linea)}, capa, clase, nombre, desde)
				continue
			}
			anotar(linea, capa, clase, nombre, desde)

		case *osm.Relation:
			// A PROPOSITO FUERA, y hay que saber que se pierde: las lagunas y
			// embalses mapeados como multipoligono (una relacion con su
			// contorno y sus islas) no salen. Armarlos bien es un problema de
			// por si —contornos partidos en decenas de trozos que hay que
			// coser— y lo que se gana en un mapa de reparto es una mancha azul
			// de mas. La costa, que es lo que de verdad hace falta, viene en
			// vias sueltas y SI entra.
			salida.Descartes["relación (multipolígono) no soportada"]++
		}
	}
	if err := escaner.Err(); err != nil {
		return nil, fmt.Errorf("leyendo el .pbf: %w", err)
	}
	if len(salida.Rasgos) == 0 {
		// Una salida vacia NO es una salida buena (`CLAUDE.md` §3): un `.pbf`
		// truncado o de otro sitio se lee sin un solo error y deja cero rasgos.
		return nil, fmt.Errorf("el .pbf no dejó ni un rasgo dibujable: ¿es el fichero correcto?")
	}
	return salida, nil
}

// queEsLaVia decide en que capa cae una via, o dice que no cae en ninguna.
func queEsLaVia(v *osm.Way, nivel Nivel, descartes map[string]int) (capa, clase string, desde uint8, nombre string, sirve bool) {
	nombre = v.Tags.Find("name")

	if v.Tags.Find("natural") == "coastline" {
		return capaCosta, "costa", costaDesde, "", true
	}
	if esAgua(v.Tags) {
		return capaAgua, "agua", aguaDesde, nombre, true
	}
	if h := v.Tags.Find("highway"); h != "" {
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
	return "", "", 0, "", false
}

func esAgua(t osm.Tags) bool {
	return t.Find("natural") == "water" ||
		t.Find("landuse") == "reservoir" ||
		t.Find("waterway") == "riverbank" ||
		t.Find("waterway") == "dock"
}
