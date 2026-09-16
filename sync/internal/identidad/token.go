package identidad

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/sha512"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"hash"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
)

// EL VERIFICADOR DEL TOKEN DE AUTH, que es lo que este servicio debió tener desde el
// principio.
//
// # Por qué existe, y qué pasaba sin él
//
// `DeCabeceras` saca la identidad de `X-Persona`, que debía poner «el proxy que verifica
// el token delante de este servicio». **Ese proxy no existe.** Traefik enruta
// `reparto.procovar.cloud/sync` directo al contenedor y no añade ninguna cabecera, así que
// `X-Persona` llegaba SIEMPRE vacía y este servicio contestaba 401 a todo.
//
// Lo que eso provocaba aguas arriba es mucho peor que un 401: el cliente de la aplicación
// trata un 401 que sobrevive a renovar como «la sesión murió», así que **echaba a la
// persona a la pantalla de acceso en cuanto volvía la señal** — justo en el momento en el
// que iba a subir el trabajo del día. Visto el 16/09/2026 con el teléfono en la mano:
// «cogio internet y volvio a cerrarme la session y no subio nada».
//
// Y no subió nunca nada: `POST /sync/aparato` llevaba 401 desde el primer día.
//
// El propio comentario de `identidad.go` avisaba de la condición —«confiar en una cabecera
// es seguro exactamente mientras nadie más pueda llegar a este puerto»— y el puerto está
// publicado en internet. O sea que la premisa se rompió al desplegar, no al programar.
//
// # Qué se lee
//
// El mismo token de auth que ya verifica `reparto-api`, con el mismo secreto y las mismas
// reglas: HS256, `alg` que tiene que coincidir con uno nuestro, firma comparada en tiempo
// constante, y `exp` obligatorio. Un token sin caducidad es una sesión que no muere nunca.
//
// El alcance sale como en `reparto-api`: **la sucursal del token manda, y sin sucursal se
// ven todas** (Super Admin). Dos reglas distintas en dos servicios sería peor que el fallo
// que se está arreglando.

var algoritmos = map[string]func() hash.Hash{
	"HS256": sha256.New,
	"HS384": sha512.New384,
	"HS512": sha512.New,
}

// ErrTokenRoto: no es un JWT, o no se puede leer.
var ErrTokenRoto = errors.New("token ilegible")

// DeToken construye la fuente de identidad que verifica el token de auth.
func DeToken(secreto []byte) Fuente {
	return func(r *http.Request) (Identidad, error) {
		crudo := ""
		if cab := r.Header.Get("Authorization"); cab != "" {
			if partes := strings.Fields(cab); len(partes) == 2 &&
				strings.EqualFold(partes[0], "Bearer") {
				crudo = partes[1]
			}
		}
		if strings.TrimSpace(crudo) == "" {
			return Identidad{}, ErrSinSesion
		}
		id, err := verificar(crudo, secreto)
		if err != nil {
			return Identidad{}, err
		}
		// Se guarda DESPUÉS de verificar, nunca antes: lo que se reenvía al reparto tiene
		// que ser un token que ya pasó por la firma, el `exp` y el alcance de aquí.
		_ = crudo
		return id, nil
	}
}

type reclamos struct {
	Sub           string   `json:"sub"`
	ID            string   `json:"id"`
	BranchID      string   `json:"branchId"`
	BranchIDSnake string   `json:"branch_id"`
	Sucursal      string   `json:"sucursal"`
	Role          string   `json:"role"`
	Rol           string   `json:"rol"`
	Roles         []string `json:"roles"`
	Exp           *float64 `json:"exp"`
	Nbf           *float64 `json:"nbf"`
}

// UnmarshalJSON tolera que los campos de texto vengan como `null` o como número.
//
// `branchId: null` es LO NORMAL en un Super Admin, y reventar ahí lo dejaría fuera de su
// propio sistema. Es el mismo trato que le da `reparto-api`.
func (c *reclamos) UnmarshalJSON(b []byte) error {
	var suelto map[string]json.RawMessage
	if err := json.Unmarshal(b, &suelto); err != nil {
		return err
	}
	texto := func(clave string) string {
		v, hay := suelto[clave]
		if !hay {
			return ""
		}
		var s string
		if json.Unmarshal(v, &s) == nil {
			return s
		}
		return ""
	}
	numero := func(clave string) *float64 {
		v, hay := suelto[clave]
		if !hay {
			return nil
		}
		var f float64
		if json.Unmarshal(v, &f) != nil {
			return nil
		}
		return &f
	}
	c.Sub = texto("sub")
	c.ID = texto("id")
	c.Role = texto("role")
	c.Rol = texto("rol")
	if v, hay := suelto["roles"]; hay {
		_ = json.Unmarshal(v, &c.Roles)
	}
	c.BranchID = texto("branchId")
	c.BranchIDSnake = texto("branch_id")
	c.Sucursal = texto("sucursal")
	c.Exp = numero("exp")
	c.Nbf = numero("nbf")
	return nil
}

// margen: un minuto de holgura contra relojes que no cuadran. El aparato marca la hora del
// suceso y el servidor la suya, y en un teléfono que lleva el día entero sin sincronizar
// esa diferencia existe.
const margen = time.Minute

