package api

// EL KILO QUE NADIE PUSO, Y CÓMO SE DICE SIN ROMPER A NADIE.
//
// `orders.weight` nació `NOT NULL DEFAULT 1` (00001_init.sql:276), heredado del
// `weight Float @default(1)` del Prisma de delivery. Un pedido cuyo peso nadie sabe no
// llega al aparato como 0 —que al menos chirría— sino como **1 kg**, que es perfectamente
// creíble para un paquete. De ahí se suma en la tarjeta «Peso Total» de Informes, en el
// pie de sus dos tablas, en el Excel que alguien abre para cobrar y en la barra de
// capacidad del camión, que es la que decide qué cabe.
//
// El propio lado Go ya tiene escrita la regla contraria, en `internal/ventra`: «`weightKg`
// viene null en muchos productos y eso NO es cero: cero kilos es una mentira».
//
// LA DECISIÓN (00007_lo_que_no_se_sabe.sql): no se le cambia el tipo a `weight` —eso
// rompería a toda APK instalada, que lo lee como número— sino que **la duda viaja al
// lado**, en un campo nuevo. Un campo nuevo lo ignora quien no lo conoce.
//
// Y SON TRES ESTADOS, NO DOS. Ésa es la mitad del valor de estas pruebas y por eso van en
// terna, no en pareja: `false` es «hay constancia y nada respalda ese peso», `null` es «no
// consta». Confundirlos es volver a lo mismo por el otro lado — acusar de inventado un
// peso que probablemente es bueno — y hoy `null` es la inmensa mayoría, porque el espejo
// todavía no escribe `origen_peso` (ver `CrearRenglonDePedido` en db/queries/orders.sql).

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/google/uuid"

	"procovar/reparto-api/internal/store/sqlc"
)

// pesoDeLaFila saca `pesoRespaldado` tal cual vino en el JSON: se mira el CRUDO y no una
// estructura de Go, porque lo que hay que distinguir es `false` de `null` de ausente, y
// una estructura con puntero ya ha borrado la diferencia entre las dos últimas.
func pesoDeLaFila(t *testing.T, crudo json.RawMessage) (presente bool, valor *bool) {
	t.Helper()
	var m map[string]json.RawMessage
	if err := json.Unmarshal(crudo, &m); err != nil {
		t.Fatalf("fila ilegible: %v", err)
	}
	b, hay := m["pesoRespaldado"]
	if !hay {
		return false, nil
	}
	if string(b) == "null" {
		return true, nil
	}
	var v bool
	if err := json.Unmarshal(b, &v); err != nil {
		t.Fatalf("pesoRespaldado no es un booleano: %s", b)
	}
	return true, &v
}

// tresPedidosConSuDuda deja los tres estados en las tres listas del doble.
func tresPedidosConSuDuda() (*dobleDePedidos, [3]uuid.UUID) {
	d := datosDePedidos()
	no, si := false, true

	inventado := pedidosStgA // hay constancia y nada lo respalda
	bueno := pedidosStgB     // algún renglón trae peso propio
	noConsta := uuid.New()   // no se guardó de dónde salía

	d.pedidos[0].PesoRespaldado = &no
	d.pedidos[1].PesoRespaldado = &si
	d.pedidos = append(d.pedidos, sqlc.ListarPedidosRow{
		ID: noConsta, CustomerName: "Sin constancia", Address: "Calle 4", Weight: 1,
		Status: sqlc.OrderStatusPending, BranchID: pedidosPg(pedidosSucStg),
		SucursalNombre: pedidosPtr("Santiago"),
	})

	d.disponibles = []sqlc.ListarPedidosDisponiblesRow{
		{ID: inventado, CustomerName: "Bar de Santiago", Address: "Calle 1", Weight: 1,
			BranchID: pedidosPg(pedidosSucStg), PesoRespaldado: &no},
		{ID: bueno, CustomerName: "Cafetería del puerto", Address: "Calle 2", Weight: 5,
			BranchID: pedidosPg(pedidosSucStg), PesoRespaldado: &si},
		{ID: noConsta, CustomerName: "Sin constancia", Address: "Calle 4", Weight: 1,
			BranchID: pedidosPg(pedidosSucStg)},
	}
	d.totalDisponibles = 3
	return d, [3]uuid.UUID{inventado, bueno, noConsta}
}

