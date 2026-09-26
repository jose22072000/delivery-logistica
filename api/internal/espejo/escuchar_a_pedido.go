package espejo

import (
	"context"
	"errors"
	"log/slog"
	"time"
)

// EL BUCLE QUE ESCUCHA A PEDIDO.
//
// Lee bloqueado del stream y reacciona a cada aviso. **No hay sondeo**: `XReadGroup` con
// `BLOCK` devuelve en cuanto entra algo. Jose, 26/09/2026: «que notifique ya cada vez que
// salga uno, así entra directo, que compruebe y ya envíe; nada de polling».
//
// EL ORDEN DE UNA VUELTA, y cada paso está donde está por algo:
//
//  1. Se leen hasta [CuantosDeUnaVez] avisos (o se espera a que entre uno).
//  2. Se AGRUPAN por sucursal. Si en dos segundos llegan cien avisos de Camagüey se pide
//     un lote y no cien: mandar una petición por aviso es volver al problema de origen por
//     el otro lado.
//  3. Se trae y se guarda.
//  4. Y SÓLO ENTONCES se reconocen (`XACK`). Reconocer antes y fallar el guardado es
//     perder ese pedido sin que nadie se entere.
//
// De vez en cuando se recogen los colgados: lo que otra réplica cogió y no llegó a
// reconocer porque se cayó. Sin eso, un reinicio en mal momento pierde pedidos en silencio,
// que es justo lo que el stream venía a evitar.

// QueHaceFaltaTraer resume una tanda de avisos ya agrupada: a quién hay que ir a buscar.
//
// Se separa del bucle para poder probarla sin Redis y sin PEDIDO: lo que decide qué se
// pide es esto, y es donde se puede meter un fallo caro.
type QueHaceFaltaTraer struct {
	// Pedidos concretos, por su id en PEDIDO.
	Pedidos []string
	// Sucursales que hay que repasar enteras: llegó una tanda de CSV y no viene `id`.
	Sucursales []string
	// Lo que hay que QUITAR de la base del reparto. Es el único motivo que no requiere ir
	// a pedir nada, y el único que si se ignora deja un pedido en un camión que ya no
	// existe y nadie lo echa en falta.
	Borrados []string
	// Si alguno llegó sin sucursal: hay que mirar todas. Debería ser raro.
	TodasLasSucursales bool
}

// AgruparAvisos convierte una tanda en qué hay que hacer.
//
// SIN REPETIDOS: el mismo pedido puede venir dos veces en la misma tanda —se le puso el
// domicilio y a los dos segundos apareció la factura— y pedirlo dos veces es pagar dos
// vueltas por la conexión de allá para escribir lo mismo.
//
// UN BORRADO MANDA SOBRE UN TRAER. Si en la misma tanda un pedido se actualizó y después
// se borró, lo que vale es el borrado: traerlo lo resucitaría, y un pedido resucitado se
// carga en un camión.
func AgruparAvisos(avisos []AvisoDePedido) QueHaceFaltaTraer {
	var q QueHaceFaltaTraer
	pedidos := map[string]bool{}
	sucursales := map[string]bool{}
	borrados := map[string]bool{}

	for _, a := range avisos {
		switch a.Motivo {
		case MotivoBorrado:
			if a.PedidoID != "" {
				borrados[a.PedidoID] = true
			}
		case MotivoFactura, MotivoDomicilio:
			if a.PedidoID != "" {
				pedidos[a.PedidoID] = true
				continue
			}
			// Un aviso de factura sin id no dice a quién traer. No se descarta en
			// silencio: se repasa su sucursal, que es lo que sí se puede hacer.
			if a.SucursalID != "" {
				sucursales[a.SucursalID] = true
			} else {
				q.TodasLasSucursales = true
			}
		case MotivoImportacion:
			if a.SucursalID != "" {
				sucursales[a.SucursalID] = true
			} else {
				q.TodasLasSucursales = true
			}
		default:
			// UN MOTIVO QUE NO SE CONOCE NO SE TIRA. Puede ser uno nuevo de PEDIDO contra
			// una versión vieja de esto: se repasa su sucursal, que es la reacción segura
			// —cuesta una vuelta y no pierde nada—. Descartarlo sería perder el pedido
			// sin un solo error.
			if a.SucursalID != "" {
				sucursales[a.SucursalID] = true
			} else {
				q.TodasLasSucursales = true
			}
		}
	}

	for id := range pedidos {
		// El borrado manda: ver el encabezado.
		if borrados[id] {
			continue
		}
		q.Pedidos = append(q.Pedidos, id)
	}
	for id := range sucursales {
		q.Sucursales = append(q.Sucursales, id)
	}
	for id := range borrados {
		q.Borrados = append(q.Borrados, id)
	}
	return q
}

