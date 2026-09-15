package api

// Las pruebas del espejo. Sin VPN, sin Ventra y sin PEDIDO: el lector de Ventra es una
// interfaz y los dos servicios de fuera son `httptest`, así que esto se corre en cada
// compilación y no «cuando haya una Ventra a mano».

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sort"
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

	// Los pedidos y las lápidas de la bajada. Van aparte de `tableroFalso.pedidos`: el
	// tablero necesita coordenadas y peso, y esto necesita marcas de tiempo y renglones.
	sync    []pedidoSync
	salidas []salidaSync

	// El padrón de clientes de la bajada, entero. El doble lo sirve por tandas
	// respetando `Limite` y `Desplazamiento`, como el SQL: lo que se comprueba es que el
	// manejador sepa pedir la tanda siguiente.
	padron []sqlc.ListarClientesRow
}

func nuevoEspejo() *espejoFalso {
	return &espejoFalso{
		tableroFalso: nuevoTablero(),
		guardados:    map[string]int{},
	}
}

// --------------------------------------------------------------- la bajada de pedidos
//
// EL DOBLE REPITE LAS REGLAS DEL SQL, no contesta lo que le pidan: el `desde` estricto, el
// `hasta` inclusivo, las dos sucursales en AND, el interruptor de los archivados, el orden
// por la marca y el tope. Lo que hay que comprobar aquí es que el manejador respeta lo que
// la consulta le devuelve —y, sobre todo, que `cambiado_at` es el MÁS NUEVO del pedido y
// de sus renglones—, y con un doble que dijera a todo que sí no se comprobaría nada.

type renglonSync struct {
	linea int32
	desc  string
	marca time.Time // el `updated_at` del renglón
}

type pedidoSync struct {
	id        uuid.UUID
	sucursal  uuid.UUID
	nombre    string
	archivado bool
	marca     time.Time // el `updated_at` del pedido
	renglones []renglonSync
}

// cambiadoAt es el `GREATEST(o.updated_at, max(oi.updated_at))` de la consulta.
func (p pedidoSync) cambiadoAt() time.Time {
	m := p.marca
	for _, r := range p.renglones {
		if r.marca.After(m) {
			m = r.marca
		}
	}
	return m
}

type salidaSync struct {
	pedido   uuid.UUID
	sucursal uuid.UUID
	motivo   sqlc.SalidaDePedido
	salioAt  time.Time
}

func (q *espejoFalso) DiferenciasDePedidos(_ context.Context, arg sqlc.DiferenciasDePedidosParams) ([]sqlc.DiferenciasDePedidosRow, error) {
	var filas []sqlc.DiferenciasDePedidosRow
	for _, p := range q.sync {
		cambiado := p.cambiadoAt()
		// `desde` ESTRICTO y `hasta` INCLUSIVO, como el SQL: dos ventanas seguidas no se
		// pisan ni dejan hueco.
		if arg.Desde.Valid && !cambiado.After(arg.Desde.Time) {
			continue
		}
		if arg.Hasta.Valid && cambiado.After(arg.Hasta.Time) {
			continue
		}
		if arg.Sucursal.Valid && [16]byte(p.sucursal) != arg.Sucursal.Bytes {
			continue
		}
		if arg.BranchID.Valid && [16]byte(p.sucursal) != arg.BranchID.Bytes {
			continue
		}
		if p.archivado && !arg.ConArchivados {
			continue
		}
		filas = append(filas, sqlc.DiferenciasDePedidosRow{
			ID:           p.id,
			CustomerName: p.nombre,
			Address:      "una calle",
			Archivado:    p.archivado,
			BranchID:     pgtype.UUID{Bytes: [16]byte(p.sucursal), Valid: true},
			UpdatedAt:    pgtype.Timestamptz{Time: p.marca, Valid: true},
			CambiadoAt:   pgtype.Timestamptz{Time: cambiado, Valid: true},
		})
	}
	sort.Slice(filas, func(i, j int) bool {
		if filas[i].CambiadoAt.Time.Equal(filas[j].CambiadoAt.Time) {
			return filas[i].ID.String() < filas[j].ID.String()
		}
		return filas[i].CambiadoAt.Time.Before(filas[j].CambiadoAt.Time)
	})
	if int(arg.Tope) < len(filas) {
		filas = filas[:arg.Tope]
	}
	return filas, nil
}

