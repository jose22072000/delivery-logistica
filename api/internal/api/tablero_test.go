package api

// Las pruebas del tablero, POR HTTP y con un doble de la base.
//
// Van en el paquete `api` y no en `api_test` porque montan `rutasTablero`, que no se
// exporta: quien las llama de verdad es `Rutas()` en servidor.go, y aquí hace falta poder
// montarlas solas sin tocar ese fichero.
//
// El doble NO es un «devuelve lo que te pidan»: repite las reglas del SQL de verdad —la
// única de (columna, posición), el `route_id IS NULL`, la misma sucursal para el pedido y
// la columna, el RESTRICT de la columna con tarjetas dentro—. Un doble que contesta a todo
// es un doble que aprueba cualquier cosa, y justo lo que hay que comprobar aquí es que el
// manejador respeta lo que la base le impone.

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

const secretoTab = "un-secreto-de-pruebas-de-al-menos-32-caracteres"

var (
	sucStg = uuid.MustParse("11111111-1111-1111-1111-111111111111")
	sucHol = uuid.MustParse("22222222-2222-2222-2222-222222222222")

	colCentro = uuid.MustParse("c0000000-0000-0000-0000-00000000000a")
	colVista  = uuid.MustParse("c0000000-0000-0000-0000-00000000000b")
	colVacia  = uuid.MustParse("c0000000-0000-0000-0000-00000000000c")

	ped1    = uuid.MustParse("0d000000-0000-0000-0000-000000000001")
	ped2    = uuid.MustParse("0d000000-0000-0000-0000-000000000002")
	ped3    = uuid.MustParse("0d000000-0000-0000-0000-000000000003")
	pedRuta = uuid.MustParse("0d000000-0000-0000-0000-000000000009")
	pedHol  = uuid.MustParse("0d000000-0000-0000-0000-00000000000f")

	rutaNueva = uuid.MustParse("4a000000-0000-0000-0000-000000000001")
)

// --------------------------------------------------------------------------- el doble

type pedidoFalso struct {
	id       uuid.UUID
	sucursal uuid.UUID
	nombre   string
	peso     float64
	ruta     *uuid.UUID
	lat, lng float64
	factura  *sqlc.FacturaEstado
}

type colocacion struct {
	columna  uuid.UUID
	posicion int32
}

type tableroFalso struct {
	sqlc.Querier

	origenes    []sqlc.ListarOrigenesRow
	columnas    map[uuid.UUID]sqlc.BoardColumn
	pedidos     map[uuid.UUID]pedidoFalso
	colocadas   map[uuid.UUID]colocacion
	creadas     []string
	sinOrigen   bool
	borrarFalla bool
	capacidad   float64

	// Lo que se vio pasar al armar la ruta: es lo que se comprueba.
	rutaCreada  *sqlc.CrearRutaParams
	enganchados []uuid.UUID
	totales     *sqlc.FijarTotalesDeRutaParams
}

func nuevoTablero() *tableroFalso {
	igual := sqlc.FacturaEstadoIgual
	t := &tableroFalso{
		columnas: map[uuid.UUID]sqlc.BoardColumn{
			colCentro: {ID: colCentro, BranchID: sucStg, Nombre: "Centro", Posicion: 1},
			colVista:  {ID: colVista, BranchID: sucStg, Nombre: "Vista Alegre", Posicion: 2},
			colVacia:  {ID: colVacia, BranchID: sucStg, Nombre: "Carretera", Posicion: 3},
		},
		pedidos: map[uuid.UUID]pedidoFalso{
			ped1:    {id: ped1, sucursal: sucStg, nombre: "Ana", peso: 30, lat: 20.02, lng: -75.82, factura: &igual},
			ped2:    {id: ped2, sucursal: sucStg, nombre: "Beto", peso: 40, lat: 20.05, lng: -75.80, factura: &igual},
			ped3:    {id: ped3, sucursal: sucStg, nombre: "Ana", peso: 10, lat: 20.03, lng: -75.83, factura: &igual},
			pedRuta: {id: pedRuta, sucursal: sucStg, nombre: "Ya salió", peso: 5, lat: 20.1, lng: -75.9, ruta: &colCentro, factura: &igual},
			pedHol:  {id: pedHol, sucursal: sucHol, nombre: "De Holguín", peso: 7, lat: 20.9, lng: -76.2, factura: &igual},
		},
		colocadas: map[uuid.UUID]colocacion{},
		origenes: []sqlc.ListarOrigenesRow{{
			ID: uuid.New(), Name: "Almacén principal", Lat: 20.0247, Lng: -75.8219,
			BranchID:  pgtype.UUID{Bytes: [16]byte(sucStg), Valid: true},
			CreatedAt: pgtype.Timestamptz{Time: time.Now().Add(-48 * time.Hour), Valid: true},
		}},
	}
	return t
}

// tresPuestasDeja Centro con tres tarjetas en las posiciones 1, 2 y 3.
func (q *tableroFalso) tresPuestas() {
	q.colocadas[ped1] = colocacion{colCentro, 1}
	q.colocadas[ped2] = colocacion{colCentro, 2}
	q.colocadas[ped3] = colocacion{colCentro, 3}
}

