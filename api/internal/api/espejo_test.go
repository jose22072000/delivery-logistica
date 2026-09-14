package api

// Las pruebas del espejo. Sin VPN, sin Ventra y sin PEDIDO: el lector de Ventra es una
// interfaz y los dos servicios de fuera son `httptest`, así que esto se corre en cada
// compilación y no «cuando haya una Ventra a mano».

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

// --------------------------------------------------------------------------- el doble

type espejoFalso struct {
	*tableroFalso

	ajustes   sqlc.Setting
	marcada   int
	guardados map[string]int // sucursal|sku -> veces que se escribió
}

func nuevoEspejo() *espejoFalso {
	return &espejoFalso{
		tableroFalso: nuevoTablero(),
		guardados:    map[string]int{},
	}
}

func (q *espejoFalso) ObtenerAjustes(context.Context) (sqlc.Setting, error) { return q.ajustes, nil }

func (q *espejoFalso) MarcarCatalogoTraido(context.Context) error {
	q.marcada++
	q.ajustes.CatalogoTraidoAt = pgtype.Timestamptz{Time: time.Now(), Valid: true}
	return nil
}

func (q *espejoFalso) GuardarProductoDelCatalogo(_ context.Context, arg sqlc.GuardarProductoDelCatalogoParams) (sqlc.GuardarProductoDelCatalogoRow, error) {
	clave := *arg.SucursalCodigo + "|" + *arg.Sku
	q.guardados[clave]++
	return sqlc.GuardarProductoDelCatalogoRow{ID: uuid.New(), Name: arg.Name, Sku: arg.Sku}, nil
}

func (q *espejoFalso) ListarSucursales(_ context.Context, persona pgtype.UUID) ([]sqlc.ListarSucursalesRow, error) {
	stg, hol := "STG", "HOL"
	ahora := pgtype.Timestamptz{Time: time.Now(), Valid: true}
	todas := []sqlc.ListarSucursalesRow{
		{ID: sucStg, Name: "Santiago", ExternalID: &stg, UpdatedAt: ahora},
		{ID: sucHol, Name: "Holguín", ExternalID: &hol, UpdatedAt: ahora},
	}
	if !persona.Valid {
		return todas, nil
	}
	var salida []sqlc.ListarSucursalesRow
	for _, b := range todas {
		if [16]byte(b.ID) == persona.Bytes {
			salida = append(salida, b)
		}
	}
	return salida, nil
}

func (q *espejoFalso) ListarVehiculos(context.Context, pgtype.UUID) ([]sqlc.ListarVehiculosRow, error) {
	return nil, nil
}
func (q *espejoFalso) ListarRutas(context.Context, sqlc.ListarRutasParams) ([]sqlc.ListarRutasRow, error) {
	return nil, nil
}
func (q *espejoFalso) ListarProductos(context.Context, sqlc.ListarProductosParams) ([]sqlc.Product, error) {
	return nil, nil
}
func (q *espejoFalso) ListarClientes(context.Context, sqlc.ListarClientesParams) ([]sqlc.ListarClientesRow, error) {
	return nil, nil
}

// --------------------------------------------------------------------------- Ventra de mentira

type ventraFalsa struct {
	bases    map[string]string
	catalogo map[string][]FilaDeVentra
	fallo    error
	llamadas int
}

func (v *ventraFalsa) Bases(context.Context) (map[string]string, error) {
	if v.fallo != nil {
		return nil, v.fallo
	}
	return v.bases, nil
}

func (v *ventraFalsa) Catalogo(_ context.Context, base string) ([]FilaDeVentra, error) {
	v.llamadas++
	return v.catalogo[base], nil
}

// ventraDePrueba es el lector que el montador le pone al servidor. Vive aquí, en las
// pruebas, y no en el paquete: el lector de verdad ya es un campo de `Servidor`.
//
// SE PONE ANTES DE MONTAR, que es como lo llaman todas las pruebas de este fichero: el
// montador lo lee al construir el servidor. Al acabar cada prueba se restaura, así que una
// no le deja el lector puesto a la siguiente.
var ventraDePrueba LectorDeVentra