// esperado es lo que tiene que decir cada uno de los tres, en las tres pantallas.
func compruebaLaTerna(t *testing.T, filas map[uuid.UUID]json.RawMessage, ids [3]uuid.UUID, donde string) {
	t.Helper()
	casos := []struct {
		id     uuid.UUID
		quien  string
		quiere *bool
		porQue string
	}{
		{ids[0], "el del peso inventado", pedidosPtr(false),
			"hay constancia de que ningún renglón sabe pesar: ese kilo se lo puso el DEFAULT"},
		{ids[1], "el del peso bueno", pedidosPtr(true),
			"algún renglón trae peso propio y el número sale de algo"},
		{ids[2], "el que no consta", nil,
			"NO SE GUARDÓ de dónde salía. Un `false` aquí acusaría de inventado un peso " +
				"que probablemente es bueno, que es la misma mentira por el otro lado"},
	}
	for _, c := range casos {
		fila, hay := filas[c.id]
		if !hay {
			t.Fatalf("%s: no salió %s", donde, c.quien)
		}
		presente, valor := pesoDeLaFila(t, fila)
		if !presente {
			t.Fatalf("%s: %s salió SIN `pesoRespaldado`.\n"+
				"El campo es lo único que dice si ese `weight` sale de algo; sin él, un kilo "+
				"inventado y un kilo de verdad se leen igual", donde, c.quien)
		}
		switch {
		case c.quiere == nil && valor != nil:
			t.Errorf("%s: %s tenía que salir `null` y salió %v.\n%s", donde, c.quien, *valor, c.porQue)
		case c.quiere != nil && valor == nil:
			t.Errorf("%s: %s tenía que salir %v y salió `null`.\n%s", donde, c.quien, *c.quiere, c.porQue)
		case c.quiere != nil && valor != nil && *c.quiere != *valor:
			t.Errorf("%s: %s tenía que salir %v y salió %v.\n%s", donde, c.quien, *c.quiere, *valor, c.porQue)
		}
	}
}

// porID indexa las filas crudas de una respuesta con `{orders: [...]}`.
func porID(t *testing.T, cuerpo []byte) map[uuid.UUID]json.RawMessage {
	t.Helper()
	var sobre struct {
		Orders []json.RawMessage `json:"orders"`
	}
	if err := json.Unmarshal(cuerpo, &sobre); err != nil {
		t.Fatalf("respuesta ilegible: %s", cuerpo)
	}
	salida := map[uuid.UUID]json.RawMessage{}
	for _, f := range sobre.Orders {
		var soloID struct {
			ID uuid.UUID `json:"id"`
		}
		if err := json.Unmarshal(f, &soloID); err != nil {
			t.Fatalf("fila sin id: %s", f)
		}
		salida[soloID.ID] = f
	}
	return salida
}

// 1. EL CATÁLOGO (`GET /api/orders`).
func TestElCatalogoDiceSiElPesoSaleDeAlgo(t *testing.T) {
	d, ids := tresPedidosConSuDuda()
	h := servidorDePedidos(t, d)

	w := pedirPedidos(t, h, http.MethodGet, "/api/orders?limit=50", tokenDeSantiagoPedidos(t), "", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	compruebaLaTerna(t, porID(t, w.Body.Bytes()), ids, "el catálogo")
}

// 2. LA LISTA DEL ARMADOR (`GET /api/orders/available`), que es la que alimenta la barra
// de capacidad del camión: la que decide qué cabe. Si la duda no llega aquí, no llega a
// donde más cuesta.
func TestLaListaDelArmadorDiceSiElPesoSaleDeAlgo(t *testing.T) {
	d, ids := tresPedidosConSuDuda()
	h := servidorDePedidos(t, d)

	w := pedirPedidos(t, h, http.MethodGet, "/api/orders/available", tokenDeSantiagoPedidos(t), "", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	compruebaLaTerna(t, porID(t, w.Body.Bytes()), ids, "la lista del armador")
}

// 3. EL DETALLE (`GET /api/orders/{id}`), uno por uno.
func TestElDetalleDiceSiElPesoSaleDeAlgo(t *testing.T) {
	d, ids := tresPedidosConSuDuda()
	h := servidorDePedidos(t, d)

	filas := map[uuid.UUID]json.RawMessage{}
	for _, id := range ids {
		w := pedirPedidos(t, h, http.MethodGet, "/api/orders/"+id.String(),
			tokenDeSantiagoPedidos(t), "", nil)
		if w.Code != http.StatusOK {
			t.Fatalf("código %d para %s: %s", w.Code, id, w.Body.String())
		}
		filas[id] = json.RawMessage(w.Body.Bytes())
	}
	compruebaLaTerna(t, filas, ids, "el detalle")
}