func (q *tableroFalso) ResolverSucursal(_ context.Context, id uuid.UUID) (sqlc.ResolverSucursalRow, error) {
	switch id {
	case sucStg:
		c := "STG"
		return sqlc.ResolverSucursalRow{ID: sucStg, Name: "Santiago", ExternalID: &c}, nil
	case sucHol:
		c := "HOL"
		return sqlc.ResolverSucursalRow{ID: sucHol, Name: "Holguín", ExternalID: &c}, nil
	}
	return sqlc.ResolverSucursalRow{}, pgx.ErrNoRows
}

func (q *tableroFalso) ObtenerSucursal(_ context.Context, arg sqlc.ObtenerSucursalParams) (sqlc.Branch, error) {
	if arg.Sucursal.Valid && uuid.UUID(arg.Sucursal.Bytes) != arg.ID {
		return sqlc.Branch{}, pgx.ErrNoRows
	}
	switch arg.ID {
	case sucStg:
		return sqlc.Branch{ID: sucStg, Name: "Santiago"}, nil
	case sucHol:
		return sqlc.Branch{ID: sucHol, Name: "Holguín"}, nil
	}
	return sqlc.Branch{}, pgx.ErrNoRows
}

func (q *tableroFalso) ListarOrigenes(_ context.Context, sucursal pgtype.UUID) ([]sqlc.ListarOrigenesRow, error) {
	if q.sinOrigen {
		return nil, nil
	}
	var salida []sqlc.ListarOrigenesRow
	for _, o := range q.origenes {
		if sucursal.Valid && o.BranchID.Bytes != sucursal.Bytes {
			continue
		}
		salida = append(salida, o)
	}
	return salida, nil
}

func (q *tableroFalso) ListarColumnasDelTablero(_ context.Context, arg sqlc.ListarColumnasDelTableroParams) ([]sqlc.ListarColumnasDelTableroRow, error) {
	var salida []sqlc.ListarColumnasDelTableroRow
	for _, c := range q.columnas {
		if c.BranchID != arg.BranchID {
			continue
		}
		if arg.Sucursal.Valid && c.BranchID != uuid.UUID(arg.Sucursal.Bytes) {
			continue
		}
		fila := sqlc.ListarColumnasDelTableroRow{
			ID: c.ID, BranchID: c.BranchID, Nombre: c.Nombre, Posicion: c.Posicion,
		}
		for ped, col := range q.colocadas {
			if col.columna == c.ID {
				fila.Pedidos++
				fila.PesoKg += q.pedidos[ped].peso
			}
		}
		salida = append(salida, fila)
	}
	sort.Slice(salida, func(i, j int) bool { return salida[i].Posicion < salida[j].Posicion })
	return salida, nil
}

func (q *tableroFalso) ObtenerColumna(_ context.Context, arg sqlc.ObtenerColumnaParams) (sqlc.BoardColumn, error) {
	c, ok := q.columnas[arg.ID]
	if !ok {
		return sqlc.BoardColumn{}, pgx.ErrNoRows
	}
	if arg.Sucursal.Valid && c.BranchID != uuid.UUID(arg.Sucursal.Bytes) {
		return sqlc.BoardColumn{}, pgx.ErrNoRows
	}
	return c, nil
}

func (q *tableroFalso) CrearColumna(_ context.Context, arg sqlc.CrearColumnaParams) (sqlc.BoardColumn, error) {
	for _, c := range q.columnas {
		// El índice único es `(branch_id, lower(nombre))`: «centro» y «Centro» son la
		// misma zona para quien las escribe.
		if c.BranchID == arg.BranchID && strings.EqualFold(c.Nombre, arg.Nombre) {
			return sqlc.BoardColumn{}, &pgconn.PgError{Code: "23505"}
		}
	}
	pos := int32(1)
	for _, c := range q.columnas {
		if c.BranchID == arg.BranchID && c.Posicion >= pos {
			pos = c.Posicion + 1
		}
	}
	nueva := sqlc.BoardColumn{ID: uuid.New(), BranchID: arg.BranchID, Nombre: arg.Nombre, Posicion: pos}
	q.columnas[nueva.ID] = nueva
	q.creadas = append(q.creadas, arg.Nombre)
	return nueva, nil
}

// ReordenarColumnas repite el `array_position`: la posición de cada una es su sitio en la
// lista, y las que no vengan no se tocan.
func (q *tableroFalso) ReordenarColumnas(_ context.Context, arg sqlc.ReordenarColumnasParams) (int64, error) {
	var n int64
	for i, id := range arg.Ids {
		c, ok := q.columnas[id]
		if !ok || c.BranchID != arg.BranchID {
			continue
		}
		if arg.Sucursal.Valid && c.BranchID != uuid.UUID(arg.Sucursal.Bytes) {
			continue
		}
		c.Posicion = int32(i + 1)
		q.columnas[id] = c
		n++
	}
	return n, nil
}

func (q *tableroFalso) ContarPedidosEnColumna(_ context.Context, arg sqlc.ContarPedidosEnColumnaParams) (int64, error) {
	var n int64
	for _, c := range q.colocadas {
		if c.columna == arg.ColumnaID {
			n++
		}
	}
	return n, nil
}

func (q *tableroFalso) VaciarColumna(_ context.Context, arg sqlc.VaciarColumnaParams) (int64, error) {
	var n int64
	for ped, c := range q.colocadas {
		if c.columna == arg.ColumnaID {
			delete(q.colocadas, ped)
			n++
		}
	}
	return n, nil
}

