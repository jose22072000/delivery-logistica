package api

// LAS PRUEBAS DEL REPARTO.
//
// Van en el paquete `api` —y no en `api_test`— porque lo que hay que probar es
// `rutasDeReparto` montada CON SUS MIDDLEWARES, ruta por ruta. Montar el router entero no
// vale: lo que se escapa en un recurso como éste no es que no compile, es que una ruta se
// quedó sin alcance.
//
// El doble repite los WHERE del SQL de verdad (`db/queries/routes.sql`). Ahí está el
// valor: si una prueba pasa porque el doble es más permisivo que Postgres, la prueba no
// prueba nada. Los tres sitios donde se ha copiado el WHERE con lupa son el alcance por
// sucursal, el `route_id IS NULL` del enganche y el `ultima_ruta_id` del cierre.
//
// Y una cosa que se prueba SIN escribir una sola línea: el doble embebe `sqlc.Querier` sin
// implementarlo, así que cualquier consulta que el manejador llame y no esté aquí revienta
// con un nil. Por eso el cierre demuestra también que NO TOCA INVENTARIO: si tocara,
// llamaría a una consulta de productos y la prueba moriría.

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

const secretoDeRutas = "un-secreto-de-pruebas-de-al-menos-32-caracteres"

var (
	stgDeRutas = uuid.MustParse("11111111-1111-1111-1111-111111111111")
	holDeRutas = uuid.MustParse("22222222-2222-2222-2222-222222222222")

	camionStg = uuid.MustParse("aaaaaaaa-0000-0000-0000-000000000001")
	camionHol = uuid.MustParse("bbbbbbbb-0000-0000-0000-000000000002")
)

// --------------------------------------------------------------------------- el doble

type pedidoDeRutas struct {
	id         uuid.UUID
	operacion  *string
	cliente    string
	endLat     *float64
	endLng     *float64
	peso       float64
	costo      *float64
	factura    *sqlc.FacturaEstado
	sucursal   uuid.UUID
	externalID *string
	fuente     *sqlc.Procedencia

	rutaID     *uuid.UUID // route_id: va cargado AHORA
	ultimaRuta *uuid.UUID // ultima_ruta_id: en qué camión VIAJÓ
	stopOrder  *int32
	segmentKm  *float64
	precio     *float64
	tramo      sqlc.TripLeg
	estado     sqlc.OrderStatus

	resultado   *sqlc.StopResult
	resultadoAt *time.Time
	nota        *string
	entregadoEn *time.Time

	renglones []sqlc.OrderItem
}

type rutaDeRutas struct {
	id        uuid.UUID
	codigo    string
	nombre    *string
	estado    sqlc.RouteStatus
	vehiculo  *uuid.UUID
	sucursal  *uuid.UUID
	origenLat *float64
	origenLng *float64
	km        float64
	peso      float64
	precio    float64
	optimized bool
	creadoPor *string
	creada    time.Time
	salida    *time.Time
	regreso   *time.Time
}

type camionDeRutas struct {
	id        uuid.UUID
	nombre    string
	capacidad float64
	estado    sqlc.VehicleStatus
	sucursal  *uuid.UUID
}

type dobleDeRutas struct {
	sqlc.Querier

	pedidos  map[uuid.UUID]*pedidoDeRutas
	rutas    map[uuid.UUID]*rutaDeRutas
	camiones map[uuid.UUID]*camionDeRutas

	// Lo que se vio pasar: con qué sucursal llegó cada consulta.
	sucursalVista []pgtype.UUID
}

// alcanza repite el `($n::uuid IS NULL OR branch_id = $n::uuid)` del SQL.
func alcanza(param pgtype.UUID, propia *uuid.UUID) bool {
	if !param.Valid {
		return true
	}
	return propia != nil && [16]byte(*propia) == param.Bytes
}

// alcanzaCamion repite el WHERE de vehículos, que ADEMÁS deja pasar los de `branch_id`
// NULL: son los compartidos, y un camión de todas se usa desde cualquier sucursal.
func alcanzaCamion(param pgtype.UUID, propia *uuid.UUID) bool {
	if !param.Valid || propia == nil {
		return true
	}
	return [16]byte(*propia) == param.Bytes
}

func (d *dobleDeRutas) ResolverSucursal(_ context.Context, id uuid.UUID) (sqlc.ResolverSucursalRow, error) {
	switch id {
	case stgDeRutas:
		c := "STG"
		return sqlc.ResolverSucursalRow{ID: stgDeRutas, Name: "Santiago", ExternalID: &c}, nil
	case holDeRutas:
		c := "HOL"
		return sqlc.ResolverSucursalRow{ID: holDeRutas, Name: "Holguín", ExternalID: &c}, nil
	}
	return sqlc.ResolverSucursalRow{}, pgx.ErrNoRows
}

func (d *dobleDeRutas) ListarRutas(_ context.Context, arg sqlc.ListarRutasParams) ([]sqlc.ListarRutasRow, error) {
	d.sucursalVista = append(d.sucursalVista, arg.Sucursal)
	var salida []sqlc.ListarRutasRow
	for _, r := range d.rutas {
		if !alcanza(arg.Sucursal, r.sucursal) {
			continue
		}
		salida = append(salida, sqlc.ListarRutasRow{
			ID: r.id, RouteCode: &r.codigo, Name: r.nombre, Status: r.estado,
			OriginLat: r.origenLat, OriginLng: r.origenLng,
			TotalDistance: r.km, TotalWeight: r.peso, TotalPrice: r.precio,
			VehicleID: pgOpcionalDeRutas(r.vehiculo), BranchID: pgOpcionalDeRutas(r.sucursal),
			Optimized: r.optimized, CreadoPor: r.creadoPor,
			CreatedAt: pgtype.Timestamptz{Time: r.creada, Valid: true},
		})
	}
	return salida, nil
}

func (d *dobleDeRutas) ObtenerRuta(_ context.Context, arg sqlc.ObtenerRutaParams) (sqlc.ObtenerRutaRow, error) {
	d.sucursalVista = append(d.sucursalVista, arg.Sucursal)
	r, hay := d.rutas[arg.ID]
	if !hay || !alcanza(arg.Sucursal, r.sucursal) {
		return sqlc.ObtenerRutaRow{}, pgx.ErrNoRows
	}
	fila := sqlc.ObtenerRutaRow{
		ID: r.id, RouteCode: &r.codigo, Name: r.nombre, Status: r.estado,
		OriginLat: r.origenLat, OriginLng: r.origenLng,
		TotalDistance: r.km, TotalWeight: r.peso, TotalPrice: r.precio,
		VehicleID: pgOpcionalDeRutas(r.vehiculo), BranchID: pgOpcionalDeRutas(r.sucursal),
		Optimized: r.optimized, CreadoPor: r.creadoPor,
		CreatedAt:  pgtype.Timestamptz{Time: r.creada, Valid: true},
		StartedAt:  horaOpcionalDeRutas(r.salida),
		FinishedAt: horaOpcionalDeRutas(r.regreso),
	}
	if r.vehiculo != nil {
		if v, hay := d.camiones[*r.vehiculo]; hay {
			nombre, estado, cap := v.nombre, v.estado, v.capacidad
			fila.VehiculoNombre = &nombre
			fila.VehiculoEstado = &estado
			fila.VehiculoCapacidad = &cap
		}
	}
	return fila, nil
}

func (d *dobleDeRutas) ListarParadasDeRutas(_ context.Context, arg sqlc.ListarParadasDeRutasParams) ([]sqlc.ListarParadasDeRutasRow, error) {
	d.sucursalVista = append(d.sucursalVista, arg.Sucursal)
	var salida []sqlc.ListarParadasDeRutasRow
	for _, p := range d.pedidos {
		if p.rutaID == nil || !enLista(arg.RutaIds, *p.rutaID) {
			continue
		}
		if !alcanza(arg.Sucursal, &p.sucursal) {
			continue
		}
		salida = append(salida, sqlc.ListarParadasDeRutasRow{
			RouteID: pgOpcionalDeRutas(p.rutaID), ID: p.id, OperationNumber: p.operacion,
			CustomerName: p.cliente, EndLat: p.endLat, EndLng: p.endLng,
			Weight: p.peso, Price: p.precio, PedidoCosto: p.costo, SegmentKm: p.segmentKm,
			StopOrder: p.stopOrder, TripLeg: p.tramo, Status: p.estado,
			Resultado: p.resultado, ResultadoNota: p.nota,
			DeliveredAt: horaOpcionalDeRutas(p.entregadoEn),
			ExternalID:  p.externalID, Source: p.fuente,
			BranchID: pgDeRutas(p.sucursal),
		})
	}
	ordenarPorParada(salida)
	return salida, nil
}

