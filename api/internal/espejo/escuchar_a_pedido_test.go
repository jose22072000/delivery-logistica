package espejo

import (
	"context"
	"errors"
	"log/slog"
	"testing"
	"time"
)

// EL ESPEJO ESCUCHA A PEDIDO Y NO PIERDE UN AVISO.
//
// PEDIDO deja un aviso en un stream de Redis cada vez que un pedido pasa a importarle al
// reparto. Esto lo lee bloqueado —entra en cuanto lo sueltan, sin sondeo— y reacciona.
//
// LO QUE SE PRUEBA, y son las tres formas de perder un pedido sin que salte nada:
//
//  1. **Reconocer antes de guardar.** Si se hace `XACK` y luego el guardado falla, ese
//     aviso no lo vuelve a leer nadie: el pedido se queda fuera del reparto para siempre y
//     no hay ningún error en ninguna pantalla.
//  2. **Descartar lo que no se entiende.** Un motivo nuevo de PEDIDO contra una versión
//     vieja de esto tiene que acabar en «repasa esa sucursal», no en la basura.
//  3. **Resucitar un borrado.** Si en la misma tanda un pedido se actualizó y después se
//     borró, traerlo lo devuelve a la vida — y un pedido resucitado se carga en un camión
//     que ya no tenía que llevarlo.

// ---------------------------------------------------------------- el doble del stream

type streamFalso struct {
	tandas      [][]AvisoDePedido
	vuelta      int
	reconocidos []string
	colgados    []AvisoDePedido
	grupoCreado bool
	fallaAlLeer error
}

func (s *streamFalso) CrearGrupo(context.Context, string, string) error {
	s.grupoCreado = true
	return nil
}

func (s *streamFalso) Leer(
	context.Context, string, string, string, int, time.Duration,
) ([]AvisoDePedido, error) {
	if s.fallaAlLeer != nil {
		return nil, s.fallaAlLeer
	}
	if s.vuelta >= len(s.tandas) {
		return nil, nil
	}
	t := s.tandas[s.vuelta]
	s.vuelta++
	return t, nil
}

func (s *streamFalso) Reconocer(_ context.Context, _, _ string, ids ...string) error {
	s.reconocidos = append(s.reconocidos, ids...)
	return nil
}

func (s *streamFalso) RecogerColgados(
	context.Context, string, string, string, time.Duration, int,
) ([]AvisoDePedido, error) {
	c := s.colgados
	s.colgados = nil
	return c, nil
}

func escuchadorDePrueba(s *streamFalso, atender func(context.Context, QueHaceFaltaTraer) error) *Escuchador {
	return NuevoEscuchador(s, PorDefecto(), slog.New(slog.DiscardHandler), atender)
}

// ---------------------------------------------------------------- las pruebas

// EL XACK VA DESPUÉS DE GUARDAR. Es la regla que no es opcional.
func TestSiElGuardadoFallaLosAvisosNOSeReconocen(t *testing.T) {
	s := &streamFalso{tandas: [][]AvisoDePedido{{
		{ID: "1-0", Motivo: MotivoFactura, PedidoID: "ped-1"},
		{ID: "1-1", Motivo: MotivoFactura, PedidoID: "ped-2"},
	}}}
	e := escuchadorDePrueba(s, func(context.Context, QueHaceFaltaTraer) error {
		return errors.New("PEDIDO no contesta")
	})

	e.UnaVuelta(context.Background())

	if len(s.reconocidos) != 0 {
		t.Fatalf(
			"se reconocieron avisos que NO se llegaron a guardar: esos pedidos no los "+
				"vuelve a leer nadie y se quedan fuera del reparto para siempre, sin un "+
				"solo error. Reconocidos: %v", s.reconocidos,
		)
	}
}

