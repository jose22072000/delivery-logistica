package api

// EL TOPE DE LA BAJADA NO PUEDE PERDER NI UNA FILA.
//
// Es el fallo del §3 del `CLAUDE.md`, el que más caro sale aquí: se pide un tope, se marca
// `truncado`, y la marca que se devuelve es el RELOJ en vez de la de la última fila
// servida. Entonces lo que no cupo queda por debajo del siguiente `desde` y no lo vuelve a
// pedir nadie nunca más. No revienta nada: el aparato dice que está al día con un cuarto
// de los clientes. Pasó el 15/09/2026 contra producción — 2.000 de 8.034 — y no lo vio
// nadie hasta que alguien leyó la base del teléfono.
//
// Por eso estas pruebas SIEMBRAN MÁS FILAS QUE EL TOPE. Con pocos datos el fallo es
// invisible: la primera tanda cabe entera y todo sale verde.

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

// ---------------------------------------------------------------------------
// La siembra
// ---------------------------------------------------------------------------

// sembrarPadronYCatalogo mete `cuantos` clientes y `cuantos` productos de STG, cada uno con
// SU marca —un minuto de diferencia entre filas— y todos dentro de la última hora.
//
// Marcas distintas a propósito: es el caso NORMAL, el que tiene que resolverse por `hasta`
// sin cursor ninguno. El caso de las marcas repetidas tiene su prueba aparte, más abajo.
func sembrarPadronYCatalogo(q *espejoFalso, cuantos int) {
	stg := "STG"
	base := time.Now().UTC().Add(-time.Hour)
	for i := 0; i < cuantos; i++ {
		marca := base.Add(time.Duration(i) * time.Minute)

		idc := uuid.New()
		q.padron = append(q.padron, sqlc.ListarClientesRow{
			ID: idc, Name: fmt.Sprintf("Cliente %03d", i),
			Lat: 20.0, Lng: -75.0, SucursalCodigo: &stg,
			SyncedAt: pgtype.Timestamptz{Time: marca, Valid: true},
		})

		idp := uuid.New()
		sku := fmt.Sprintf("SKU-%03d", i)
		q.catalogoDelEspejo = append(q.catalogoDelEspejo, sqlc.Product{
			ID: idp, Name: fmt.Sprintf("Producto %03d", i), Sku: &sku,
			SucursalCodigo: &stg,
			UpdatedAt:      pgtype.Timestamptz{Time: marca, Valid: true},
		})
	}
}

// tanda es una vuelta de la cadena, ya leída.
type tanda struct {
	clientes  map[string]bool
	productos map[string]bool
	hasta     string
	continuar string
	truncado  bool
}