func (d *dobleDeRutas) ListarRenglonesDeRutas(_ context.Context, arg sqlc.ListarRenglonesDeRutasParams) ([]sqlc.ListarRenglonesDeRutasRow, error) {
	var salida []sqlc.ListarRenglonesDeRutasRow
	for _, p := range d.pedidos {
		if p.rutaID == nil || !enLista(arg.RutaIds, *p.rutaID) || !alcanza(arg.Sucursal, &p.sucursal) {
			continue
		}
		for _, g := range p.renglones {
			salida = append(salida, sqlc.ListarRenglonesDeRutasRow{
				RouteID: pgOpcionalDeRutas(p.rutaID), OrderID: p.id, Linea: g.Linea,
				Description: g.Description, Quantity: g.Quantity, Packs: g.Packs,
			})
		}
	}
	return salida, nil
}

// ListarParadasQueViajaronEnRuta va por `ultima_ruta_id`: el devuelto sigue estando.
func (d *dobleDeRutas) ListarParadasQueViajaronEnRuta(_ context.Context, arg sqlc.ListarParadasQueViajaronEnRutaParams) ([]sqlc.ListarParadasQueViajaronEnRutaRow, error) {
	var salida []sqlc.ListarParadasQueViajaronEnRutaRow
	for _, p := range d.pedidos {
		if p.ultimaRuta == nil || [16]byte(*p.ultimaRuta) != arg.RutaID.Bytes {
			continue
		}
		if !alcanza(arg.Sucursal, &p.sucursal) {
			continue
		}
		salida = append(salida, sqlc.ListarParadasQueViajaronEnRutaRow{
			ID: p.id, OperationNumber: p.operacion, CustomerName: p.cliente,
			Weight: p.peso, StopOrder: p.stopOrder, Resultado: p.resultado,
			ResultadoNota: p.nota, DeliveredAt: horaOpcionalDeRutas(p.entregadoEn),
			ExternalID: p.externalID, Source: p.fuente, BranchID: pgDeRutas(p.sucursal),
		})
	}
	return salida, nil
}

// PedidosParaArmarRuta repite las cinco condiciones del SQL. `factura_estado` NO se filtra
// aquí a propósito: el corte a sólo `igual` lo hace el manejador para poder nombrar cuál
// falla y por qué.
func (d *dobleDeRutas) PedidosParaArmarRuta(_ context.Context, arg sqlc.PedidosParaArmarRutaParams) ([]sqlc.PedidosParaArmarRutaRow, error) {
	d.sucursalVista = append(d.sucursalVista, arg.Sucursal)
	var salida []sqlc.PedidosParaArmarRutaRow
	for _, id := range arg.PedidoIds { // el orden de la base; aquí, el de los ids
		p, hay := d.pedidos[id]
		switch {
		case !hay, p.rutaID != nil, p.endLat == nil, p.endLng == nil:
			continue
		case p.fuente == nil || *p.fuente != sqlc.ProcedenciaPedido:
			continue
		case !alcanza(arg.Sucursal, &p.sucursal):
			continue
		}
		salida = append(salida, sqlc.PedidosParaArmarRutaRow{
			ID: p.id, OperationNumber: p.operacion, CustomerName: p.cliente,
			EndLat: p.endLat, EndLng: p.endLng, Weight: p.peso, PedidoCosto: p.costo,
			FacturaEstado: p.factura, BranchID: pgDeRutas(p.sucursal),
			ExternalID: p.externalID, Source: p.fuente,
		})
	}
	return salida, nil
}

func (d *dobleDeRutas) ContarRutasDelDia(_ context.Context, prefijo string) (int64, error) {
	var n int64
	for _, r := range d.rutas {
		if strings.HasPrefix(r.codigo, prefijo) {
			n++
		}
	}
	return n, nil
}

func (d *dobleDeRutas) CrearRuta(_ context.Context, arg sqlc.CrearRutaParams) (sqlc.CrearRutaRow, error) {
	r := &rutaDeRutas{
		id: uuid.New(), nombre: arg.Name, estado: sqlc.RouteStatusPlanned,
		origenLat: arg.OriginLat, origenLng: arg.OriginLng, creadoPor: arg.CreadoPor,
		creada: time.Now(),
	}
	if arg.RouteCode != nil {
		r.codigo = *arg.RouteCode
	}
	if arg.VehicleID.Valid {
		v := uuid.UUID(arg.VehicleID.Bytes)
		r.vehiculo = &v
	}
	if arg.BranchID.Valid {
		b := uuid.UUID(arg.BranchID.Bytes)
		r.sucursal = &b
	}
	d.rutas[r.id] = r
	return sqlc.CrearRutaRow{
		ID: r.id, Name: r.nombre, RouteCode: arg.RouteCode, Status: r.estado,
		OriginLat: r.origenLat, OriginLng: r.origenLng,
		VehicleID: arg.VehicleID, BranchID: arg.BranchID, CreadoPor: arg.CreadoPor,
	}, nil
}

// EngancharPedidoARuta repite el WHERE ENTERO, incluido `route_id IS NULL`: es la carrera
// de dos logísticos armando a la vez, y devolver 1 aquí siempre haría pasar una prueba que
// en producción falla.
func (d *dobleDeRutas) EngancharPedidoARuta(_ context.Context, arg sqlc.EngancharPedidoARutaParams) (int64, error) {
	p, hay := d.pedidos[arg.PedidoID]
	if !hay || p.rutaID != nil || !alcanza(arg.Sucursal, &p.sucursal) {
		return 0, nil
	}
	ruta := uuid.UUID(arg.RutaID.Bytes)
	p.rutaID = &ruta
	p.ultimaRuta = &ruta // LOS DOS, y el segundo no se suelta nunca
	p.stopOrder = arg.StopOrder
	p.segmentKm = arg.SegmentKm
	p.tramo = sqlc.TripLegOutbound
	cero := 0.0
	p.precio = &cero
	if arg.Price != nil {
		v := *arg.Price
		p.precio = &v
	}
	return 1, nil
}

func (d *dobleDeRutas) FijarTotalesDeRuta(_ context.Context, arg sqlc.FijarTotalesDeRutaParams) (sqlc.FijarTotalesDeRutaRow, error) {
	r, hay := d.rutas[arg.ID]
	if !hay || !alcanza(arg.Sucursal, r.sucursal) {
		return sqlc.FijarTotalesDeRutaRow{}, pgx.ErrNoRows
	}
	r.km, r.peso, r.precio, r.optimized = arg.TotalDistance, arg.TotalWeight, arg.TotalPrice, true
	return sqlc.FijarTotalesDeRutaRow{ID: r.id, TotalDistance: r.km, TotalWeight: r.peso, TotalPrice: r.precio, Optimized: true}, nil
}

func (d *dobleDeRutas) ActualizarEstadoDeRuta(_ context.Context, arg sqlc.ActualizarEstadoDeRutaParams) (sqlc.ActualizarEstadoDeRutaRow, error) {
	r, hay := d.rutas[arg.ID]
	if !hay || !alcanza(arg.Sucursal, r.sucursal) {
		return sqlc.ActualizarEstadoDeRutaRow{}, pgx.ErrNoRows
	}
	if arg.Name != nil {
		r.nombre = arg.Name
	}
	if arg.Status != nil {
		r.estado = *arg.Status
		ahora := time.Now()
		switch *arg.Status {
		case sqlc.RouteStatusInProgress:
			if r.salida == nil { // sólo la PRIMERA vez que arranca
				r.salida = &ahora
			}
			r.regreso = nil
		case sqlc.RouteStatusCompleted:
			r.regreso = &ahora
		}
	}
	return sqlc.ActualizarEstadoDeRutaRow{ID: r.id, Status: r.estado, VehicleID: pgOpcionalDeRutas(r.vehiculo)}, nil
}

func (d *dobleDeRutas) CambiarVehiculoDeRuta(_ context.Context, arg sqlc.CambiarVehiculoDeRutaParams) (sqlc.CambiarVehiculoDeRutaRow, error) {
	r, hay := d.rutas[arg.ID]
	if !hay || !alcanza(arg.Sucursal, r.sucursal) {
		return sqlc.CambiarVehiculoDeRutaRow{}, pgx.ErrNoRows
	}
	if arg.VehicleID.Valid {
		v := uuid.UUID(arg.VehicleID.Bytes)
		r.vehiculo = &v
	} else {
		r.vehiculo = nil
	}
	if arg.Name != nil {
		r.nombre = arg.Name
	}
	if arg.Status != nil {
		r.estado = *arg.Status
	}
	return sqlc.CambiarVehiculoDeRutaRow{ID: r.id, Status: r.estado, VehicleID: arg.VehicleID}, nil
}

