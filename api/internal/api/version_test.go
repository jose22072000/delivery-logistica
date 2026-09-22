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
		Ficheros    map[string]struct {
			Bytes  int64  `json:"bytes"`
			SHA256 string `json:"sha256"`
		} `json:"ficheros"`
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
	t.Setenv("APP_DESCARGA_ANDROID_BYTES", "77646816")
	t.Setenv("APP_DESCARGA_ANDROID_SHA256", huellaDeLaApk)

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
	t.Setenv("APP_DESCARGA_ANDROID_BYTES", "77646816")
	t.Setenv("APP_DESCARGA_ANDROID_SHA256", huellaDeLaApk)

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

// La huella de mentira de estas pruebas. 64 hexadecimales.
const huellaDeLaApk = "565647928d03200b2eda25ef28bde55e0f0d3e034f99d561f38b33a6aa47c49e"

// EL ANUNCIO DICE CUÁNTO PESA Y QUÉ HUELLA TIENE — 22/09/2026.
//
// Jose se puso a bajar la APK por datos móviles y vio «30 MB/?»: no sabía cuántos datos
// le iba a costar. El tamaño salía del `Content-Length`, y Cloudflare lo quita de la
// respuesta completa. Un número que depende de lo que no se controla no es un número.
func TestElAnuncioLlevaElTamanoYLaHuella(t *testing.T) {
	t.Setenv("APP_ULTIMA_VERSION", "1.5.0")
	t.Setenv("APP_DESCARGA_ANDROID", "https://archivos.procovar.cloud/reparto/apk/reparto-1.5.0.apk")
	t.Setenv("APP_DESCARGA_ANDROID_BYTES", "77646816")
	t.Setenv("APP_DESCARGA_ANDROID_SHA256", huellaDeLaApk)

	a := leerAnuncio(t, servidor(t))
	f, hay := a.Ultima.Ficheros["android"]
	if !hay {
		t.Fatalf("sin esto la pantalla enseña «? MB» y nadie sabe qué va a gastar: %+v", a.Ultima)
	}
	if f.Bytes != 77646816 {
		t.Fatalf("bytes %d", f.Bytes)
	}
	if f.SHA256 != huellaDeLaApk {
		t.Fatalf("huella %q", f.SHA256)
	}
}

// `descargas` SE QUEDA COMO ESTABA, y esta prueba es la que lo sujeta.
//
// Las APK instaladas leen `descargas` esperando una cadena por clave, y su lector se
// salta en silencio lo que no lo sea. Convertirlo en objetos no daría un error: daría
// teléfonos que dejan de ofrecer la actualización sin decir nada, y sin poder
// actualizarse para arreglarlo.
func TestDescargasSigueSiendoLaURLPelada(t *testing.T) {
	t.Setenv("APP_ULTIMA_VERSION", "1.5.0")
	t.Setenv("APP_DESCARGA_ANDROID", "https://archivos.procovar.cloud/reparto/apk/reparto-1.5.0.apk")
	t.Setenv("APP_DESCARGA_ANDROID_BYTES", "77646816")
	t.Setenv("APP_DESCARGA_ANDROID_SHA256", huellaDeLaApk)

	w := pedir(t, servidor(t), http.MethodGet, "/api/version", "", nil)
	var crudo struct {
		Ultima struct {
			Descargas map[string]any `json:"descargas"`
		} `json:"ultima"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &crudo); err != nil {
		t.Fatalf("no es JSON: %v", err)
	}
	if _, esCadena := crudo.Ultima.Descargas["android"].(string); !esCadena {
		t.Fatalf("descargas.android tiene que seguir siendo una cadena para las APK que ya "+
			"están instaladas, y vino %T", crudo.Ultima.Descargas["android"])
	}
}
