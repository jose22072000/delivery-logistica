package reparto

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/sincro"
)

// LA DIRECCIÓN A LA QUE SE REENVÍA UN APUNTE, que es lo que tiró el día entero.
//
// El aparato encola la ruta SIN prefijo —`/board/columns`— porque es la que usa contra su
// propia base. `reparto-api` las sirve todas bajo `/api`. Reenviarlas tal cual daba 404 en
// cada apunte, y un 4xx aquí es «rechazo de negocio»: acababan en la bandeja como si el
// reparto hubiera dicho que no.
//
// Y lo peor era el efecto dominó: el apunte rechazado era el que CREA la zona del tablero,
// así que los cinco que colocaban pedidos dentro se caían detrás con «el identificador
// provisional todavía no corresponde a nada». Seis apuntes de trabajo real, perdidos por
// una barra, el 16/09/2026.
//
// Este paquete no tenía NI UNA prueba. Por eso sobrevivió.
func TestElApunteSeReenviaBajoApi(t *testing.T) {
	var vistas []string
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			// La ruta ENTERA, con su query: si se perdiera el `branchId` el reparto no
			// sabría de qué sucursal es la zona.
			vistas = append(vistas, r.URL.RequestURI())
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"id":"` + uuid.NewString() + `"}`))
		}))
	defer servidor.Close()

	c := Nuevo(servidor.URL, "clave-de-prueba", 5*time.Second)

	casos := []struct {
		ruta     string
		esperada string
	}{
		{"/board/columns?branchId=abc", "/api/board/columns?branchId=abc"},
		{"/board/placements/p-1", "/api/board/placements/p-1"},
		{"/routes/r-1/results", "/api/routes/r-1/results"},
	}
	for _, caso := range casos {
		vistas = nil
		_, err := c.Aplicar(context.Background(), sincro.Peticion{
			Metodo:   http.MethodPost,
			Ruta:     caso.ruta,
			Cuerpo:   json.RawMessage(`{"nombre":"Vista"}`),
			Hecho:    time.Now(),
			Sucursal: uuid.New(),
			Persona:  "quien-sea",
			Clave:    "k",
		})
		if err != nil {
			t.Fatalf("%s: no tenía que fallar: %v", caso.ruta, err)
		}
		if len(vistas) != 1 || vistas[0] != caso.esperada {
			t.Errorf("se llamó a %v, se esperaba %q — sin el `/api` el reparto contesta "+
				"404 y el apunte acaba en la bandeja de rechazos", vistas, caso.esperada)
		}
	}
}

// Y el `/api` se pone UNA sola vez: si `REPARTO_URL` ya lo trajera, `/api/api/...` sería
// el mismo fallo por el otro lado. Es exactamente lo que le pasó al Tablero en la web.
func TestNoSeDuplicaElApi(t *testing.T) {
	var vista string
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			vista = r.URL.Path
			_, _ = w.Write([]byte(`{}`))
		}))
	defer servidor.Close()

	_, err := Nuevo(servidor.URL, "k", 5*time.Second).Aplicar(
		context.Background(), sincro.Peticion{
			Metodo: http.MethodPost, Ruta: "/board/columns",
			Hecho: time.Now(), Sucursal: uuid.New(), Persona: "x", Clave: "k",
		})
	if err != nil {
		t.Fatalf("no tenía que fallar: %v", err)
	}
	if vista != "/api/board/columns" {
		t.Errorf("ruta = %q, se esperaba /api/board/columns", vista)
	}
}