func (d *dobleDeRutas) CambiarEstadoDeVehiculo(_ context.Context, arg sqlc.CambiarEstadoDeVehiculoParams) (int64, error) {
	v, hay := d.camiones[arg.ID]
	if !hay || !alcanzaCamion(arg.Sucursal, v.sucursal) {
		return 0, nil
	}
	v.estado = arg.Status
	return 1, nil
}

func (d *dobleDeRutas) ObtenerVehiculoParaCapacidad(_ context.Context, id uuid.UUID) (sqlc.ObtenerVehiculoParaCapacidadRow, error) {
	v, hay := d.camiones[id]
	if !hay {
		return sqlc.ObtenerVehiculoParaCapacidadRow{}, pgx.ErrNoRows
	}
	return sqlc.ObtenerVehiculoParaCapacidadRow{
		ID: v.id, Name: v.nombre, Capacity: v.capacidad, Status: v.estado,
		BranchID: pgOpcionalDeRutas(v.sucursal),
	}, nil
}

func (d *dobleDeRutas) ObtenerVehiculo(_ context.Context, arg sqlc.ObtenerVehiculoParams) (sqlc.ObtenerVehiculoRow, error) {
	v, hay := d.camiones[arg.ID]
	if !hay || !alcanzaCamion(arg.Sucursal, v.sucursal) {
		return sqlc.ObtenerVehiculoRow{}, pgx.ErrNoRows
	}
	return sqlc.ObtenerVehiculoRow{ID: v.id, Name: v.nombre, Capacity: v.capacidad, Status: v.estado}, nil
}

// MarcarResultadoDeParada: la consulta más delicada del reparto, copiada tal cual.
func (d *dobleDeRutas) MarcarResultadoDeParada(_ context.Context, arg sqlc.MarcarResultadoDeParadaParams) (int64, error) {
	p, hay := d.pedidos[arg.PedidoID]
	if !hay || p.ultimaRuta == nil || [16]byte(*p.ultimaRuta) != arg.RutaID.Bytes {
		return 0, nil
	}
	if !alcanza(arg.Sucursal, &p.sucursal) {
		return 0, nil
	}
	ahora := time.Now()
	p.resultado = &arg.Resultado
	p.resultadoAt = &ahora
	p.nota = arg.Nota
	if arg.Resultado == sqlc.StopResultEntregado {
		p.entregadoEn = &ahora
		p.estado = sqlc.OrderStatusDelivered
	} else {
		p.entregadoEn = nil
		p.estado = sqlc.OrderStatusPending
		p.rutaID = nil // baja del camión; `ultima_ruta_id` y `stop_order` NO se tocan
	}
	return 1, nil
}

func (d *dobleDeRutas) SoltarPedidosDeRuta(_ context.Context, arg sqlc.SoltarPedidosDeRutaParams) (int64, error) {
	var n int64
	for _, p := range d.pedidos {
		if p.rutaID == nil || [16]byte(*p.rutaID) != arg.RutaID.Bytes || !alcanza(arg.Sucursal, &p.sucursal) {
			continue
		}
		p.rutaID = nil
		p.stopOrder = nil
		p.segmentKm = nil
		p.tramo = sqlc.TripLegOutbound
		n++
	}
	return n, nil
}

func (d *dobleDeRutas) BorrarRuta(_ context.Context, arg sqlc.BorrarRutaParams) (int64, error) {
	r, hay := d.rutas[arg.ID]
	if !hay || !alcanza(arg.Sucursal, r.sucursal) {
		return 0, nil
	}
	delete(d.rutas, arg.ID)
	return 1, nil
}

// --------------------------------------------------------------------------- la fuente

// fuenteDeRutas da acceso al doble y, sobre todo, HACE DE VERDAD LA TRANSACCIÓN: guarda
// una copia antes y la restaura si la función devuelve error. Sin eso, «a medias no vale»
// sería una frase del comentario y no algo comprobado.
type fuenteDeRutas struct{ q *dobleDeRutas }

func (f fuenteDeRutas) Consultas() sqlc.Querier { return f.q }

func (f fuenteDeRutas) EnTx(_ context.Context, fn func(sqlc.Querier) error) error {
	copia := f.q.clonar()
	if err := fn(f.q); err != nil {
		f.q.restaurar(copia)
		return err
	}
	return nil
}

type fotoDeRutas struct {
	pedidos  map[uuid.UUID]pedidoDeRutas
	rutas    map[uuid.UUID]rutaDeRutas
	camiones map[uuid.UUID]camionDeRutas
}

func (d *dobleDeRutas) clonar() fotoDeRutas {
	foto := fotoDeRutas{
		pedidos:  map[uuid.UUID]pedidoDeRutas{},
		rutas:    map[uuid.UUID]rutaDeRutas{},
		camiones: map[uuid.UUID]camionDeRutas{},
	}
	for id, p := range d.pedidos {
		foto.pedidos[id] = *p
	}
	for id, r := range d.rutas {
		foto.rutas[id] = *r
	}
	for id, v := range d.camiones {
		foto.camiones[id] = *v
	}
	return foto
}

func (d *dobleDeRutas) restaurar(foto fotoDeRutas) {
	d.pedidos = map[uuid.UUID]*pedidoDeRutas{}
	d.rutas = map[uuid.UUID]*rutaDeRutas{}
	d.camiones = map[uuid.UUID]*camionDeRutas{}
	for id, p := range foto.pedidos {
		copia := p
		d.pedidos[id] = &copia
	}
	for id, r := range foto.rutas {
		copia := r
		d.rutas[id] = &copia
	}
	for id, v := range foto.camiones {
		copia := v
		d.camiones[id] = &copia
	}
}

// --------------------------------------------------------------------------- el montaje

func montarRutas(t *testing.T, q *dobleDeRutas) http.Handler {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoDeRutas)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	reg := slog.New(slog.NewTextHandler(io.Discard, nil))
	porteria := alcance.NuevaPorteria(fuenteDeRutas{q: q}, reg)
	verif := auth.NuevoVerificador([]byte(secretoDeRutas))
	s := NuevoServidor(cfg, reg, porteria, verif, func(context.Context) error { return nil })

	rt := httpx.NuevoRouter(httpx.IDDePeticion, httpx.ConRegistro(reg), httpx.RecuperarPanico, httpx.SinCache)
	sesion := []httpx.Medio{verif.Exigir, porteria.Exigir}
	admin := []httpx.Medio{verif.Exigir, auth.ExigirAdmin, porteria.Exigir}
	s.rutasDeReparto(rt, sesion, admin)
	return rt.Handler()
}

// --------------------------------------------------------------------------- utilidades

func pgDeRutas(id uuid.UUID) pgtype.UUID { return pgtype.UUID{Bytes: [16]byte(id), Valid: true} }

func pgOpcionalDeRutas(id *uuid.UUID) pgtype.UUID {
	if id == nil {
		return pgtype.UUID{}
	}
	return pgDeRutas(*id)
}

func horaOpcionalDeRutas(t *time.Time) pgtype.Timestamptz {
	if t == nil {
		return pgtype.Timestamptz{}
	}
	return pgtype.Timestamptz{Time: *t, Valid: true}
}

func enLista(ids []uuid.UUID, id uuid.UUID) bool {
	for _, x := range ids {
		if x == id {
			return true
		}
	}
	return false
}

// ordenarPorParada repite el `ORDER BY stop_order ASC NULLS LAST` del SQL.
func ordenarPorParada(filas []sqlc.ListarParadasDeRutasRow) {
	for i := 1; i < len(filas); i++ {
		for j := i; j > 0 && menorParada(filas[j], filas[j-1]); j-- {
			filas[j], filas[j-1] = filas[j-1], filas[j]
		}
	}
}

func menorParada(a, b sqlc.ListarParadasDeRutasRow) bool {
	switch {
	case a.StopOrder == nil:
		return false
	case b.StopOrder == nil:
		return true
	}
	return *a.StopOrder < *b.StopOrder
}