func (q *tableroFalso) MoverPedidosDeColumna(_ context.Context, arg sqlc.MoverPedidosDeColumnaParams) (int64, error) {
	origen, ok1 := q.columnas[arg.ColumnaOrigen]
	destino, ok2 := q.columnas[arg.ColumnaDestino]
	if !ok1 || !ok2 || origen.BranchID != destino.BranchID {
		return 0, nil
	}
	tope := int32(0)
	for _, c := range q.colocadas {
		if c.columna == destino.ID && c.posicion > tope {
			tope = c.posicion
		}
	}
	var n int64
	for ped, c := range q.colocadas {
		if c.columna != origen.ID {
			continue
		}
		q.colocadas[ped] = colocacion{destino.ID, tope + c.posicion}
		n++
	}
	return n, nil
}

// BorrarColumna repite el `ON DELETE RESTRICT`: con tarjetas dentro, la base se niega con
// un 23503. Es la mitad de la prueba que importa — sin esto, el 409 se podría estar
// dando sólo por el contador y el 500 seguiría ahí esperando a una carrera.
func (q *tableroFalso) BorrarColumna(_ context.Context, arg sqlc.BorrarColumnaParams) (int64, error) {
	c, ok := q.columnas[arg.ID]
	if !ok {
		return 0, nil
	}
	if arg.Sucursal.Valid && c.BranchID != uuid.UUID(arg.Sucursal.Bytes) {
		return 0, nil
	}
	if q.borrarFalla {
		return 0, &pgconn.PgError{Code: "23503", ConstraintName: "board_placements_column_id_fkey"}
	}
	for _, col := range q.colocadas {
		if col.columna == arg.ID {
			return 0, &pgconn.PgError{Code: "23503", ConstraintName: "board_placements_column_id_fkey"}
		}
	}
	delete(q.columnas, arg.ID)
	return 1, nil
}

func (q *tableroFalso) ColocarPedido(_ context.Context, arg sqlc.ColocarPedidoParams) (sqlc.BoardPlacement, error) {
	p, ok := q.pedidos[arg.PedidoID]
	c, ok2 := q.columnas[arg.ColumnaID]
	// Las cuatro condiciones del `WHERE` del INSERT de verdad.
	if !ok || !ok2 || p.sucursal != c.BranchID || p.ruta != nil {
		return sqlc.BoardPlacement{}, pgx.ErrNoRows
	}
	if arg.Sucursal.Valid && c.BranchID != uuid.UUID(arg.Sucursal.Bytes) {
		return sqlc.BoardPlacement{}, pgx.ErrNoRows
	}
	// La única de (columna, posición): si ya hay OTRA tarjeta en ese sitio, la base
	// revienta. Es lo que prueba que el manejador abre hueco antes de soltar.
	for ped, col := range q.colocadas {
		if ped != arg.PedidoID && col.columna == arg.ColumnaID && col.posicion == arg.Posicion {
			return sqlc.BoardPlacement{}, &pgconn.PgError{Code: "23505", ConstraintName: "board_placements_posicion_unica"}
		}
	}
	q.colocadas[arg.PedidoID] = colocacion{arg.ColumnaID, arg.Posicion}
	return sqlc.BoardPlacement{
		OrderID: arg.PedidoID, ColumnID: arg.ColumnaID, Posicion: arg.Posicion,
		ColocadoPor: arg.ColocadoPor,
		ColocadoAt:  pgtype.Timestamptz{Time: time.Now(), Valid: true},
	}, nil
}

func (q *tableroFalso) AbrirHuecoEnColumna(_ context.Context, arg sqlc.AbrirHuecoEnColumnaParams) (int64, error) {
	var n int64
	for ped, c := range q.colocadas {
		if c.columna == arg.ColumnaID && c.posicion >= arg.DesdePosicion {
			q.colocadas[ped] = colocacion{c.columna, c.posicion + 1}
			n++
		}
	}
	return n, nil
}

func (q *tableroFalso) CerrarHuecoEnColumna(_ context.Context, arg sqlc.CerrarHuecoEnColumnaParams) (int64, error) {
	var n int64
	for ped, c := range q.colocadas {
		if c.columna == arg.ColumnaID && c.posicion > arg.DesdePosicion {
			q.colocadas[ped] = colocacion{c.columna, c.posicion - 1}
			n++
		}
	}
	return n, nil
}

func (q *tableroFalso) QuitarPedidoDelTablero(_ context.Context, arg sqlc.QuitarPedidoDelTableroParams) (sqlc.QuitarPedidoDelTableroRow, error) {
	c, ok := q.colocadas[arg.PedidoID]
	if !ok {
		return sqlc.QuitarPedidoDelTableroRow{}, pgx.ErrNoRows
	}
	delete(q.colocadas, arg.PedidoID)
	return sqlc.QuitarPedidoDelTableroRow{OrderID: arg.PedidoID, ColumnID: c.columna, Posicion: c.posicion}, nil
}

func (q *tableroFalso) ObtenerPedido(_ context.Context, arg sqlc.ObtenerPedidoParams) (sqlc.ObtenerPedidoRow, error) {
	p, ok := q.pedidos[arg.ID]
	if !ok {
		return sqlc.ObtenerPedidoRow{}, pgx.ErrNoRows
	}
	if arg.Sucursal.Valid && p.sucursal != uuid.UUID(arg.Sucursal.Bytes) {
		return sqlc.ObtenerPedidoRow{}, pgx.ErrNoRows
	}
	fila := sqlc.ObtenerPedidoRow{ID: p.id, CustomerName: p.nombre, Weight: p.peso}
	if p.ruta != nil {
		fila.RouteID = pgtype.UUID{Bytes: [16]byte(*p.ruta), Valid: true}
	}
	return fila, nil
}