func (q *espejoFalso) ListarRenglonesDePedidos(_ context.Context, arg sqlc.ListarRenglonesDePedidosParams) ([]sqlc.ListarRenglonesDePedidosRow, error) {
	pedidos := map[uuid.UUID]bool{}
	for _, id := range arg.PedidoIds {
		pedidos[id] = true
	}
	var salida []sqlc.ListarRenglonesDePedidosRow
	for _, p := range q.sync {
		if !pedidos[p.id] {
			continue
		}
		// El alcance va también aquí, como en el SQL: `order_items` no tiene sucursal y
		// sin el cruce bastaría con acertar un uuid para leer la mercancía de otra.
		if arg.Sucursal.Valid && [16]byte(p.sucursal) != arg.Sucursal.Bytes {
			continue
		}
		for _, r := range p.renglones {
			salida = append(salida, sqlc.ListarRenglonesDePedidosRow{
				ID: uuid.New(), OrderID: p.id, Linea: r.linea,
				Description: r.desc, Quantity: 1,
				UpdatedAt: pgtype.Timestamptz{Time: r.marca, Valid: true},
			})
		}
	}
	return salida, nil
}

func (q *espejoFalso) PedidosQueSalieronDelAlcance(_ context.Context, arg sqlc.PedidosQueSalieronDelAlcanceParams) ([]sqlc.PedidosQueSalieronDelAlcanceRow, error) {
	var filas []sqlc.PedidosQueSalieronDelAlcanceRow
	for _, f := range q.salidas {
		if arg.Desde.Valid && !f.salioAt.After(arg.Desde.Time) {
			continue
		}
		if arg.Hasta.Valid && f.salioAt.After(arg.Hasta.Time) {
			continue
		}
		if arg.Sucursal.Valid && [16]byte(f.sucursal) != arg.Sucursal.Bytes {
			continue
		}
		if arg.BranchID.Valid && [16]byte(f.sucursal) != arg.BranchID.Bytes {
			continue
		}
		// Sin sucursal ninguna —el Super Admin, que ve las ocho— sólo cuentan los
		// borrados: mudarse de sucursal no lo saca de SU vista.
		if !arg.Sucursal.Valid && !arg.BranchID.Valid && f.motivo != sqlc.SalidaDePedidoBorrado {
			continue
		}
		filas = append(filas, sqlc.PedidosQueSalieronDelAlcanceRow{
			OrderID:  f.pedido,
			BranchID: pgtype.UUID{Bytes: [16]byte(f.sucursal), Valid: true},
			Motivo:   f.motivo,
			SalioAt:  pgtype.Timestamptz{Time: f.salioAt, Valid: true},
		})
	}
	sort.Slice(filas, func(i, j int) bool { return filas[i].SalioAt.Time.Before(filas[j].SalioAt.Time) })
	if int(arg.Tope) < len(filas) {
		filas = filas[:arg.Tope]
	}
	return filas, nil
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

// ListarClientes REPITE EL `LIMIT … OFFSET …` del SQL. Es la parte que importa: con un
// doble que devolviera siempre la lista entera, el fallo de los 2.000 clientes no se ve.
func (q *espejoFalso) ListarClientes(_ context.Context, arg sqlc.ListarClientesParams) ([]sqlc.ListarClientesRow, error) {
	desde := int(arg.Desplazamiento)
	if desde >= len(q.padron) {
		return nil, nil
	}
	hasta := desde + int(arg.Limite)
	if hasta > len(q.padron) {
		hasta = len(q.padron)
	}
	return q.padron[desde:hasta], nil
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
// `warehouses` sigue sin poder servirse: los almacenes viven en Accesos, que no da marca de
// cambio ni dice qué borró. Mandarlo como `{"puestos":[],"quitados":[]}` le diría al
// aparato «no ha cambiado ningún almacén», que es lo contrario de la verdad, y desde el
// almacén se mide lo que se le cobra al cliente por el domicilio.
//
// `orders` YA NO ESTÁ en esa lista: se sirve de verdad. Que no vuelva a entrar.
func TestLaBajadaNombraLoQueNoSabeServirEnVezDeMandarloVacio(t *testing.T) {
	h := montarTab(t, nuevoEspejo())
	w := pedirTab(t, h, http.MethodGet, "/api/sync/cambios", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)

	cambios := m["cambios"].(map[string]any)
	if _, hay := cambios["warehouses"]; hay {
		t.Fatal("«warehouses» sale como conjunto vacío: eso le dice al aparato que no cambió nada")
	}
	if _, hay := cambios["orders"]; !hay {
		t.Fatalf("«orders» tiene que venir servido: %s", w.Body.String())
	}

	faltan := map[string]bool{}
	for _, f := range m["faltan"].([]any) {
		faltan[f.(string)] = true
	}
	if !faltan["warehouses"] {
		t.Fatalf("«warehouses» no está nombrado en «faltan»: %s", w.Body.String())
	}
	if faltan["orders"] {
		t.Fatal("«orders» sigue declarado como que falta, y ya se sirve")
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

// ---------------------------------------------------------------------------
// LOS PEDIDOS DE LA BAJADA — lo que hace posible el día sin conexión
// ---------------------------------------------------------------------------

var (
	pedAntiguo   = uuid.MustParse("5d000000-0000-0000-0000-000000000001")
	pedTocado    = uuid.MustParse("5d000000-0000-0000-0000-000000000002")
	pedArchivado = uuid.MustParse("5d000000-0000-0000-0000-000000000003")
	pedRenglon   = uuid.MustParse("5d000000-0000-0000-0000-000000000004")
	pedMudado    = uuid.MustParse("5d000000-0000-0000-0000-000000000005")
	pedDeHolguin = uuid.MustParse("5d000000-0000-0000-0000-000000000006")
)

// conPedidos deja el espejo con cuatro pedidos de Santiago repartidos a los dos lados de
// una marca, más uno de Holguín para que se vea que el alcance sigue puesto.
//
// Devuelve la marca: lo de antes de ella no tiene que salir, lo de después sí.
func conPedidos(q *espejoFalso) time.Time {
	ahora := time.Now().UTC()
	marca := ahora.Add(-12 * time.Hour)
	antes := ahora.Add(-24 * time.Hour)
	despues := ahora.Add(-1 * time.Hour)

	q.sync = []pedidoSync{
		// Tocado ANTES de la marca: no cambió nada de él desde que el aparato bajó.
		{id: pedAntiguo, sucursal: sucStg, nombre: "Ana la de siempre", marca: antes,
			renglones: []renglonSync{{linea: 1, desc: "malta", marca: antes}}},
		// Tocado DESPUÉS: es lo que el aparato tiene que llevarse.
		{id: pedTocado, sucursal: sucStg, nombre: "Beto", marca: despues,
			renglones: []renglonSync{{linea: 1, desc: "cerveza", marca: despues}}},
		// Archivado en PEDIDO después de la marca: el aparato tiene que BORRARLO.
		{id: pedArchivado, sucursal: sucStg, nombre: "Carlos", marca: despues, archivado: true},
		// EL PEDIDO NO SE TOCÓ; le cambió un RENGLÓN. Tiene que salir igual, o el aparato
		// se queda con la lista de mercancía vieja.
		{id: pedRenglon, sucursal: sucStg, nombre: "Delia", marca: antes,
			renglones: []renglonSync{
				{linea: 1, desc: "refresco", marca: antes},
				{linea: 2, desc: "ron - LÍNEA NUEVA", marca: despues},
			}},
		{id: pedDeHolguin, sucursal: sucHol, nombre: "De Holguín", marca: despues},
	}
	// Uno que se MUDÓ de Santiago a Holguín, y uno BORRADO. Los dos tienen que
	// desaparecer del aparato de Santiago aunque su fila no diga nada (o ya no exista).
	q.salidas = []salidaSync{
		{pedido: pedMudado, sucursal: sucStg, motivo: sqlc.SalidaDePedidoMovido, salioAt: despues},
	}
	return marca
}

// conjuntoDe saca `cambios.<nombre>` de la respuesta.
func conjuntoDe(t *testing.T, m map[string]any, nombre string) (map[string]bool, map[string]bool, []any) {
	t.Helper()
	c, hay := m["cambios"].(map[string]any)[nombre]
	if !hay {
		t.Fatalf("no vino la colección %q", nombre)
	}
	conj := c.(map[string]any)
	puestos := map[string]bool{}
	crudos := conj["puestos"].([]any)
	for _, p := range crudos {
		puestos[p.(map[string]any)["id"].(string)] = true
	}
	quitados := map[string]bool{}
	for _, q := range conj["quitados"].([]any) {
		quitados[q.(string)] = true
	}
	return puestos, quitados, crudos
}

// LA PRUEBA QUE CIERRA EL AGUJERO: lo tocado después de la marca sale, lo anterior no, y
// lo archivado sale en `quitados` — no en `puestos` con una bandera que alguien tiene que
// acordarse de mirar.
func TestLaBajadaDeDiferenciasTraeLoTocadoYQuitaLoArchivado(t *testing.T) {
	q := nuevoEspejo()
	marca := conPedidos(q)
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodGet,
		"/api/sync/cambios?desde="+marca.Format(time.RFC3339), tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	puestos, quitados, _ := conjuntoDe(t, leerTab(t, w), "orders")

	if !puestos[pedTocado.String()] {
		t.Fatal("un pedido tocado después de la marca no salió en las diferencias")
	}
	if puestos[pedAntiguo.String()] || quitados[pedAntiguo.String()] {
		t.Fatal("un pedido anterior a la marca salió: la bajada por diferencias no diferencia nada")
	}
	if puestos[pedArchivado.String()] {
		t.Fatal("un pedido archivado salió en «puestos»: seguiría en el tablero del aparato")
	}
	if !quitados[pedArchivado.String()] {
		t.Fatal("un pedido archivado no salió en «quitados»: la lista local sólo crece")
	}
	// Y el alcance sigue puesto: lo de Holguín no se baja a un aparato de Santiago.
	if puestos[pedDeHolguin.String()] || quitados[pedDeHolguin.String()] {
		t.Fatal("se coló un pedido de otra sucursal")
	}
}

// SI CAMBIA UN RENGLÓN, EL PEDIDO SALE. El pedido no se tocó —su `updated_at` es de ayer—
// pero una de sus líneas sí, y lo que sube al camión son las líneas. Y tiene que venir con
// los renglones dentro: mandar el aviso sin la mercancía nueva no arregla nada.
func TestUnRenglonTocadoSacaASuPedidoConSuMercancia(t *testing.T) {
	q := nuevoEspejo()
	marca := conPedidos(q)
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodGet,
		"/api/sync/cambios?desde="+marca.Format(time.RFC3339), tokenTab(t, sucStg.String()), "")
	puestos, _, crudos := conjuntoDe(t, leerTab(t, w), "orders")

	if !puestos[pedRenglon.String()] {
		t.Fatal("cambió un renglón y el pedido no salió: el aparato se queda con la lista de mercancía vieja")
	}
	for _, p := range crudos {
		fila := p.(map[string]any)
		if fila["id"] != pedRenglon.String() {
			continue
		}
		items := fila["items"].([]any)
		if len(items) != 2 {
			t.Fatalf("el pedido salió sin sus renglones: %v", items)
		}
		// La marca que se devuelve es la del RENGLÓN, que es la más nueva. Con la del
		// pedido, el aparato volvería a pedirlo en cada bajada para siempre.
		devuelta, err := time.Parse(time.RFC3339, fila["updatedAt"].(string))
		if err != nil {
			t.Fatalf("«updatedAt» ilegible: %v", fila["updatedAt"])
		}
		if !devuelta.After(marca) {
			t.Fatalf("la marca devuelta es la del pedido y no la del renglón: %v", devuelta)
		}
		return
	}
	t.Fatal("no se encontró el pedido en «puestos»")
}

// `quitados` NO ES SÓLO LO BORRADO. Un pedido que se muda de sucursal deja de salir en las
// consultas de la vieja, así que sin las lápidas se quedaría en ese aparato para siempre —
// y seguiría apareciendo en un tablero que ya no es el suyo.
func TestUnPedidoQueSaleDelAlcanceDeLaSucursalSeQuita(t *testing.T) {
	q := nuevoEspejo()
	marca := conPedidos(q)
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodGet,
		"/api/sync/cambios?desde="+marca.Format(time.RFC3339), tokenTab(t, sucStg.String()), "")
	_, quitados, _ := conjuntoDe(t, leerTab(t, w), "orders")
	if !quitados[pedMudado.String()] {
		t.Fatalf("el pedido que se mudó de sucursal no salió en «quitados»: %s", w.Body.String())
	}
}

// LA CARGA INICIAL NO LLEVA ARCHIVADOS NI QUITADOS. El aparato empieza vacío: no hay nada
// que borrarle, y bajarle el histórico archivado de ocho meses le llena el tope con lo que
// no va a repartir y deja fuera lo del día.
func TestLaCargaInicialNoTraeArchivadosNiQuitados(t *testing.T) {
	q := nuevoEspejo()
	conPedidos(q)
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodGet, "/api/sync/cambios", tokenTab(t, sucStg.String()), "")
	puestos, quitados, _ := conjuntoDe(t, leerTab(t, w), "orders")

	if puestos[pedArchivado.String()] {
		t.Fatal("la carga inicial trajo un pedido archivado")
	}
	if len(quitados) != 0 {
		t.Fatalf("la carga inicial trae «quitados» y el aparato no tiene nada: %v", quitados)
	}
	if !puestos[pedAntiguo.String()] || !puestos[pedTocado.String()] {
		t.Fatalf("la carga inicial tiene que traerlo todo: %s", w.Body.String())
	}
}

// EL TOPE NO PUEDE PERDER PEDIDOS.
//
// Con `truncado`, la marca que se devuelve deja de ser el reloj y pasa a ser la de la
// última fila servida. Si se devolviera el reloj, el aparato pediría la próxima vez «a
// partir de ahora» y lo que no cupo no lo pediría nadie nunca más: sería trabajo perdido
// sin un solo error.
func TestElTopeTruncaSinPerderNiUnPedido(t *testing.T) {
	q := nuevoEspejo()
	marca := conPedidos(q)
	// Marcas distintas y separadas, para que el corte pueda caer entre dos.
	ahora := time.Now().UTC()
	q.salidas = nil
	q.sync = []pedidoSync{
		{id: pedAntiguo, sucursal: sucStg, nombre: "primero", marca: ahora.Add(-4 * time.Hour)},
		{id: pedTocado, sucursal: sucStg, nombre: "segundo", marca: ahora.Add(-3 * time.Hour)},
		{id: pedRenglon, sucursal: sucStg, nombre: "tercero", marca: ahora.Add(-2 * time.Hour)},
	}
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodGet,
		"/api/sync/cambios?tope=2&desde="+marca.Format(time.RFC3339), tokenTab(t, sucStg.String()), "")
	m := leerTab(t, w)
	if truncado, _ := m["truncado"].(bool); !truncado {
		t.Fatalf("no cupo todo y no se dijo: %s", w.Body.String())
	}
	puestos, _, _ := conjuntoDe(t, m, "orders")
	if len(puestos) != 2 {
		t.Fatalf("la tanda no respetó el tope: %v", puestos)
	}
	hasta := m["hasta"].(string)
	if time.Since(mustHora(t, hasta)) < time.Hour {
		t.Fatalf("con «truncado» la marca tiene que ser la de la última fila servida, no el reloj: %s", hasta)
	}

	// Segunda vuelta con la marca devuelta: tiene que traer lo que faltaba, sin repetir.
	w = pedirTab(t, h, http.MethodGet,
		"/api/sync/cambios?tope=2&desde="+hasta, tokenTab(t, sucStg.String()), "")
	m = leerTab(t, w)
	puestos2, _, _ := conjuntoDe(t, m, "orders")
	if !puestos2[pedRenglon.String()] {
		t.Fatalf("el pedido que no cupo se perdió para siempre: %s", w.Body.String())
	}
	if puestos2[pedAntiguo.String()] || puestos2[pedTocado.String()] {
		t.Fatalf("la segunda tanda repitió lo ya servido: %s", w.Body.String())
	}
	if truncado, _ := m["truncado"].(bool); truncado {
		t.Fatal("ya cupo todo y sigue diciendo «truncado»")
	}
}