func tokenDeRutas(t *testing.T, reclamos map[string]any) string {
	t.Helper()
	if _, hay := reclamos["exp"]; !hay {
		reclamos["exp"] = time.Now().Add(time.Hour).Unix()
	}
	cab := b64DeRutas(t, map[string]any{"alg": "HS256", "typ": "JWT"})
	cuerpo := b64DeRutas(t, reclamos)
	mac := hmac.New(sha256.New, []byte(secretoDeRutas))
	mac.Write([]byte(cab + "." + cuerpo))
	return cab + "." + cuerpo + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func b64DeRutas(t *testing.T, v any) string {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

func deSantiagoEnRutas(t *testing.T) string {
	return tokenDeRutas(t, map[string]any{"sub": "p-stg", "email": "stg@procovar.cu",
		"role": "OPERADOR", "branchId": stgDeRutas.String()})
}

func superAdminEnRutas(t *testing.T) string {
	return tokenDeRutas(t, map[string]any{"sub": "p-sa", "role": "SUPER ADMIN"})
}

func llamarRutas(t *testing.T, h http.Handler, metodo, ruta, jwt, cuerpo string) *httptest.ResponseRecorder {
	t.Helper()
	var cuerpoLector io.Reader
	if cuerpo != "" {
		cuerpoLector = strings.NewReader(cuerpo)
	}
	r := httptest.NewRequest(metodo, ruta, cuerpoLector)
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

func errorDeRutas(t *testing.T, w *httptest.ResponseRecorder) string {
	t.Helper()
	var cuerpo struct {
		Error string `json:"error"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &cuerpo); err != nil {
		t.Fatalf("respuesta ilegible (%d): %s", w.Code, w.Body.String())
	}
	return cuerpo.Error
}

// --------------------------------------------------------------------------- los datos

func textoDeRutas(s string) *string { return &s }

func decimalDeRutas(v float64) *float64 { return &v }

// datosDeReparto deja tres pedidos de Santiago listos para armar y uno de Holguín, con un
// camión en cada sucursal. Las coordenadas están elegidas para que el orden por cercanía
// NO sea el orden en que se leen: así el greedy se nota.
func datosDeReparto() (*dobleDeRutas, [3]uuid.UUID, uuid.UUID) {
	fuente := sqlc.ProcedenciaPedido
	igual := sqlc.FacturaEstadoIgual

	lejos := uuid.MustParse("cccccccc-0000-0000-0000-000000000001")
	cerca := uuid.MustParse("cccccccc-0000-0000-0000-000000000002")
	medio := uuid.MustParse("cccccccc-0000-0000-0000-000000000003")
	ajeno := uuid.MustParse("dddddddd-0000-0000-0000-000000000004")

	nuevo := func(id uuid.UUID, nombre string, lat, lng, peso float64, sucursal uuid.UUID, ext string) *pedidoDeRutas {
		return &pedidoDeRutas{
			id: id, cliente: nombre, operacion: textoDeRutas("X-" + nombre),
			endLat: decimalDeRutas(lat), endLng: decimalDeRutas(lng), peso: peso,
			costo: decimalDeRutas(10), factura: &igual, sucursal: sucursal,
			externalID: textoDeRutas(ext), fuente: &fuente, estado: sqlc.OrderStatusPending,
			tramo: sqlc.TripLegOutbound,
			renglones: []sqlc.OrderItem{
				{Linea: 1, Description: "Ron " + nombre, Quantity: 6, Packs: decimalDeRutas(1)},
			},
		}
	}

	d := &dobleDeRutas{
		pedidos: map[uuid.UUID]*pedidoDeRutas{
			lejos: nuevo(lejos, "Lejos", 0, 0.30, 40, stgDeRutas, "PED-1"),
			cerca: nuevo(cerca, "Cerca", 0, 0.05, 30, stgDeRutas, "PED-2"),
			medio: nuevo(medio, "Medio", 0, 0.15, 30, stgDeRutas, "PED-3"),
			ajeno: nuevo(ajeno, "Ajeno", 0, 0.10, 10, holDeRutas, "PED-4"),
		},
		rutas: map[uuid.UUID]*rutaDeRutas{},
		camiones: map[uuid.UUID]*camionDeRutas{
			camionStg: {id: camionStg, nombre: "Camión de Santiago", capacidad: 100,
				estado: sqlc.VehicleStatusAvailable, sucursal: &stgDeRutas},
			camionHol: {id: camionHol, nombre: "Camión de Holguín", capacidad: 500,
				estado: sqlc.VehicleStatusAvailable, sucursal: &holDeRutas},
		},
	}
	return d, [3]uuid.UUID{lejos, cerca, medio}, ajeno
}

// cuerpoDeArmado arma el JSON del POST con el origen en (0,0).
func cuerpoDeArmado(vehiculo string, pedidos ...uuid.UUID) string {
	ids := make([]string, 0, len(pedidos))
	for _, id := range pedidos {
		ids = append(ids, `"`+id.String()+`"`)
	}
	return fmt.Sprintf(`{"name":"Reparto de la mañana","vehicleId":%q,"originLat":0,"originLng":0,"orderIds":[%s]}`,
		vehiculo, strings.Join(ids, ","))
}

// armarRutaDePrueba deja una ruta creada y devuelve su id.
func armarRutaDePrueba(t *testing.T, h http.Handler, jwt string, pedidos ...uuid.UUID) uuid.UUID {
	t.Helper()
	w := llamarRutas(t, h, http.MethodPost, "/api/routes", jwt, cuerpoDeArmado(camionStg.String(), pedidos...))
	if w.Code != http.StatusCreated {
		t.Fatalf("no se pudo armar la ruta (%d): %s", w.Code, w.Body.String())
	}
	var ruta RutaSalida
	if err := json.Unmarshal(w.Body.Bytes(), &ruta); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	return ruta.ID
}

// ---------------------------------------------------------------------------
// Geometría
// ---------------------------------------------------------------------------

func TestHaversineDaLosKilometrosDeSiempre(t *testing.T) {
	// Un grado de latitud en el ecuador son ~111,19 km con R = 6371.
	km := haversineKm(0, 0, 1, 0)
	if math.Abs(km-111.19) > 0.05 {
		t.Fatalf("un grado de latitud dio %.3f km", km)
	}
	if km := haversineKm(20.0, -75.8, 20.0, -75.8); km != 0 {
		t.Fatalf("el mismo punto no puede distar %v km", km)
	}
}

func TestElOrdenDeVisitaEsElVecinoMasProximo(t *testing.T) {
	a := uuid.New()
	b := uuid.New()
	c := uuid.New()
	// Se dan de lejos a cerca: si el orden saliera igual que la lista, no habría greedy.
	orden := ordenVecinoMasProximo(0, 0, []paradaGeo{
		{id: a, lat: 0, lng: 0.30},
		{id: b, lat: 0, lng: 0.05},
		{id: c, lat: 0, lng: 0.15},
	})
	if len(orden) != 3 || orden[0] != b || orden[1] != c || orden[2] != a {
		t.Fatalf("el camión no fue por cercanía: %v", orden)
	}
}

// El desempate lo gana el PRIMERO de la lista. Con dos clientes en el mismo edificio —que
// los hay— un `<=` daría un orden distinto cada vez que cambie la lectura de la base.
func TestEnUnEmpateGanaElPrimeroDeLaLista(t *testing.T) {
	primero := uuid.New()
	segundo := uuid.New()
	orden := ordenVecinoMasProximo(0, 0, []paradaGeo{
		{id: primero, lat: 0, lng: 0.10},
		{id: segundo, lat: 0, lng: -0.10},
	})
	if orden[0] != primero {
		t.Fatal("con la misma distancia tiene que ganar el primero de la lista")
	}
}

func TestSinParadasNoHayOrden(t *testing.T) {
	if orden := ordenVecinoMasProximo(0, 0, nil); len(orden) != 0 {
		t.Fatalf("sin paradas el orden es vacío, y salió %v", orden)
	}
	uno := uuid.New()
	orden := ordenVecinoMasProximo(10, 10, []paradaGeo{{id: uno, lat: 0, lng: 0}})
	if len(orden) != 1 || orden[0] != uno {
		t.Fatalf("con una parada el orden es esa parada: %v", orden)
	}
}

// ---------------------------------------------------------------------------
// POST /api/routes — el armado
// ---------------------------------------------------------------------------

// LA PRUEBA DEL ARMADO: los cuatro campos que se escriben en cada pedido y el orden.
func TestArmarRutaEnganchaLosPedidosConSusCuatroCampos(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	lejos, cerca, medio := stg[0], stg[1], stg[2]

	w := llamarRutas(t, h, http.MethodPost, "/api/routes", deSantiagoEnRutas(t),
		cuerpoDeArmado(camionStg.String(), lejos, cerca, medio))
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}

	var ruta RutaSalida
	if err := json.Unmarshal(w.Body.Bytes(), &ruta); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	if ruta.RouteCode == nil || !strings.HasPrefix(*ruta.RouteCode, "RT-") || !strings.HasSuffix(*ruta.RouteCode, "-001") {
		t.Fatalf("el código de ruta no es RT-AAAAMMDD-001: %v", ruta.RouteCode)
	}
	if ruta.Status != string(sqlc.RouteStatusPlanned) {
		t.Fatalf("una ruta recién armada nace planned, y nació %q", ruta.Status)
	}

	// El orden de visita: de los tres, primero el más cercano al origen.
	esperado := map[uuid.UUID]int32{cerca: 1, medio: 2, lejos: 3}
	for id, posicion := range esperado {
		p := d.pedidos[id]
		if p.rutaID == nil || *p.rutaID != ruta.ID {
			t.Fatalf("%s no quedó enganchado a la ruta", p.cliente)
		}
		if p.ultimaRuta == nil || *p.ultimaRuta != ruta.ID {
			t.Fatalf("%s no guardó en qué camión viajó", p.cliente)
		}
		if p.stopOrder == nil || *p.stopOrder != posicion {
			t.Fatalf("%s tenía que ser la parada %d y fue %v", p.cliente, posicion, p.stopOrder)
		}
		if p.tramo != sqlc.TripLegOutbound {
			t.Fatalf("%s no salió como ida", p.cliente)
		}
		// `segmentKm` es la distancia RADIAL desde el almacén a ese cliente, no el tramo
		// del recorrido: es la medida con la que se cobra el domicilio.
		radial := haversineKm(0, 0, *p.endLat, *p.endLng)
		if p.segmentKm == nil || math.Abs(*p.segmentKm-radial) > 0.0001 {
			t.Fatalf("%s: segmentKm tiene que ser la distancia desde el almacén (%.3f) y fue %v",
				p.cliente, radial, p.segmentKm)
		}
	}

	// Los km de la ruta son el CIRCUITO CERRADO: ida por las tres y vuelta al almacén.
	esperadaKm := haversineKm(0, 0, 0, 0.05) + haversineKm(0, 0.05, 0, 0.15) +
		haversineKm(0, 0.15, 0, 0.30) + haversineKm(0, 0.30, 0, 0)
	guardada := d.rutas[ruta.ID]
	if math.Abs(guardada.km-esperadaKm) > 0.0001 {
		t.Fatalf("los km de la ruta no cuentan la vuelta: %.4f en vez de %.4f", guardada.km, esperadaKm)
	}
	if guardada.peso != 100 {
		t.Fatalf("el peso total salió %v", guardada.peso)
	}
	if guardada.precio != 30 {
		t.Fatalf("el precio total es la suma de los pedidoCosto, y salió %v", guardada.precio)
	}
	if !guardada.optimized {
		t.Fatal("la ruta armada tiene que quedar marcada como optimizada")
	}
	// `price` se COPIA de `pedidoCosto`: aquí no se calcula ningún precio.
	if p := d.pedidos[cerca]; p.precio == nil || *p.precio != 10 {
		t.Fatalf("el precio del pedido no se copió de pedidoCosto: %v", p.precio)
	}
}

// El camión NO se ocupa al armar: entre que se arma la ruta de mañana y sale, el camión
// sigue disponible. Marcarlo aquí impedía armar la ruta mientras el camión está fuera.
func TestArmarRutaNoOcupaElCamion(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	armarRutaDePrueba(t, h, deSantiagoEnRutas(t), stg[1])
	if d.camiones[camionStg].estado != sqlc.VehicleStatusAvailable {
		t.Fatal("armar la ruta ocupó el camión, y sólo lo ocupa despacharla")
	}
}

func TestArmarRutaValidaEnElOrdenDelPliego(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)

	casos := []struct {
		nombre  string
		cuerpo  string
		codigo  int
		mensaje string
	}{
		{"sin coordenadas", `{"vehicleId":"x","orderIds":["y"]}`, http.StatusBadRequest, msgFaltanCoordenadas},
		{"sin camión", fmt.Sprintf(`{"originLat":0,"originLng":0,"orderIds":[%q]}`, stg[0]),
			http.StatusBadRequest, msgFaltaVehiculo},
		{"sin pedidos", fmt.Sprintf(`{"originLat":0,"originLng":0,"vehicleId":%q,"orderIds":[]}`, camionStg),
			http.StatusBadRequest, msgSinPedidos},
		{"orderIds que no es lista", fmt.Sprintf(`{"originLat":0,"originLng":0,"vehicleId":%q,"orderIds":"uno"}`, camionStg),
			http.StatusBadRequest, msgSinPedidos},
	}
	for _, c := range casos {
		w := llamarRutas(t, h, http.MethodPost, "/api/routes", jwt, c.cuerpo)
		if w.Code != c.codigo {
			t.Fatalf("%s: código %d (%s)", c.nombre, w.Code, w.Body.String())
		}
		if got := errorDeRutas(t, w); got != c.mensaje {
			t.Fatalf("%s: mensaje %q, se esperaba %q", c.nombre, got, c.mensaje)
		}
	}
	// El cero es una coordenada válida: lo que se rechaza es la ausencia.
	w := llamarRutas(t, h, http.MethodPost, "/api/routes", jwt, cuerpoDeArmado(camionStg.String(), stg[0]))
	if w.Code != http.StatusCreated {
		t.Fatalf("el origen (0,0) tiene que valer: %d %s", w.Code, w.Body.String())
	}
	_ = d
}

// EL MENSAJE LITERAL, que es lo que ve el logístico cuando otro se le adelantó.
func TestArmarRutaDiceCuantosPedidosYaEstanEnOtraRuta(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)

	armarRutaDePrueba(t, h, jwt, stg[1]) // «Cerca» se va en la primera ruta

	w := llamarRutas(t, h, http.MethodPost, "/api/routes", jwt,
		cuerpoDeArmado(camionStg.String(), stg[0], stg[1], stg[2]))
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	const literal = "1 de los 3 pedidos ya están en otra ruta. Vuelve a elegirlos."
	if got := errorDeRutas(t, w); got != literal {
		t.Fatalf("el literal del pliego es %q y salió %q", literal, got)
	}
	// Y no se creó nada a medias: sigue habiendo UNA ruta.
	if len(d.rutas) != 1 {
		t.Fatalf("el rechazo dejó %d rutas", len(d.rutas))
	}
}

func TestArmarRutaConTodosOcupadosDiceQueNoEstanDisponibles(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	armarRutaDePrueba(t, h, jwt, stg[1])

	w := llamarRutas(t, h, http.MethodPost, "/api/routes", jwt, cuerpoDeArmado(camionStg.String(), stg[1]))
	if w.Code != http.StatusBadRequest || errorDeRutas(t, w) != msgPedidosNoDisponibles {
		t.Fatalf("código %d, mensaje %q", w.Code, errorDeRutas(t, w))
	}
}

// En un camión sólo sube lo facturado y que cuadre, y se dice CUÁL falla y por qué: un
// «no se pudo» a secas obliga a adivinar cuál de los quince pedidos sobra.
func TestArmarRutaSoloEntraLoFacturadoYDiceCualFalla(t *testing.T) {
	d, stg, _ := datosDeReparto()
	cambiado := sqlc.FacturaEstadoCambiado
	d.pedidos[stg[0]].factura = &cambiado
	d.pedidos[stg[1]].factura = nil // sin cotejar
	h := montarRutas(t, d)

	w := llamarRutas(t, h, http.MethodPost, "/api/routes", deSantiagoEnRutas(t),
		cuerpoDeArmado(camionStg.String(), stg[0], stg[1], stg[2]))
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	mensaje := errorDeRutas(t, w)
	const esperado = "En una ruta sólo entra lo facturado y que cuadre. 2 no cumplen: " +
		"X-Lejos (cambió en la factura), X-Cerca (sin cotejar)."
	if mensaje != esperado {
		t.Fatalf("mensaje:\n  %q\nse esperaba:\n  %q", mensaje, esperado)
	}
	if len(d.rutas) != 0 {
		t.Fatal("se armó la ruta a pesar del rechazo")
	}
}

func TestArmarRutaConMasDeCincoSinFacturaCuentaElResto(t *testing.T) {
	d, _, _ := datosDeReparto()
	sinFactura := sqlc.FacturaEstadoSinFactura
	fuente := sqlc.ProcedenciaPedido
	var ids []uuid.UUID
	for i := 0; i < 7; i++ {
		id := uuid.New()
		d.pedidos[id] = &pedidoDeRutas{
			id: id, cliente: fmt.Sprintf("Cliente %d", i), endLat: decimalDeRutas(0), endLng: decimalDeRutas(float64(i) / 100),
			factura: &sinFactura, sucursal: stgDeRutas, fuente: &fuente,
		}
		ids = append(ids, id)
	}
	h := montarRutas(t, d)
	w := llamarRutas(t, h, http.MethodPost, "/api/routes", deSantiagoEnRutas(t),
		cuerpoDeArmado(camionStg.String(), ids...))
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d", w.Code)
	}
	mensaje := errorDeRutas(t, w)
	if !strings.HasPrefix(mensaje, "En una ruta sólo entra lo facturado y que cuadre. 7 no cumplen: ") {
		t.Fatalf("mensaje %q", mensaje)
	}
	if !strings.HasSuffix(mensaje, " y 2 más.") {
		t.Fatalf("no cuenta los que no nombra: %q", mensaje)
	}
	if n := strings.Count(mensaje, "(sin facturar)"); n != 5 {
		t.Fatalf("tiene que nombrar a CINCO y nombró a %d", n)
	}
}

// Igualar la capacidad exacta SÍ pasa; un gramo más, no. Y el mensaje lleva el peso con un
// decimal y la capacidad sin formatear.
func TestArmarRutaCapacidadExactaPasaYPasarseNo(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)

	// 40 + 30 + 30 = 100, que es justo la capacidad del camión de Santiago.
	w := llamarRutas(t, h, http.MethodPost, "/api/routes", jwt,
		cuerpoDeArmado(camionStg.String(), stg[0], stg[1], stg[2]))
	if w.Code != http.StatusCreated {
		t.Fatalf("igualar la capacidad tiene que pasar: %d %s", w.Code, w.Body.String())
	}

	// Y ahora uno más de la cuenta.
	d2, stg2, _ := datosDeReparto()
	d2.pedidos[stg2[0]].peso = 40.5
	h2 := montarRutas(t, d2)
	w = llamarRutas(t, h2, http.MethodPost, "/api/routes", jwt,
		cuerpoDeArmado(camionStg.String(), stg2[0], stg2[1], stg2[2]))
	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	const esperado = "Peso total (100.5 kg) supera la capacidad del vehículo (100 kg)"
	if got := errorDeRutas(t, w); got != esperado {
		t.Fatalf("mensaje %q, se esperaba %q", got, esperado)
	}
}

// Si el camión no existe, la ruta se arma igual y SIN camión: guardar un id que no está en
// `vehicles` reventaría contra la clave ajena con un 500 sin explicación.
func TestArmarRutaConUnCamionQueNoExisteNoValidaCapacidadYSeArmaSinEl(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	w := llamarRutas(t, h, http.MethodPost, "/api/routes", deSantiagoEnRutas(t),
		cuerpoDeArmado(uuid.New().String(), stg[0], stg[1], stg[2]))
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var ruta RutaSalida
	_ = json.Unmarshal(w.Body.Bytes(), &ruta)
	if ruta.VehicleID != nil {
		t.Fatalf("la ruta se quedó con un camión que no existe: %v", ruta.VehicleID)
	}
}

// EL ALCANCE, en el armado: los ids de otra sucursal no suben a tu camión.
func TestArmarRutaNoCogePedidosDeOtraSucursal(t *testing.T) {
	d, stg, ajeno := datosDeReparto()
	h := montarRutas(t, d)

	w := llamarRutas(t, h, http.MethodPost, "/api/routes", deSantiagoEnRutas(t),
		cuerpoDeArmado(camionStg.String(), stg[1], ajeno))
	if w.Code != http.StatusConflict {
		t.Fatalf("el pedido de Holguín tenía que faltar: %d %s", w.Code, w.Body.String())
	}
	if got := errorDeRutas(t, w); got != "1 de los 2 pedidos ya están en otra ruta. Vuelve a elegirlos." {
		t.Fatalf("mensaje %q", got)
	}
	if d.pedidos[ajeno].rutaID != nil {
		t.Fatal("el pedido de Holguín acabó en un camión de Santiago")
	}
}

// El Super Admin dice la sucursal en el asistente; quien tiene alcance no puede pasarla.
func TestLaSucursalDelCuerpoSoloValeParaElSuperAdmin(t *testing.T) {
	d, _, ajeno := datosDeReparto()
	h := montarRutas(t, d)

	// Super Admin eligiendo Holguín: coge el de Holguín y la ruta nace de Holguín.
	cuerpo := fmt.Sprintf(`{"vehicleId":%q,"originLat":0,"originLng":0,"branchId":%q,"orderIds":[%q]}`,
		camionHol, holDeRutas, ajeno)
	w := llamarRutas(t, h, http.MethodPost, "/api/routes", superAdminEnRutas(t), cuerpo)
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var ruta RutaSalida
	_ = json.Unmarshal(w.Body.Bytes(), &ruta)
	if ruta.BranchID == nil || *ruta.BranchID != holDeRutas {
		t.Fatalf("la ruta no nació en Holguín: %v", ruta.BranchID)
	}

	// El mismo cuerpo desde Santiago: su alcance manda y el pedido de Holguín no está.
	d2, _, ajeno2 := datosDeReparto()
	h2 := montarRutas(t, d2)
	cuerpo = fmt.Sprintf(`{"vehicleId":%q,"originLat":0,"originLng":0,"branchId":%q,"orderIds":[%q]}`,
		camionStg, holDeRutas, ajeno2)
	w = llamarRutas(t, h2, http.MethodPost, "/api/routes", deSantiagoEnRutas(t), cuerpo)
	if w.Code != http.StatusBadRequest || errorDeRutas(t, w) != msgPedidosNoDisponibles {
		t.Fatalf("Santiago se llevó un pedido de Holguín pasando branchId: %d %s", w.Code, w.Body.String())
	}
}

// ---------------------------------------------------------------------------
// GET /api/routes y /api/routes/{id}
// ---------------------------------------------------------------------------

func TestLaRutaSaleConSuSucursalSuCamionYSusParadas(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[0], stg[1], stg[2])

	w := llamarRutas(t, h, http.MethodGet, "/api/routes/"+id.String(), jwt, "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var ruta RutaSalida
	if err := json.Unmarshal(w.Body.Bytes(), &ruta); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	if ruta.Branch == nil || ruta.Branch.ID != stgDeRutas {
		t.Fatal("falta la sucursal: sin ella el Super Admin ve ocho listas mezcladas")
	}
	if ruta.Vehicle == nil || ruta.Vehicle.ID != camionStg {
		t.Fatal("falta el camión de la ruta")
	}
	if len(ruta.Orders) != 3 {
		t.Fatalf("la ruta tiene 3 paradas y salieron %d", len(ruta.Orders))
	}
	if ruta.Orders[0].CustomerName != "Cerca" {
		t.Fatalf("las paradas no salen por orden de visita: %s", ruta.Orders[0].CustomerName)
	}
	if len(ruta.Orders[0].Items) != 1 {
		t.Fatalf("la parada tiene que traer sus renglones: %+v", ruta.Orders[0].Items)
	}

	// Y la lista, con lo mismo dentro.
	w = llamarRutas(t, h, http.MethodGet, "/api/routes", jwt, "")
	var lista []RutaSalida
	if err := json.Unmarshal(w.Body.Bytes(), &lista); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	if len(lista) != 1 || len(lista[0].Orders) != 3 {
		t.Fatalf("la lista no trae las paradas: %s", w.Body.String())
	}
}

func TestUnaRutaDeOtraSucursalNoExisteParaTi(t *testing.T) {
	d, _, ajeno := datosDeReparto()
	h := montarRutas(t, d)
	// La arma el Super Admin para Holguín.
	cuerpo := fmt.Sprintf(`{"vehicleId":%q,"originLat":0,"originLng":0,"branchId":%q,"orderIds":[%q]}`,
		camionHol, holDeRutas, ajeno)
	w := llamarRutas(t, h, http.MethodPost, "/api/routes", superAdminEnRutas(t), cuerpo)
	var ruta RutaSalida
	_ = json.Unmarshal(w.Body.Bytes(), &ruta)

	jwt := deSantiagoEnRutas(t)
	for _, caso := range []struct{ metodo, ruta, cuerpo, mensaje string }{
		{http.MethodGet, "/api/routes/" + ruta.ID.String(), "", httpx.MsgNoEncontrado},
		{http.MethodPatch, "/api/routes/" + ruta.ID.String(), `{"status":"in_progress"}`, httpx.MsgNoEncontrado},
		{http.MethodDelete, "/api/routes/" + ruta.ID.String(), "", httpx.MsgNoEncontrado},
		{http.MethodPost, "/api/routes/" + ruta.ID.String() + "/results",
			`{"resultados":[{"orderId":"` + ajeno.String() + `","resultado":"entregado"}]}`, msgRutaNoEncontrada},
	} {
		w := llamarRutas(t, jwt2handler(h), caso.metodo, caso.ruta, jwt, caso.cuerpo)
		if w.Code != http.StatusNotFound {
			t.Fatalf("%s %s: código %d", caso.metodo, caso.ruta, w.Code)
		}
		if got := errorDeRutas(t, w); got != caso.mensaje {
			t.Fatalf("%s: mensaje %q, se esperaba %q", caso.metodo, got, caso.mensaje)
		}
	}
	// Y el pedido de Holguín sigue en su ruta.
	if d.pedidos[ajeno].rutaID == nil {
		t.Fatal("Santiago consiguió tocar un pedido de Holguín")
	}
}

// jwt2handler existe sólo para que el bucle de arriba se lea; devuelve el mismo handler.
func jwt2handler(h http.Handler) http.Handler { return h }

// ---------------------------------------------------------------------------
// PATCH /api/routes/{id}
// ---------------------------------------------------------------------------

// Despachar OCUPA el camión; completarla lo LIBERA.
func TestDespacharOcupaElCamionYCompletarLoLibera(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1])

	w := llamarRutas(t, h, http.MethodPatch, "/api/routes/"+id.String(), jwt, `{"status":"in_progress"}`)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if d.camiones[camionStg].estado != sqlc.VehicleStatusInUse {
		t.Fatal("la ruta salió y el camión sigue disponible")
	}
	if d.rutas[id].salida == nil {
		t.Fatal("no se apuntó la hora de salida")
	}
	salida := *d.rutas[id].salida

	// Volver a marcarla en curso NO reescribe la hora de salida: es con la que se mide
	// cuánto se demoró.
	llamarRutas(t, h, http.MethodPatch, "/api/routes/"+id.String(), jwt, `{"status":"in_progress"}`)
	if !d.rutas[id].salida.Equal(salida) {
		t.Fatal("una corrección reescribió la hora de salida")
	}

	w = llamarRutas(t, h, http.MethodPatch, "/api/routes/"+id.String(), jwt, `{"status":"completed"}`)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if d.camiones[camionStg].estado != sqlc.VehicleStatusAvailable {
		t.Fatal("la ruta se completó y el camión sigue ocupado")
	}
	if d.rutas[id].regreso == nil {
		t.Fatal("no se apuntó la hora de regreso")
	}
}

func TestCambiarDeCamionLiberaElViejoYOcupaElNuevo(t *testing.T) {
	d, stg, _ := datosDeReparto()
	// Un camión compartido, de los de `branch_id` NULL.
	compartido := uuid.New()
	d.camiones[compartido] = &camionDeRutas{id: compartido, nombre: "Camión de todas",
		capacidad: 1000, estado: sqlc.VehicleStatusAvailable}
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1])
	llamarRutas(t, h, http.MethodPatch, "/api/routes/"+id.String(), jwt, `{"status":"in_progress"}`)

	w := llamarRutas(t, h, http.MethodPatch, "/api/routes/"+id.String(), jwt,
		fmt.Sprintf(`{"vehicleId":%q}`, compartido))
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if d.camiones[camionStg].estado != sqlc.VehicleStatusAvailable {
		t.Fatal("el camión viejo se quedó ocupado")
	}
	if d.camiones[compartido].estado != sqlc.VehicleStatusInUse {
		t.Fatal("el camión nuevo no quedó ocupado")
	}
	if d.rutas[id].vehiculo == nil || *d.rutas[id].vehiculo != compartido {
		t.Fatal("la ruta no cambió de camión")
	}
}

func TestNoSePuedeEngancharElCamionDeOtraSucursal(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1])

	w := llamarRutas(t, h, http.MethodPatch, "/api/routes/"+id.String(), jwt,
		fmt.Sprintf(`{"vehicleId":%q}`, camionHol))
	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if d.camiones[camionHol].estado != sqlc.VehicleStatusAvailable {
		t.Fatal("se ocupó un camión de Holguín desde Santiago")
	}
}

func TestUnEstadoDeRutaInventadoEs400YNoUn500(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1])

	w := llamarRutas(t, h, http.MethodPatch, "/api/routes/"+id.String(), jwt, `{"status":"despachadisima"}`)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(errorDeRutas(t, w), "despachadisima") {
		t.Fatalf("el mensaje no dice qué estado llegó: %q", errorDeRutas(t, w))
	}
}

// ---------------------------------------------------------------------------
// DELETE /api/routes/{id}
// ---------------------------------------------------------------------------

func TestBorrarLaRutaSueltaLosPedidosPeroNoSuPasado(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[0], stg[1])
	llamarRutas(t, h, http.MethodPatch, "/api/routes/"+id.String(), jwt, `{"status":"in_progress"}`)

	w := llamarRutas(t, h, http.MethodDelete, "/api/routes/"+id.String(), jwt, "")
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if _, sigue := d.rutas[id]; sigue {
		t.Fatal("la ruta no se borró")
	}
	if d.camiones[camionStg].estado != sqlc.VehicleStatusAvailable {
		t.Fatal("borrar la ruta dejó el camión ocupado para siempre")
	}
	for _, i := range []int{0, 1} {
		p := d.pedidos[stg[i]]
		if p.rutaID != nil || p.stopOrder != nil || p.segmentKm != nil {
			t.Fatalf("%s no volvió a la lista de disponibles", p.cliente)
		}
		// El pasado no se reescribe porque alguien deshaga la ruta de hoy.
		if p.ultimaRuta == nil || *p.ultimaRuta != id {
			t.Fatalf("%s perdió en qué camión viajó", p.cliente)
		}
	}
}

// ---------------------------------------------------------------------------
// POST /api/routes/{id}/results — EL CIERRE
// ---------------------------------------------------------------------------

// LA PRUEBA DEL CIERRE. Es la que no se puede romper: un devuelto suelta el camión pero
// NO su `ultima_ruta_id` ni su `stop_order`. Soltar los dos lo borraba de la hoja de
// cierre y el post-despacho dejaba de cuadrar.
func TestElDevueltoSueltaElCamionPeroSigueEnLaHojaDeLaRuta(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	entregado, devuelto, cancelado := stg[1], stg[2], stg[0]
	id := armarRutaDePrueba(t, h, jwt, entregado, devuelto, cancelado)

	cuerpo := fmt.Sprintf(`{"resultados":[
		{"orderId":%q,"resultado":"entregado"},
		{"orderId":%q,"resultado":"devuelto","nota":"  el cliente no estaba  "},
		{"orderId":%q,"resultado":"cancelado"}
	]}`, entregado, devuelto, cancelado)
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var salida salidaDeCierre
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	if len(salida.Aplicados) != 3 || len(salida.Rechazados) != 0 {
		t.Fatalf("aplicados %d, rechazados %d", len(salida.Aplicados), len(salida.Rechazados))
	}

	// El entregado: fija la hora de entrega y SIGUE en el camión.
	e := d.pedidos[entregado]
	if e.entregadoEn == nil {
		t.Fatal("el entregado no fijó deliveredAt")
	}
	if e.rutaID == nil || *e.rutaID != id {
		t.Fatal("el entregado se bajó del camión")
	}
	if e.estado != sqlc.OrderStatusDelivered {
		t.Fatalf("el entregado quedó en estado %q", e.estado)
	}

	// El devuelto y el cancelado: sueltan `route_id` y CONSERVAN el resto.
	for _, id2 := range []uuid.UUID{devuelto, cancelado} {
		p := d.pedidos[id2]
		if p.rutaID != nil {
			t.Fatalf("%s no bajó del camión: no puede repartirse mañana", p.cliente)
		}
		if p.ultimaRuta == nil || *p.ultimaRuta != id {
			t.Fatalf("%s perdió su ultimaRutaId: desaparece de la hoja de cierre", p.cliente)
		}
		if p.stopOrder == nil {
			t.Fatalf("%s perdió su número de parada", p.cliente)
		}
		if p.entregadoEn != nil {
			t.Fatalf("%s conserva la hora de entrega y se pintará «entregado»", p.cliente)
		}
		if p.estado != sqlc.OrderStatusPending {
			t.Fatalf("%s quedó en estado %q", p.cliente, p.estado)
		}
	}
	// La nota se guarda recortada: un devuelto sin motivo es un número que nadie sabe
	// explicar tres semanas después.
	if n := d.pedidos[devuelto].nota; n == nil || *n != "el cliente no estaba" {
		t.Fatalf("la nota quedó %v", n)
	}
	// Y la ruta NO cambia de estado con el cierre: eso es el PATCH.
	if d.rutas[id].estado != sqlc.RouteStatusPlanned {
		t.Fatalf("el cierre movió el estado de la ruta a %q", d.rutas[id].estado)
	}
}

// Un devuelto YA cerrado se puede corregir: por eso el universo va por `ultima_ruta_id` y
// no por `route_id`, que ya soltó.
func TestSePuedeCorregirElResultadoDeUnDevuelto(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	pedido := stg[1]
	id := armarRutaDePrueba(t, h, jwt, pedido)

	cuerpo := fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"devuelto"}]}`, pedido)
	llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)
	if d.pedidos[pedido].rutaID != nil {
		t.Fatal("el devuelto no soltó el camión")
	}

	cuerpo = fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, pedido)
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)
	var salida salidaDeCierre
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	if len(salida.Aplicados) != 1 {
		t.Fatalf("no se pudo corregir un devuelto ya cerrado: %s", w.Body.String())
	}
	if d.pedidos[pedido].entregadoEn == nil {
		t.Fatal("la corrección no fijó la hora de entrega")
	}
}

