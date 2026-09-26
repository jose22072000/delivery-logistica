package espejo

import (
	"encoding/json"
	"strings"
	"testing"
)

func numero(v float64) *float64 { return &v }

func pedidoCompleto() PedidoDeFuera {
	return PedidoDeFuera{
		ID:                "ped-1",
		Folio:             "X-2992",
		Fecha:             "2026-09-01T10:00:00Z",
		Estado:            "completada",
		SucursalCodigo:    "STG",
		Direccion:         "Calle del pedido 4",
		Telefono:          "53000000",
		UpdatedAt:         "2026-09-13T18:20:00Z",
		Archivado:         true,
		FechaComprometida: "2026-09-15T12:00:00Z",
		RequiereDomicilio: true,
		CostoDomicilio:    numero(350),
		FacturaEstado:     "igual",
		FacturaNumero:     "F-77",
		FacturaAt:         "2026-09-02T09:00:00Z",
		FacturaDomicilio:  numero(350),
		Cliente: &ClienteDelPedido{
			Nombre: "Bodega La Esquina", Direccion: "Calle de la ficha 9",
			Municipio: "Songo", Latitud: numero(20.02), Longitud: numero(-75.82),
		},
		Vendedor: &VendedorDelPedido{Codigo: "V12"},
		Items: []RenglonDeFuera{
			{Codigo: "MLT", Producto: "Malta", Unidades: numero(24), Packs: numero(2), PesoKg: numero(7.2)},
		},
	}
}

func TestElLoteLlevaLaMarcaDeAgua(t *testing.T) {
	// ES LA PRUEBA QUE MÁS IMPORTA DE ESTE FICHERO. Sin `pedidoUpdatedAt` en el cuerpo, el
	// reparto guarda el pedido con la columna a nulo, el `since` no existe nunca, y CADA
	// CICLO vuelve a barrer el año entero: 56.000 pedidos cada minuto por la conexión de
	// allá para traer las cuatro filas que se movieron.
	o := ArmarLote([]PedidoDeFuera{pedidoCompleto()}).Orders[0]
	if o.PedidoUpdatedAt == nil || *o.PedidoUpdatedAt != "2026-09-13T18:20:00Z" {
		t.Fatalf("el lote tiene que llevar pedidoUpdatedAt; llevó %v", o.PedidoUpdatedAt)
	}
}

func TestElLoteCopiaLoQueSeUsaParaFiltrar(t *testing.T) {
	// Todo esto viajaba antes dentro de un `meta` con el pedido entero, y filtrar por
	// municipio o por estado obligaba a leer y descartar cincuenta mil pedidos completos.
	o := ArmarLote([]PedidoDeFuera{pedidoCompleto()}).Orders[0]
	casos := []struct {
		que   string
		tiene any
		quiso any
	}{
		{"externalId", o.ExternalID, "ped-1"},
		{"operationNumber", o.OperationNumber, "X-2992"},
		{"sucursalExternalId", o.SucursalExternalID, "STG"},
		{"customerName", o.CustomerName, "Bodega La Esquina"},
		{"archivado", o.Archivado, true},
		{"requiereDomicilio", o.RequiereDomicilio, true},
	}
	for _, c := range casos {
		if c.tiene != c.quiso {
			t.Errorf("%s: salió %v y tenía que salir %v", c.que, c.tiene, c.quiso)
		}
	}
	for _, c := range []struct {
		que   string
		tiene *string
		quiso string
	}{
		{"estado", o.Estado, "completada"},
		{"municipio", o.Municipio, "Songo"},
		{"vendedor", o.Vendedor, "V12"},
		{"sucursalCodigo", o.SucursalCodigo, "STG"},
		{"facturaEstado", o.FacturaEstado, "igual"},
		{"facturaNumero", o.FacturaNumero, "F-77"},
		{"orderDate", o.OrderDate, "2026-09-01T10:00:00Z"},
		{"fechaComprometida", o.FechaComprometida, "2026-09-15T12:00:00Z"},
	} {
		if c.tiene == nil || *c.tiene != c.quiso {
			t.Errorf("%s: salió %v y tenía que salir %q", c.que, c.tiene, c.quiso)
		}
	}
	if o.PedidoCosto == nil || *o.PedidoCosto != 350 {
		t.Errorf("pedidoCosto es el que puso la APK en PEDIDO; salió %v", o.PedidoCosto)
	}
}

