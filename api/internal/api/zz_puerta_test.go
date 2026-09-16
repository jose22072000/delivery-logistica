package api

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// montarCot monta LAS RUTAS DE COTIZACION, que `montarTab` no monta.
func montarCot(t *testing.T, q sqlc.Querier, llave string) http.Handler {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoTab)
	t.Setenv("SERVICE_API_KEY", llave)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuracion: %v", err)
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	s := NuevoServidor(cfg, reg,
		alcance.NuevaPorteria(fuenteTab{q: q}, reg),
		auth.NuevoVerificador([]byte(secretoTab)), nil)
	rt := httpx.NuevoRouter(httpx.IDDePeticion, httpx.ConRegistro(reg), httpx.RecuperarPanico, httpx.SinCache)
	sesion := []httpx.Medio{s.verif.Exigir, s.porteria.Exigir}
	admin := []httpx.Medio{s.verif.Exigir, auth.ExigirAdmin, s.porteria.Exigir}
	s.rutasCotizacion(rt, sesion, admin)
	return rt.Handler()
}

var _ = strings.TrimSpace

// Sin llave, y con llave + cabecera de sucursal ajena.
func TestAuditoriaPuertaDeCotizacion(t *testing.T) {
	q := nuevoEspejo()
	h := montarCot(t, q, "la-llave-buena")

	// 1 · sin llave ninguna
	r := httptest.NewRequest(http.MethodPost, "/api/quote/batch", nil)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	t.Logf("sin llave           -> %d %s", w.Code, w.Body.String())

	// 2 · con llave mala
	r = httptest.NewRequest(http.MethodPost, "/api/quote/batch", nil)
	r.Header.Set("X-Api-Key", "no-es-la-buena")
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	t.Logf("llave mala          -> %d %s", w.Code, w.Body.String())

	// 3 · con sesion de persona normal (sin llave)
	r = httptest.NewRequest(http.MethodPost, "/api/quote/batch", nil)
	r.Header.Set("Authorization", "Bearer "+tokenTab(t, sucStg.String()))
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	t.Logf("sesion de persona   -> %d %s", w.Code, w.Body.String())

	// 4 · CON la llave buena y cuerpo vacio: se pasa la puerta
	r = httptest.NewRequest(http.MethodPost, "/api/quote/batch", strings.NewReader(`{"pedidos":[]}`))
	r.Header.Set("X-Api-Key", "la-llave-buena")
	r.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	t.Logf("llave buena         -> %d %s", w.Code, w.Body.String())

	// 5 · CON la llave buena + X-Sucursal-Id de OTRA sucursal: se intenta acotar
	r = httptest.NewRequest(http.MethodPost, "/api/quote/batch", strings.NewReader(`{"pedidos":[]}`))
	r.Header.Set("X-Api-Key", "la-llave-buena")
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("X-Sucursal-Id", sucStg.String())
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	t.Logf("llave + X-Sucursal  -> %d %s", w.Code, w.Body.String())
}
