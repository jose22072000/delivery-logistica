package config_test

import (
	"strings"
	"testing"

	"procovar/reparto-api/internal/config"
)

// Lo mismo que el resto de este fichero: lo que se prueba no es que lea
// variables, es que **no arranque** con media configuración. Un anuncio de mapa
// a medias no se ve como un error: se ve como «el mapa no se descarga», y eso
// se descubre en el patio de un almacén.

const huellaBuena = "ed9c3bf5dd964bc0fa319b1807bb5d7c620db057dbf76e6a270463e407f1e9c9"

func loMinimo(t *testing.T) {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
}

func TestSinPaqueteDeMapaArrancaYNoAnuncia(t *testing.T) {
	loMinimo(t)

	c, err := config.Cargar("dev")
	if err != nil {
		t.Fatal(err)
	}
	if c.Mapa.HayAlguno() {
		t.Fatal("sin ninguna MAPA_* no se anuncia nada: inventarse un nivel manda a " +
			"diez personas a un enlace que no existe")
	}
}

func TestUnNivelCompletoSeAnuncia(t *testing.T) {
	loMinimo(t)
	t.Setenv("MAPA_VERSION", "260916")
	t.Setenv("MAPA_FECHA", "2026-09-16")
	t.Setenv("MAPA_COMPLETO_URL", "https://reparto.procovar.cloud/mapa/cuba-completo.pmtiles")
	t.Setenv("MAPA_COMPLETO_BYTES", "25763142")
	t.Setenv("MAPA_COMPLETO_SHA256", huellaBuena)

	c, err := config.Cargar("dev")
	if err != nil {
		t.Fatal(err)
	}
	if len(c.Mapa.Paquetes) != 1 {
		t.Fatalf("se anunciaron %d niveles y se configuró 1", len(c.Mapa.Paquetes))
	}
	p := c.Mapa.Paquetes[0]
	if p.Nivel != "completo" {
		t.Errorf("el nivel salió como %q: se saca del nombre de la variable", p.Nivel)
	}
	if p.Bytes != 25763142 {
		t.Errorf("bytes = %d", p.Bytes)
	}
	if p.SHA256 != huellaBuena {
		t.Errorf("sha256 = %q", p.SHA256)
	}
	if p.Version != "260916" {
		t.Errorf("versión = %q", p.Version)
	}
	// La fecha se guarda normalizada: una que el aparato no sepa leer sale como
	// «sin fecha» y eso no se distingue de no haberla puesto.
	if p.Fecha != "2026-09-16T00:00:00Z" {
		t.Errorf("fecha = %q; se esperaba normalizada a RFC3339", p.Fecha)
	}
}

// El orden importa: lo primero que ve la persona tiene que ser lo más barato de
// bajar. Se configuran al revés a propósito.
func TestLosNivelesSalenDeMenorAMayor(t *testing.T) {
	loMinimo(t)
	t.Setenv("MAPA_VERSION", "260916")
	t.Setenv("MAPA_DETALLADO_URL", "https://x/d.pmtiles")
	t.Setenv("MAPA_DETALLADO_BYTES", "61089619")
	t.Setenv("MAPA_DETALLADO_SHA256", huellaBuena)
	t.Setenv("MAPA_BASICO_URL", "https://x/b.pmtiles")
	t.Setenv("MAPA_BASICO_BYTES", "2375346")
	t.Setenv("MAPA_BASICO_SHA256", huellaBuena)

	c, err := config.Cargar("dev")
	if err != nil {
		t.Fatal(err)
	}
	if len(c.Mapa.Paquetes) != 2 {
		t.Fatalf("%d niveles", len(c.Mapa.Paquetes))
	}
	if c.Mapa.Paquetes[0].Nivel != "basico" || c.Mapa.Paquetes[1].Nivel != "detallado" {
		t.Fatalf("salieron en el orden %q, %q: tienen que ir de menor a mayor tamaño",
			c.Mapa.Paquetes[0].Nivel, c.Mapa.Paquetes[1].Nivel)
	}
}

func TestUrlDeMapaSinVersionNoArranca(t *testing.T) {
	loMinimo(t)
	t.Setenv("MAPA_COMPLETO_URL", "https://x/c.pmtiles")
	t.Setenv("MAPA_COMPLETO_BYTES", "100")
	t.Setenv("MAPA_COMPLETO_SHA256", huellaBuena)

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "MAPA_VERSION") {
		t.Fatalf("sin versión el aparato no puede saber si lo suyo se quedó viejo, "+
			"así que no se anunciaría nunca: %v", err)
	}
}

func TestVersionDeMapaSinNingunNivelNoArranca(t *testing.T) {
	loMinimo(t)
	t.Setenv("MAPA_VERSION", "260916")

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "MAPA_") {
		t.Fatalf("se anunciaría que hay mapa sin decir de dónde bajarlo: %v", err)
	}
}

