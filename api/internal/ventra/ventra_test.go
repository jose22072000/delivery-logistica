// Las pruebas del lector de Ventra, contra un Ventra de mentira.
//
// LO QUE SE PRUEBA AQUÍ NO ES QUE SEPA LEER UN JSON. Son las dos formas que tiene esto de
// hacer daño en silencio, las dos apuntadas en `docs/API-VENTRA.md` y en el encabezado de
// `ventra.go`:
//
//  1. Que un fallo —la VPN caída, un 500, una base apagada— DEGRADE DICIÉNDOLO y no
//     devuelva una lista vacía que el espejo tomaría por un catálogo bueno.
//  2. Que el catálogo se pida SUCURSAL POR SUCURSAL, porque el precio y las existencias
//     varían por sucursal y un catálogo único ofrecería en Camagüey lo que sólo hay en La
//     Habana, al precio de La Habana.
//
// Nada de esto necesita VPN ni un Ventra a mano: se corre en cada compilación.
package ventra

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"procovar/reparto-api/internal/api"
	"procovar/reparto-api/internal/config"
)

func callado() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

// ventraDeMentira levanta un servidor que contesta lo que se le diga y apunta cada
// petición que recibe. El cliente sale ya apuntando a él.
type ventraDeMentira struct {
	*httptest.Server
	mu       sync.Mutex
	rutas    []string
	cabezas  []http.Header
	llamadas int
}

func (v *ventraDeMentira) apuntar(r *http.Request) {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.llamadas++
	v.rutas = append(v.rutas, r.URL.RequestURI())
	v.cabezas = append(v.cabezas, r.Header.Clone())
}

func (v *ventraDeMentira) vistas() []string {
	v.mu.Lock()
	defer v.mu.Unlock()
	return append([]string(nil), v.rutas...)
}

func montar(t *testing.T, manejador func(w http.ResponseWriter, r *http.Request)) (*Cliente, *ventraDeMentira) {
	t.Helper()
	v := &ventraDeMentira{}
	v.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		v.apuntar(r)
		manejador(w, r)
	}))
	t.Cleanup(v.Close)
	c := Nuevo(&config.Config{VentraURL: v.URL, VentraToken: "token-de-pruebas"}, callado())
	return c, v
}

// responder escribe un JSON tal cual, sin tocarlo: la gracia es poder mandar exactamente
// la forma que contesta Ventra, con sus nombres de columna y sus nulos.
func responder(w http.ResponseWriter, cuerpo string) {
	w.Header().Set("content-type", "application/json")
	_, _ = io.WriteString(w, cuerpo)
}

// El JSON de `/axis/databases` tal como lo contestó producción el 04/09/2026. Diez bases
// para ocho sucursales: `moa` y `palmasoriano` no son nuestras.
const basesDeVentra = `[
 {"database":"camaguey","branchName":"CAMAGUEY","connected":true},
 {"database":"granma","branchName":"BAYAMO","connected":true},
 {"database":"guantanamo","branchName":"GUANTANAMO","connected":true},
 {"database":"habana","branchName":"LA HABANA","connected":true},
 {"database":"holguinmoa","branchName":"HOLGUIN","connected":true},
 {"database":"moa","branchName":"MOA","connected":true},
 {"database":"palmasoriano","branchName":"PALMA SORIANO","connected":true},
 {"database":"santiago","branchName":"SANTIAGO","connected":true},
 {"database":"sspiritus","branchName":"SANCTI SPIRITUS","connected":true},
 {"database":"tunas","branchName":"LAS TUNAS","connected":true}]`

// ---------------------------------------------------------------------------
// Las bases se preguntan, no se adivinan
// ---------------------------------------------------------------------------