// Una parada de OTRA ruta se rechaza, con el motivo literal del contrato.
func TestNoSePuedeCerrarUnaParadaDeOtraRuta(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	unaRuta := armarRutaDePrueba(t, h, jwt, stg[1])
	otraRuta := armarRutaDePrueba(t, h, jwt, stg[0])

	// El pedido de la otra ruta, y además un id que no existe y uno que no es un id.
	cuerpo := fmt.Sprintf(`{"resultados":[
		{"orderId":%q,"resultado":"entregado"},
		{"orderId":%q,"resultado":"entregado"},
		{"orderId":"no-soy-un-id","resultado":"entregado"}
	]}`, stg[0], uuid.New())
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+unaRuta.String()+"/results", jwt, cuerpo)
	if w.Code != http.StatusOK {
		t.Fatalf("el cierre no aborta: acumula. Código %d", w.Code)
	}
	var salida salidaDeCierre
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	if len(salida.Aplicados) != 0 || len(salida.Rechazados) != 3 {
		t.Fatalf("aplicados %d, rechazados %d: %s", len(salida.Aplicados), len(salida.Rechazados), w.Body.String())
	}
	for _, r := range salida.Rechazados {
		if r.Motivo != msgParadaAjena {
			t.Fatalf("motivo %q", r.Motivo)
		}
	}
	// Y el pedido de la otra ruta se quedó como estaba.
	if p := d.pedidos[stg[0]]; p.resultado != nil || p.rutaID == nil || *p.rutaID != otraRuta {
		t.Fatal("se tocó la parada de otra ruta")
	}
}

