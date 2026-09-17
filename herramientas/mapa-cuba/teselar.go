// DE LOS RASGOS A LAS TESELAS.
//
// AQUI ESTA LA RAZON POR LA QUE ESTO OCUPA 88 MB Y NO 6,5 GB, y conviene tenerla
// delante porque es lo unico que hay que entender de todo el fichero:
//
//	En teselas de imagen, la MISMA carretera se dibuja otra vez en cada nivel
//	de zoom, y cada nivel tiene cuatro veces mas teselas que el anterior. Cuba
//	hasta el z15 son ~492.000 imagenes.
//
//	En teselas vectoriales viaja la GEOMETRIA, y el aparato la dibuja al
//	tamano que haga falta. Los niveles de zoom siguen existiendo —hay que
//	partir la geometria en trozos manejables y simplificarla— pero lo que se
//	guarda en cada uno son unos cuantos miles de puntos, no un millon de
//	pixeles de colores.
//
// Eso es lo que hace MAPS.ME, y es la razon por la que baja 88 MB y no 6,5 GB.
package main

import (
	"fmt"
	"math"

	"github.com/paulmach/orb"
	"github.com/paulmach/orb/encoding/mvt"
	"github.com/paulmach/orb/geojson"
	"github.com/paulmach/orb/maptile"
	"github.com/paulmach/orb/simplify"
)

// Recuento es lo que se dice al terminar. Se mide, no se estima.
type Recuento struct {
	Teselas  int
	Rasgos   int
	PorZoom  map[uint8]int
	BytesMVT int64
}

func aX(lon float64, z uint8) float64 { return (lon + 180) / 360 * float64(uint32(1)<<z) }

func aY(lat float64, z uint8) float64 {
	r := lat * math.Pi / 180
	return (1 - math.Log(math.Tan(r)+1/math.Cos(r))/math.Pi) / 2 * float64(uint32(1)<<z)
}

// Teselar parte [rasgos] en teselas y las mete en [dentro].
func Teselar(dentro *Escritor, rasgos []Rasgo, nivel Nivel, aviso func(string)) (*Recuento, error) {
	cuenta := &Recuento{PorZoom: map[uint8]int{}}

	for z := uint8(0); z <= nivel.ZoomMax; z++ {
		cuantas := uint32(1) << z
		// Los rasgos de este zoom, repartidos por tesela. Se guardan indices y
		// no copias: un rasgo cruza varias teselas y copiarlo en cada una
		// multiplica la memoria por nada.
		cubos := map[[2]uint32][]int{}
		for i := range rasgos {
			if rasgos[i].Desde > z {
				continue
			}
			c := rasgos[i].Caja
			x0 := int64(math.Floor(aX(c.Min[0], z)))
			x1 := int64(math.Floor(aX(c.Max[0], z)))
			// El eje Y va al reves: la latitud MAXIMA es la tesela de arriba.
			y0 := int64(math.Floor(aY(c.Max[1], z)))
			y1 := int64(math.Floor(aY(c.Min[1], z)))
			for x := x0; x <= x1; x++ {
				for y := y0; y <= y1; y++ {
					if x < 0 || y < 0 || x >= int64(cuantas) || y >= int64(cuantas) {
						continue
					}
					clave := [2]uint32{uint32(x), uint32(y)}
					cubos[clave] = append(cubos[clave], i)
				}
			}
		}

		for clave, indices := range cubos {
			bytes, cuantosRasgos, err := unaTesela(rasgos, indices, nivel, z, clave[0], clave[1])
			if err != nil {
				return nil, err
			}
			if len(bytes) == 0 {
				// Todo lo que caia aqui se quedo en nada al simplificar. No se
				// escribe: una tesela vacia pesa y no pinta.
				continue
			}
			if err := dentro.Anadir(z, clave[0], clave[1], bytes); err != nil {
				return nil, err
			}
			cuenta.Teselas++
			cuenta.PorZoom[z]++
			cuenta.Rasgos += cuantosRasgos
			cuenta.BytesMVT += int64(len(bytes))
		}
		aviso(fmt.Sprintf("  z%-2d  %7d teselas  %10.1f MB acumulados",
			z, cuenta.PorZoom[z], float64(cuenta.BytesMVT)/1e6))
	}
	return cuenta, nil
}

