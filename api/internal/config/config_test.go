package config_test

import (
	"strings"
	"testing"

	"procovar/reparto-api/internal/config"
)

// Lo que se prueba aquí no es que lea variables: es que NO ARRANQUE cuando falta algo.
// Un servicio que se levanta a medias pasa la comprobación de salud del desplegador y da
// 500 a media tarde, en la pantalla de alguien que está cargando un camión.

const secretoBueno = "un-secreto-de-pruebas-de-al-menos-32-caracteres"

func TestSinVariablesObligatoriasNoArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "")
	t.Setenv("JWT_SECRET", "")

	_, err := config.Cargar("dev")
	if err == nil {
		t.Fatal("tenía que fallar")
	}
	// Las dos en el MISMO mensaje: ir de una en una son dos despliegues para descubrir
	// dos variables.
	if !strings.Contains(err.Error(), "DATABASE_URL") || !strings.Contains(err.Error(), "JWT_SECRET") {
		t.Fatalf("el mensaje tiene que nombrar las dos que faltan: %v", err)
	}
}

func TestSecretoCortoNoArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", "corto")

	_, err := config.Cargar("dev")
	if err == nil || !strings.Contains(err.Error(), "JWT_SECRET") {
		t.Fatalf("un secreto corto se rompe fuera de línea y abre la sucursal entera: %v", err)
	}
}

func TestCadenaDeConexionQueNoLoEsNoArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "localhost")
	t.Setenv("JWT_SECRET", secretoBueno)

	if _, err := config.Cargar("dev"); err == nil {
		t.Fatal("tenía que fallar antes de intentar conectarse")
	}
}

func TestValorMalFormadoNoArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)

	casos := map[string]map[string]string{
		"puerto que no es número":    {"PUERTO": "ocho mil"},
		"entorno inventado":          {"ENTORNO": "casi-produccion"},
		"duración sin unidad":        {"TIEMPO_LECTURA": "30"},
		"conexiones en negativo":     {"POOL_MAX_CONNS": "-1"},
		"mínimo mayor que el máximo": {"POOL_MIN_CONNS": "50", "POOL_MAX_CONNS": "10"},
	}
	for nombre, vars := range casos {
		t.Run(nombre, func(t *testing.T) {
			for k, v := range vars {
				t.Setenv(k, v)
			}
			if _, err := config.Cargar("dev"); err == nil {
				t.Fatal("tenía que fallar al arrancar")
			}
		})
	}
}

func TestConLoObligatorioArrancaConLosValoresDeLaCasa(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)

	c, err := config.Cargar("v1.2.3")
	if err != nil {
		t.Fatalf("tenía que arrancar: %v", err)
	}
	if c.Direccion() != ":8080" {
		t.Fatalf("puerto por defecto: %q", c.Direccion())
	}
	if c.Version != "v1.2.3" {
		t.Fatalf("la versión la incrusta el compilador: %q", c.Version)
	}
	if c.EnProduccion() {
		t.Fatal("por defecto NO es producción: quien despliega tiene que decirlo")
	}
}