func conVentra(t *testing.T, v LectorDeVentra) {
	t.Helper()
	anterior := ventraDePrueba
	ventraDePrueba = v
	t.Cleanup(func() { ventraDePrueba = anterior })
}

// --------------------------------------------------------------------------- pruebas

// SIN LECTOR DE VENTRA, 502 Y NO 200 CON CEROS. Un catálogo que dice «he escrito 0
// productos» cuando en realidad no ha preguntado a nadie deja al logístico mirando
// precios de hace tres semanas sin un solo aviso.
func TestProductosSyncSinLectorDeVentraEs502(t *testing.T) {
	conVentra(t, nil)
	h := montarTab(t, nuevoEspejo())
	w := pedirTab(t, h, http.MethodPost, "/api/products/sync", tokenTab(t, ""), "")
	if w.Code != http.StatusBadGateway {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "No se pudo preguntar a Ventra") {
		t.Fatalf("mensaje %q", w.Body.String())
	}
}

// El upsert es por (sucursal, sku): pasar el mismo lote dos veces NO duplica nada. Es la
// condición para poder reintentar cuando la VPN se corta a la mitad.
func TestProductosSyncEsReaplicable(t *testing.T) {
	v := &ventraFalsa{
		bases: map[string]string{"STG": "ventra_stg", "HOL": "ventra_hol"},
		catalogo: map[string][]FilaDeVentra{
			"ventra_stg": {
				{Sku: "MALTA-1", Nombre: "Malta 355 ml", Activo: true},
				{Sku: "", Nombre: "Sin sku", Activo: true},        // se salta: no hay por dónde reconocerla
				{Sku: "RETIRADO", Nombre: "Viejo", Activo: false}, // se salta: retirado en Ventra
			},
			"ventra_hol": {{Sku: "AGUA-5", Nombre: "Agua 5 L", Activo: true}},
		},
	}
	conVentra(t, v)
	q := nuevoEspejo()
	h := montarTab(t, q)
	jwt := tokenTab(t, "")

	for vuelta := 1; vuelta <= 2; vuelta++ {
		// `forzar` porque la segunda vuelta cae dentro del intervalo de doce horas.
		w := pedirTab(t, h, http.MethodPost, "/api/products/sync?forzar=1", jwt, "")
		if w.Code != http.StatusOK {
			t.Fatalf("vuelta %d: código %d (%s)", vuelta, w.Code, w.Body.String())
		}
		m := leerTab(t, w)
		if n, _ := m["escritos"].(float64); n != 2 {
			t.Fatalf("vuelta %d: escritos %v, cuerpo %s", vuelta, m["escritos"], w.Body.String())
		}
	}
	// Dos vueltas, dos escrituras por producto, PERO sólo dos productos: el upsert los
	// pisa, no los duplica.
	if len(q.guardados) != 2 {
		t.Fatalf("el catálogo se duplicó: %+v", q.guardados)
	}
	if q.guardados["STG|MALTA-1"] != 2 || q.guardados["HOL|AGUA-5"] != 2 {
		t.Fatalf("no se reescribieron los dos: %+v", q.guardados)
	}
}

// Si TODAS las sucursales fallan, la hora NO se marca: hay que poder reintentar antes de
// las doce horas en vez de quedarse medio día con el catálogo a medias.
func TestSiNingunaSucursalCuadraNoSeMarcaLaHora(t *testing.T) {
	conVentra(t, &ventraFalsa{bases: map[string]string{}})
	q := nuevoEspejo()
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/products/sync", tokenTab(t, ""), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	if n, _ := m["conError"].(float64); n != 2 {
		t.Fatalf("conError %v: %s", m["conError"], w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "sin base de Ventra que le cuadre") {
		t.Fatalf("falta el literal del contrato: %s", w.Body.String())
	}
	if q.marcada != 0 {
		t.Fatal("se marcó la hora sin haber escrito nada")
	}
}

