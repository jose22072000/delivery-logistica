// Validación de la identidad que emite auth.procovar.cloud.
//
// AQUÍ NO SE COMPRUEBAN CONTRASEÑAS, y no es una tarea pendiente: es la decisión. Quien
// manda en personas, roles y sucursales es auth, y punto (`docs/identidad.md`). Dos
// sitios comprobando contraseñas son dos sitios donde dar de baja a alguien, y el día
// que se olvide uno, la persona despedida sigue entrando por el otro.
//
// Lo que se hace aquí es leer un token ya firmado y creerle SÓLO si la firma cuadra.
//
// La verificación va a mano, con `crypto/hmac`, y no con una biblioteca de JWT. Son
// treinta líneas de recorte de cadenas y un HMAC; a cambio no hay una dependencia más
// que mantener, y sobre todo el algoritmo está FIJADO en el código: la familia de fallos
// clásica del JWT es aceptar el `alg` que venga en el token —`none`, o RS256 verificado
// con la clave pública como si fuera secreto HMAC— y eso aquí no se puede ni escribir.
package auth

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
)

var (
	ErrSinToken   = errors.New("no viene token")
	ErrTokenRoto  = errors.New("el token no tiene la forma de un JWT")
	ErrFirma      = errors.New("la firma no cuadra")
	ErrCaducado   = errors.New("el token está caducado")
	ErrSinPersona = errors.New("el token no dice de quién es")
)

// Usuario es lo que el token dice de quien pide. Nada de esto se consulta en la base:
// la base de personas es la de auth.
type Usuario struct {
	ID       string // `sub` (APK) o `id` (web) — el identificador de la persona
	Email    string
	Nombre   string
	Rol      string   // el principal, para las comprobaciones que ya existen
	Roles    []string // todos, para lo que venga
	Sucursal string   // "" = no pertenece a ninguna (Super Admin)
}

// EsAdmin: la comprobación de `/api/branches`, que exige administrador.
func (u *Usuario) EsAdmin() bool {
	if strings.EqualFold(u.Rol, "admin") {
		return true
	}
	for _, r := range u.Roles {
		if strings.EqualFold(r, "admin") {
			return true
		}
	}
	return false
}

// EsSuperAdmin: administrador SIN sucursal. La distinción importa porque es quien ve las
// ocho sucursales y quien puede elegir una por cabecera; un administrador con sucursal
// sigue viendo sólo la suya.
func (u *Usuario) EsSuperAdmin() bool { return u.EsAdmin() && u.Sucursal == "" }

// Verificador guarda el secreto. Se construye una vez al arrancar.
type Verificador struct {
	secreto []byte
	// margen para el desfase de reloj entre este servidor y el de auth. Sin él, dos
	// máquinas con medio minuto de diferencia rechazan tokens recién emitidos.
	margen time.Duration
}

func NuevoVerificador(secreto []byte) *Verificador {
	return &Verificador{secreto: secreto, margen: 60 * time.Second}
}

// DelaPeticion saca el token y lo valida.
//
// El orden es el del contrato: cabecera `Authorization: Bearer <token>` primero —es por
// donde entra la APK— y si no, la cookie `token`, que es lo que deja el login único de
// la web.
func (v *Verificador) DelaPeticion(r *http.Request) (*Usuario, error) {
	crudo := ""
	if cab := r.Header.Get("Authorization"); cab != "" {
		if partes := strings.Fields(cab); len(partes) == 2 && strings.EqualFold(partes[0], "Bearer") {
			crudo = partes[1]
		}
	}
	if crudo == "" {
		if c, err := r.Cookie("token"); err == nil {
			crudo = c.Value
		}
	}
	if strings.TrimSpace(crudo) == "" {
		return nil, ErrSinToken
	}
	return v.Verificar(crudo)
}