func TestLaDireccionDelPedidoMandaSobreLaDeLaFicha(t *testing.T) {
	// La del pedido es a dónde hay que llevar ESTA mercancía; la de la ficha es dónde suele
	// estar el cliente. No son lo mismo y el chofer va a la primera.
	o := ArmarLote([]PedidoDeFuera{pedidoCompleto()}).Orders[0]
	if o.Address == nil || *o.Address != "Calle del pedido 4" {
		t.Errorf("tenía que quedarse la del pedido; quedó %v", o.Address)
	}

	sinDireccion := pedidoCompleto()
	sinDireccion.Direccion = "   "
	o = ArmarLote([]PedidoDeFuera{sinDireccion}).Orders[0]
	if o.Address == nil || *o.Address != "Calle de la ficha 9" {
		t.Errorf("sin la del pedido tenía que caer a la de la ficha; quedó %v", o.Address)
	}
}

func TestElNombreNuncaVaVacio(t *testing.T) {
	// El lote no guarda un pedido sin `customerName` —contesta `falta-customerName`— y el
	// nombre es lo que el chofer busca en la puerta.
	p := pedidoCompleto()
	p.Cliente.Nombre = ""
	p.Encargado = "Yoandra"
	if n := ArmarLote([]PedidoDeFuera{p}).Orders[0].CustomerName; n != "Yoandra" {
		t.Errorf("sin nombre de cliente tenía que usar el encargado; usó %q", n)
	}
	p.Encargado = ""
	if n := ArmarLote([]PedidoDeFuera{p}).Orders[0].CustomerName; n != "Cliente" {
		t.Errorf("sin nadie tenía que quedar «Cliente»; quedó %q", n)
	}
}

func TestLasCoordenadasSalenDeLaFichaDelCliente(t *testing.T) {
	o := ArmarLote([]PedidoDeFuera{pedidoCompleto()}).Orders[0]
	if o.Lat == nil || *o.Lat != 20.02 || o.Lng == nil || *o.Lng != -75.82 {
		t.Fatalf("las coordenadas no llegaron: %v / %v", o.Lat, o.Lng)
	}
	// Sin ficha van nulas y el lote saltará el pedido con `sin-geolocalizacion`, que es lo
	// correcto: sin coordenadas no se puede ni ordenar la ruta ni medir la distancia.
	sinFicha := pedidoCompleto()
	sinFicha.Cliente = nil
	o = ArmarLote([]PedidoDeFuera{sinFicha}).Orders[0]
	if o.Lat != nil || o.Lng != nil {
		t.Errorf("sin ficha de cliente no puede haber coordenadas; salieron %v / %v", o.Lat, o.Lng)
	}
}

func TestElPesoViajaTalComoLoMandoPedido(t *testing.T) {
	// PEDIDO ya cruzó cada línea contra Ventra con los vínculos que ató una persona. Volver
	// a resolverlo aquí es tener el mismo dato dos veces y descubrir tarde que no coinciden.
	it := ArmarLote([]PedidoDeFuera{pedidoCompleto()}).Orders[0].Items[0]
	if it.PesoKg == nil || *it.PesoKg != 7.2 {
		t.Errorf("el pesoKg tenía que llegar tal cual; llegó %v", it.PesoKg)
	}
	if it.Packs == nil || *it.Packs != 2 {
		t.Errorf("los bultos tenían que llegar tal cual; llegaron %v", it.Packs)
	}
	if it.Quantity != 24 {
		t.Errorf("las unidades tenían que llegar tal cual; llegaron %v", it.Quantity)
	}
}

func TestUnaLineaSinUnidadesCuentaComoUna(t *testing.T) {
	// Un 0 haría que el peso por unidad de venta multiplicara a cero y la línea entera
	// pesara nada: en el camión cabría todo.
	p := pedidoCompleto()
	p.Items[0].Unidades = nil
	if q := ArmarLote([]PedidoDeFuera{p}).Orders[0].Items[0].Quantity; q != 1 {
		t.Errorf("sin unidades tenía que quedar 1; quedó %v", q)
	}
}

func TestElLoteNoEsUnaVistaPrevia(t *testing.T) {
	// Lo que se pide del espejo es justamente que los pedidos ENTREN. Un `preview` en true
	// cotizaría y no escribiría nada, con un 200 y sin un solo error.
	cuerpo := ArmarLote([]PedidoDeFuera{pedidoCompleto()})
	if cuerpo.Preview {
		t.Error("el espejo nunca manda el lote en vista previa")
	}
	if !cuerpo.UseWarehouseWeights {
		t.Error("el catálogo local es el respaldo de las líneas sin peso: tiene que ir en true")
	}
}