func verificar(token string, secreto []byte) (Identidad, error) {
	partes := strings.Split(token, ".")
	if len(partes) != 3 {
		return Identidad{}, ErrTokenRoto
	}

	cabecera, err := decodificar(partes[0])
	if err != nil {
		return Identidad{}, ErrTokenRoto
	}
	var cab struct {
		Alg string `json:"alg"`
	}
	if err := json.Unmarshal(cabecera, &cab); err != nil {
		return Identidad{}, ErrTokenRoto
	}
	// El `alg` del token NO elige nada: sólo tiene que coincidir con uno de los nuestros.
	// Un token que diga `none` o `RS256` se cae aquí, no más abajo.
	nuevoHash, ok := algoritmos[cab.Alg]
	if !ok {
		return Identidad{}, fmt.Errorf("%w: algoritmo %q no admitido", ErrSinSesion, cab.Alg)
	}

	firma, err := decodificar(partes[2])
	if err != nil {
		return Identidad{}, ErrTokenRoto
	}
	mac := hmac.New(nuevoHash, secreto)
	mac.Write([]byte(partes[0] + "." + partes[1]))
	// Tiempo constante: comparar firmas con `==` filtra por el tiempo de respuesta
	// cuántos bytes iniciales acertó quien prueba.
	if !hmac.Equal(mac.Sum(nil), firma) {
		return Identidad{}, ErrSinSesion
	}

	cuerpo, err := decodificar(partes[1])
	if err != nil {
		return Identidad{}, ErrTokenRoto
	}
	var c reclamos
	if err := json.Unmarshal(cuerpo, &c); err != nil {
		return Identidad{}, ErrTokenRoto
	}

	ahora := time.Now()
	// Sin `exp` no hay sesión que muera nunca. Se exige.
	if c.Exp == nil {
		return Identidad{}, fmt.Errorf("%w: el token no trae exp", ErrSinSesion)
	}
	if ahora.After(time.Unix(int64(*c.Exp), 0).Add(margen)) {
		return Identidad{}, fmt.Errorf("%w: caducado", ErrSinSesion)
	}
	if c.Nbf != nil && ahora.Add(margen).Before(time.Unix(int64(*c.Nbf), 0)) {
		return Identidad{}, fmt.Errorf("%w: todavía no vale", ErrSinSesion)
	}

	var id Identidad
	id.Persona = primero(c.Sub, c.ID)
	if id.Persona == "" {
		return Identidad{}, ErrSinSesion
	}

	sucursal := strings.TrimSpace(primero(c.BranchID, c.BranchIDSnake, c.Sucursal))
	if sucursal == "" {
		// SIN SUCURSAL **NO** SIGNIFICA «TODAS». Sólo lo significa para un SUPER ADMIN.
		//
		// Ésta es la regla 1 de la casa y ya costó dinero una vez: «el alcance sale de
		// quién pregunta, no de lo que mande el cliente… ya pasó en delivery: un operador
		// de Santiago vio los precios de La Habana».
		//
		// Un token sin sucursal lo puede tener alguien a quien todavía no le han dado la
		// suya, o alguien mal dado de alta. Tratar ese hueco como «las ocho» convierte un
		// dato que FALTA en el permiso más grande que hay. Palabras de Jose, 16/09/2026:
		// «sin sucursal no es por el tipo de usuario no hagas eso por q entonces un
		// usuario sin sucursal ve todas eso esta malisimo».
		//
		// Así que se exige el rol. Los dos que ven todo están en `rolesQueVenTodo`;
		// cualquier otro sin sucursal se queda fuera, que es el fallo barato: se arregla
		// dándole la suya.
		if !veTodo(c) {
			return Identidad{}, fmt.Errorf(
				"%w: sin sucursal y sin un rol que vea todo no hay alcance que aplicar",
				ErrSinSesion)
		}
		id.EsSuperAdmin = true
		return id, nil
	}
	s, err := uuid.Parse(sucursal)
	if err != nil {
		// Una sucursal que no se entiende NO se trata como «ninguna»: eso convertiría un
		// dato roto en permiso para verlo todo.
		return Identidad{}, ErrSinSesion
	}
	id.Sucursal = s
	return id, nil
}

// LOS DOS ROLES QUE VEN LAS OCHO SUCURSALES, y no hay más.
//
// Salen de la tabla `role` de Accesos, leída el 16/09/2026, que tiene SIETE y no los cinco
// que dice el `CLAUDE.md` de Procovar: ADMINISTRADOR, DESARROLLADOR, GERENTE, GESTOR,
// OPERADOR, SUPER ADMIN y SUPERVISOR.
//
//   - `SUPER ADMIN` administra todo Procovar. Palabras de Jose: «los super
//     administradores pueden tocar en todos lados».
//   - `DESARROLLADOR` está por encima todavía: «y el desarrollador mucho mas arriba aun».
//
// Los otros cinco pertenecen a UNA sucursal, incluido `ADMINISTRADOR` — y por eso la
// comparación es contra el texto exacto y no «contiene admin»: un ADMINISTRADOR sin su
// sucursal se llevaría las ocho, que es justo la fuga que se está tapando.
//
// Se compara como texto porque así es como lo compara PEDIDO, que es la fuente.
var rolesQueVenTodo = []string{"SUPER ADMIN", "DESARROLLADOR"}

func veTodo(c reclamos) bool {
	candidatos := append([]string{c.Role, c.Rol}, c.Roles...)
	for _, candidato := range candidatos {
		for _, permitido := range rolesQueVenTodo {
			if strings.EqualFold(strings.TrimSpace(candidato), permitido) {
				return true
			}
		}
	}
	return false
}

func decodificar(s string) ([]byte, error) {
	return base64.RawURLEncoding.DecodeString(s)
}

func primero(valores ...string) string {
	for _, v := range valores {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}
