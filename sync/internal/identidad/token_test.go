package identidad

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"
)

// EL VERIFICADOR DEL TOKEN, que es lo que faltaba para que este servicio aceptara a nadie.
//
// Sin él, `X-Persona` llegaba vacía —el proxy que debía ponerla no existe— y esto
// contestaba 401 a TODO. Nada se subió nunca, y el cliente trataba ese 401 como «la sesión
// murió»: echaba a la persona justo cuando volvía la señal.

const secreto = "0123456789012345678901234567890123456789"

func firmar(t *testing.T, cuerpo map[string]any, alg string) string {
	t.Helper()
	cabecera, _ := json.Marshal(map[string]string{"alg": alg, "typ": "JWT"})
	carga, _ := json.Marshal(cuerpo)
	b := func(v []byte) string { return base64.RawURLEncoding.EncodeToString(v) }
	sinFirma := b(cabecera) + "." + b(carga)
	mac := hmac.New(sha256.New, []byte(secreto))
	mac.Write([]byte(sinFirma))
	return sinFirma + "." + b(mac.Sum(nil))
}

func conToken(t *testing.T, token string) (Identidad, error) {
	t.Helper()
	r := httptest.NewRequest(http.MethodPost, "/sync/aparato", nil)
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	return DeToken([]byte(secreto))(r)
}

func TestUnTokenBuenoEntraConSuSucursal(t *testing.T) {
	suc := uuid.New()
	id, err := conToken(t, firmar(t, map[string]any{
		"sub":      "persona-1",
		"branchId": suc.String(),
		"exp":      time.Now().Add(time.Hour).Unix(),
	}, "HS256"))
	if err != nil {
		t.Fatalf("un token bueno tenía que entrar: %v", err)
	}
	if id.Persona != "persona-1" {
		t.Errorf("persona = %q", id.Persona)
	}
	if id.Sucursal != suc {
		t.Errorf("sucursal = %v, se esperaba %v", id.Sucursal, suc)
	}
	if id.EsSuperAdmin {
		t.Error("con sucursal en el token NO es Super Admin: vería las ocho")
	}
}

func TestLosDosRolesQueVenTodoEntranSinSucursal(t *testing.T) {
	// Jose, 16/09/2026: «los super administradores pueden tocar en todos lados y el
	// desarrollador mucho mas arriba aun». Los dos, y nadie más.
	for _, rol := range []string{"SUPER ADMIN", "DESARROLLADOR"} {
		id, err := conToken(t, firmar(t, map[string]any{
			"sub":      "jefe",
			"branchId": nil,
			"role":     rol,
			"exp":      time.Now().Add(time.Hour).Unix(),
		}, "HS256"))
		if err != nil {
			t.Fatalf("%s tenía que entrar: %v", rol, err)
		}
		if !id.EsSuperAdmin {
			t.Errorf("%s sin sucursal ve las ocho", rol)
		}
	}
}

func TestSinSucursalYSinSerSuperAdminNoSeVeNada(t *testing.T) {
	// LA REGLA 1 DE LA CASA, y ya costó dinero una vez: «un operador de Santiago vio los
	// precios de La Habana». Un token sin sucursal lo puede tener alguien a quien no le
	// han dado la suya todavía; tratar ese hueco como «las ocho» convierte un dato que
	// FALTA en el permiso más grande que hay.
	//
	// Jose, 16/09/2026: «sin sucursal no es por el tipo de usuario no hagas eso por q
	// entonces un usuario sin sucursal ve todas eso esta malisimo».
	// Los cinco roles de la tabla `role` de Accesos que pertenecen a UNA sucursal.
	for _, rol := range []string{
		"", "OPERADOR", "GESTOR", "SUPERVISOR", "ADMINISTRADOR", "GERENTE",
	} {
		cuerpo := map[string]any{
			"sub":      "alguien",
			"branchId": nil,
			"exp":      time.Now().Add(time.Hour).Unix(),
		}
		if rol != "" {
			cuerpo["role"] = rol
		}
		if _, err := conToken(t, firmar(t, cuerpo, "HS256")); err == nil {
			t.Errorf("rol %q sin sucursal NO puede ver las ocho", rol)
		}
	}
}

func TestAdministradorNoEsSuperAdmin(t *testing.T) {
	// `ADMINISTRADOR` es de UNA sucursal. Comparar con «contiene admin» lo dejaría pasar
	// y le daría las ocho.
	if _, err := conToken(t, firmar(t, map[string]any{
		"sub":      "admin-de-una",
		"branchId": nil,
		"role":     "ADMINISTRADOR",
		"exp":      time.Now().Add(time.Hour).Unix(),
	}, "HS256")); err == nil {
		t.Fatal("un ADMINISTRADOR sin sucursal no puede ver las ocho")
	}
}

