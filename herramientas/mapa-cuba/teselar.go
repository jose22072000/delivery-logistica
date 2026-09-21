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
	// SE RECORTA CAPA POR CAPA, y no todas hasta el mismo sitio: una linea
	// necesita margen alrededor de la tesela y una mancha no. Por que, y lo que
	// costaba no distinguirlo, en `recorteDe`.
	for _, capa := range l {
		capa.Clip(recorteDe(capa.Name))
		capa.Simplify(simplify.DouglasPeucker(tolerancia(z)))
		capa.RemoveEmpty(1, 1)
	}

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
	// SE ENDEREZA AL FINAL, con la geometria ya recortada y simplificada. Hoy
	// daria igual hacerlo antes —`Clip` no le da la vuelta a un anillo y
	// `Simplify` nunca tira el primero, que es el de fuera—, pero eso son dos
	// promesas de `orb` que no estan escritas en ninguna parte suya. Al final es
	// lo unico que no depende de ellas, y no cuesta nada.
	enderezarAnillos(l)

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

// ── EL SENTIDO DE GIRO DE LOS ANILLOS ────────────────────────────────────────
//
// UN AGUJERO NO SE DIBUJA CON UNA ETIQUETA: se dibuja **dando la vuelta al
// anillo**. Es lo unico que distingue «la laguna que hay dentro del bosque» de
// «otra mancha de bosque encima de la laguna», y no hay ningun campo en el
// formato que lo diga.
//
// La especificacion MVT (2.1, «Winding order») lo pide asi, **en coordenadas de
// tesela**, donde la Y crece HACIA ABAJO:
//
//	el anillo de fuera, en sentido HORARIO
//	los de dentro,      en sentido ANTIHORARIO
//
// Con la Y hacia abajo, «horario en la pantalla» es area con signo POSITIVO, que
// es lo que `orb` llama `CCW`. No es una errata: `orb.Ring.Orientation` mira el
// signo del area tal cual, sin saber para donde mira la Y, y su propio
// decodificador usa exactamente ese criterio para decidir donde empieza un
// poligono nuevo. Por eso aqui se pide `CCW` para el de fuera.
//
// `orb` **no lo hace solo**: escribe los anillos en el orden y el sentido en que
// se los den. Hasta el 21/09/2026 daba igual porque ningun rasgo tenia agujeros
// —una via cerrada es un anillo y nada mas— y estaba apuntado en el informe de
// ese dia como lo que habia que arreglar «cuando los haya». Ya los hay.
//
// Lo que pasa si esto falta, y por eso se arregla aunque el pintor de hoy no se
// entere: un lector que siga la especificacion —`pmtiles show`, tippecanoe,
// MapLibre— lee el agujero como un poligono aparte y **pinta el bosque encima de
// la laguna**. Y el pintor nuestro rellena con `nonZero`, que tambien necesita
// que los dos anillos giren al reves para dejar el hueco.
func enderezarAnillos(capas mvt.Layers) {
	for _, capa := range capas {
		for _, rasgo := range capa.Features {
			switch g := rasgo.Geometry.(type) {
			case orb.Polygon:
				rasgo.Geometry = enderezarPoligono(g)
			case orb.MultiPolygon:
				for i, p := range g {
					g[i] = enderezarPoligono(p)
				}
			case orb.Ring:
				enderezarAnillo(g, orb.CCW)
			}
		}
	}
}

// enderezarPoligono: el primer anillo es el de fuera y los demas son agujeros.
// Ese es el orden que da `orb` y el que arma `repartirAgujeros`.
//
// Y DE PASO TIRA LOS AGUJEROS QUE NO TIENEN AREA, que no es una limpieza de
// adorno: al proyectar a la tesela las coordenadas se redondean a numeros
// enteros, asi que **una isla mas pequena que una unidad de tesela se aplasta
// hasta quedarse en una raya**. En el `basico` son 1.879 de los 11.832 anillos
// de dentro. Un anillo aplastado no pinta nada, ocupa, y sobre todo **no se
// puede enderezar**: no gira ni para un lado ni para el otro, asi que deja el
// fichero en un estado que no se puede comprobar. Se van aqui, y asi la
// comprobacion de `-comprobar` puede ser dura: todo agujero que quede, gira.
func enderezarPoligono(p orb.Polygon) orb.Polygon {
	if len(p) == 0 {
		return p
	}
	enderezarAnillo(p[0], orb.CCW)
	vivos := p[:1]
	for _, anillo := range p[1:] {
		if len(anillo) < 4 || anillo.Orientation() == 0 {
			continue
		}
		enderezarAnillo(anillo, orb.CW)
		vivos = append(vivos, anillo)
	}
	return vivos
}

func enderezarAnillo(a orb.Ring, quiere orb.Orientation) {
	// Menos de tres puntos no tiene area y `Orientation` leeria fuera del
	// anillo. `RemoveEmpty` ya los quita, pero una funcion que contesta bien
	// sola es la que no se rompe cuando alguien mueve el orden de arriba.
	if len(a) < 3 {
		return
	}
	if a.Orientation() != quiere {
		a.Reverse()
	}
}

// ── HASTA DONDE SE RECORTA CADA CAPA ─────────────────────────────────────────
//
// **Aqui estaba el dinero de los multipoligonos, y no donde parecia.**
//
// El recorte que trae `orb` por defecto —el que usa mapbox-gl— no es el borde de
// la tesela: es de -4096 a 8191, o sea **una tesela de margen por cada lado, un
// cuadrado de 3x3**. Para una linea eso es justo lo que hace falta: una
// carretera cortada exactamente en el borde se dibuja con su grosor y deja una
// costura blanca entre dos teselas.
//
// Para una MANCHA es pagar nueve veces. Mientras las manchas eran manzanas y
// parques no se notaba —caben enteras en una tesela—, pero un bosque cosido de
// una relacion cruza cientos de teselas, y con el margen de 3x3 cada una de esas
// teselas se lleva el contorno de sus ocho vecinas ademas del suyo. Medido sobre
// el `completo`: la capa `suelo` pasaba de 11,4 MB a 34,4 MB al meter las
// relaciones, y la mayor parte de esos 23 MB eran contorno repetido que ninguna
// de esas teselas llega a pintar.
//
// Una mancha no tiene grosor, asi que le sobra el margen. Se le deja el justo
// para que la simplificacion no meta un borde HACIA DENTRO y aparezca una raya
// del color del papel entre dos teselas: la simplificacion puede mover un punto
// hasta `tolerancia` unidades, y 64 es ocho veces eso.
const margenDeLasManchas = 64

var recorteDeLasManchas = orb.Bound{
	Min: orb.Point{-margenDeLasManchas, -margenDeLasManchas},
	Max: orb.Point{mvt.DefaultExtent + margenDeLasManchas - 1, mvt.DefaultExtent + margenDeLasManchas - 1},
}

func recorteDe(capa string) orb.Bound {
	if esDeRelleno(capa) {
		return recorteDeLasManchas
	}
	return mvt.MapboxGLDefaultExtentBound
}
