package httpx

import (
	"net/http"
	"sort"
	"strings"
)

// El enrutado es el de la biblioteca estándar (net/http, Go 1.22+): patrones con método
// y con comodines, `GET /api/vehicles/{id}`. SIN DEPENDENCIAS EXTERNAS a propósito —
// esto es un servicio que tiene que seguir compilando dentro de cinco años en una VPS a
// la que se llega por una conexión de Cuba; cada router de terceros es una versión que
// alguien tendrá que subir y una forma nueva de que las rutas se comporten distinto de
// como se leen.
//
// Lo único que añade este envoltorio sobre `http.ServeMux` es que los 404 y los 405
// salgan con el formato {"error": "..."} igual que todo lo demás. ServeMux los escribe
// en texto plano, y un cliente que espera JSON siempre y se encuentra "404 page not
// found" no enseña nada útil: enseña un fallo de parseo.
type Router struct {
	mux     *http.ServeMux
	metodos map[string][]string // patrón sin método -> métodos registrados
	medios  []Medio             // se aplican a TODA ruta de este router
	montado bool
}

// NuevoRouter crea el enrutador. Los middlewares dados envuelven todas las rutas,
// incluidos el 404 y el 405, para que también queden en el registro.
func NuevoRouter(medios ...Medio) *Router {
	return &Router{
		mux:     http.NewServeMux(),
		metodos: map[string][]string{},
		medios:  medios,
	}
}

// Manejar registra un manejador para un método y un patrón.
//
// `medios` son los propios de ESA ruta y van por dentro de los del router: ahí es donde
// se cuelgan la sesión y el alcance, que no valen para /health ni para /version.
func (rt *Router) Manejar(metodo, patron string, h http.Handler, medios ...Medio) {
	if rt.montado {
		panic("httpx: no se pueden añadir rutas después de montar el router")
	}
	rt.metodos[patron] = append(rt.metodos[patron], metodo)
	rt.mux.Handle(metodo+" "+patron, Encadenar(h, medios...))
}

// ManejarFunc es Manejar con una función.
func (rt *Router) ManejarFunc(metodo, patron string, h http.HandlerFunc, medios ...Medio) {
	rt.Manejar(metodo, patron, h, medios...)
}

// Handler cierra el router y devuelve lo que se le pasa al servidor.
func (rt *Router) Handler() http.Handler {
	if !rt.montado {
		rt.montado = true
		// Por cada patrón, una entrada SIN método que recoge los métodos que no se
		// registraron. ServeMux prefiere siempre el patrón con método, así que esto
		// sólo se alcanza cuando el método no encaja: es el 405, con su cabecera Allow.
		for patron, metodos := range rt.metodos {
			permitidos := append([]string(nil), metodos...)
			sort.Strings(permitidos)
			// OPTIONS lo contesta el middleware de CORS antes de llegar aquí.
			allow := strings.Join(append(permitidos, http.MethodOptions), ", ")
			rt.mux.Handle(patron, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Allow", allow)
				Error(w, r, http.StatusMethodNotAllowed, MsgMetodoNoValido)
			}))
		}
		// Todo lo que no case con nada.
		rt.mux.Handle("/", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			Error(w, r, http.StatusNotFound, MsgNoEncontrado)
		}))
	}
	return Encadenar(rt.mux, rt.medios...)
}
