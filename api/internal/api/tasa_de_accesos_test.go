// LA LECTURA DE LA TASA QUE VIENE DE ACCESOS.
//
// No había ninguna prueba de este cliente, y por eso vivió meses un fallo que dejaba a
// TODAS las sucursales sin tasa: la comprobación de «no hay» daba por nulo también el
// campo AUSENTE, y Accesos no manda el campo `tasa` cuando la tasa existe.
//
// El fallo no se veía porque degradaba a un estado legítimo —«esta sucursal no tiene tasa
// de cambio todavía»—, una frase que puede ser verdad y que nadie iba a cuestionar.
// Mientras tanto todos los importes salían en USD.
package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"procovar/reparto-api/internal/config"
)

// accesosDePrueba levanta un Accesos de mentira que contesta lo que se le diga, y devuelve
// el cliente de tasas apuntando a él. La firma se calcula de verdad; el servidor no la
// mira, que aquí lo que se prueba es cómo se LEE la respuesta.
func accesosDePrueba(t *testing.T, cuerpo string) *tasasDeAccesos {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("content-type", "application/json")
		_, _ = w.Write([]byte(cuerpo))
	}))
	t.Cleanup(srv.Close)

	return &tasasDeAccesos{firmante: accesosHTTP{cfg: &config.Config{
		AuthURL:        srv.URL,
		AuthClientID:   "reparto",
		AuthSigningKey: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
	}}}
}

// EL CASO DEL FALLO. Así contesta Accesos cuando la sucursal SÍ tiene tasa: los campos
// sueltos, y NINGÚN campo `tasa`. Es exactamente el cuerpo de
// `auth/src/app/api/service/tasas/route.ts`, que hace `{...t, horasFresca, aviso}`.
func TestUnaTasaBuenaSeLeeAunqueNoVengaElCampoTasa(t *testing.T) {
	c := accesosDePrueba(t, `{
		"codigo":"STG","cupPorUsd":700,"fuente":"entrega","tarifaBase":1,
		"traidoAt":"2026-09-09T22:03:04.076Z","fresca":false,
		"horasFresca":24,"aviso":"La tasa es del 9/9/2026 y puede estar desfasada."
	}`)

	tasa, err := c.TasaDeSucursal(context.Background(), "STG")
	if err != nil {
		t.Fatalf("no tenía que fallar: %v", err)
	}
	if tasa == nil {
		t.Fatal("se leyó como «no hay tasa» una respuesta que SÍ trae tasa: " +
			"es el fallo que dejaba las ocho sucursales en USD")
	}
	if tasa.CupPorUsd != 700 {
		t.Errorf("cupPorUsd = %v, se esperaba 700", tasa.CupPorUsd)
	}
	if tasa.Codigo != "STG" {
		t.Errorf("codigo = %q, se esperaba STG", tasa.Codigo)
	}
	// `fresca:false` viene de Accesos y se respeta: quien decide si la tasa está pasada
	// es Accesos, no este servicio.
	if tasa.Fresca {
		t.Error("Accesos dijo que no es fresca y aquí salió fresca")
	}
}

// Y EL OTRO LADO: `tasa: null` SÍ significa que no hay, y tiene que seguir significándolo.
// Sin esta, «arreglar» la de arriba quitando la comprobación entera pasaría por buena.
func TestTasaNullSigueSignificandoQueNoHay(t *testing.T) {
	c := accesosDePrueba(t, `{"tasa":null,"codigo":"GR","aviso":"sin tasa para GR"}`)

	tasa, err := c.TasaDeSucursal(context.Background(), "GR")
	if err != nil {
		t.Fatalf("no tenía que fallar: %v", err)
	}
	if tasa != nil {
		t.Fatalf("`tasa: null` es «no hay» y se leyó como una tasa: %+v", tasa)
	}
}

// Sin `cupPorUsd` no hay nada que convertir, venga como venga el resto. Un cero o una
// cadena donde debía ir el número no puede convertirse en «tasa cero», que multiplicaría
// todos los importes por nada.
func TestSinCupPorUsdNoHayTasa(t *testing.T) {
	for nombre, cuerpo := range map[string]string{
		"falta el campo":  `{"codigo":"HAB","fuente":"entrega"}`,
		"viene como nulo": `{"codigo":"HAB","cupPorUsd":null}`,
	} {
		t.Run(nombre, func(t *testing.T) {
			tasa, err := accesosDePrueba(t, cuerpo).TasaDeSucursal(context.Background(), "HAB")
			if err != nil {
				t.Fatalf("no tenía que fallar: %v", err)
			}
			if tasa != nil {
				t.Fatalf("sin cupPorUsd no puede salir una tasa: %+v", tasa)
			}
		})
	}
}

// AUSENTE SIGNIFICA FRESCA. Lo dice el comentario del código y conviene que lo diga una
// prueba: si Accesos no se pronuncia, no se inventa un aviso de tasa vieja.
func TestSinCampoFrescaSeConsideraFresca(t *testing.T) {
	tasa, err := accesosDePrueba(t, `{"codigo":"CAM","cupPorUsd":320}`).
		TasaDeSucursal(context.Background(), "CAM")
	if err != nil {
		t.Fatalf("no tenía que fallar: %v", err)
	}
	if tasa == nil {
		t.Fatal("tenía que haber tasa")
	}
	if !tasa.Fresca {
		t.Error("sin `fresca` en la respuesta, se considera fresca")
	}
}

// Y que el cuerpo que se prueba arriba es de verdad el que manda Accesos: si alguien
// cambia la forma de la respuesta allí, esto no lo caza —viven en repos distintos— pero
// al menos deja escrito contra qué se probó.
func TestElCuerpoDePruebaEsJSONValido(t *testing.T) {
	var x map[string]any
	if err := json.Unmarshal([]byte(`{"codigo":"STG","cupPorUsd":700,"fresca":false}`), &x); err != nil {
		t.Fatal(err)
	}
	if _, hay := x["tasa"]; hay {
		t.Fatal("la respuesta buena de Accesos NO lleva campo `tasa`: ese es el punto")
	}
}