func (q *tableroFalso) ListarPedidosColocados(_ context.Context, arg sqlc.ListarPedidosColocadosParams) ([]sqlc.ListarPedidosColocadosRow, error) {
	var salida []sqlc.ListarPedidosColocadosRow
	for ped, c := range q.colocadas {
		col := q.columnas[c.columna]
		if col.BranchID != arg.BranchID {
			continue
		}
		p := q.pedidos[ped]
		salida = append(salida, sqlc.ListarPedidosColocadosRow{
			OrderID: ped, ColumnID: c.columna, Posicion: c.posicion,
			ColumnaNombre: col.Nombre, CustomerName: p.nombre, Weight: p.peso,
			KmAlAlmacen: kmDelTablero(arg.OrigenLat, arg.OrigenLng, p.lat, p.lng),
		})
	}
	sort.Slice(salida, func(i, j int) bool { return salida[i].Posicion < salida[j].Posicion })
	return salida, nil
}

func (q *tableroFalso) AvisosDelTablero(_ context.Context, arg sqlc.AvisosDelTableroParams) (sqlc.AvisosDelTableroRow, error) {
	var fila sqlc.AvisosDelTableroRow
	for ped, c := range q.colocadas {
		if q.columnas[c.columna].BranchID != arg.BranchID {
			continue
		}
		fila.Colocados++
		if q.pedidos[ped].ruta != nil {
			fila.EnOtraRuta++
		}
	}
	return fila, nil
}

func (q *tableroFalso) ListarPedidosSinColocar(_ context.Context, arg sqlc.ListarPedidosSinColocarParams) ([]sqlc.ListarPedidosSinColocarRow, error) {
	var salida []sqlc.ListarPedidosSinColocarRow
	for _, p := range q.pedidos {
		if p.sucursal != arg.BranchID || p.ruta != nil {
			continue
		}
		if _, puesto := q.colocadas[p.id]; puesto {
			continue
		}
		salida = append(salida, sqlc.ListarPedidosSinColocarRow{
			ID: p.id, CustomerName: p.nombre, Weight: p.peso,
			KmAlAlmacen: kmDelTablero(arg.OrigenLat, arg.OrigenLng, p.lat, p.lng),
		})
	}
	// El encargo: el más cerca del almacén primero.
	sort.Slice(salida, func(i, j int) bool { return salida[i].KmAlAlmacen < salida[j].KmAlAlmacen })
	if int32(len(salida)) > arg.Limite {
		salida = salida[:arg.Limite]
	}
	return salida, nil
}

func (q *tableroFalso) ContarPedidosSinColocar(_ context.Context, arg sqlc.ContarPedidosSinColocarParams) (int64, error) {
	var n int64
	for _, p := range q.pedidos {
		if p.sucursal != arg.BranchID || p.ruta != nil {
			continue
		}
		if _, puesto := q.colocadas[p.id]; puesto {
			continue
		}
		n++
	}
	return n, nil
}

// --------------------------------------------------------------------------- montaje

type fuenteTab struct{ q sqlc.Querier }

func (f fuenteTab) Consultas() sqlc.Querier { return f.q }

// EnTx corre la función tal cual. El doble no deshace nada: lo que se prueba aquí es el
// manejador, no el aislamiento de Postgres.
func (f fuenteTab) EnTx(_ context.Context, fn func(sqlc.Querier) error) error { return fn(f.q) }

func montarTab(t *testing.T, q sqlc.Querier) http.Handler {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoTab)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	s := NuevoServidor(cfg, reg,
		alcance.NuevaPorteria(fuenteTab{q: q}, reg),
		auth.NuevoVerificador([]byte(secretoTab)),
		nil)

	rt := httpx.NuevoRouter(httpx.IDDePeticion, httpx.ConRegistro(reg), httpx.RecuperarPanico, httpx.SinCache)
	sesion := []httpx.Medio{s.verif.Exigir, s.porteria.Exigir}
	admin := []httpx.Medio{s.verif.Exigir, auth.ExigirAdmin, s.porteria.Exigir}
	s.rutasTablero(rt, sesion, admin)
	s.rutasEspejo(rt, sesion, admin)
	return rt.Handler()
}

