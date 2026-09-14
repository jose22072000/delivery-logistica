package auth_test

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/sha512"
	"encoding/base64"
	"encoding/json"
	"hash"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"procovar/reparto-api/internal/auth"
)

const secreto = "un-secreto-de-pruebas-de-al-menos-32-caracteres"

func firmar(t *testing.T, alg string, reclamos map[string]any) string {
	t.Helper()
	if _, hay := reclamos["exp"]; !hay {
		reclamos["exp"] = time.Now().Add(time.Hour).Unix()
	}
	cab := b64(t, map[string]any{"alg": alg, "typ": "JWT"})
	cuerpo := b64(t, reclamos)
	var nuevo func() hash.Hash
	switch alg {
	case "HS512":
		nuevo = sha512.New
	default:
		nuevo = sha256.New
	}
	mac := hmac.New(nuevo, []byte(secreto))
	mac.Write([]byte(cab + "." + cuerpo))
	return cab + "." + cuerpo + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func b64(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

// El token de la web (login único) y el de la APK traen la identidad con nombres
// distintos —`id` y `sub`— porque las dos puertas están abiertas a la vez y el mismo
// servicio atiende a las dos.
func TestSeAceptanLosDosTokens(t *testing.T) {
	v := auth.NuevoVerificador([]byte(secreto))

	web, err := v.Verificar(firmar(t, "HS256", map[string]any{
		"id": "web-1", "email": "a@b.cu", "name": "Ana", "role": "OPERADOR", "branchId": "s-1",
	}))
	if err != nil || web.ID != "web-1" || web.Sucursal != "s-1" {
		t.Fatalf("token de la web: %v %+v", err, web)
	}

	apk, err := v.Verificar(firmar(t, "HS512", map[string]any{
		"sub": "apk-1", "roles": []string{"SUPERVISOR"}, "sucursal": "s-2",
	}))
	if err != nil || apk.ID != "apk-1" || apk.Sucursal != "s-2" || apk.Rol != "SUPERVISOR" {
		t.Fatalf("token de la APK: %v %+v", err, apk)
	}
}

// `branchId: null` es lo NORMAL en el Super Admin. Reventar ahí lo dejaría fuera de su
// propio sistema.
func TestBranchIdNuloEsSuperAdmin(t *testing.T) {
	v := auth.NuevoVerificador([]byte(secreto))
	u, err := v.Verificar(firmar(t, "HS256", map[string]any{
		"id": "sa", "role": "admin", "branchId": nil,
	}))
	if err != nil {
		t.Fatalf("%v", err)
	}
	if u.Sucursal != "" || !u.EsSuperAdmin() {
		t.Fatalf("%+v", u)
	}
}

// Un admin CON sucursal no es Super Admin: sigue viendo sólo la suya.
func TestAdminConSucursalNoEsSuperAdmin(t *testing.T) {
	v := auth.NuevoVerificador([]byte(secreto))
	u, _ := v.Verificar(firmar(t, "HS256", map[string]any{"id": "a", "role": "admin", "branchId": "s-1"}))
	if !u.EsAdmin() {
		t.Fatal("es admin")
	}
	if u.EsSuperAdmin() {
		t.Fatal("pero NO Super Admin: pertenece a una sucursal")
	}
}

// El `alg` del token no elige nada. Ésta es la familia de fallos clásica del JWT.
func TestAlgoritmoDelTokenNoMandaNada(t *testing.T) {
	v := auth.NuevoVerificador([]byte(secreto))

	cab := b64(t, map[string]any{"alg": "none", "typ": "JWT"})
	cuerpo := b64(t, map[string]any{"sub": "colado", "exp": time.Now().Add(time.Hour).Unix()})
	if _, err := v.Verificar(cab + "." + cuerpo + "."); err == nil {
		t.Fatal("«alg: none» tenía que rechazarse")
	}

	// Firmado de verdad, pero diciendo que es RS256: la firma HMAC cuadra si alguien
	// verifica con la clave pública como secreto. Aquí ni se intenta.
	cab = b64(t, map[string]any{"alg": "RS256", "typ": "JWT"})
	mac := hmac.New(sha256.New, []byte(secreto))
	mac.Write([]byte(cab + "." + cuerpo))
	token := cab + "." + cuerpo + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	if _, err := v.Verificar(token); err == nil {
		t.Fatal("RS256 tenía que rechazarse")
	}
}

// Sin `exp` no hay sesión que muera nunca.
func TestTokenSinCaducidadSeRechaza(t *testing.T) {
	v := auth.NuevoVerificador([]byte(secreto))
	cab := b64(t, map[string]any{"alg": "HS256"})
	cuerpo := b64(t, map[string]any{"sub": "x"})
	mac := hmac.New(sha256.New, []byte(secreto))
	mac.Write([]byte(cab + "." + cuerpo))
	if _, err := v.Verificar(cab + "." + cuerpo + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil))); err == nil {
		t.Fatal("tenía que rechazarse")
	}
}

// El orden del contrato: primero la cabecera (por donde entra la APK), y si no, la
// cookie que deja el login único de la web.
func TestPrimeroLaCabeceraLuegoLaCookie(t *testing.T) {
	v := auth.NuevoVerificador([]byte(secreto))

	r := httptest.NewRequest(http.MethodGet, "/api/orders", nil)
	r.AddCookie(&http.Cookie{Name: "token", Value: firmar(t, "HS256", map[string]any{"id": "de-la-cookie"})})
	u, err := v.DelaPeticion(r)
	if err != nil || u.ID != "de-la-cookie" {
		t.Fatalf("cookie: %v %+v", err, u)
	}

	r.Header.Set("Authorization", "Bearer "+firmar(t, "HS256", map[string]any{"id": "de-la-cabecera"}))
	u, err = v.DelaPeticion(r)
	if err != nil || u.ID != "de-la-cabecera" {
		t.Fatalf("cabecera: %v %+v", err, u)
	}
}

// Un token con otro secreto no entra, por muy bien formado que esté.
func TestOtroSecretoNoEntra(t *testing.T) {
	v := auth.NuevoVerificador([]byte("otro-secreto-igual-de-largo-que-el-bueno"))
	if _, err := v.Verificar(firmar(t, "HS256", map[string]any{"id": "x"})); err == nil {
		t.Fatal("tenía que rechazarse")
	}
}