func TestLosCamposVaciosViajanComoAusentes(t *testing.T) {
	// Un `""` guardado se lee en pantalla como un dato que está y no dice nada, y filtrar
	// por él devuelve cosas que no son.
	p := PedidoDeFuera{ID: "x", SucursalCodigo: "HOL", Cliente: &ClienteDelPedido{Nombre: "N"}}
	crudo, err := json.Marshal(ArmarLote([]PedidoDeFuera{p}).Orders[0])
	if err != nil {
		t.Fatalf("no se pudo serializar: %v", err)
	}
	var visto map[string]any
	if err := json.Unmarshal(crudo, &visto); err != nil {
		t.Fatalf("no se pudo leer: %v", err)
	}
	for _, campo := range []string{"facturaEstado", "facturaNumero", "municipio", "vendedor", "orderDate", "pedidoUpdatedAt"} {
		if visto[campo] != nil {
			t.Errorf("%s tenía que ir nulo y fue %v", campo, visto[campo])
		}
	}
}

// UN ALMACÉN SIN `mezclado` NO AFIRMA QUE EL PEDIDO SALGA DE UNO SOLO.
//
// # Qué pasa si esto se rompe
//
// `AlmacenDelPedido.Mezclado` es `*bool` con `omitempty`, y las dos cosas hacen falta. Con un
// `bool` pelado, un `almacen` que llegue de PEDIDO SIN `mezclado` se lee como `false` —así
// entiende Go un campo ausente—, esta estructura se vuelve a serializar hacia la puerta del
// lote y sale `"mezclado": false` EXPLÍCITO. La puerta lo guarda como `false` y la base acaba
// AFIRMANDO que el pedido sale de un solo almacén sin que nadie lo haya comprobado.
//
// Lo que eso cuesta: un pedido de Santiago con seis renglones de AURORA y seis de PV-STGO.
// PEDIDO resuelve el desempate y manda `codigo: "2"`, pero una versión suya que todavía no
// mande `mezclado` dejaría guardado «no está mezclado». Nadie sabe que son DOS recogidas,
// ninguna pantalla lo desmiente, y el que despacha va a AURORA y se deja media carga en
// PV-STGO. Un NULL dice «no se sabe»; un `false` dice «comprobado que no», y es mentira.
//
// Es el mismo modo de fallo que `internal/api/almacenes.go` documenta para `activo`: dos lados
// leyendo el mismo campo y entendiendo cosas distintas, sin que falle nada.
//
// SE MIRA EL JSON QUE SALE y no el campo de la estructura: lo que hace daño es el `false`
// serializado, y un `*bool` sin `omitempty` tiene el campo bien y emite `"mezclado":null`,
// que la puerta también lee bien — pero el día que alguien lo vuelva a poner `bool`, mirar la
// estructura no lo caza y mirar el JSON sí.
func TestUnAlmacenSinMezcladoNoAfirmaQueNoLoEsta(t *testing.T) {
	// Como llega de PEDIDO: el bloque `almacen` SIN `mezclado`.
	var p PedidoDeFuera
	if err := json.Unmarshal([]byte(`{
		"id":"ped-1","sucursalCodigo":"STG",
		"almacen":{"codigo":"2","nombre":"AURORA","sucursalCodigo":"STG"}
	}`), &p); err != nil {
		t.Fatalf("no se entendió el pedido: %v", err)
	}
	if p.Almacen == nil {
		t.Fatal("el almacén no se leyó")
	}
	if p.Almacen.Mezclado != nil {
		t.Fatalf("un `mezclado` ausente se leyó como %v: eso AFIRMA que el pedido sale de un "+
			"solo almacén, y nadie lo ha comprobado", *p.Almacen.Mezclado)
	}

	crudo, err := json.Marshal(ArmarLote([]PedidoDeFuera{p}))
	if err != nil {
		t.Fatalf("no se pudo serializar el lote: %v", err)
	}
	if strings.Contains(string(crudo), `"mezclado":false`) {
		t.Fatalf("el lote manda `\"mezclado\":false` sobre algo que PEDIDO no dijo: la puerta "+
			"lo va a guardar como «comprobado que no está mezclado» — %s", crudo)
	}

	// LA OTRA MITAD: cuando PEDIDO SÍ lo dice, viaja. Sin esto, «no afirma de más» se cumple
	// tirando el campo siempre, y entonces un pedido de dos recogidas nunca se marca.
	for _, caso := range []struct {
		valor  string
		quiere string
	}{
		{`true`, `"mezclado":true`},
		{`false`, `"mezclado":false`},
	} {
		var q PedidoDeFuera
		if err := json.Unmarshal([]byte(`{"id":"p","almacen":{"codigo":"2","mezclado":`+
			caso.valor+`}}`), &q); err != nil {
			t.Fatalf("no se entendió: %v", err)
		}
		salida, err := json.Marshal(ArmarLote([]PedidoDeFuera{q}))
		if err != nil {
			t.Fatalf("no se pudo serializar: %v", err)
		}
		if !strings.Contains(string(salida), caso.quiere) {
			t.Errorf("con `mezclado: %s` el lote tenía que llevar %s; llevó %s",
				caso.valor, caso.quiere, salida)
		}
	}
}