func tokenTab(t *testing.T, sucursal string) string {
	t.Helper()
	reclamos := map[string]any{
		"sub": "p-logistico", "role": "OPERADOR",
		"exp": time.Now().Add(time.Hour).Unix(),
	}
	if sucursal != "" {
		reclamos["branchId"] = sucursal
	} else {
		reclamos["role"] = "SUPER ADMIN"
	}
	cab := b64Tab(t, map[string]any{"alg": "HS256", "typ": "JWT"})
	cuerpo := b64Tab(t, reclamos)
	mac := hmac.New(sha256.New, []byte(secretoTab))
	mac.Write([]byte(cab + "." + cuerpo))
	return cab + "." + cuerpo + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func b64Tab(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

func pedirTab(t *testing.T, h http.Handler, metodo, ruta, jwt, cuerpo string) *httptest.ResponseRecorder {
	t.Helper()
	var lector io.Reader
	if cuerpo != "" {
		lector = strings.NewReader(cuerpo)
	}
	r := httptest.NewRequest(metodo, ruta, lector)
	if jwt != "" {
		r.Header.Set("Authorization", "Bearer "+jwt)
	}
	if cuerpo != "" {
		r.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)
	return w
}

func leerTab(t *testing.T, w *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &m); err != nil {
		t.Fatalf("respuesta ilegible (%d): %s", w.Code, w.Body.String())
	}
	return m
}

// --------------------------------------------------------------------------- pruebas

// LA PRUEBA DE LA REAPLICABILIDAD.
//
// El tablero se usa sin red y sus órdenes suben en lotes que se reintentan. Colocar dos
// veces el mismo pedido en el mismo sitio tiene que dejar EL MISMO TABLERO: ni dos
// tarjetas, ni un error, ni los vecinos corridos una posición en cada reintento.
func TestColocarDosVecesElMismoPedidoEnElMismoSitioNoFalla(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas() // Centro: ped1=1, ped2=2, ped3=3
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	cuerpo := `{"columnaId":"` + colCentro.String() + `","posicion":2}`
	for intento := 1; intento <= 3; intento++ {
		w := pedirTab(t, h, http.MethodPut, "/api/board/placements/"+ped2.String(), jwt, cuerpo)
		if w.Code != http.StatusOK {
			t.Fatalf("intento %d: código %d, cuerpo %s", intento, w.Code, w.Body.String())
		}
	}

	// Una sola tarjeta por pedido: lo sostiene la clave primaria, y el manejador no la
	// puede haber esquivado.
	if len(q.colocadas) != 3 {
		t.Fatalf("hay %d colocaciones y tenían que ser 3: %+v", len(q.colocadas), q.colocadas)
	}
	// Y el tablero está EXACTAMENTE como estaba: reaplicar no corre a nadie de sitio.
	esperado := map[uuid.UUID]colocacion{
		ped1: {colCentro, 1}, ped2: {colCentro, 2}, ped3: {colCentro, 3},
	}
	for ped, quiero := range esperado {
		if q.colocadas[ped] != quiero {
			t.Fatalf("tras tres reintentos, %s quedó en %+v y tenía que estar en %+v",
				ped, q.colocadas[ped], quiero)
		}
	}
}

// Mover de verdad sí cambia el tablero, y cierra el hueco que deja atrás.
func TestMoverUnaTarjetaDeColumnaCierraElHueco(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodPut, "/api/board/placements/"+ped1.String(), jwt,
		`{"columnaId":"`+colVista.String()+`","posicion":1}`)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if q.colocadas[ped1] != (colocacion{colVista, 1}) {
		t.Fatalf("ped1 quedó en %+v", q.colocadas[ped1])
	}
	// Los que quedaban detrás en Centro suben: sin esto las posiciones se van separando
	// hasta que alguien lee «la parada 47» de una columna de nueve.
	if q.colocadas[ped2] != (colocacion{colCentro, 1}) || q.colocadas[ped3] != (colocacion{colCentro, 2}) {
		t.Fatalf("no se cerró el hueco: ped2=%+v ped3=%+v", q.colocadas[ped2], q.colocadas[ped3])
	}
}

// LA OTRA PRUEBA QUE IMPORTA: la base se niega y la persona recibe algo que entiende.
func TestBorrarColumnaConPedidosDaElErrorClaroYNoUn500(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodDelete, "/api/board/columns/"+colCentro.String(), jwt, "")
	if w.Code != http.StatusConflict {
		t.Fatalf("tenía que ser 409 y fue %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	if m["error"] != "«Centro» tiene 3 pedidos puestos" {
		t.Fatalf("mensaje %q", m["error"])
	}
	if n, _ := m["pedidos"].(float64); n != 3 {
		t.Fatalf("sin el número, la persona no sabe si vaciar dos o mover ochenta: %v", m["pedidos"])
	}
	if _, sigue := q.columnas[colCentro]; !sigue {
		t.Fatal("la columna se borró igual")
	}
	if len(q.colocadas) != 3 {
		t.Fatal("las tarjetas se perdieron por el camino")
	}
}

// Y si la base se niega DESPUÉS de haber contado cero —alguien colocó una tarjeta entre
// la cuenta y el borrado—, tampoco puede salir un 500 con la jerga de Postgres dentro.
func TestSiLaBaseSeNiegaEnElUltimoMomentoTampocoEs500(t *testing.T) {
	q := nuevoTablero()
	q.borrarFalla = true // 23503 aunque el contador diga cero
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodDelete, "/api/board/columns/"+colVacia.String(), jwt, "")
	if w.Code != http.StatusConflict {
		t.Fatalf("tenía que ser 409 y fue %d: %s", w.Code, w.Body.String())
	}
	if strings.Contains(w.Body.String(), "23503") || strings.Contains(w.Body.String(), "Error interno") {
		t.Fatalf("salió la jerga del motor: %s", w.Body.String())
	}
}

func TestBorrarColumnaConVaciarDevuelveLasTarjetasASinColocar(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodDelete, "/api/board/columns/"+colCentro.String()+"?vaciar=1", jwt, "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if len(q.colocadas) != 0 {
		t.Fatalf("quedaron tarjetas puestas: %+v", q.colocadas)
	}
	if _, sigue := q.columnas[colCentro]; sigue {
		t.Fatal("la columna no se borró")
	}
}