func mustHora(t *testing.T, s string) time.Time {
	t.Helper()
	v, err := time.Parse(time.RFC3339, s)
	if err != nil {
		t.Fatalf("hora ilegible %q: %v", s, err)
	}
	return v
}

// EL PADRÓN ENTERO, TANDA A TANDA — el fallo de los 2.000 clientes.
//
// El 15/09/2026 se leyó la base del aparato después de la bajada contra producción:
// `clientes = 2000` redondos, y con esa cuenta (Super Admin) son 8.034. El catálogo y el
// padrón se servían siempre con `LIMIT tope OFFSET 0` ordenados por nombre, y se marcaba
// `truncado` al llegar al tope — pero no había por dónde seguir: la tanda siguiente pedía
// exactamente lo mismo. La bajada se dio por buena con un cuarto de los clientes y **nadie
// se enteró**, que es el patrón que más daño hace en este proyecto.
//
// Esta prueba falla si el encadenado deja de avanzar: si `continuar` desaparece, si no se
// lee, o si el desplazamiento vuelve a cero.
func TestElPadronSeSirveEnteroEnTandas(t *testing.T) {
	q := nuevoEspejo()
	stg := "STG"
	const total = 7
	for i := 0; i < total; i++ {
		q.padron = append(q.padron, sqlc.ListarClientesRow{
			ID:             uuid.New(),
			Name:           fmt.Sprintf("Cliente %02d", i),
			Lat:            20.0,
			Lng:            -75.0,
			SucursalCodigo: &stg,
		})
	}
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	vistos := map[string]bool{}
	continuar := ""
	tandas := 0
	for {
		tandas++
		if tandas > 10 {
			t.Fatal("la cadena de tandas no termina")
		}
		url := "/api/sync/cambios?tope=3"
		if continuar != "" {
			url += "&continuar=" + continuar
		}
		w := pedirTab(t, h, http.MethodGet, url, jwt, "")
		m := leerTab(t, w)

		puestos, _, _ := conjuntoDe(t, m, "customers")
		for id := range puestos {
			if vistos[id] {
				t.Fatalf("tanda %d: repitió un cliente ya servido (%s)", tandas, id)
			}
			vistos[id] = true
		}

		truncado, _ := m["truncado"].(bool)
		if !truncado {
			break
		}
		siguiente, _ := m["continuar"].(string)
		if siguiente == "" {
			t.Fatalf("tanda %d dijo «truncado» y no dijo por dónde seguir: %s",
				tandas, w.Body.String())
		}
		if siguiente == continuar {
			t.Fatalf("tanda %d: el cursor no avanza, la siguiente traería lo mismo", tandas)
		}
		continuar = siguiente
	}

	if len(vistos) != total {
		t.Fatalf("se sirvieron %d clientes de %d: %v", len(vistos), total, vistos)
	}
	if tandas != 3 {
		t.Fatalf("7 clientes de 3 en 3 son 3 tandas, no %d", tandas)
	}
}

