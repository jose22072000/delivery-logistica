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