// LA TRAMPA DE LAS TRES VARIABLES. Con dos de tres el aparato o baja a ciegas o
// se queda con medio fichero creyéndolo bueno, y las dos cosas pasan en silencio.
func TestUnNivelAMediasNoArranca(t *testing.T) {
	casos := map[string]map[string]string{
		"sin BYTES": {
			"MAPA_COMPLETO_URL":    "https://x/c.pmtiles",
			"MAPA_COMPLETO_SHA256": huellaBuena,
		},
		"sin SHA256": {
			"MAPA_COMPLETO_URL":   "https://x/c.pmtiles",
			"MAPA_COMPLETO_BYTES": "100",
		},
		"sin URL": {
			"MAPA_COMPLETO_BYTES":  "100",
			"MAPA_COMPLETO_SHA256": huellaBuena,
		},
	}
	for nombre, vars := range casos {
		t.Run(nombre, func(t *testing.T) {
			loMinimo(t)
			t.Setenv("MAPA_VERSION", "260916")
			for k, v := range vars {
				t.Setenv(k, v)
			}
			_, err := config.Cargar("dev")
			if err == nil {
				t.Fatal("arrancó con el nivel a medias")
			}
			if !strings.Contains(err.Error(), "completo") {
				t.Fatalf("el mensaje tiene que nombrar el nivel: %v", err)
			}
		})
	}
}

// Un sha256 con un carácter de menos rechaza TODAS las descargas, para siempre, y
// desde fuera se ve como «el mapa no se descarga nunca».
func TestUnSha256QueNoLoEsNoArranca(t *testing.T) {
	casos := map[string]string{
		// Los dos primeros son LA trampa, y se descubrió rompiendo la guarda a
		// propósito: con 63 o 65 caracteres el error salta igual porque un
		// hexadecimal de longitud impar no se puede decodificar, así que esos
		// dos casos NO comprueban la comprobación de longitud. El que la
		// comprueba es el de 62: es hexadecimal perfecto y no es un sha256, que
		// además es lo que pasa de verdad cuando alguien copia el hash y se deja
		// un trozo.
		"corto y aun así hexadecimal": huellaBuena[:62],
		"largo y aun así hexadecimal": huellaBuena + "ab",
		"corto":                       huellaBuena[:63],
		"largo":                       huellaBuena + "a",
		"no hexadecimal":              strings.Repeat("z", 64),
	}
	for nombre, huella := range casos {
		t.Run(nombre, func(t *testing.T) {
			loMinimo(t)
			t.Setenv("MAPA_VERSION", "260916")
			t.Setenv("MAPA_COMPLETO_URL", "https://x/c.pmtiles")
			t.Setenv("MAPA_COMPLETO_BYTES", "100")
			t.Setenv("MAPA_COMPLETO_SHA256", huella)

			_, err := config.Cargar("dev")
			if err == nil || !strings.Contains(err.Error(), "SHA256") {
				t.Fatalf("%s: %v", nombre, err)
			}
		})
	}
}

func TestBytesDeMapaQueNoEsNumeroNoArranca(t *testing.T) {
	loMinimo(t)
	t.Setenv("MAPA_VERSION", "260916")
	t.Setenv("MAPA_COMPLETO_URL", "https://x/c.pmtiles")
	t.Setenv("MAPA_COMPLETO_BYTES", "25,8 MB")
	t.Setenv("MAPA_COMPLETO_SHA256", huellaBuena)

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "BYTES") {
		t.Fatalf("un tamaño que no es un número deja al aparato sin poder avisar: %v", err)
	}
}

func TestUrlDeMapaSinEsquemaNoArranca(t *testing.T) {
	loMinimo(t)
	t.Setenv("MAPA_VERSION", "260916")
	t.Setenv("MAPA_COMPLETO_URL", "reparto.procovar.cloud/mapa/c.pmtiles")
	t.Setenv("MAPA_COMPLETO_BYTES", "100")
	t.Setenv("MAPA_COMPLETO_SHA256", huellaBuena)

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "http://") {
		t.Fatalf("una URL sin esquema no falla al arrancar, falla al bajarla: %v", err)
	}
}

func TestLaFechaDelMapaQueNoSeEntiendeNoArranca(t *testing.T) {
	loMinimo(t)
	t.Setenv("MAPA_VERSION", "260916")
	t.Setenv("MAPA_FECHA", "16/09/2026")
	t.Setenv("MAPA_COMPLETO_URL", "https://x/c.pmtiles")
	t.Setenv("MAPA_COMPLETO_BYTES", "100")
	t.Setenv("MAPA_COMPLETO_SHA256", huellaBuena)

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "MAPA_FECHA") {
		t.Fatalf("%v", err)
	}
}