func pedirTanda(t *testing.T, h http.Handler, jwt, desde, continuar string, tope int) tanda {
	t.Helper()
	url := fmt.Sprintf("/api/sync/cambios?tope=%d", tope)
	if desde != "" {
		url += "&desde=" + desde
	}
	if continuar != "" {
		url += "&continuar=" + continuar
	}
	w := pedirTab(t, h, http.MethodGet, url, jwt, "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	cli, _, _ := conjuntoDe(t, m, "customers")
	pro, _, _ := conjuntoDe(t, m, "products")
	hasta, _ := m["hasta"].(string)
	sigue, _ := m["continuar"].(string)
	truncado, _ := m["truncado"].(bool)
	return tanda{clientes: cli, productos: pro, hasta: hasta, continuar: sigue, truncado: truncado}
}

// apuntar suma lo de una tanda y se queja si algo viene dos veces.
func apuntar(t *testing.T, vuelta int, donde, loDeLaTanda map[string]bool, que string) {
	t.Helper()
	for id := range loDeLaTanda {
		if donde[id] {
			t.Fatalf("vuelta %d: %s repetido (%s). La cadena está dando vueltas sobre lo "+
				"mismo en vez de avanzar", vuelta, que, id)
		}
		donde[id] = true
	}
}

// ---------------------------------------------------------------------------
// Las pruebas
// ---------------------------------------------------------------------------

// EL APARATO ENCADENA CON LAS DOS COSAS —la marca y el cursor— Y NO PIERDE NI REPITE.
//
// Es lo que hace `app/lib/nucleo/sincro/bajada.dart`: aplica la tanda, se apunta el `hasta`
// como nueva marca de frescura y devuelve el `continuar` tal cual.
func TestLaBajadaEncadenaElPadronYElCatalogoEnterosSinPerderNiRepetir(t *testing.T) {
	const total, tope = 17, 5
	q := nuevoEspejo()
	sembrarPadronYCatalogo(q, total)
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	vistosCli, vistosPro := map[string]bool{}, map[string]bool{}
	desde, continuar := "", ""
	for vuelta := 1; ; vuelta++ {
		if vuelta > 20 {
			t.Fatalf("la cadena no termina: %d clientes y %d productos servidos",
				len(vistosCli), len(vistosPro))
		}
		x := pedirTanda(t, h, jwt, desde, continuar, tope)
		apuntar(t, vuelta, vistosCli, x.clientes, "cliente")
		apuntar(t, vuelta, vistosPro, x.productos, "producto")
		if !x.truncado {
			break
		}
		if x.hasta == "" {
			t.Fatalf("vuelta %d: dijo «truncado» y no mandó marca", vuelta)
		}
		desde, continuar = x.hasta, x.continuar
	}

	if len(vistosCli) != total || len(vistosPro) != total {
		t.Fatalf("se perdieron filas por el camino: bajaron %d/%d clientes y %d/%d productos",
			len(vistosCli), total, len(vistosPro), total)
	}
}

// LA QUE CAZA EL FALLO DE VERDAD: **encadenando SÓLO por la marca, sin cursor ninguno.**
//
// Hay dos clientes de este endpoint y no uno. El aparato devuelve el `continuar`; el
// SINCRONIZADOR, que es quien está delante de las APK instaladas, encadena por `hasta` y
// nada más. Si la respuesta devuelve el reloj en vez de la marca de la última fila servida,
// este de aquí pide la vuelta siguiente «a partir de ahora» y **todo lo que no cupo en la
// primera tanda deja de existir para él**, sin un error, sin un aviso y sin una línea en
// ningún registro.
//
// Por eso esta prueba tira a propósito el cursor en cada vuelta.
func TestLaBajadaNoPierdeNadaAunqueSeTireElCursorYSoloSeSigaLaMarca(t *testing.T) {
	const total, tope = 17, 5
	q := nuevoEspejo()
	sembrarPadronYCatalogo(q, total)
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	vistosCli, vistosPro := map[string]bool{}, map[string]bool{}
	desde := ""
	for vuelta := 1; ; vuelta++ {
		if vuelta > 20 {
			t.Fatalf("la cadena no termina sin cursor: %d clientes y %d productos servidos "+
				"de %d. Con marcas distintas, `hasta` tiene que bastar para avanzar",
				len(vistosCli), len(vistosPro), total)
		}
		// EL CURSOR SE TIRA: se pasa "" en cada vuelta, a propósito.
		x := pedirTanda(t, h, jwt, desde, "", tope)
		for id := range x.clientes {
			vistosCli[id] = true
		}
		for id := range x.productos {
			vistosPro[id] = true
		}
		if !x.truncado {
			break
		}
		if x.hasta == desde {
			t.Fatalf("vuelta %d: dijo «truncado» y devolvió la MISMA marca (%s). Sin cursor, "+
				"la vuelta siguiente trae exactamente lo mismo para siempre", vuelta, x.hasta)
		}
		desde = x.hasta
	}

	if len(vistosCli) != total || len(vistosPro) != total {
		t.Fatalf("SE PERDIERON FILAS EN SILENCIO: siguiendo sólo la marca bajaron %d/%d "+
			"clientes y %d/%d productos. La respuesta tiene que devolver como «hasta» la "+
			"marca de la ÚLTIMA FILA SERVIDA, no el reloj: con el reloj, lo que no cupo en "+
			"la tanda queda por debajo del próximo «desde» y no lo vuelve a pedir nadie "+
			"(CLAUDE.md §3, los 2.000 clientes de 8.034)",
			len(vistosCli), total, len(vistosPro), total)
	}
}

// EL `hasta` DE UNA TANDA CORTADA ES LA MARCA DE UNA FILA, NO EL RELOJ.
//
// La de arriba prueba la consecuencia; ésta prueba la causa, y lo dice con el número
// delante para que el mensaje se entienda sin leerse el código.
func TestElHastaDeUnaTandaCortadaEsLaMarcaDeLaUltimaFilaServida(t *testing.T) {
	const total, tope = 9, 3
	q := nuevoEspejo()
	sembrarPadronYCatalogo(q, total)
	h := montarTab(t, q)

	antesDePedir := time.Now().UTC()
	x := pedirTanda(t, h, tokenTab(t, sucStg.String()), "", "", tope)
	if !x.truncado {
		t.Fatalf("con %d filas y tope %d la tanda tiene que venir cortada", total, tope)
	}
	hasta := mustHora(t, x.hasta)
	if !hasta.Before(antesDePedir) {
		t.Fatalf("«hasta» vale %s, que es el reloj de la petición (%s) y no la marca de "+
			"ninguna fila servida. Con el reloj, las %d filas que no cupieron quedan por "+
			"debajo del próximo «desde» y no se piden nunca más",
			hasta.Format(time.RFC3339Nano), antesDePedir.Format(time.RFC3339Nano), total-tope)
	}
	// Y no puede haberse pasado de la última servida: la siguiente fila sin servir tiene
	// que seguir estando por encima de la raya.
	if len(x.clientes) != tope {
		t.Fatalf("la tanda tenía que traer %d clientes y trajo %d", tope, len(x.clientes))
	}
}

// MILES DE FILAS CON LA MISMA MARCA: el caso que el cursor existe para resolver.
//
// No es de laboratorio. El traspaso metió los 7.975 clientes de producción en UNA
// transacción, y `now()` en Postgres es la del INICIO de la transacción: las 7.975 filas
// comparten `synced_at` al microsegundo. Con un cursor de sólo marca —o sin cursor— un
// grupo más grande que el tope o se repite para siempre o se salta por la mitad.
func TestUnGrupoConLaMismaMarcaMasGrandeQueElTopeSeSirveEntero(t *testing.T) {
	const total, tope = 11, 4
	q := nuevoEspejo()
	stg := "STG"
	// LA MISMA marca para las once, al microsegundo, como la deja una transacción.
	deGolpe := time.Now().UTC().Add(-time.Hour).Truncate(time.Microsecond)
	for i := 0; i < total; i++ {
		q.padron = append(q.padron, sqlc.ListarClientesRow{
			ID: uuid.New(), Name: fmt.Sprintf("Cliente %03d", i),
			Lat: 20.0, Lng: -75.0, SucursalCodigo: &stg,
			SyncedAt: pgtype.Timestamptz{Time: deGolpe, Valid: true},
		})
	}
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	vistos := map[string]bool{}
	desde, continuar := "", ""
	for vuelta := 1; ; vuelta++ {
		if vuelta > 15 {
			t.Fatalf("la cadena no termina: %d de %d clientes servidos", len(vistos), total)
		}
		x := pedirTanda(t, h, jwt, desde, continuar, tope)
		apuntar(t, vuelta, vistos, x.clientes, "cliente")
		if !x.truncado {
			break
		}
		if x.continuar == continuar {
			t.Fatalf("vuelta %d: el cursor no avanzó (%q). Con todas las filas en la misma "+
				"marca, el cursor es lo ÚNICO que puede avanzar", vuelta, continuar)
		}
		desde, continuar = x.hasta, x.continuar
	}

	if len(vistos) != total {
		t.Fatalf("se sirvieron %d clientes de %d, todos con la misma marca: el cursor "+
			"(marca, id) tiene que empezar donde acabó la tanda anterior", len(vistos), total)
	}
}

// Y ESE GRUPO PARTIDO NO PUEDE DEVOLVER SU PROPIA MARCA COMO `hasta`.
//
// Si la devolviera, quien siga sólo por la marca —el sincronizador— pediría «a partir de
// esa marca» y el resto del grupo, que tiene EXACTAMENTE esa marca, no volvería a salir.
// Retroceder es repetir trabajo; devolver la marca del grupo partido es perderlo.
func TestUnGrupoPartidoDevuelveUnaMarcaAnteriorAlGrupo(t *testing.T) {
	const total, tope = 7, 3
	q := nuevoEspejo()
	stg := "STG"
	deGolpe := time.Now().UTC().Add(-time.Hour).Truncate(time.Microsecond)
	for i := 0; i < total; i++ {
		q.padron = append(q.padron, sqlc.ListarClientesRow{
			ID: uuid.New(), Name: fmt.Sprintf("Cliente %03d", i),
			Lat: 20.0, Lng: -75.0, SucursalCodigo: &stg,
			SyncedAt: pgtype.Timestamptz{Time: deGolpe, Valid: true},
		})
	}
	h := montarTab(t, q)

	x := pedirTanda(t, h, tokenTab(t, sucStg.String()), "", "", tope)
	if !x.truncado {
		t.Fatal("con 7 filas y tope 3 la tanda viene cortada")
	}
	hasta := mustHora(t, x.hasta)
	if !hasta.Before(deGolpe) {
		t.Fatalf("«hasta» vale %s y el grupo entero está en %s: quien vuelva a pedir por "+
			"esa marca no recibirá las %d filas del grupo que no cupieron",
			hasta.Format(time.RFC3339Nano), deGolpe.Format(time.RFC3339Nano), total-tope)
	}
}

// LA BAJADA POR MARCA SE APOYA EN EL ESQUEMA, ASÍ QUE EL ESQUEMA SE VIGILA.
//
// `DiferenciasDeClientes` y `DiferenciasDeProductos` ordenan y cortan por `synced_at` y por
// `updated_at`. Una fila sin marca no tendría por dónde continuarse: se quedaría clavada en
// el mismo punto de la cadena y no bajaría jamás. Hoy no puede pasar porque las dos columnas
// son NOT NULL, y eso es un supuesto del que depende la corrección — así que no se deja
// escrito en un comentario, que es lo que no falla nunca. Se comprueba.
func TestLaBajadaPorMarcaExigeQueLasDosColumnasSeanNotNull(t *testing.T) {
	bruto, err := os.ReadFile("../../db/migrations/00001_init.sql")
	if err != nil {
		t.Fatalf("no se pudo leer la migración: %v", err)
	}
	esquema := string(bruto)

	for _, caso := range []struct{ tabla, columna string }{
		{"customers", "synced_at"},
		{"products", "updated_at"},
	} {
		cuerpo := cuerpoDeLaTabla(t, esquema, caso.tabla)
		linea := regexp.MustCompile(`(?m)^\s*` + caso.columna + `\s+timestamptz[^,\n]*`)
		encontrada := linea.FindString(cuerpo)
		if encontrada == "" {
			t.Fatalf("no se encontró la columna %s.%s en la migración", caso.tabla, caso.columna)
		}
		if !strings.Contains(strings.ToUpper(encontrada), "NOT NULL") {
			t.Errorf("%s.%s ya no es NOT NULL: %q\n"+
				"La bajada del aparato ordena y corta por esa columna (DiferenciasDe%s). "+
				"Una fila sin marca no se puede continuar: se queda clavada en la cadena y "+
				"no baja nunca. O vuelve a ser NOT NULL, o la bajada necesita otra forma de "+
				"paginarse y esta prueba cambia con ella.",
				caso.tabla, caso.columna, strings.TrimSpace(encontrada), caso.tabla)
		}
	}
}

// cuerpoDeLaTabla saca el `CREATE TABLE <nombre> ( … );` del esquema.
func cuerpoDeLaTabla(t *testing.T, esquema, tabla string) string {
	t.Helper()
	i := strings.Index(esquema, "CREATE TABLE "+tabla+" (")
	if i < 0 {
		t.Fatalf("no hay CREATE TABLE %s en la migración", tabla)
	}
	resto := esquema[i:]
	j := strings.Index(resto, "\n);")
	if j < 0 {
		t.Fatalf("no se encontró el final de CREATE TABLE %s", tabla)
	}
	return resto[:j]
}

// ---------------------------------------------------------------------------
// El tercero de la familia: POST /api/admin/recompute
// ---------------------------------------------------------------------------

// PEDIR UN TOPE Y NO MIRAR CUÁNTOS VINIERON, que es el §3 en una línea.
//
// El recosteo le pide a PEDIDO una ventana de días con `limit=5000` y PEDIDO corta sin
// decirlo. Una ventana de 30 días son hoy ~13.000 pedidos: se recosteaban 5.000, la
// pantalla decía «total: 5000, recosteados: 5000» y los otros 8.000 se quedaban con el
// precio viejo. Nadie lo nota hasta cuadrar la caja, y para entonces ya se cobró.
//
// No se puede paginar —`/integration/orders` no da cursor; partir la ventana en tramos es
// lo que hace `internal/espejo`, que es el que barre el histórico—, así que lo que manda la
// regla es lo otro: **decirlo, nombrando lo que se quedó fuera**.
func TestElRecosteoDiceCuandoPedidoLeCortoElTope(t *testing.T) {
	pedidos := make([]string, 0, TopeDelRecosteo)
	for i := 0; i < TopeDelRecosteo; i++ {
		pedidos = append(pedidos, fmt.Sprintf(`{"id":"p-%d"}`, i))
	}
	pedido := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.Contains(r.URL.RawQuery, fmt.Sprintf("limit=%d", TopeDelRecosteo)) {
			t.Errorf("no se pidió el tope que se comprueba: %s", r.URL.RawQuery)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = fmt.Fprintf(w, `{"orders":[%s]}`, strings.Join(pedidos, ","))
	}))
	defer pedido.Close()

	lote := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"weightsSource":"warehouse","results":[]}`))
	}))
	defer lote.Close()

	t.Setenv("SERVICE_API_KEY", "clave")
	t.Setenv("PEDIDO_API_URL", pedido.URL)
	t.Setenv("DELIVERY_URL", lote.URL)
	h := montarTab(t, nuevoEspejo())

	w := pedirTab(t, h, http.MethodPost, "/api/admin/recompute", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	if truncado, _ := m["truncado"].(bool); !truncado {
		t.Fatalf("PEDIDO devolvió justo el tope (%d) y la respuesta no lo dice: %s\n"+
			"Un recosteo que se calla que le cortaron deja miles de pedidos con el precio "+
			"viejo y la pantalla en verde (CLAUDE.md §3).", TopeDelRecosteo, w.Body.String())
	}
	aviso, _ := m["aviso"].(string)
	if !strings.Contains(aviso, "tope") || !strings.Contains(aviso, "dias") {
		t.Fatalf("el aviso no dice qué pasó ni qué hacer: %q", aviso)
	}
}

// Y NO SALTA CUANDO NO TOCA. Un aviso que sale siempre deja de leerse, y entonces tampoco
// se lee el día que importa: las dos pruebas van en pareja.
func TestElRecosteoNoAvisaCuandoCabeTodo(t *testing.T) {
	pedido := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"orders":[{"id":"p-1"},{"id":"p-2"}]}`))
	}))
	defer pedido.Close()
	lote := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"weightsSource":"warehouse","results":[]}`))
	}))
	defer lote.Close()

	t.Setenv("SERVICE_API_KEY", "clave")
	t.Setenv("PEDIDO_API_URL", pedido.URL)
	t.Setenv("DELIVERY_URL", lote.URL)
	h := montarTab(t, nuevoEspejo())

	w := pedirTab(t, h, http.MethodPost, "/api/admin/recompute", tokenTab(t, sucStg.String()), "")
	m := leerTab(t, w)
	if _, hay := m["truncado"]; hay {
		t.Fatalf("avisó de un corte que no hubo: %s", w.Body.String())
	}
	if _, hay := m["aviso"]; hay {
		t.Fatalf("avisó de un corte que no hubo: %s", w.Body.String())
	}
}