func TestUnResultadoDesconocidoSeRechazaConSuValor(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1], stg[2])

	cuerpo := fmt.Sprintf(`{"resultados":[
		{"orderId":%q,"resultado":"casi"},
		{"orderId":%q}
	]}`, stg[1], stg[2])
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)
	var salida salidaDeCierre
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	if len(salida.Rechazados) != 2 {
		t.Fatalf("rechazados %d: %s", len(salida.Rechazados), w.Body.String())
	}
	if salida.Rechazados[0].Motivo != "resultado 'casi' desconocido" {
		t.Fatalf("motivo %q", salida.Rechazados[0].Motivo)
	}
	// Un resultado que no vino se interpola como `undefined`, calcado de delivery: quien
	// lee el mensaje está mirando el JSON que mandó, y ahí el campo no está.
	if salida.Rechazados[1].Motivo != "resultado 'undefined' desconocido" {
		t.Fatalf("motivo %q", salida.Rechazados[1].Motivo)
	}
}

func TestCerrarSinResultadosYConCuerpoRotoDaElMismoMensaje(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1])

	for _, cuerpo := range []string{`{"resultados":[]}`, `{}`, `{"resultados":`, `esto no es json`} {
		w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("cuerpo %q: código %d", cuerpo, w.Code)
		}
		if got := errorDeRutas(t, w); got != msgSinResultados {
			t.Fatalf("cuerpo %q: mensaje %q", cuerpo, got)
		}
	}
}