// Los slugs no se parecen a lo que uno supondría: `granma` es BAYAMO, `sspiritus` es
// Sancti Spíritus, `tunas` es Las Tunas. Adivinar falla en cuatro de diez y deja una
// sucursal entera sin catálogo sin que salte nada.
func TestBasesSeLeenDeVentraYSeEmparejanConNuestrosCodigos(t *testing.T) {
	c, v := montar(t, func(w http.ResponseWriter, _ *http.Request) { responder(w, basesDeVentra) })

	bases, err := c.Bases(context.Background())
	if err != nil {
		t.Fatalf("tenía que leerlas: %v", err)
	}
	quiero := map[string]string{
		"CAM": "camaguey", "GR": "granma", "GTO": "guantanamo", "HAB": "habana",
		"HOL": "holguinmoa", "STG": "santiago", "SS": "sspiritus", "TUN": "tunas",
	}
	for codigo, slug := range quiero {
		if bases[codigo] != slug {
			t.Errorf("%s tenía que ser %q y es %q", codigo, slug, bases[codigo])
		}
	}
	// MOA Y PALMA SORIANO NO SE EMPAREJAN CON NADIE. Meterlas en HOL y STG «porque caen
	// en esa provincia» pondría las existencias y los precios de Moa en el catálogo de
	// Holguín, y eso no lo nota nadie hasta cobrar mal un domicilio.
	if len(bases) != len(quiero) {
		t.Fatalf("son ocho sucursales, no %d: %v", len(bases), bases)
	}
	for _, slug := range bases {
		if slug == "moa" || slug == "palmasoriano" {
			t.Fatalf("%q no es una sucursal nuestra y se coló: %v", slug, bases)
		}
	}
	if len(v.vistas()) != 1 || !strings.HasPrefix(v.vistas()[0], rutaBases) {
		t.Fatalf("tenía que preguntar a %s: %v", rutaBases, v.vistas())
	}
}

// Si Ventra contesta bases y NINGUNA cuadra, eso es un error a la cara y no un mapa vacío:
// un mapa vacío se lee como «no hay nada que bajar» y el catálogo se queda viejo callado.
func TestBasesQueNoCuadranConNingunaSucursalEsError(t *testing.T) {
	c, _ := montar(t, func(w http.ResponseWriter, _ *http.Request) {
		responder(w, `[{"database":"inventada","branchName":"OTRA COSA","connected":true}]`)
	})
	bases, err := c.Bases(context.Background())
	if err == nil {
		t.Fatalf("tenía que fallar, y devolvió %v", bases)
	}
	if !strings.Contains(err.Error(), "VENTRA_BASES") {
		t.Errorf("el mensaje tiene que decir cómo se arregla: %v", err)
	}
}

// Una base nueva o renombrada se empareja desde el entorno, sin tocar código.
func TestVentraBasesDelEntornoPisaLaTablaDeDentro(t *testing.T) {
	v := &ventraDeMentira{}
	v.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		v.apuntar(r)
		responder(w, `[{"database":"santiago2","branchName":"SANTIAGO NUEVA","connected":true}]`)
	}))
	t.Cleanup(v.Close)
	c := Nuevo(&config.Config{
		VentraURL: v.URL, VentraToken: "t",
		VentraBases: map[string]string{"STG": "santiago2"},
	}, callado())

	bases, err := c.Bases(context.Background())
	if err != nil || bases["STG"] != "santiago2" {
		t.Fatalf("tenía que emparejarla por el entorno: %v %v", bases, err)
	}
}

// Ventra sin bases no es «no hay catálogo»: es que no se le pudo preguntar bien (token sin
// scope, por ejemplo). Error, no mapa vacío.
func TestBasesVaciasSonError(t *testing.T) {
	c, _ := montar(t, func(w http.ResponseWriter, _ *http.Request) { responder(w, `[]`) })
	if _, err := c.Bases(context.Background()); err == nil {
		t.Fatal("una lista vacía de bases tiene que ser un error")
	}
}

// ---------------------------------------------------------------------------
// El catálogo se pide POR SUCURSAL
// ---------------------------------------------------------------------------