// Escuchador es el bucle. Se monta una vez y se corre con el contexto del proceso.
type Escuchador struct {
	lector         LectorDeAvisos
	stream         string
	grupo          string
	quien          string
	reg            *slog.Logger
	atender        func(ctx context.Context, q QueHaceFaltaTraer) error
	ultimaRecogida time.Time
}

// NuevoEscuchador lo arma. `atender` es lo que hace el trabajo de verdad —traer y
// guardar—, y se pasa desde fuera para que este fichero no sepa nada de PEDIDO ni de la
// base: así se prueba el bucle sin levantar ninguna de las dos.
func NuevoEscuchador(
	lector LectorDeAvisos, o Opciones, reg *slog.Logger,
	atender func(ctx context.Context, q QueHaceFaltaTraer) error,
) *Escuchador {
	stream := o.Stream
	if stream == "" {
		stream = StreamPorDefecto
	}
	if reg == nil {
		reg = slog.Default()
	}
	return &Escuchador{
		lector: lector, stream: stream, grupo: GrupoDelEspejo,
		quien: QuienConsume(), reg: reg, atender: atender,
	}
}

// Correr crea el grupo y se queda escuchando hasta que se cancele el contexto.
func (e *Escuchador) Correr(ctx context.Context) error {
	// EL GRUPO, LO PRIMERO. Mientras no exista, PEDIDO acumula avisos y su pantalla lo
	// dice con esas palabras: «el reparto todavía no ha creado su grupo de lectura».
	if err := e.lector.CrearGrupo(ctx, e.stream, e.grupo); err != nil {
		return err
	}
	e.reg.Info("escuchando los avisos de PEDIDO",
		"stream", e.stream, "grupo", e.grupo, "consumidor", e.quien)

	for {
		if ctx.Err() != nil {
			e.reg.Info("se deja de escuchar a PEDIDO")
			return nil
		}
		e.UnaVuelta(ctx)
	}
}

// UnaVuelta lee, atiende y reconoce. Exportada para poder probarla sin bucle ni relojes.
func (e *Escuchador) UnaVuelta(ctx context.Context) {
	avisos, err := e.lector.Leer(ctx, e.stream, e.grupo, e.quien, CuantosDeUnaVez, CuantoSeEspera)
	if err != nil && !errors.Is(err, context.Canceled) {
		// Redis caído no puede tumbar el espejo: el ciclo lento es la red de debajo y
		// sigue trayendo lo suyo. Se dice y se vuelve a intentar.
		e.reg.Warn("no se pudo leer el canal de avisos de PEDIDO", "err", err)
		return
	}

	// LOS COLGADOS, de vez en cuando. Lo que otra réplica cogió y no reconoció porque se
	// cayó: con `>` nadie los volvería a leer nunca.
	if time.Since(e.ultimaRecogida) > CadaCuantoSeRecogenLosColgados {
		e.ultimaRecogida = time.Now()
		colgados, err := e.lector.RecogerColgados(ctx, e.stream, e.grupo, e.quien,
			CuantoAguantaUnColgado, CuantosDeUnaVez)
		if err != nil {
			e.reg.Warn("no se pudieron recoger los avisos colgados", "err", err)
		} else if len(colgados) > 0 {
			e.reg.Info("se recogen avisos que otro consumidor dejó a medias",
				"cuantos", len(colgados))
			avisos = append(avisos, colgados...)
		}
	}

	if len(avisos) == 0 {
		return
	}

	q := AgruparAvisos(avisos)
	if err := e.atender(ctx, q); err != nil {
		// NO SE RECONOCE. Si se reconociera, estos avisos no los vuelve a leer nadie y
		// esos pedidos se pierden sin un solo error. Quedan «cogidos» y los recoge la
		// pasada de colgados, o la siguiente réplica.
		e.reg.Error("no se pudo atender la tanda de avisos: NO se reconocen",
			"avisos", len(avisos), "pedidos", len(q.Pedidos),
			"sucursales", len(q.Sucursales), "borrados", len(q.Borrados), "err", err)
		return
	}

	ids := make([]string, 0, len(avisos))
	for _, a := range avisos {
		ids = append(ids, a.ID)
	}
	if err := e.lector.Reconocer(ctx, e.stream, e.grupo, ids...); err != nil {
		// Ya está guardado, así que no se pierde nada: el aviso se volverá a leer y el
		// guardado es un upsert. Se dice porque si esto pasa siempre, `XPENDING` crece y
		// alguien tiene que mirarlo.
		e.reg.Warn("la tanda se guardó pero no se pudo reconocer", "avisos", len(ids), "err", err)
		return
	}
	e.reg.Info("tanda de avisos de PEDIDO atendida",
		"avisos", len(ids), "pedidos", len(q.Pedidos),
		"sucursales", len(q.Sucursales), "borrados", len(q.Borrados))
}