// El intervalo: sin forzar, no se vuelve a preguntar antes de las doce horas.
func TestProductosSyncRespetaElIntervalo(t *testing.T) {
	v := &ventraFalsa{bases: map[string]string{"STG": "ventra_stg"}}
	conVentra(t, v)
	q := nuevoEspejo()
	q.ajustes.CatalogoTraidoAt = pgtype.Timestamptz{Time: time.Now().Add(-time.Hour), Valid: true}
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/products/sync", tokenTab(t, ""), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d", w.Code)
	}
	if saltado, _ := leerTab(t, w)["saltado"].(bool); !saltado {
		t.Fatalf("no se saltó: %s", w.Body.String())
	}
	if v.llamadas != 0 {
		t.Fatal("preguntó a Ventra igual")
	}
}

// La clave de servicio abre la puerta sin sesión: la ruta la dispara un temporizador.
func TestProductosSyncEntraConClaveDeServicio(t *testing.T) {
	t.Setenv("SERVICE_API_KEY", "la-clave-del-espejo")
	conVentra(t, &ventraFalsa{bases: map[string]string{}})
	h := montarTab(t, nuevoEspejo())

	r := httptest.NewRequest(http.MethodPost, "/api/products/sync", nil)
	r.Header.Set("X-Api-Key", "la-clave-del-espejo")
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}

	// Y una clave equivocada NO entra, ni siquiera para mirar.
	r = httptest.NewRequest(http.MethodPost, "/api/products/sync", nil)
	r.Header.Set("X-Api-Key", "la-que-no-es")
	w = httptest.NewRecorder()
	h.ServeHTTP(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("una clave mala entró: %d", w.Code)
	}
}

// Sin la clave de servicio no se puede hablar con PEDIDO, y eso se dice ANTES de bajar
// cinco mil pedidos, no después.
func TestRecomputeSinClaveDeServicioEs500(t *testing.T) {
	t.Setenv("SERVICE_API_KEY", "")
	h := montarTab(t, nuevoEspejo())
	w := pedirTab(t, h, http.MethodPost, "/api/admin/recompute", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusInternalServerError {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if leerTab(t, w)["error"] != "SERVICE_API_KEY no configurada en el servidor" {
		t.Fatalf("mensaje %q", w.Body.String())
	}
}

func TestRecomputeDevuelve502ConLoQueDijoPedido(t *testing.T) {
	pedido := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte("la base de PEDIDO no contesta"))
	}))
	defer pedido.Close()

	t.Setenv("SERVICE_API_KEY", "clave")
	t.Setenv("PEDIDO_API_URL", pedido.URL)
	h := montarTab(t, nuevoEspejo())

	w := pedirTab(t, h, http.MethodPost, "/api/admin/recompute", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusBadGateway {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	// El cuerpo de PEDIDO viaja dentro: sin él, «502» no dice nada que se pueda arreglar.
	if !strings.Contains(w.Body.String(), "PEDIDO 500") ||
		!strings.Contains(w.Body.String(), "la base de PEDIDO no contesta") {
		t.Fatalf("mensaje %q", w.Body.String())
	}
}

// Que no haya nada que recostear NO es un fallo, y la pantalla necesita poder decirlo con
// esas palabras.
func TestRecomputeSinPedidosEs200ConMensaje(t *testing.T) {
	pedido := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Api-Key") == "" {
			t.Error("la petición a PEDIDO fue sin clave de servicio")
		}
		if !strings.Contains(r.URL.RawQuery, "sucursalCodigo=STG") {
			t.Errorf("el alcance no viajó como código: %s", r.URL.RawQuery)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"orders": []any{}})
	}))
	defer pedido.Close()

	t.Setenv("SERVICE_API_KEY", "clave")
	t.Setenv("PEDIDO_API_URL", pedido.URL)
	h := montarTab(t, nuevoEspejo())

	w := pedirTab(t, h, http.MethodPost, "/api/admin/recompute?dias=900",
		tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	// 900 días se acota a 120: con «todos los días» esto se convierte en una consulta de
	// 3.500 pedidos por la conexión de Cuba.
	if n, _ := m["dias"].(float64); n != 120 {
		t.Fatalf("los días no se acotaron: %v", m["dias"])
	}
	if !strings.Contains(m["message"].(string), "No hay pedidos con geolocalización") {
		t.Fatalf("mensaje %q", m["message"])
	}
}