// EL PRECIO Y LAS EXISTENCIAS VARÍAN POR SUCURSAL. Sin `?database=` llega un consolidado
// que no es de ninguna, y guardarlo como si lo fuera es peor que no tenerlo.
func TestCatalogoSePidePorSucursalYCadaUnaTraeSuPrecio(t *testing.T) {
	precios := map[string]string{
		"santiago":   `[{"sku":"ALIM0010","name":"ACEITE SOYA","precioUsd":20,"existencias":4,"isActive":true}]`,
		"holguinmoa": `[{"sku":"ALIM0010","name":"ACEITE SOYA","precioUsd":23.5,"existencias":0,"isActive":true}]`,
	}
	c, v := montar(t, func(w http.ResponseWriter, r *http.Request) {
		cuerpo, hay := precios[r.URL.Query().Get("database")]
		if !hay {
			t.Errorf("se pidió el catálogo sin base o con una desconocida: %s", r.URL.RequestURI())
			cuerpo = `[]`
		}
		responder(w, cuerpo)
	})

	stg, err := c.Catalogo(context.Background(), "santiago")
	if err != nil {
		t.Fatalf("santiago: %v", err)
	}
	hol, err := c.Catalogo(context.Background(), "holguinmoa")
	if err != nil {
		t.Fatalf("holguinmoa: %v", err)
	}
	if stg[0].Precio == nil || *stg[0].Precio != 20 {
		t.Errorf("el precio de Santiago: %v", stg[0].Precio)
	}
	if hol[0].Precio == nil || *hol[0].Precio != 23.5 {
		t.Errorf("el precio de Holguín: %v", hol[0].Precio)
	}
	if stg[0].Existencias == nil || *stg[0].Existencias != 4 {
		t.Errorf("las existencias de Santiago: %v", stg[0].Existencias)
	}
	// Y que de verdad se mandó la base en la query las dos veces.
	for _, ruta := range v.vistas() {
		if !strings.Contains(ruta, "database=") {
			t.Fatalf("se pidió el catálogo sin ?database=: %s", ruta)
		}
	}
}

// Sin base no se sale a la red: un catálogo sin sucursal no es de nadie.
func TestCatalogoSinBaseNiSaleALaRed(t *testing.T) {
	c, v := montar(t, func(w http.ResponseWriter, _ *http.Request) { responder(w, `[]`) })
	if _, err := c.Catalogo(context.Background(), "  "); err == nil {
		t.Fatal("tenía que negarse")
	}
	if v.llamadas != 0 {
		t.Fatalf("no tenía que preguntar nada y preguntó %d veces", v.llamadas)
	}
}

// Los nombres de verdad son `existencias` y `precioUsd`; los alias son la red de seguridad
// para el día que renombren una columna. Perder todos los precios en silencio por un
// nombre cambiado es el fallo que no se ve: el catálogo entra igual, con las mismas filas.
func TestCatalogoLeeLosAliasDeLasColumnas(t *testing.T) {
	c, _ := montar(t, func(w http.ResponseWriter, _ *http.Request) {
		responder(w, `[{"productCode":"ALIM0020","productName":"QUESO GOUDA","categoria":"ALIM",
		  "unidad":"unidad","pesoKg":1.5,"stock":"7","price":"22.50","isActive":true}]`)
	})
	filas, err := c.Catalogo(context.Background(), "santiago")
	if err != nil {
		t.Fatalf("%v", err)
	}
	f := filas[0]
	if f.Sku != "ALIM0020" || f.Nombre != "QUESO GOUDA" || f.Categoria != "ALIM" || f.Unidad != "unidad" {
		t.Errorf("el texto no se leyó: %+v", f)
	}
	if f.PesoKg == nil || *f.PesoKg != 1.5 {
		t.Errorf("el peso: %v", f.PesoKg)
	}
	if f.Precio == nil || *f.Precio != 22.5 {
		t.Errorf("el precio venía como cadena y tenía que leerse: %v", f.Precio)
	}
	if f.Existencias == nil || *f.Existencias != 7 {
		t.Errorf("las existencias venían como cadena: %v", f.Existencias)
	}
}

// `weightKg` viene null en muchos productos y eso NO es cero: cero kilos es una mentira
// que el cotizador se cree, y «no lo sé» es lo que hay que poder distinguir.
func TestPesoNuloNoEsCero(t *testing.T) {
	c, _ := montar(t, func(w http.ResponseWriter, _ *http.Request) {
		responder(w, `[{"sku":"A","name":"Algo","weightKg":null,"precioUsd":null,"existencias":"","isActive":true}]`)
	})
	filas, err := c.Catalogo(context.Background(), "santiago")
	if err != nil {
		t.Fatalf("%v", err)
	}
	if filas[0].PesoKg != nil || filas[0].Precio != nil || filas[0].Existencias != nil {
		t.Fatalf("lo que Ventra no dijo tiene que quedar en nil: %+v", filas[0])
	}
}