// El 404 del cierre es FEMENINO y distinto del de la ruta. Hay clientes que comparan el
// texto, así que esto no es cosmética.
func TestElCierreDiceNoEncontradaYElDetalleNoEncontrado(t *testing.T) {
	d, _, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	inventada := uuid.New().String()

	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+inventada+"/results", jwt,
		`{"resultados":[{"orderId":"x","resultado":"entregado"}]}`)
	if w.Code != http.StatusNotFound || errorDeRutas(t, w) != msgRutaNoEncontrada {
		t.Fatalf("código %d, mensaje %q", w.Code, errorDeRutas(t, w))
	}
	w = llamarRutas(t, h, http.MethodGet, "/api/routes/"+inventada, jwt, "")
	if w.Code != http.StatusNotFound || errorDeRutas(t, w) != httpx.MsgNoEncontrado {
		t.Fatalf("código %d, mensaje %q", w.Code, errorDeRutas(t, w))
	}
}

// El parte del aviso a PEDIDO sale en la respuesta y NO miente: mientras no haya canal,
// `ok` es false y el motivo va escrito. Un aviso que nadie recibe y que además se declara
// enviado es peor que no avisar, porque nadie lo busca.
func TestElCierreCuentaLoQueLePasoAlAvisoAPedido(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1])

	// Se sustituye el canal para comprobar QUÉ se le manda.
	//
	// Con candado y guardándolo TODO, no sólo lo último: el aviso de «despachado» del
	// armado sale en una goroutine y puede llegar aquí en cualquier momento. Quedarse con
	// la última llamada haría que esta prueba fallara una vez de cada tantas, que es la
	// peor clase de prueba: la que se acaba ejecutando con `-count=1` y mirando para otro
	// lado.
	anterior := avisarEstadoAPedido
	defer func() { avisarEstadoAPedido = anterior }()
	var candado sync.Mutex
	var visto []AvisoDeParada
	avisarEstadoAPedido = func(_ context.Context, avisos []AvisoDeParada) ParteAPedido {
		candado.Lock()
		visto = append(visto, avisos...)
		candado.Unlock()
		return ParteAPedido{Ok: true, Enviados: len(avisos), Aplicados: len(avisos)}
	}

	cuerpo := fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"devuelto","nota":"nadie abrió"}]}`, stg[1])
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)
	var salida salidaDeCierre
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	if !salida.APedido.Ok || salida.APedido.Enviados != 1 {
		t.Fatalf("el parte a PEDIDO salió %+v", salida.APedido)
	}
	candado.Lock()
	defer candado.Unlock()
	var devuelto *AvisoDeParada
	for i, a := range visto {
		if a.Estado == "devuelto" {
			devuelto = &visto[i]
		}
	}
	if devuelto == nil {
		t.Fatalf("a PEDIDO no le llegó el devuelto: %+v", visto)
	}
	if devuelto.PedidoID != "PED-2" || devuelto.Nota != "nadie abrió" {
		t.Fatalf("lo que se le mandó a PEDIDO no cuadra: %+v", *devuelto)
	}
}

func TestSinCanalElParteDiceQueNoSeEnvio(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d)
	jwt := deSantiagoEnRutas(t)
	id := armarRutaDePrueba(t, h, jwt, stg[1])

	cuerpo := fmt.Sprintf(`{"resultados":[{"orderId":%q,"resultado":"entregado"}]}`, stg[1])
	w := llamarRutas(t, h, http.MethodPost, "/api/routes/"+id.String()+"/results", jwt, cuerpo)
	var salida salidaDeCierre
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	if salida.APedido.Ok || salida.APedido.Error == "" {
		t.Fatalf("el parte tiene que decir que no salió: %+v", salida.APedido)
	}
}

// ---------------------------------------------------------------------------
// La sesión
// ---------------------------------------------------------------------------

func TestLasSeisRutasExigenSesion(t *testing.T) {
	d, _, _ := datosDeReparto()
	h := montarRutas(t, d)
	id := uuid.New().String()
	for _, caso := range [][2]string{
		{http.MethodGet, "/api/routes"},
		{http.MethodPost, "/api/routes"},
		{http.MethodGet, "/api/routes/" + id},
		{http.MethodPatch, "/api/routes/" + id},
		{http.MethodDelete, "/api/routes/" + id},
		{http.MethodPost, "/api/routes/" + id + "/results"},
	} {
		w := llamarRutas(t, h, caso[0], caso[1], "", "")
		if w.Code != http.StatusUnauthorized {
			t.Fatalf("%s %s: código %d, una ruta sin sesión", caso[0], caso[1], w.Code)
		}
		if got := strings.TrimSpace(w.Body.String()); got != `{"error":"Unauthorized"}` {
			t.Fatalf("%s %s: cuerpo %q", caso[0], caso[1], got)
		}
	}
}