// El cursor lleva el `desde` de la PRIMERA tanda, y sin eso la segunda no emite nada.
//
// El catálogo y el padrón se filtran en Go contra el `desde` de la petición, y en una
// bajada por diferencias ese `desde` avanza entre tandas. Si el cursor no conservara el
// original, la tanda dos pagina hasta el final del padrón sin mandar una sola fila: el
// aparato se queda con la primera tanda y con la sensación de haber terminado.
func TestElCursorConservaElDesdeDeLaCadena(t *testing.T) {
	q := nuevoEspejo()
	stg := "STG"
	ayer := time.Now().UTC().Add(-24 * time.Hour)
	for i := 0; i < 4; i++ {
		q.padron = append(q.padron, sqlc.ListarClientesRow{
			ID:             uuid.New(),
			Name:           fmt.Sprintf("Cliente %02d", i),
			Lat:            20.0,
			Lng:            -75.0,
			SucursalCodigo: &stg,
			// Tocados AYER: con el `desde` de la primera tanda entran; con uno posterior,
			// no.
			SyncedAt: pgtype.Timestamptz{Time: ayer, Valid: true},
		})
	}
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	desde := ayer.Add(-time.Hour).Format(time.RFC3339)
	w := pedirTab(t, h, http.MethodGet, "/api/sync/cambios?tope=2&desde="+desde, jwt, "")
	m := leerTab(t, w)
	primera, _, _ := conjuntoDe(t, m, "customers")
	if len(primera) != 2 {
		t.Fatalf("la primera tanda tenía que traer 2: %s", w.Body.String())
	}
	continuar, _ := m["continuar"].(string)
	if continuar == "" {
		t.Fatalf("sin cursor no hay segunda tanda: %s", w.Body.String())
	}

	// La segunda tanda va con el `hasta` que devolvió la primera —que es lo que hace el
	// aparato— MÁS el cursor. Los clientes son de ayer, así que contra ese `desde` no
	// pasarían: el cursor es lo único que los salva.
	hasta := m["hasta"].(string)
	w = pedirTab(t, h, http.MethodGet,
		"/api/sync/cambios?tope=2&desde="+hasta+"&continuar="+continuar, jwt, "")
	m = leerTab(t, w)
	segunda, _, _ := conjuntoDe(t, m, "customers")
	if len(segunda) != 2 {
		t.Fatalf("los otros dos clientes se perdieron para siempre: %s", w.Body.String())
	}
	for id := range segunda {
		if primera[id] {
			t.Fatalf("la segunda tanda repitió lo ya servido: %s", id)
		}
	}
}