// Y CUANDO SÍ SE GUARDA, SE RECONOCEN. Sin esta mitad, «no reconocer» se cumple no
// reconociendo nunca, y entonces `XPENDING` crece sin parar y todo se relee en bucle.
func TestCuandoSeGuardaBienLosAvisosSeReconocen(t *testing.T) {
	s := &streamFalso{tandas: [][]AvisoDePedido{{
		{ID: "1-0", Motivo: MotivoFactura, PedidoID: "ped-1"},
		{ID: "1-1", Motivo: MotivoDomicilio, PedidoID: "ped-2"},
	}}}
	e := escuchadorDePrueba(s, func(context.Context, QueHaceFaltaTraer) error { return nil })

	e.UnaVuelta(context.Background())

	if len(s.reconocidos) != 2 {
		t.Fatalf("no se reconoció la tanda guardada: %v", s.reconocidos)
	}
}

func TestLosColgadosDeOtroConsumidorSeRecogen(t *testing.T) {
	s := &streamFalso{
		tandas:   [][]AvisoDePedido{{{ID: "2-0", Motivo: MotivoFactura, PedidoID: "ped-9"}}},
		colgados: []AvisoDePedido{{ID: "1-0", Motivo: MotivoFactura, PedidoID: "ped-1"}},
	}
	var visto QueHaceFaltaTraer
	e := escuchadorDePrueba(s, func(_ context.Context, q QueHaceFaltaTraer) error {
		visto = q
		return nil
	})

	e.UnaVuelta(context.Background())

	if len(visto.Pedidos) != 2 {
		t.Fatalf(
			"no se recogió lo que otra réplica dejó a medias: con `>` nadie lo vuelve a "+
				"leer nunca y ese pedido se pierde en silencio. Se atendieron: %v",
			visto.Pedidos,
		)
	}
}

// ---------------------------------------------------------------- el agrupado

func TestUnBorradoMandaSobreUnTraer(t *testing.T) {
	q := AgruparAvisos([]AvisoDePedido{
		{ID: "1-0", Motivo: MotivoFactura, PedidoID: "ped-1"},
		{ID: "1-1", Motivo: MotivoBorrado, PedidoID: "ped-1"},
	})

	if len(q.Pedidos) != 0 {
		t.Fatalf(
			"se va a traer un pedido que PEDIDO acaba de borrar: traerlo lo resucita, y "+
				"un pedido resucitado se carga en un camión. Traer: %v", q.Pedidos,
		)
	}
	if len(q.Borrados) != 1 || q.Borrados[0] != "ped-1" {
		t.Fatalf("el borrado se perdió: %v", q.Borrados)
	}
}

func TestElMismoPedidoDosVecesSePideUna(t *testing.T) {
	q := AgruparAvisos([]AvisoDePedido{
		{ID: "1-0", Motivo: MotivoDomicilio, PedidoID: "ped-1"},
		{ID: "1-1", Motivo: MotivoFactura, PedidoID: "ped-1"},
	})

	if len(q.Pedidos) != 1 {
		t.Fatalf(
			"se pide el mismo pedido dos veces: son dos vueltas por la conexión de allá "+
				"para escribir lo mismo. %v", q.Pedidos,
		)
	}
}

// UN MOTIVO QUE NO SE CONOCE NO SE TIRA.
//
// Puede ser uno nuevo de PEDIDO contra una versión vieja de esto. Descartarlo pierde el
// pedido sin un solo error; repasar su sucursal cuesta una vuelta y no pierde nada.
func TestUnMotivoDesconocidoRepasaSuSucursal(t *testing.T) {
	q := AgruparAvisos([]AvisoDePedido{
		{ID: "1-0", Motivo: "algo_que_todavia_no_existe", PedidoID: "ped-1", SucursalID: "cam"},
	})

	if len(q.Sucursales) != 1 || q.Sucursales[0] != "cam" {
		t.Fatalf(
			"un motivo desconocido se tiró a la basura: si PEDIDO añade uno, esos "+
				"pedidos dejan de entrar y nadie se entera. %+v", q,
		)
	}
}

func TestUnaImportacionRepasaSuSucursalYNoPideUnPedido(t *testing.T) {
	q := AgruparAvisos([]AvisoDePedido{
		{ID: "1-0", Motivo: MotivoImportacion, SucursalID: "stg"},
	})

	if len(q.Pedidos) != 0 {
		t.Fatalf("una tanda de CSV no trae id: no hay pedido que pedir")
	}
	if len(q.Sucursales) != 1 || q.Sucursales[0] != "stg" {
		t.Fatalf("no se repasa la sucursal que acaba de importar: %+v", q)
	}
}

