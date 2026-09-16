package api

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

const claveDeServicioDePrueba = "clave-de-servicio-de-pruebas-larga"

// montarCotizacion monta SÓLO las rutas de cotización, que ninguna otra prueba montaba.
// Por eso sus dos guardas —la llave y el borrado de la cabecera— llevaban vivas sin que
// nadie las hubiera ejercitado una sola vez.
func montarCotizacion(t *testing.T, q sqlc.Querier) http.Handler {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoTab)
	t.Setenv("SERVICE_API_KEY", claveDeServicioDePrueba)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	s := NuevoServidor(cfg, reg,
		alcance.NuevaPorteria(fuenteTab{q: q}, reg),
		auth.NuevoVerificador([]byte(secretoTab)),
		nil)

	rt := httpx.NuevoRouter(httpx.IDDePeticion, httpx.ConRegistro(reg), httpx.RecuperarPanico, httpx.SinCache)
	sesion := []httpx.Medio{s.verif.Exigir, s.porteria.Exigir}
	admin := []httpx.Medio{s.verif.Exigir, auth.ExigirAdmin, s.porteria.Exigir}
	s.rutasCotizacion(rt, sesion, admin)
	return rt.Handler()
}

// LA PUERTA DE SERVICIO SÓLO LA ABRE LA LLAVE, y ni siquiera una sesión de persona.
//
// `POST /api/quote/batch` es por donde entra el lote de PEDIDO con los pedidos de las ocho
// sucursales. Su actor sintético lleva desde el 16/09/2026 un `Rol: "SUPER ADMIN"`
// explícito —sin él, `VeTodasLasSucursales` decía que no y la puerta contestaba 403 a
// todo: 84 rechazos en quince minutos—. Ese rol hace que esta guarda importe más, no
// menos: lo único que separa la puerta de «cualquiera con sesión» es la llave.
func TestLaPuertaDeCotizacionSoloLaAbreLaLlave(t *testing.T) {
	h := montarCotizacion(t, &dobleDePanel{})

	casos := []struct {
		nombre   string
		preparar func(*http.Request)
		abre     bool
	}{
		{"sin nada", func(*http.Request) {}, false},
		{"con la llave mal", func(r *http.Request) {
			r.Header.Set("X-Api-Key", "esta-no-es")
		}, false},
		{"con una sesión de persona normal", func(r *http.Request) {
			r.Header.Set("Authorization", "Bearer "+tokenTab(t, uuid.New().String()))
		}, false},
		{"con la llave buena", func(r *http.Request) {
			r.Header.Set("X-Api-Key", claveDeServicioDePrueba)
		}, true},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodPost, "/api/quote/batch",
				strings.NewReader(`{}`))
			r.Header.Set("Content-Type", "application/json")
			c.preparar(r)
			w := httptest.NewRecorder()
			h.ServeHTTP(w, r)

			if !c.abre {
				if w.Code != http.StatusUnauthorized {
					t.Fatalf("código %d, se esperaba 401: esta puerta escribe pedidos "+
						"de las ocho sucursales y sólo la abre la llave — %s",
						w.Code, w.Body.String())
				}
				return
			}
			// Con la llave buena pasa la portería. Que el cuerpo vacío dé 400 es lo
			// esperado; lo que NO puede dar es 401 ni 403.
			if w.Code == http.StatusUnauthorized || w.Code == http.StatusForbidden {
				t.Fatalf("código %d con la llave buena: el lote de PEDIDO no entra y "+
					"nadie se entera — %s", w.Code, w.Body.String())
			}
		})
	}
}

// Y CON LA LLAVE NO SE PUEDE ACOTAR A UNA SUCURSAL.
//
// El actor sintético no tiene sucursal propia, así que `alcance.Resolver` caería en la
// cabecera `X-Sucursal-Id` si ésta llegara viva. Quien tuviera la llave podría entonces
// acotar el lote nocturno a una sola sucursal y **el reparto se comería en silencio los
// pedidos de las otras siete**: 200 OK, cero errores, cero pedidos, y nadie mirando. Es la
// forma exacta de los 2.284 que se perdieron (`CLAUDE.md` §3).
//
// Lo único que lo impide es un `r.Header.Del` en `cotizacion.go`, que hasta hoy no tenía
// ni una prueba: se podía borrar y todo seguía verde.
//
// Se prueba contra el middleware DIRECTAMENTE y no mandando una petición entera, y eso es
// deliberado: por la ruta completa, un cuerpo de lote válido tendría que atravesar medio
// cotizador antes de tocar el alcance, y una prueba que depende de eso deja de comprobar
// esta guarda el día que el cotizador rechace antes. Aquí se comprueba lo único que
// importa: que la cabecera no llega viva al otro lado, y que quien llega lleva su rol.
func TestConLaLlaveNoSePuedeAcotarAUnaSucursal(t *testing.T) {
	var llego string
	var usuario *auth.Usuario
	dentro := soloServicioDeCotizacion(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			llego = r.Header.Get(alcance.CabeceraSucursal)
			usuario = auth.De(r)
		}))

	r := httptest.NewRequest(http.MethodPost, "/api/quote/batch", strings.NewReader(`{}`))
	// La sucursal que mandaría quien quisiera estrechar el lote.
	r.Header.Set(alcance.CabeceraSucursal, holDePanel.String())
	dentro.ServeHTTP(httptest.NewRecorder(), r)

	if llego != "" {
		t.Errorf("la cabecera %s llegó viva (%q): quien tenga la llave puede acotar el "+
			"lote a una sucursal y los pedidos de las otras siete se pierden en silencio",
			alcance.CabeceraSucursal, llego)
	}
	if usuario == nil {
		t.Fatal("no se colgó ninguna persona: la portería devolvería 500")
	}
	// Y el rol, que es la otra mitad: sin él la portería contesta 403 a todo lo que entre
	// por aquí. Fue lo que dejó 84 lotes de PEDIDO rechazados en quince minutos.
	if !alcance.VeTodasLasSucursales(usuario) {
		t.Errorf("la persona de servicio (%+v) no ve las ocho sucursales: el lote de "+
			"PEDIDO entra con 403", *usuario)
	}
}
