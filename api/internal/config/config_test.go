package config_test

import (
	"strings"
	"testing"
	"time"

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

// ---------------------------------------------------------------------------
// Las variables de las otras aplicaciones de la casa
// ---------------------------------------------------------------------------

// Las URLs mal escritas se cazan AL ARRANCAR. Una `PEDIDO_API_URL` sin esquema no falla al
// concatenar: falla al hacer la petición, dentro de una goroutine de fondo, y lo único que
// se ve es un aviso que no llegó a nadie.
func TestUnaUrlSinEsquemaNoArranca(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)

	casos := map[string]map[string]string{
		"PEDIDO_API_URL sin esquema":     {"PEDIDO_API_URL": "pedido.procovar.cloud"},
		"DELIVERY_URL sin esquema":       {"DELIVERY_URL": "localhost:8080"},
		"PROCOVAR_AUTH_URL sin esquema":  {"PROCOVAR_AUTH_URL": "auth.procovar.cloud"},
		"milisegundos que no son número": {"CATALOGO_CADA_MS": "doce horas"},
		"milisegundos en negativo":       {"ALMACENES_CACHE_MS": "-5"},
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

// Sin ellas SÍ arranca, y con los valores de la casa. `PEDIDO_API_URL` no es obligatoria a
// propósito: sin ella el servicio hace todo lo demás y las dos cosas que la necesitan —el
// canal y el recosteo— lo DICEN en vez de callarse.
func TestSinLasDeFueraArrancaConLosValoresDeLaCasa(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)

	c, err := config.Cargar("dev")
	if err != nil {
		t.Fatalf("tenía que arrancar sin las de fuera: %v", err)
	}
	if c.PedidoAPIURL != "" || c.DeliveryURL != "" || c.AuthSigningKey != "" {
		t.Fatalf("no se inventa ninguna: %q %q %q", c.PedidoAPIURL, c.DeliveryURL, c.AuthSigningKey)
	}
	if c.AuthURL != "https://auth.procovar.cloud" {
		t.Fatalf("la URL de Accesos por defecto es la de la casa, y salió %q", c.AuthURL)
	}
	if c.AuthClientID != "delivery" {
		t.Fatalf("el cliente por defecto es \"delivery\", y salió %q", c.AuthClientID)
	}
	if c.CatalogoCada != 12*time.Hour {
		t.Fatalf("el catálogo se baja cada 12 h por defecto, y salió %s", c.CatalogoCada)
	}
	if c.AlmacenesCache != 5*time.Minute {
		t.Fatalf("los almacenes se recuerdan 5 min por defecto, y salió %s", c.AlmacenesCache)
	}
}

// La barra final se quita AQUÍ y no en cada sitio que concatena: una de más produce
// `//integration/orders/status`, que unos servidores toleran y otros contestan con un 404
// que nadie sabe explicar.
func TestALasUrlsSeLesQuitaLaBarraFinal(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://u:c@localhost:5432/b")
	t.Setenv("JWT_SECRET", secretoBueno)
	t.Setenv("PEDIDO_API_URL", "https://pedido.procovar.cloud/")
	t.Setenv("CATALOGO_CADA_MS", "60000")

	c, err := config.Cargar("dev")
	if err != nil {
		t.Fatalf("tenía que arrancar: %v", err)
	}
	if c.PedidoAPIURL != "https://pedido.procovar.cloud" {
		t.Fatalf("no se le quitó la barra: %q", c.PedidoAPIURL)
	}
	if c.CatalogoCada != time.Minute {
		t.Fatalf("CATALOGO_CADA_MS viene en milisegundos: %s", c.CatalogoCada)
	}
}