// Sin sucursal hay que mirar todas. Debería ser raro, y por eso se dice en vez de callarlo.
func TestUnAvisoSinSucursalMiraTodas(t *testing.T) {
	q := AgruparAvisos([]AvisoDePedido{{ID: "1-0", Motivo: MotivoImportacion}})

	if !q.TodasLasSucursales {
		t.Fatalf("un aviso sin sucursal se descartó: %+v", q)
	}
}

// UNA IMPORTACIÓN CON `id` PIDE ESE PEDIDO, NO BARRE LA SUCURSAL.
//
// PEDIDO cambió el 26/09/2026: el aviso de importación ya no es uno por tanda de CSV sino
// UNO POR PEDIDO —sólo los que pasan su filtro—, y cae a uno por sucursal cuando pasan de
// cincuenta. Sin esta rama, cada uno de esos avisos disparaba un barrido entero: cincuenta
// pedidos importados serían cincuenta barridos, peor que lo que había antes.
func TestUnaImportacionConIDPideEsePedido(t *testing.T) {
	q := AgruparAvisos([]AvisoDePedido{
		{ID: "1-0", Motivo: MotivoImportacion, PedidoID: "ped-1", SucursalID: "cam"},
		{ID: "1-1", Motivo: MotivoImportacion, PedidoID: "ped-2", SucursalID: "cam"},
	})

	if len(q.Pedidos) != 2 {
		t.Fatalf("no se pidieron los pedidos que venían con id: %+v", q)
	}
	if len(q.Sucursales) != 0 {
		t.Fatalf(
			"se barrió la sucursal teniendo los ids: con cincuenta avisos eso son "+
				"cincuenta barridos. %+v", q,
		)
	}
}

// UN CLIENTE QUE SE MUEVE REPASA EL PADRÓN, UNA VEZ POR TANDA.
//
// PEDIDO añadió el motivo `cliente` el 26/09/2026: el reparto ordena las paradas por la
// coordenada del cliente, así que si alguien corrige dónde vive y esto no se entera, la
// ruta se arma hacia el sitio de antes — con números y todo, sin un solo error.
//
// SE PIDEN POR SU ID, no repasando el padrón: PEDIDO abrió `?ids=` el mismo día a petición
// de este lado. Veinte clientes movidos son veinte filas, no las 8.673 del padrón.
func TestUnClienteMovidoSePidePorSuID(t *testing.T) {
	q := AgruparAvisos([]AvisoDePedido{
		{ID: "1-0", Motivo: MotivoCliente, PedidoID: "cli-1", SucursalID: "cam"},
		{ID: "1-1", Motivo: MotivoCliente, PedidoID: "cli-2", SucursalID: "cam"},
	})

	if len(q.Clientes) != 2 {
		t.Fatalf(
			"no se van a traer los clientes movidos: las rutas se armarían hacia el "+
				"sitio de antes, con números y todo. %+v", q,
		)
	}
	if len(q.Pedidos) != 0 {
		t.Fatalf(
			"el id de un aviso de cliente es un CLIENTE, no un pedido: pedirlo como "+
				"pedido no encuentra nada y el cliente sigue mal. %+v", q,
		)
	}
	if len(q.Sucursales) != 0 {
		t.Fatalf("se barrieron pedidos por un aviso que no va de pedidos: %+v", q)
	}
}

