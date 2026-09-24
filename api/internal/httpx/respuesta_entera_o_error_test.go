package httpx_test

// UNA RESPUESTA SALE ENTERA O SALE COMO ERROR. Nunca a medias con un código de éxito.
//
// El caso que puso esto aquí, cazado el 24/09/2026 probando la API desde fuera:
//
//	POST /api/routes con "originLat": 1e308  ->  201 y el cuerpo VACÍO
//	GET  /api/routes a partir de entonces    ->  200 y el cuerpo VACÍO, para siempre
//
// La ruta se guardaba con `total_distance = NaN` (la resta de la haversine se desborda y
// `math.Sin(±Inf)` es NaN) y `json.Encoder` se niega a codificar un no-finito. Pero el
// código de éxito YA estaba escrito cuando el codificador fallaba, así que por fuera se
// veía un 2xx con cero bytes: la lista de rutas de la sucursal entera desaparecida, sin un
// error que enseñar ni un código que distinguir de «no hay rutas».
//
// Es el §3 del CLAUDE.md —una lista que vuelve a medias con 200— y el §4 —nada se descarta
// en silencio— a la vez.
//
// LAS PRUEBAS VAN EN PAREJA, como manda la casa: una que el 500 salga cuando el cuerpo no
// se puede codificar, y otra que NO salga cuando sí se puede. Sin la segunda, un `JSON`
// que contestara 500 SIEMPRE pasaría la primera.

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"procovar/reparto-api/internal/httpx"
)

// conNoFinito es el cuerpo que rompe al codificador: un `float64` que no es finito.
// Se llega a él sin ninguna mala intención —una distancia calculada sobre una coordenada
// desbordada— y por eso se prueba con la forma de una respuesta de verdad.
type conNoFinito struct {
	ID            string  `json:"id"`
	TotalDistance float64 `json:"totalDistance"`
}

func TestUnCuerpoQueNoSeCodificaSaleComo500YNoComoUn200Vacio(t *testing.T) {
	var registro bytes.Buffer
	reg := slog.New(slog.NewTextHandler(&registro, nil))

	h := httpx.Encadenar(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			httpx.JSON(w, r, http.StatusCreated, conNoFinito{ID: "la-ruta", TotalDistance: math.NaN()})
		}),
		httpx.ConRegistro(reg),
	)

	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/api/routes", nil))

	if w.Code != http.StatusInternalServerError {
		t.Fatalf("un cuerpo que no se puede codificar tiene que ser 500, y fue %d con el cuerpo %q.\n"+
			"  Un 2xx con el cuerpo cortado es justo el fallo que esta prueba existe para cazar: "+
			"el cliente lo da por bueno y la lista desaparece sin que nadie vea un error.",
			w.Code, w.Body.String())
	}
	if got := strings.TrimSpace(w.Body.String()); got != `{"error":"Error interno"}` {
		t.Fatalf("el cuerpo del 500 tiene que ser el del contrato y fue %q", got)
	}
	if !strings.Contains(registro.String(), "no se pudo codificar") {
		t.Fatalf("tiene que quedar dicho en el registro por qué se perdió la respuesta, y el registro fue:\n%s",
			registro.String())
	}
}

// Y LA OTRA MITAD: un cuerpo normal sale con su código y su contenido. Sin esta, un `JSON`
// que contestara 500 siempre dejaría la de arriba en verde y la API entera rota.
func TestUnCuerpoNormalSigueSaliendoConSuCodigoYSuContenido(t *testing.T) {
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	h := httpx.Encadenar(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			httpx.JSON(w, r, http.StatusCreated, conNoFinito{ID: "la-ruta", TotalDistance: 66.7})
		}),
		httpx.ConRegistro(reg),
	)

	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/api/routes", nil))

	if w.Code != http.StatusCreated {
		t.Fatalf("código %d, se esperaba 201: %s", w.Code, w.Body.String())
	}
	var vuelta conNoFinito
	if err := json.Unmarshal(w.Body.Bytes(), &vuelta); err != nil {
		t.Fatalf("la respuesta buena tiene que ser JSON legible y fue %q: %v", w.Body.String(), err)
	}
	if vuelta.ID != "la-ruta" || vuelta.TotalDistance != 66.7 {
		t.Fatalf("la respuesta buena volvió cambiada: %+v", vuelta)
	}
	if ct := w.Header().Get("Content-Type"); ct != "application/json; charset=utf-8" {
		t.Fatalf("Content-Type %q", ct)
	}
}

// Un cuerpo nulo sigue siendo «sólo el código», que es lo que usan los 204 y compañía.
func TestUnCuerpoNuloSigueSiendoSoloElCodigo(t *testing.T) {
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	h := httpx.Encadenar(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			httpx.JSON(w, r, http.StatusNoContent, nil)
		}),
		httpx.ConRegistro(reg),
	)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/x", nil))
	if w.Code != http.StatusNoContent || w.Body.Len() != 0 {
		t.Fatalf("código %d con %d bytes; se esperaba 204 sin cuerpo", w.Code, w.Body.Len())
	}
}