// LA BAJADA NO PUEDE MENTIR CON UN CONJUNTO VACÍO.
//
// `orders` todavía no se sabe servir por diferencias. Mandarlo como
// `{"puestos":[],"quitados":[]}` le diría al aparato «no ha cambiado ningún pedido», que
// es lo contrario de la verdad, y el logístico prepararía el día con la foto de ayer.
func TestLaBajadaNombraLoQueNoSabeServirEnVezDeMandarloVacio(t *testing.T) {
	h := montarTab(t, nuevoEspejo())
	w := pedirTab(t, h, http.MethodGet, "/api/sync/cambios", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)

	cambios := m["cambios"].(map[string]any)
	if _, hay := cambios["orders"]; hay {
		t.Fatal("«orders» sale como conjunto vacío: eso le dice al aparato que no cambió nada")
	}
	faltan := m["faltan"].([]any)
	visto := false
	for _, f := range faltan {
		if f == "orders" {
			visto = true
		}
	}
	if !visto {
		t.Fatalf("«orders» no está nombrado en «faltan»: %s", w.Body.String())
	}
	if m["aviso"] == nil || m["aviso"].(string) == "" {
		t.Fatal("falta el aviso que explica por qué")
	}
}

// `hasta` LO PONE EL SERVIDOR, y la primera bajada es completa.
func TestLaBajadaTraeLaMarcaDelServidor(t *testing.T) {
	h := montarTab(t, nuevoEspejo())
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodGet, "/api/sync/cambios", jwt, "")
	m := leerTab(t, w)
	if completa, _ := m["completa"].(bool); !completa {
		t.Fatal("sin «desde», la bajada tiene que ser la carga inicial")
	}
	hasta, err := time.Parse(time.RFC3339, m["hasta"].(string))
	if err != nil || time.Since(hasta) > time.Minute {
		t.Fatalf("«hasta» no es una marca del servidor: %v", m["hasta"])
	}

	// Con `desde` en el futuro no cambió nada, pero las colecciones siguen ahí: ausente
	// y vacío significan cosas distintas y no se pueden confundir.
	futuro := time.Now().Add(time.Hour).UTC().Format(time.RFC3339)
	w = pedirTab(t, h, http.MethodGet, "/api/sync/cambios?desde="+futuro, jwt, "")
	m = leerTab(t, w)
	if completa, _ := m["completa"].(bool); completa {
		t.Fatal("con «desde» ya no es carga inicial")
	}
	sucursales := m["cambios"].(map[string]any)["branches"].(map[string]any)
	if len(sucursales["puestos"].([]any)) != 0 {
		t.Fatalf("con «desde» en el futuro no puede venir nada: %s", w.Body.String())
	}

	// Y un «desde» que no es una fecha es un 400 que lo dice, no un silencio.
	w = pedirTab(t, h, http.MethodGet, "/api/sync/cambios?desde=ayer", jwt, "")
	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
}

// El tablero de la bajada es POR SUCURSAL: al Super Admin sin elegir no se le mandan las
// ocho mezcladas, se le dice que falta elegir.
func TestLaBajadaDelTableroPideSucursal(t *testing.T) {
	h := montarTab(t, nuevoEspejo())

	w := pedirTab(t, h, http.MethodGet, "/api/sync/cambios", tokenTab(t, ""), "")
	m := leerTab(t, w)
	if _, hay := m["cambios"].(map[string]any)["boardColumns"]; hay {
		t.Fatal("se mandó el tablero sin saber de qué sucursal")
	}

	w = pedirTab(t, h, http.MethodGet, "/api/sync/cambios?sucursal="+sucStg.String(), tokenTab(t, ""), "")
	m = leerTab(t, w)
	cols, hay := m["cambios"].(map[string]any)["boardColumns"]
	if !hay {
		t.Fatalf("con sucursal tenía que venir el tablero: %s", w.Body.String())
	}
	if len(cols.(map[string]any)["puestos"].([]any)) != 3 {
		t.Fatalf("columnas: %s", w.Body.String())
	}
}
