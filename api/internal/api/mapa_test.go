package api_test

import (
	"encoding/json"
	"net/http"
	"testing"
)

// EL ANUNCIO DEL PAQUETE DE MAPA. Lo mismo que `version_test.go` y por el mismo
// motivo: que un servidor sin nada colgado no mande a nadie a ninguna parte, y
// que uno con algo colgado diga qué, cuánto pesa y cómo comprobar que llegó
// entero.

type anuncioDeMapa struct {
	Niveles []struct {
		Nivel   string `json:"nivel"`
		Version string `json:"version"`
		Fecha   string `json:"fecha"`
		Bytes   int64  `json:"bytes"`
		SHA256  string `json:"sha256"`
		URL     string `json:"url"`
	} `json:"niveles"`
}

const huellaCompleto = "ed9c3bf5dd964bc0fa319b1807bb5d7c620db057dbf76e6a270463e407f1e9c9"
const huellaBasico = "21e725bac45518ad5b889e0afa2927fb78d25946b19c485b1ce66dbc13100a0b"

func leerAnuncioDeMapa(t *testing.T, h http.Handler, ruta string) anuncioDeMapa {
	t.Helper()
	w := pedir(t, h, http.MethodGet, ruta, "", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var a anuncioDeMapa
	if err := json.Unmarshal(w.Body.Bytes(), &a); err != nil {
		t.Fatalf("no es JSON del contrato: %v — %s", err, w.Body.String())
	}
	return a
}

// Sin nada colgado, `niveles` es null y el aparato no ofrece descargar nada.
func TestSinPaqueteDeMapaNoSeAnunciaNada(t *testing.T) {
	a := leerAnuncioDeMapa(t, servidor(t), "/api/mapa")
	if a.Niveles != nil {
		t.Fatalf("no hay nada colgado y aun así se anuncia algo: %+v", a.Niveles)
	}
}

func TestSeAnuncianLosNivelesConSuTamanoYSuHuella(t *testing.T) {
	t.Setenv("MAPA_VERSION", "260916")
	t.Setenv("MAPA_FECHA", "2026-09-16")
	t.Setenv("MAPA_BASICO_URL", "https://reparto.procovar.cloud/mapa/cuba-basico.pmtiles")
	t.Setenv("MAPA_BASICO_BYTES", "2375346")
	t.Setenv("MAPA_BASICO_SHA256", huellaBasico)
	t.Setenv("MAPA_COMPLETO_URL", "https://reparto.procovar.cloud/mapa/cuba-completo.pmtiles")
	t.Setenv("MAPA_COMPLETO_BYTES", "25763142")
	t.Setenv("MAPA_COMPLETO_SHA256", huellaCompleto)

	a := leerAnuncioDeMapa(t, servidor(t), "/api/mapa")
	if len(a.Niveles) != 2 {
		t.Fatalf("se anunciaron %d niveles: %+v", len(a.Niveles), a.Niveles)
	}
	// De menor a mayor: lo primero que ve la persona es lo más barato de bajar.
	if a.Niveles[0].Nivel != "basico" || a.Niveles[1].Nivel != "completo" {
		t.Fatalf("orden %q, %q", a.Niveles[0].Nivel, a.Niveles[1].Nivel)
	}

	b := a.Niveles[0]
	// EL TAMAÑO VIAJA. Sin él la pantalla no puede decir «son 2,4 MB» antes de
	// empezar, y entonces alguien baja a ciegas con los datos de Cuba.
	if b.Bytes != 2375346 {
		t.Errorf("bytes = %d", b.Bytes)
	}
	// Y LA HUELLA TAMBIÉN. Es lo único que separa «bajado» de «bajado entero».
	if b.SHA256 != huellaBasico {
		t.Errorf("sha256 = %q", b.SHA256)
	}
	if b.URL != "https://reparto.procovar.cloud/mapa/cuba-basico.pmtiles" {
		t.Errorf("url = %q", b.URL)
	}
	if b.Version != "260916" {
		t.Errorf("versión = %q: es contra ésta contra la que el aparato compara lo suyo", b.Version)
	}
	if b.Fecha != "2026-09-16T00:00:00Z" {
		t.Errorf("fecha = %q", b.Fecha)
	}
}

// LA DIRECCIÓN, comprobada contra el router de verdad y no copiada del código.
// Las del Tablero repetían `/api/api/board` y todo salía verde mientras las diez
// llamadas daban 404 (`CLAUDE.md` §5).
func TestElMapaSaleEnLasDosRutasYSinSesion(t *testing.T) {
	t.Setenv("MAPA_VERSION", "260916")
	t.Setenv("MAPA_BASICO_URL", "https://x/b.pmtiles")
	t.Setenv("MAPA_BASICO_BYTES", "2375346")
	t.Setenv("MAPA_BASICO_SHA256", huellaBasico)

	h := servidor(t)
	for _, ruta := range []string{"/mapa", "/api/mapa"} {
		// SIN token: el aparato lo consulta al arrancar, antes de que haya
		// nadie dentro. Con sesión no serviría para eso.
		a := leerAnuncioDeMapa(t, h, ruta)
		if len(a.Niveles) != 1 {
			t.Fatalf("%s devolvió %d niveles", ruta, len(a.Niveles))
		}
	}
}

// Ni una petición a OpenStreetMap, ni a Geofabrik, ni a ningún sitio: todo sale
// de la configuración leída al arrancar. Se comprueba de la única forma que vale
// —que conteste igual sin red y al instante— pidiéndolo muchas veces seguidas.
func TestElAnuncioDelMapaNoSaleAPedirleNadaANadie(t *testing.T) {
	t.Setenv("MAPA_VERSION", "260916")
	t.Setenv("MAPA_BASICO_URL", "https://x/b.pmtiles")
	t.Setenv("MAPA_BASICO_BYTES", "2375346")
	t.Setenv("MAPA_BASICO_SHA256", huellaBasico)

	h := servidor(t)
	for i := 0; i < 50; i++ {
		if a := leerAnuncioDeMapa(t, h, "/api/mapa"); len(a.Niveles) != 1 {
			t.Fatalf("en la vuelta %d devolvió %d niveles", i, len(a.Niveles))
		}
	}
}