func TestUnaSucursalQueNoSeEntiendeNoAbreTodO(t *testing.T) {
	// Lo peligroso sería tratarla como «ninguna»: un dato roto se convertiría en permiso
	// para verlo todo. Es la regla 1 de la casa.
	if _, err := conToken(t, firmar(t, map[string]any{
		"sub":      "x",
		"branchId": "esto-no-es-un-uuid",
		"exp":      time.Now().Add(time.Hour).Unix(),
	}, "HS256")); err == nil {
		t.Fatal("una sucursal ilegible tiene que rechazarse, no abrirlo todo")
	}
}

func TestLaFirmaSeComprueba(t *testing.T) {
	bueno := firmar(t, map[string]any{
		"sub": "x", "branchId": uuid.New().String(),
		"exp": time.Now().Add(time.Hour).Unix(),
	}, "HS256")
	// Se cambia un carácter de la firma.
	malo := bueno[:len(bueno)-1] + "A"
	if malo == bueno {
		t.Skip("la firma acababa en A")
	}
	if _, err := conToken(t, malo); err == nil {
		t.Fatal("una firma que no cuadra tiene que rechazarse")
	}
}

func TestUnTokenSinExpNoVale(t *testing.T) {
	// Sin `exp` no hay sesión que muera nunca.
	if _, err := conToken(t, firmar(t, map[string]any{
		"sub": "x", "branchId": uuid.New().String(),
	}, "HS256")); err == nil {
		t.Fatal("un token sin caducidad tiene que rechazarse")
	}
}

func TestUnTokenCaducadoNoVale(t *testing.T) {
	if _, err := conToken(t, firmar(t, map[string]any{
		"sub": "x", "branchId": uuid.New().String(),
		"exp": time.Now().Add(-2 * time.Hour).Unix(),
	}, "HS256")); err == nil {
		t.Fatal("un token caducado tiene que rechazarse")
	}
}

func TestElAlgNoElige(t *testing.T) {
	// Un token que diga `none` se cae ANTES de mirar la firma. Es el ataque clásico.
	cabecera, _ := json.Marshal(map[string]string{"alg": "none", "typ": "JWT"})
	carga, _ := json.Marshal(map[string]any{
		"sub": "x", "exp": time.Now().Add(time.Hour).Unix(),
	})
	b := func(v []byte) string { return base64.RawURLEncoding.EncodeToString(v) }
	if _, err := conToken(t, b(cabecera)+"."+b(carga)+"."); err == nil {
		t.Fatal("`alg: none` tiene que rechazarse")
	}
}

func TestSinCabeceraNoHaySesion(t *testing.T) {
	if _, err := conToken(t, ""); err == nil {
		t.Fatal("sin Authorization no hay identidad")
	}
}

// EL TOKEN SE GUARDA PARA REENVIARLO, y sólo si pasó la verificación.
//
// Este servicio no escribe los datos: se los manda a `reparto-api`, y esa llamada la tiene
// que firmar LA MISMA PERSONA. Con la clave de servicio, `/api/board/columns` contestaba
// 401 «no viene token» y el apunte se quedaba en la cola para siempre — así se quedó la
// zona «Vista» dentro de un teléfono. Ver `identidad.Identidad.Token`.
func TestElTokenVerificadoSeGuardaParaReenviarlo(t *testing.T) {
	token := firmar(t, map[string]any{
		"sub":      "persona-1",
		"branchId": uuid.New().String(),
		"exp":      time.Now().Add(time.Hour).Unix(),
	}, "HS256")

	id, err := conToken(t, token)
	if err != nil {
		t.Fatalf("un token bueno tenía que entrar: %v", err)
	}
	if id.Token != token {
		t.Errorf("no se guardó el token para reenviarlo: %q", id.Token)
	}
}

// Y un token QUE NO PASA no deja nada detrás. Guardarlo antes de comprobar la firma sería
// reenviarle al reparto un token que aquí se rechazó, que es peor que no comprobarlo.
func TestUnTokenQueNoPasaNoDejaTokenQueReenviar(t *testing.T) {
	casos := map[string]string{
		"firma cambiada": firmar(t, map[string]any{
			"sub": "x", "branchId": uuid.New().String(),
			"exp": time.Now().Add(time.Hour).Unix(),
		}, "HS256") + "roto",
		"caducado": firmar(t, map[string]any{
			"sub": "x", "branchId": uuid.New().String(),
			"exp": time.Now().Add(-2 * time.Hour).Unix(),
		}, "HS256"),
		"sin sucursal y sin rol que vea todo": firmar(t, map[string]any{
			"sub": "x", "role": "GESTOR",
			"exp": time.Now().Add(time.Hour).Unix(),
		}, "HS256"),
	}
	for nombre, token := range casos {
		t.Run(nombre, func(t *testing.T) {
			id, err := conToken(t, token)
			if err == nil {
				t.Fatal("tenía que rechazarse")
			}
			if id.Token != "" {
				t.Errorf("un token rechazado no puede salir de aquí para reenviarse: %q",
					id.Token)
			}
		})
	}
}