// El espejo se salta lo inactivo. Si un día quitan `isActive`, darlo por retirado tiraría
// el catálogo entero —cero productos escritos— sin un solo error.
func TestSinIsActiveSeDaPorActivo(t *testing.T) {
	c, _ := montar(t, func(w http.ResponseWriter, _ *http.Request) {
		responder(w, `[{"sku":"A","name":"Algo"},{"sku":"B","name":"Retirado","isActive":false}]`)
	})
	filas, err := c.Catalogo(context.Background(), "santiago")
	if err != nil {
		t.Fatalf("%v", err)
	}
	if !filas[0].Activo {
		t.Error("sin el campo, activo")
	}
	if filas[1].Activo {
		t.Error("con isActive=false, retirado")
	}
}

// Ventra contesta a veces un array pelado y a veces envuelto. Las dos formas valen.
func TestRespuestaEnvueltaEnRows(t *testing.T) {
	c, _ := montar(t, func(w http.ResponseWriter, _ *http.Request) {
		responder(w, `{"database":"santiago","rows":[{"sku":"A","name":"Algo","isActive":true}]}`)
	})
	filas, err := c.Catalogo(context.Background(), "santiago")
	if err != nil || len(filas) != 1 {
		t.Fatalf("%v %v", filas, err)
	}
}

// ---------------------------------------------------------------------------
// Un fallo DEGRADA DICIENDO, nunca devuelve una lista vacía
// ---------------------------------------------------------------------------

// La VPN se cae. Esto es lo que pasa entonces, y lo que NO puede pasar.
func TestFalloDeRedDegradaConMensajeYNoConListaVacia(t *testing.T) {
	c, v := montar(t, func(w http.ResponseWriter, _ *http.Request) { responder(w, `[]`) })
	v.Close() // como si el túnel estuviera caído: no contesta nadie

	filas, err := c.Catalogo(context.Background(), "santiago")
	if err == nil {
		t.Fatal("un corte de red tiene que ser un error, no un catálogo de cero productos")
	}
	if filas != nil {
		t.Fatalf("y no puede devolver lista: %v", filas)
	}
	if !strings.Contains(err.Error(), "VPN") {
		t.Errorf("el mensaje tiene que apuntar a la VPN, que es lo primero que hay que mirar: %v", err)
	}

	bases, err := c.Bases(context.Background())
	if err == nil || bases != nil {
		t.Fatalf("lo mismo con las bases: %v %v", bases, err)
	}
}

// Un 500 de Ventra tampoco es un catálogo vacío. Y el cuerpo va en el mensaje, recortado,
// porque es lo que lee quien le dio al botón de sincronizar.
func TestVentraQueContestaMalNoDevuelveListaVacia(t *testing.T) {
	c, _ := montar(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		responder(w, `{"statusCode":500,"message":"la base no responde"}`)
	})
	filas, err := c.Catalogo(context.Background(), "santiago")
	if err == nil || filas != nil {
		t.Fatalf("tenía que degradar diciéndolo: %v %v", filas, err)
	}
	if !strings.Contains(err.Error(), "500") || !strings.Contains(err.Error(), "la base no responde") {
		t.Errorf("el mensaje tiene que traer el código y lo que dijo Ventra: %v", err)
	}
}

// UNA BASE CAÍDA CONTESTA VACÍO Y SIN ERROR: lo dice la documentación de Ventra. Tomarlo
// por bueno dejaría a esa sucursal sin pesos ni precios —los pedidos sin peso y el
// pre-despacho mintiendo— sin que salte nada. Aquí el vacío es un error con el nombre de
// la base dentro.
func TestCatalogoVacioEsErrorConElNombreDeLaBase(t *testing.T) {
	c, _ := montar(t, func(w http.ResponseWriter, _ *http.Request) { responder(w, `[]`) })
	filas, err := c.Catalogo(context.Background(), "holguinmoa")
	if err == nil || filas != nil {
		t.Fatalf("un catálogo vacío no es un catálogo bueno: %v %v", filas, err)
	}
	if !strings.Contains(err.Error(), "holguinmoa") {
		t.Errorf("tiene que decir de qué sucursal se quedó sin catálogo: %v", err)
	}
}

// Y si contesta algo que ni siquiera es JSON —un portal cautivo, un proxy—, tampoco.
func TestRespuestaQueNoEsJSONEsError(t *testing.T) {
	c, _ := montar(t, func(w http.ResponseWriter, _ *http.Request) {
		responder(w, `<html><body>502 Bad Gateway</body></html>`)
	})
	if filas, err := c.Catalogo(context.Background(), "santiago"); err == nil || filas != nil {
		t.Fatalf("%v %v", filas, err)
	}
}

