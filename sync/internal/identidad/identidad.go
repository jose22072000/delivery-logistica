// Package identidad dice QUIÉN está llamando: su persona, su sucursal y si es Super Admin.
//
// Quien manda en personas, roles y sucursales es auth (`auth.procovar.cloud`), y aquí no
// hay ni va a haber una copia de esa lista: una segunda lista de personas es una segunda
// lista que mantener al día y un segundo sitio donde dar de baja a alguien.
//
// De dónde sale, hoy: de las cabeceras que pone el proxy que verifica el token delante de
// este servicio. Es provisional —lo bueno es verificar aquí el token de auth, que ya lleva
// dentro el `sub`, la sucursal y los roles (ver `docs/identidad.md`)— y por eso hay que
// pedirlo a mano con `SYNC_IDENTIDAD=cabeceras`: confiar en una cabecera es seguro
// exactamente mientras nadie más pueda llegar a este puerto, y eso es una decisión de
// despliegue que alguien tiene que tomar mirándola.
//
// El resto del servicio no se entera de nada de esto: pide la Identidad del contexto.
package identidad

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/httpx"
)

type Identidad struct {
	// El id de la persona EN AUTH. Texto, porque viene de un sistema ajeno.
	Persona string
	// Su sucursal. El alcance por sucursal es la regla de seguridad de todo el reparto.
	Sucursal uuid.UUID
	// El Super Admin ve las diez. Es la única excepción al alcance, y la única fuente de
	// conflictos de verdad (ver `docs/sincronizacion.md`).
	EsSuperAdmin bool
}

// Alcance devuelve la sucursal por la que hay que filtrar, o nil para «todas». Es lo que
// espera el parámetro anulable de las consultas: el filtro vive en el SQL, nunca en Go.
func (i Identidad) Alcance() *uuid.UUID {
	if i.EsSuperAdmin {
		return nil
	}
	s := i.Sucursal
	return &s
}

// Ve dice si esta identidad puede ver las cosas de esa sucursal.
func (i Identidad) Ve(sucursal uuid.UUID) bool {
	return i.EsSuperAdmin || i.Sucursal == sucursal
}

var ErrSinSesion = errors.New("sin sesión")

// Fuente saca la identidad de una petición. Se cambia entera el día que el token se
// verifique aquí, sin tocar ningún handler.
type Fuente func(*http.Request) (Identidad, error)

// DeCabeceras lee lo que puso el verificador de delante.
func DeCabeceras(r *http.Request) (Identidad, error) {
	persona := strings.TrimSpace(r.Header.Get("X-Persona"))
	if persona == "" {
		return Identidad{}, ErrSinSesion
	}
	var id Identidad
	id.Persona = persona
	id.EsSuperAdmin = esCierto(r.Header.Get("X-Super-Admin"))

	if v := strings.TrimSpace(r.Header.Get("X-Sucursal")); v != "" {
		s, err := uuid.Parse(v)
		if err != nil {
			return Identidad{}, ErrSinSesion
		}
		id.Sucursal = s
	} else if !id.EsSuperAdmin {
		// Sin sucursal y sin ser Super Admin no hay alcance que aplicar, y «sin alcance»
		// no puede querer decir «todas»: eso es justo cómo se ve lo que no es de uno.
		return Identidad{}, ErrSinSesion
	}
	return id, nil
}

func esCierto(v string) bool {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "1", "true", "si", "sí":
		return true
	}
	return false
}

type llave struct{}

// Con mete la identidad en el contexto. Lo usa el middleware, y las pruebas.
func Con(ctx context.Context, id Identidad) context.Context {
	return context.WithValue(ctx, llave{}, id)
}

// De la saca. El segundo valor es false cuando no pasó por el middleware.
func De(ctx context.Context) (Identidad, bool) {
	id, ok := ctx.Value(llave{}).(Identidad)
	return id, ok
}

// Exigir corta la petición si no hay sesión. El mensaje es el literal de `delivery`.
func Exigir(fuente Fuente, siguiente http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id, err := fuente(r)
		if err != nil {
			httpx.Fallo(w, http.StatusUnauthorized, "Unauthorized")
			return
		}
		siguiente.ServeHTTP(w, r.WithContext(Con(r.Context(), id)))
	})
}