// UN PEDIDO QUE DEJA DE SER REPARTIBLE SE QUITA, IGUAL QUE UNO BORRADO.
//
// Es el agujero que abría el filtro de PEDIDO y que taparon el 26/09/2026 a petición de
// este lado: desde que sólo avisan de lo que ya lleva domicilio y factura, a un pedido al
// que le quitan el domicilio o le anulan la factura **no le llegaba ningún aviso**. Se
// quedaba aquí para siempre, en la lista de disponibles, y alguien acaba metiéndolo en un
// camión. Antes lo arreglaba solo el barrido; con avisos filtrados, no.
func TestUnPedidoQueYaNoVaSeQuita(t *testing.T) {
	q := AgruparAvisos([]AvisoDePedido{
		{ID: "1-0", Motivo: MotivoYaNoVa, PedidoID: "ped-1", SucursalID: "cam"},
	})

	if len(q.Borrados) != 1 || q.Borrados[0] != "ped-1" {
		t.Fatalf(
			"un pedido que dejó de ser repartible se queda en el reparto: acaba en un "+
				"camión y nadie lo echa en falta. %+v", q,
		)
	}
	if len(q.Pedidos) != 0 {
		t.Fatalf("se fue a pedirlo en vez de quitarlo: traerlo lo deja donde estaba")
	}
}

// Y si en la misma tanda se actualizó y después dejó de ir, manda el «ya no va».
func TestYaNoVaMandaSobreUnTraer(t *testing.T) {
	q := AgruparAvisos([]AvisoDePedido{
		{ID: "1-0", Motivo: MotivoFactura, PedidoID: "ped-1"},
		{ID: "1-1", Motivo: MotivoYaNoVa, PedidoID: "ped-1"},
	})

	if len(q.Pedidos) != 0 {
		t.Fatalf("se trae un pedido que acaba de dejar de ser repartible: %+v", q)
	}
}

// LOS AVISOS QUE NO LLEVAN A NADA SE CUENTAN, Y SE DICE POR QUÉ.
//
// Lo pidió la sesión de PEDIDO y es justo lo que desde allá no se puede ver: ellos ven que
// mandaron el aviso, y **uno que sale y no lleva a nada se ve exactamente igual que uno que
// funcionó**. Lo que pasó después sólo se ve aquí.
//
// NO SON FALLOS: un pedido repetido en la misma tanda, o un traer que un borrado anuló, es
// el sistema haciendo lo correcto. Lo que hace falta es poder DECIRLO — «de veinte avisos,
// tres llevaron a algo» y «veinte de veinte» son dos situaciones distintas que se arreglan
// en sitios distintos.
func TestSeCuentanLosAvisosQueNoLlevaronANada(t *testing.T) {
	q := AgruparAvisos([]AvisoDePedido{
		// Dos del mismo pedido: uno se pide, el otro sobra.
		{ID: "1-0", Motivo: MotivoDomicilio, PedidoID: "ped-1"},
		{ID: "1-1", Motivo: MotivoFactura, PedidoID: "ped-1"},
		// Y uno que se anula solo: se actualizó y después se borró.
		{ID: "1-2", Motivo: MotivoFactura, PedidoID: "ped-2"},
		{ID: "1-3", Motivo: MotivoBorrado, PedidoID: "ped-2"},
	})

	if q.SinEfecto == 0 {
		t.Fatalf(
			"no se contó ningún aviso sin efecto: desde PEDIDO no hay forma de ver la "+
				"diferencia entre «llegó y sirvió» y «llegó y no hizo nada». %+v", q,
		)
	}
	if q.PorQueSinEfecto == "" {
		t.Fatalf("se cuentan pero no se dice por qué: un número solo no lleva a ninguna acción")
	}
}

// Y CUANDO TODOS SIRVEN, NO SE INVENTA NINGUNO. Sin esta mitad, «se cuentan» se cumple
// contando siempre, y la pantalla diría que se descarta trabajo que sí se hizo.
func TestConTodosLosAvisosUtilesNoSeCuentaNinguno(t *testing.T) {
	q := AgruparAvisos([]AvisoDePedido{
		{ID: "1-0", Motivo: MotivoFactura, PedidoID: "ped-1"},
		{ID: "1-1", Motivo: MotivoFactura, PedidoID: "ped-2"},
	})

	if q.SinEfecto != 0 {
		t.Fatalf("se contaron %d sin efecto habiendo servido los dos: %q",
			q.SinEfecto, q.PorQueSinEfecto)
	}
}