// ---------------------------------------------------------------------------
// La puerta
// ---------------------------------------------------------------------------

// Sin token no se sale a la red, y se dice cuál falta: un «401 de Ventra» es mucho más
// difícil de relacionar con una variable que falta.
func TestSinTokenNiSaleALaRedYDiceQueFalta(t *testing.T) {
	v := &ventraDeMentira{}
	v.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		v.apuntar(r)
		responder(w, basesDeVentra)
	}))
	t.Cleanup(v.Close)

	c := Nuevo(&config.Config{VentraURL: v.URL}, callado())
	_, err := c.Bases(context.Background())
	if err == nil || !strings.Contains(err.Error(), "WAREHOUSE_API_TOKEN") {
		t.Fatalf("tenía que decir qué variable falta: %v", err)
	}
	if v.llamadas != 0 {
		t.Fatalf("y no tenía que salir a la red: %d llamadas", v.llamadas)
	}

	sinURL := Nuevo(&config.Config{VentraToken: "t"}, callado())
	if _, err := sinURL.Catalogo(context.Background(), "santiago"); err == nil ||
		!strings.Contains(err.Error(), "WAREHOUSE_API_URL") {
		t.Fatalf("lo mismo con la URL: %v", err)
	}
}

// El token va como `Bearer`, que es lo único que acepta Ventra.
func TestCadaPeticionVaFirmadaConElToken(t *testing.T) {
	c, v := montar(t, func(w http.ResponseWriter, _ *http.Request) { responder(w, basesDeVentra) })
	if _, err := c.Bases(context.Background()); err != nil {
		t.Fatalf("%v", err)
	}
	if got := v.cabezas[0].Get("authorization"); got != "Bearer token-de-pruebas" {
		t.Fatalf("la autorización: %q", got)
	}
	if got := v.cabezas[0].Get("accept"); got != "application/json" {
		t.Fatalf("el accept: %q", got)
	}
}

// La barra final de la variable no puede producir `//axis/databases`: unos servidores lo
// toleran y otros contestan un 404 que nadie sabe explicar.
func TestLaBarraFinalDeLaURLNoDuplicaLaRuta(t *testing.T) {
	v := &ventraDeMentira{}
	v.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		v.apuntar(r)
		responder(w, basesDeVentra)
	}))
	t.Cleanup(v.Close)

	c := Nuevo(&config.Config{VentraURL: v.URL + "/", VentraToken: "t"}, callado())
	if _, err := c.Bases(context.Background()); err != nil {
		t.Fatalf("%v", err)
	}
	if v.vistas()[0] != rutaBases {
		t.Fatalf("la ruta pedida fue %q", v.vistas()[0])
	}
}

// El cliente tiene que valer como `LectorDeVentra` tal cual, sin adaptador: un adaptador
// escrito a mano en el arranque es lo que se queda viejo en silencio el día que la interfaz
// cambie. Esto lo comprueba el compilador, aquí y en `ventra.go`.
func TestElClienteEsElLectorQueEsperaElEspejo(t *testing.T) {
	c, _ := montar(t, func(w http.ResponseWriter, _ *http.Request) { responder(w, basesDeVentra) })
	var lector api.LectorDeVentra = c
	bases, err := lector.Bases(context.Background())
	if err != nil || bases["STG"] != "santiago" {
		t.Fatalf("por la interfaz tiene que contestar igual: %v %v", bases, err)
	}
}

// clave normaliza lo que escribe la gente y lo que escriben los ERP.
func TestClaveNormalizaTildesYEspacios(t *testing.T) {
	casos := map[string]string{
		"Sancti Spíritus": "SANCTI SPIRITUS",
		"sancti  spirit":  "SANCTI SPIRIT",
		" LA HABANA ":     "LA HABANA",
		"Camagüey":        "CAMAGUEY",
	}
	for entra, sale := range casos {
		if v := clave(entra); v != sale {
			t.Errorf("clave(%q) = %q, quería %q", entra, v, sale)
		}
	}
}

// Que el JSON de ejemplo de la documentación siga siendo JSON válido: si un día se edita a
// mano y se rompe, que lo diga esta prueba y no una en la que cueste ver por qué falla.
func TestElEjemploDeBasesEsJSONValido(t *testing.T) {
	var v any
	if err := json.Unmarshal([]byte(basesDeVentra), &v); err != nil {
		t.Fatalf("%v", err)
	}
}