func TestBorrarColumnaConDestinoMueveLasTarjetasDetras(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.colocadas[pedRuta] = colocacion{colVista, 1} // ya había una en la de destino
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodDelete,
		"/api/board/columns/"+colCentro.String()+"?destino="+colVista.String(), jwt, "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	// Detrás de lo que ya había y en su mismo orden relativo.
	if q.colocadas[ped1] != (colocacion{colVista, 2}) ||
		q.colocadas[ped2] != (colocacion{colVista, 3}) ||
		q.colocadas[ped3] != (colocacion{colVista, 4}) {
		t.Fatalf("el orden relativo se perdió: %+v", q.colocadas)
	}
}

// Sin sucursal elegida NO se enseña «todo», que es lo que parecería razonable y sería lo
// peor: ordenaría los pedidos de Holguín por su distancia al almacén de Santiago.
func TestSuperAdminSinSucursalNoVeElTableroDeTodas(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	w := pedirTab(t, h, http.MethodGet, "/api/board", tokenTab(t, ""), "")
	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if leerTab(t, w)["error"] != msgElijeSucursal {
		t.Fatalf("mensaje %q", w.Body.String())
	}
}

// Sin almacén con coordenadas NO HAY TABLERO: no se ordena por un punto inventado.
func TestSinAlmacenConCoordenadasEs409(t *testing.T) {
	q := nuevoTablero()
	q.sinOrigen = true
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodGet, "/api/board", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if leerTab(t, w)["error"] != "Santiago no tiene ningún almacén con coordenadas" {
		t.Fatalf("mensaje %q", w.Body.String())
	}
}

// Un pedido que ya va en un camión no se coloca, y se dice POR QUÉ: es un 409 que la
// persona puede arreglar, no un 404 que no explica nada.
func TestColocarUnPedidoQueYaVaEnUnaRutaEs409(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	w := pedirTab(t, h, http.MethodPut, "/api/board/placements/"+pedRuta.String(),
		tokenTab(t, sucStg.String()), `{"columnaId":"`+colCentro.String()+`","posicion":1}`)
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if leerTab(t, w)["error"] != msgYaVaEnUnaRuta {
		t.Fatalf("mensaje %q", w.Body.String())
	}
}

