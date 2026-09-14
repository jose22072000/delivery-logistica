package api

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
)

// El router ENTERO tiene que montar.
//
// No es una prueba de cortesía. `ServeMux` de Go valida los patrones AL REGISTRARLOS y
// entra en PÁNICO si dos son ambiguos —ninguno más específico que el otro—, así que un
// choque entre dos módulos no da un error de compilación ni un test rojo en su paquete:
// tira el proceso al arrancar, en producción, después de un despliegue que pasó todas las
// pruebas. Ya pasó una vez con el 405 y habría vuelto a pasar con `/api/board/columns/orden`.
//
// Cada módulo prueba SUS rutas montando su propio router con sólo las suyas. Esta es la
// única que las monta todas juntas, que es como corren de verdad.
func TestElRouterEnteroMonta(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", "0123456789012345678901234567890123456789")

	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))

	s := NuevoServidor(cfg, reg,
		alcance.NuevaPorteria(nil, reg),
		auth.NuevoVerificador([]byte("0123456789012345678901234567890123456789")),
		func(context.Context) error { return nil },
	)

	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("el router NO monta, el proceso moriría al arrancar: %v", r)
		}
	}()

	h := s.Rutas()
	if h == nil {
		t.Fatal("Rutas() devolvió nil")
	}

	// Y que de verdad responde: /health no lleva sesión, así que sirve de latido del
	// montaje entero sin tener que fabricar un token.
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("/health devolvió %d, esperaba 200", rec.Code)
	}
}