// Verificar comprueba la firma y la vigencia, y devuelve la persona.
func (v *Verificador) Verificar(token string) (*Usuario, error) {
	partes := strings.Split(token, ".")
	if len(partes) != 3 {
		return nil, ErrTokenRoto
	}

	cabecera, err := decodificar(partes[0])
	if err != nil {
		return nil, ErrTokenRoto
	}
	var cab struct {
		Alg string `json:"alg"`
	}
	if err := json.Unmarshal(cabecera, &cab); err != nil {
		return nil, ErrTokenRoto
	}
	// El `alg` del token NO elige nada: sólo tiene que coincidir con uno de los nuestros.
	// Un token que diga `none` o `RS256` se cae aquí, no más abajo.
	nuevoHash, ok := algoritmos[cab.Alg]
	if !ok {
		return nil, fmt.Errorf("%w: algoritmo %q no admitido", ErrFirma, cab.Alg)
	}

	firmaEsperada, err := decodificar(partes[2])
	if err != nil {
		return nil, ErrTokenRoto
	}
	mac := hmac.New(nuevoHash, v.secreto)
	mac.Write([]byte(partes[0] + "." + partes[1]))
	// Comparación en tiempo constante: comparar firmas con `==` filtra por el tiempo de
	// respuesta cuántos bytes iniciales acertó quien prueba.
	if !hmac.Equal(mac.Sum(nil), firmaEsperada) {
		return nil, ErrFirma
	}

	cuerpo, err := decodificar(partes[1])
	if err != nil {
		return nil, ErrTokenRoto
	}
	var c reclamos
	if err := json.Unmarshal(cuerpo, &c); err != nil {
		return nil, ErrTokenRoto
	}

	ahora := time.Now()
	// Sin `exp` no hay sesión que muera nunca. Se exige.
	if c.Exp == nil {
		return nil, fmt.Errorf("%w: el token no trae exp", ErrCaducado)
	}
	if ahora.After(time.Unix(int64(*c.Exp), 0).Add(v.margen)) {
		return nil, ErrCaducado
	}
	if c.Nbf != nil && ahora.Add(v.margen).Before(time.Unix(int64(*c.Nbf), 0)) {
		return nil, fmt.Errorf("%w: todavía no vale", ErrCaducado)
	}

	// `sub` es lo que manda auth en el token nuevo (el de la APK); `id` es lo que
	// llevaba el de la web. Se aceptan los dos porque las dos puertas están abiertas a
	// la vez y el mismo servicio atiende a las dos.
	u := &Usuario{
		ID:       primero(c.Sub, c.ID),
		Email:    c.Email,
		Nombre:   primero(c.Name, c.Nombre),
		Rol:      primero(c.Role, c.Rol),
		Roles:    c.Roles,
		Sucursal: strings.TrimSpace(primero(c.BranchID, c.BranchIDSnake, c.Sucursal)),
	}
	if u.ID == "" {
		return nil, ErrSinPersona
	}
	if u.Rol == "" && len(u.Roles) > 0 {
		u.Rol = u.Roles[0]
	}
	return u, nil
}

// reclamos: los campos que se leen del token. Van con punteros los numéricos para poder
// distinguir "no vino" de "vino cero".
//
// `branchId` llega a veces como null: por eso es *string y no string, y por eso hay tres
// nombres — `branchId` (web), `branch_id` y `sucursal` (token nuevo). Escribir sólo uno
// y que el otro llegue vacío es exactamente el fallo de «se ven cero pedidos con un 200».
type reclamos struct {
	Sub           string   `json:"sub"`
	ID            string   `json:"id"`
	Email         string   `json:"email"`
	Name          string   `json:"name"`
	Nombre        string   `json:"nombre"`
	Role          string   `json:"role"`
	Rol           string   `json:"rol"`
	Roles         []string `json:"roles"`
	BranchID      string   `json:"branchId"`
	BranchIDSnake string   `json:"branch_id"`
	Sucursal      string   `json:"sucursal"`
	Exp           *float64 `json:"exp"`
	Nbf           *float64 `json:"nbf"`
}

// UnmarshalJSON tolera que los campos de texto vengan como null o como número. El
// contrato de delivery dice "si alguno no es string, no hay usuario", pero eso sólo
// aplica a los obligatorios: un `branchId: null` es lo normal en el Super Admin, y
// reventar ahí lo dejaría fuera de su propio sistema.
func (c *reclamos) UnmarshalJSON(b []byte) error {
	type alias reclamos
	var a alias
	dec := json.NewDecoder(strings.NewReader(string(b)))
	if err := dec.Decode(&a); err != nil {
		// Un tipo inesperado en un campo suelto no puede tumbar el token entero: se
		// reintenta campo a campo y lo que no sea texto se deja vacío.
		var suelto map[string]any
		if err2 := json.Unmarshal(b, &suelto); err2 != nil {
			return err
		}
		a = alias{
			Sub:           texto(suelto, "sub"),
			ID:            texto(suelto, "id"),
			Email:         texto(suelto, "email"),
			Name:          texto(suelto, "name"),
			Nombre:        texto(suelto, "nombre"),
			Role:          texto(suelto, "role"),
			Rol:           texto(suelto, "rol"),
			Roles:         textos(suelto, "roles"),
			BranchID:      texto(suelto, "branchId"),
			BranchIDSnake: texto(suelto, "branch_id"),
			Sucursal:      texto(suelto, "sucursal"),
			Exp:           numero(suelto, "exp"),
			Nbf:           numero(suelto, "nbf"),
		}
	}
	*c = reclamos(a)
	return nil
}

var algoritmos = map[string]func() hash.Hash{
	"HS256": sha256.New,
	"HS384": sha512.New384,
	"HS512": sha512.New,
}

// Los JWT van en base64url SIN relleno; hay emisores que lo ponen igual. Se aceptan los
// dos: rechazar el token por un `=` de más es un 401 que nadie sabe explicar.
func decodificar(s string) ([]byte, error) {
	if b, err := base64.RawURLEncoding.DecodeString(s); err == nil {
		return b, nil
	}
	return base64.URLEncoding.DecodeString(s)
}

func primero(valores ...string) string {
	for _, v := range valores {
		if v != "" {
			return v
		}
	}
	return ""
}

func texto(m map[string]any, clave string) string {
	if v, ok := m[clave].(string); ok {
		return v
	}
	return ""
}

func textos(m map[string]any, clave string) []string {
	bruto, ok := m[clave].([]any)
	if !ok {
		return nil
	}
	var salida []string
	for _, v := range bruto {
		if s, ok := v.(string); ok {
			salida = append(salida, s)
		}
	}
	return salida
}

func numero(m map[string]any, clave string) *float64 {
	if v, ok := m[clave].(float64); ok {
		return &v
	}
	return nil
}