// Un pedido de otra sucursal es 404 y NO se dice que existe: decirlo ya es contar algo.
func TestColocarUnPedidoDeOtraSucursalEs404(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	w := pedirTab(t, h, http.MethodPut, "/api/board/placements/"+pedHol.String(),
		tokenTab(t, sucStg.String()), `{"columnaId":"`+colCentro.String()+`","posicion":1}`)
	if w.Code != http.StatusNotFound {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if strings.Contains(w.Body.String(), "Holguín") {
		t.Fatalf("la respuesta cuenta de más: %s", w.Body.String())
	}
}

// Quitar dos veces lo que ya no está no es un error: un lote que se reintenta no puede
// empezar a fallar por eso.
func TestQuitarDosVecesNoFalla(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	for i := 0; i < 2; i++ {
		w := pedirTab(t, h, http.MethodDelete, "/api/board/placements/"+ped2.String(), jwt, "")
		if w.Code != http.StatusOK {
			t.Fatalf("vuelta %d: código %d (%s)", i, w.Code, w.Body.String())
		}
	}
	if _, sigue := q.colocadas[ped2]; sigue {
		t.Fatal("ped2 sigue puesto")
	}
	if q.colocadas[ped3] != (colocacion{colCentro, 2}) {
		t.Fatalf("el hueco se cerró dos veces: ped3=%+v", q.colocadas[ped3])
	}
}

// La mitad izquierda sale ordenada por cercanía al almacén, que es el encargo entero.
func TestLosSinColocarSalenPorCercania(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	w := pedirTab(t, h, http.MethodGet, "/api/board/unplaced", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	lista, _ := m["pedidos"].([]any)
	if len(lista) < 3 {
		t.Fatalf("faltan pedidos: %s", w.Body.String())
	}
	anterior := -1.0
	for _, cruda := range lista {
		p := cruda.(map[string]any)
		km := p["kmAlAlmacen"].(float64)
		if km < anterior {
			t.Fatalf("la lista no va del más cerca al más lejos: %s", w.Body.String())
		}
		anterior = km
	}
	// El pedido que ya va en una ruta no está: el listón es el mismo del armador.
	if strings.Contains(w.Body.String(), "Ya salió") {
		t.Fatalf("salió un pedido que ya va en un camión: %s", w.Body.String())
	}
	// Y dos pedidos del mismo cliente son DOS tarjetas, marcadas, no una fundida.
	for _, cruda := range lista {
		p := cruda.(map[string]any)
		if p["customerName"] == "Ana" {
			if n, _ := p["mismoCliente"].(float64); n != 2 {
				t.Fatalf("no se marcó «2 pedidos de este cliente hoy»: %v", p["mismoCliente"])
			}
		}
	}
}

// El tablero entero en UNA ida y vuelta, y con la hora de la bajada dentro.
func TestElTableroTraeTodoDeUnaVez(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	h := montarTab(t, q)
	w := pedirTab(t, h, http.MethodGet, "/api/board", tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	for _, clave := range []string{"sucursal", "almacen", "columnas", "colocados", "avisos", "sinColocar", "vistoAt"} {
		if _, hay := m[clave]; !hay {
			t.Fatalf("falta «%s» en el tablero: %s", clave, w.Body.String())
		}
	}
	if len(m["columnas"].([]any)) != 3 {
		t.Fatalf("columnas: %s", w.Body.String())
	}
	if len(m["colocados"].([]any)) != 3 {
		t.Fatalf("colocados: %s", w.Body.String())
	}
}

// Dos columnas con el mismo nombre en el mismo tablero son dos camiones al mismo barrio.
func TestDosColumnasConElMismoNombreEs409(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	jwt := tokenTab(t, sucStg.String())

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns", jwt, `{"nombre":"centro"}`)
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if leerTab(t, w)["error"] != "Ya hay una columna «centro» en este tablero" {
		t.Fatalf("mensaje %q", w.Body.String())
	}
}

func TestCrearColumnaVaAlFinal(t *testing.T) {
	q := nuevoTablero()
	h := montarTab(t, q)
	w := pedirTab(t, h, http.MethodPost, "/api/board/columns", tokenTab(t, sucStg.String()),
		`{"nombre":"Reparto Norte"}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if n, _ := leerTab(t, w)["posicion"].(float64); n != 4 {
		t.Fatalf("la columna nueva no fue al final: %s", w.Body.String())
	}
}

// Sin token no se llega al tablero de nadie.
func TestElTableroExigeSesion(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	w := pedirTab(t, h, http.MethodGet, "/api/board", "", "")
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("código %d", w.Code)
	}
	if strings.TrimSpace(w.Body.String()) != `{"error":"Unauthorized"}` {
		t.Fatalf("cuerpo %q", w.Body.String())
	}
}

// El alcance por HTTP: Santiago no ve el tablero de Holguín ni pidiéndolo por `branchId`.
func TestSantiagoNoLlegaAlTableroDeHolguin(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	w := pedirTab(t, h, http.MethodGet, "/api/board?branchId="+sucHol.String(),
		tokenTab(t, sucStg.String()), "")
	if w.Code != http.StatusNotFound {
		t.Fatalf("tenía que ser 404 y fue %d: %s", w.Code, w.Body.String())
	}
}

// --------------------------------------------------------------------------- armar ruta

func (q *tableroFalso) PedidosDeColumnaParaArmarRuta(_ context.Context, arg sqlc.PedidosDeColumnaParaArmarRutaParams) ([]sqlc.PedidosDeColumnaParaArmarRutaRow, error) {
	var salida []sqlc.PedidosDeColumnaParaArmarRutaRow
	for ped, c := range q.colocadas {
		if c.columna != arg.ColumnaID {
			continue
		}
		p := q.pedidos[ped]
		// Las condiciones del SQL: sin ruta y con coordenadas. `factura_estado` NO corta
		// aquí, corta el manejador, para poder nombrar cuál falla y por qué.
		if p.ruta != nil || (p.lat == 0 && p.lng == 0) {
			continue
		}
		salida = append(salida, sqlc.PedidosDeColumnaParaArmarRutaRow{
			ID: p.id, CustomerName: p.nombre, Weight: p.peso,
			EndLat: &p.lat, EndLng: &p.lng, FacturaEstado: p.factura, Posicion: c.posicion,
		})
	}
	sort.Slice(salida, func(i, j int) bool { return salida[i].Posicion < salida[j].Posicion })
	return salida, nil
}

func (q *tableroFalso) ContarRutasDelDia(context.Context, string) (int64, error) { return 4, nil }

func (q *tableroFalso) CrearRuta(_ context.Context, arg sqlc.CrearRutaParams) (sqlc.CrearRutaRow, error) {
	q.rutaCreada = &arg
	return sqlc.CrearRutaRow{
		ID: rutaNueva, Name: arg.Name, RouteCode: arg.RouteCode,
		Status: sqlc.RouteStatusPlanned, BranchID: arg.BranchID, VehicleID: arg.VehicleID,
	}, nil
}

func (q *tableroFalso) EngancharPedidoARuta(_ context.Context, arg sqlc.EngancharPedidoARutaParams) (int64, error) {
	p, ok := q.pedidos[arg.PedidoID]
	if !ok || p.ruta != nil {
		return 0, nil // se lo llevaron entre medias
	}
	ruta := uuid.UUID(arg.RutaID.Bytes)
	p.ruta = &ruta
	q.pedidos[arg.PedidoID] = p
	q.enganchados = append(q.enganchados, arg.PedidoID)
	return 1, nil
}

func (q *tableroFalso) FijarTotalesDeRuta(_ context.Context, arg sqlc.FijarTotalesDeRutaParams) (sqlc.FijarTotalesDeRutaRow, error) {
	q.totales = &arg
	return sqlc.FijarTotalesDeRutaRow{ID: arg.ID}, nil
}

func (q *tableroFalso) QuitarDelTableroLosDeRuta(_ context.Context, arg sqlc.QuitarDelTableroLosDeRutaParams) (int64, error) {
	var n int64
	for ped := range q.colocadas {
		if p := q.pedidos[ped]; p.ruta != nil && [16]byte(*p.ruta) == arg.RutaID.Bytes {
			delete(q.colocadas, ped)
			n++
		}
	}
	return n, nil
}

func (q *tableroFalso) ObtenerVehiculoParaCapacidad(_ context.Context, id uuid.UUID) (sqlc.ObtenerVehiculoParaCapacidadRow, error) {
	return sqlc.ObtenerVehiculoParaCapacidadRow{ID: id, Name: "F-350", Capacity: q.capacidad}, nil
}

// De una columna sale una ruta, la columna se queda vacía y la columna SIGUE EXISTIENDO:
// el distrito sigue ahí mañana; lo que se vacía es lo que llevaba dentro hoy.
func TestArmarLaRutaDeUnaColumnaVaciaSusTarjetasYDejaLaColumna(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.capacidad = 1000
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	if n, _ := m["paradas"].(float64); n != 3 {
		t.Fatalf("paradas %v: %s", m["paradas"], w.Body.String())
	}
	if peso, _ := m["totalWeight"].(float64); peso != 80 {
		t.Fatalf("peso %v", m["totalWeight"])
	}
	if len(q.colocadas) != 0 {
		t.Fatalf("las tarjetas siguen puestas: %+v", q.colocadas)
	}
	if _, sigue := q.columnas[colCentro]; !sigue {
		t.Fatal("se borró la columna: el distrito sigue existiendo mañana")
	}
	// Se RESPETA el orden del logístico: él conoce las calles de su distrito.
	if len(q.enganchados) != 3 || q.enganchados[0] != ped1 || q.enganchados[2] != ped3 {
		t.Fatalf("no se respetó el orden puesto: %v", q.enganchados)
	}
	// Y la distancia es el CIRCUITO CERRADO: el camión vuelve.
	if q.totales == nil || q.totales.TotalDistance <= 0 {
		t.Fatalf("totales: %+v", q.totales)
	}
	if *q.rutaCreada.RouteCode != "RT-"+time.Now().Format("20060102")+"-005" {
		t.Fatalf("código de ruta %q", *q.rutaCreada.RouteCode)
	}
}

// Los que no cuadran con la factura se descartan NOMBRÁNDOLOS. Una columna de tres que
// produce una ruta de dos sin explicación es la manera más rápida de que el logístico
// deje de fiarse del tablero.
func TestLosQueNoCuadranConLaFacturaSeCaenConNombreYMotivo(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.capacidad = 1000
	// A ped2 nadie lo ha cotejado: NULL no es «cuadra». Con un NULL colado se armó una
	// ruta sin facturar el 2/09.
	p := q.pedidos[ped2]
	p.factura = nil
	q.pedidos[ped2] = p
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	desc := m["descartados"].([]any)
	if len(desc) != 1 {
		t.Fatalf("descartados: %s", w.Body.String())
	}
	if d := desc[0].(map[string]any); d["motivo"] != "sin cotejar" || d["customerName"] != "Beto" {
		t.Fatalf("no se dice quién falla ni por qué: %v", d)
	}
}

// Si no queda ninguno repartible NO se crea una ruta vacía, y se dice por qué se cayó
// cada uno.
func TestArmarUnaColumnaSinNadaRepartibleEs409(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.capacidad = 1000
	for _, id := range []uuid.UUID{ped1, ped2, ped3} {
		p := q.pedidos[id]
		sin := sqlc.FacturaEstadoSinFactura
		p.factura = &sin
		q.pedidos[id] = p
	}
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	if m["error"] != msgColumnaSinNada {
		t.Fatalf("mensaje %q", m["error"])
	}
	if len(m["descartados"].([]any)) != 3 {
		t.Fatalf("faltan los motivos: %s", w.Body.String())
	}
	if q.rutaCreada != nil {
		t.Fatal("se creó una ruta vacía")
	}
}

// El exceso de peso AVISA en el tablero pero al ARMAR ya no: lo que no cabe, no sube.
func TestAlArmarSeComprubaLaCapacidadDelCamion(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.capacidad = 50 // los tres pesan 80
	c := q.columnas[colCentro]
	c.VehicleID = pgtype.UUID{Bytes: [16]byte(uuid.New()), Valid: true}
	q.columnas[colCentro] = c
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "supera la capacidad del vehículo") {
		t.Fatalf("mensaje %q", w.Body.String())
	}
	if len(q.colocadas) != 3 {
		t.Fatal("se vació la columna igual")
	}
}

// Reordenar el tablero entero: llega la lista de ids en el orden nuevo.
func TestReordenarElTableroEntero(t *testing.T) {
	q := nuevoTablero()
	h := montarTab(t, q)
	cuerpo := `{"ids":["` + colVacia.String() + `","` + colCentro.String() + `","` + colVista.String() + `"]}`

	w := pedirTab(t, h, http.MethodPut, "/api/board/columns/orden", tokenTab(t, sucStg.String()), cuerpo)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if n, _ := leerTab(t, w)["reordenadas"].(float64); n != 3 {
		t.Fatalf("reordenadas %v: %s", n, w.Body.String())
	}
	if q.columnas[colVacia].Posicion != 1 || q.columnas[colVista].Posicion != 3 {
		t.Fatalf("no se reordenó: %+v", q.columnas)
	}
}

// Y por PUT a una columna suelta no se hace nada: renombrar es PATCH.
func TestPutAUnaColumnaSueltaEs405(t *testing.T) {
	h := montarTab(t, nuevoTablero())
	w := pedirTab(t, h, http.MethodPut, "/api/board/columns/"+colCentro.String(),
		tokenTab(t, sucStg.String()), `{"nombre":"Otro"}`)
	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
}