func unaTesela(rasgos []Rasgo, indices []int, nivel Nivel, z uint8, x, y uint32) ([]byte, int, error) {
	capas := map[string]*geojson.FeatureCollection{}
	for _, i := range indices {
		r := rasgos[i]
		// SE CLONA, Y NO ES UNA PRECAUCION: `orb` proyecta, recorta y simplifica
		// **mutando la geometria en sitio**. El mismo rasgo cae en varias
		// teselas y en 15 niveles de zoom; sin el clon, la PRIMERA tesela que
		// lo toca se lo lleva proyectado a coordenadas de esa tesela y todas
		// las demas dibujan basura. No salta ningun error: salen teselas
		// medio vacias y un mapa con agujeros. Lo cazó `-comprobar` al leer de
		// vuelta y ver niveles enteros sin una sola tesela.
		f := geojson.NewFeature(clonar(r.Geo))
		f.Properties["clase"] = r.Clase
		// LOS NOMBRES SOLO DONDE SE PUEDEN LEER. Un «Calle 23» metido en la
		// tesela del z6 ocupa lo mismo que en la del z14 y no se ve: a ese
		// tamano la calle entera mide dos pixeles.
		if r.Nombre != "" && z >= nivel.NombresDesde {
			f.Properties["nombre"] = r.Nombre
		}
		if capas[r.Capa] == nil {
			capas[r.Capa] = geojson.NewFeatureCollection()
		}
		capas[r.Capa].Append(f)
	}
	if len(capas) == 0 {
		return nil, 0, nil
	}

	l := mvt.NewLayers(capas)
	l.ProjectToTile(maptile.New(x, y, maptile.Zoom(z)))
	// El recorte va con el margen de una tesela alrededor (lo que trae orb por
	// defecto) y no al borde justo: una carretera cortada exactamente en el
	// borde deja una costura blanca entre dos teselas.
	l.Clip(mvt.MapboxGLDefaultExtentBound)
	l.Simplify(simplify.DouglasPeucker(tolerancia(z)))
	l.RemoveEmpty(1, 1)

	// FUERA LAS CAPAS QUE SE QUEDARON SIN NADA. `RemoveEmpty` quita los rasgos
	// pero deja la capa puesta, con su nombre y su diccionario de claves. Una
	// `costa` vacía repetida en 13.000 teselas son bytes que no pintan nada.
	vivas := l[:0]
	cuantos := 0
	for _, capa := range l {
		if len(capa.Features) == 0 {
			continue
		}
		cuantos += len(capa.Features)
		vivas = append(vivas, capa)
	}
	l = vivas
	if cuantos == 0 {
		return nil, 0, nil
	}
	datos, err := mvt.MarshalGzipped(l)
	if err != nil {
		return nil, 0, fmt.Errorf("tesela %d/%d/%d: %w", z, x, y, err)
	}
	return datos, cuantos, nil
}

// clonar hace una copia propia de la geometria. Ver el comentario de arriba.
func clonar(g orb.Geometry) orb.Geometry {
	switch v := g.(type) {
	case orb.Point:
		return v // es un valor, no comparte nada
	case orb.LineString:
		return append(orb.LineString(nil), v...)
	case orb.Polygon:
		copia := make(orb.Polygon, len(v))
		for i, anillo := range v {
			copia[i] = append(orb.Ring(nil), anillo...)
		}
		return copia
	default:
		// No hay mas formas en este generador. Si un dia las hay, que reviente
		// aqui y no en el telefono de un repartidor.
		panic(fmt.Sprintf("geometría sin clonar: %T", g))
	}
}

// cajaDe pasa el recuadro de orb al de la cabecera.
func cajaDe(b orb.Bound) Caja {
	return Caja{MinLon: b.Min[0], MinLat: b.Min[1], MaxLon: b.Max[0], MaxLat: b.Max[1]}
}
