package api_test

import (
	"encoding/json"
	"net/http"
	"testing"
)

// Lo que se comprueba aquí es el ANUNCIO de versión: que un servidor sin nada publicado
// no manda a nadie a ninguna parte, y que uno con algo publicado dice qué y de dónde.
//
// El caso de «va sin sesión» está en `api_test.go` (TestVersionYSaludSinSesion) y no se
// repite aquí.

type anuncio struct {
	Version *string `json:"version"`
	Ultima  *struct {
		Version     string            `json:"version"`
		Compilacion *int              `json:"compilacion"`
		Notas       *string           `json:"notas"`
		PublicadaAt *string           `json:"publicadaAt"`
		Descargas   map[string]string `json:"descargas"`
	} `json:"ultima"`
}

func leerAnuncio(t *testing.T, h http.Handler) anuncio {
	t.Helper()
	w := pedir(t, h, http.MethodGet, "/api/version", "", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var a anuncio
	if err := json.Unmarshal(w.Body.Bytes(), &a); err != nil {
		t.Fatalf("no es JSON del contrato: %v — %s", err, w.Body.String())
	}
	return a
}

// Sin nada publicado, `ultima` es null. Un aparato que lea esto no avisa de nada, que es
// lo correcto: inventarse una versión sería mandar a diez personas a un enlace que no
// existe.
func TestSinVersionPublicadaNoSeAnunciaNada(t *testing.T) {
	a := leerAnuncio(t, servidor(t))
	if a.Ultima != nil {
		t.Fatalf("no hay nada colgado y aun así se anuncia algo: %+v", a.Ultima)
	}
	// La versión del servicio sigue saliendo: es el latido del despliegue.
	if a.Version == nil || *a.Version != "v-pruebas" {
		t.Fatalf("la versión del servicio tiene que seguir saliendo: %+v", a.Version)
	}
}

func TestSeAnunciaLaUltimaConSuDescarga(t *testing.T) {
	t.Setenv("APP_ULTIMA_VERSION", "1.5.0")
	t.Setenv("APP_ULTIMA_COMPILACION", "12")
	t.Setenv("APP_ULTIMA_NOTAS", "El cierre de ruta ya no pierde las fotos.")
	t.Setenv("APP_ULTIMA_PUBLICADA", "2026-09-15")
	t.Setenv("APP_DESCARGA_ANDROID", "https://descargas.procovar.cloud/reparto-1.5.0.apk")

	a := leerAnuncio(t, servidor(t))
	if a.Ultima == nil {
		t.Fatal("hay una versión colgada y no se anuncia")
	}
	if a.Ultima.Version != "1.5.0" {
		t.Fatalf("versión %q", a.Ultima.Version)
	}
	if a.Ultima.Compilacion == nil || *a.Ultima.Compilacion != 12 {
		t.Fatalf("la compilación es lo único que Android compara de verdad: %v", a.Ultima.Compilacion)
	}
	if a.Ultima.Descargas["android"] == "" {
		t.Fatalf("sin enlace no hay de dónde bajarla: %+v", a.Ultima.Descargas)
	}
	if a.Ultima.PublicadaAt == nil || *a.Ultima.PublicadaAt != "2026-09-15T00:00:00Z" {
		t.Fatalf("la fecha tiene que salir normalizada: %v", a.Ultima.PublicadaAt)
	}
}

// Una plataforma sin fichero colgado NO aparece con la cadena vacía: aparecería como un
// enlace en la pantalla de alguien, y al pulsarlo no habría nada.
func TestLaPlataformaSinFicheroNoSale(t *testing.T) {
	t.Setenv("APP_ULTIMA_VERSION", "1.5.0")
	t.Setenv("APP_DESCARGA_ANDROID", "https://descargas.procovar.cloud/reparto-1.5.0.apk")

	a := leerAnuncio(t, servidor(t))
	if _, hay := a.Ultima.Descargas["windows"]; hay {
		t.Fatalf("windows no está colgado y aun así sale: %+v", a.Ultima.Descargas)
	}
	if _, hay := a.Ultima.Descargas["web"]; hay {
		t.Fatal("la web se actualiza sola: no puede haber descarga de web")
	}
	if len(a.Ultima.Descargas) != 1 {
		t.Fatalf("sólo hay una colgada: %+v", a.Ultima.Descargas)
	}
}
