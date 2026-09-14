package cotizar

import (
	"context"
	"strings"
	"sync"
	"time"
)

// LA TASA USD→CUP POR SUCURSAL (§8 de reglas-negocio.md).
//
// REGLA DE FONDO: la tasa SE PIDE A ACCESOS, NO SE TECLEA AQUÍ. Antes vivía en
// Configuración → «Monedas»: alguien escribía un número a mano y ése usaba toda la
// aplicación, mientras PEDIDO la traía de Entrega. *Dos tasas para lo mismo se separan en
// cuanto una se olvida —y se olvida, porque la de aquí no la refresca nadie—, y el mismo
// domicilio vale distinto según dónde se mire. Eso no falla en pantalla: sale un importe
// creíble y cuadra mal en la caja, que es donde se descubre tarde.*
//
// Aquí NO hay ninguna copia editable. Si Accesos no contesta, no hay tasa, y se dice.

// Tasa es lo que Accesos devuelve de una sucursal.
type Tasa struct {
	Codigo    string
	CupPorUsd float64
	// TarifaBase son CUP por km y por kg: lo que Entrega cobra por el domicilio.
	// nil = esa sucursal todavía no la tiene puesta. Viaja hasta aquí para que un pedido
	// metido a mano salga por el mismo número que uno del teléfono.
	TarifaBase *float64
	Fuente     *string
	TraidoAt   string
	// Fresca la decide ACCESOS, no este servicio: es «lleva demasiado sin actualizarse
	// allí». Ausente en la respuesta significa true.
	Fresca bool
}

// Los dos tiempos de la caché (apéndice de constantes). Viven en memoria del proceso y se
// pierden al reiniciar, que es lo correcto para un dato que no es nuestro.
const (
	// RecuerdoDeTasa: 5 min para una tasa que SÍ existe.
	//
	// POR QUÉ HAY CACHÉ: el costo se calcula por lotes de 200 pedidos y cada uno necesita
	// la tasa de SU sucursal; sin esto son 200 llamadas a Accesos por tanda. Y dura poco
	// a propósito: la tasa se mueve a diario, no por minuto.
	RecuerdoDeTasa = 5 * time.Minute

	// RecuerdoSinTasa: 20 s para el «no hay tasa».
	//
	// POR QUÉ MUCHO MENOS: «esta sucursal todavía no tiene» es un estado que alguien está
	// arreglando AHORA MISMO: se pone en Entrega, Accesos la trae… y aquí seguíamos
	// diciendo que no hay durante cinco minutos más. *Pasó de verdad: la tasa estaba
	// puesta y la pantalla seguía en USD.*
	RecuerdoSinTasa = 20 * time.Second
)

// PreguntarTasa es la llamada firmada a Accesos (`GET /api/service/tasas?codigo=…`).
// Devuelve nil cuando Accesos contesta 200 con `tasa: null` — que una sucursal no tenga
// tasa es un estado NORMAL, no un error, y por eso no viene como 404.
type PreguntarTasa func(ctx context.Context, codigo string) (*Tasa, error)

type recuerdo struct {
	tasa   *Tasa // puede ser nil: el «no hay» también se recuerda
	cuando time.Time
}

// RecuerdoDeTasas es la caché por código de sucursal.
type RecuerdoDeTasas struct {
	preguntar PreguntarTasa
	ahora     func() time.Time // inyectable para poder probar los TTL sin dormir

	mu       sync.Mutex
	guardado map[string]recuerdo
}

// NuevoRecuerdoDeTasas construye la caché. `ahora` puede ser nil (se usa time.Now).
func NuevoRecuerdoDeTasas(preguntar PreguntarTasa, ahora func() time.Time) *RecuerdoDeTasas {
	if ahora == nil {
		ahora = time.Now
	}
	return &RecuerdoDeTasas{preguntar: preguntar, ahora: ahora, guardado: map[string]recuerdo{}}
}

// DeSucursal es `tasaDeSucursal(codigo)`.
//
// NUNCA DEVUELVE LA DE OTRA SUCURSAL. Es el error que más daño hace aquí: *convertir un
// importe de Granma con la tasa de La Habana da un número creíble que nadie cuestiona, y
// aparece en la caja.* Sin tasa, el pedido se queda sin precio en CUP y se dice de qué
// sucursal falta.
func (c *RecuerdoDeTasas) DeSucursal(ctx context.Context, codigo string) *Tasa {
	clave := strings.ToUpper(strings.TrimSpace(codigo))
	if clave == "" {
		return nil // sin código no hay nada que preguntar
	}

	c.mu.Lock()
	guardada, habia := c.guardado[clave]
	c.mu.Unlock()

	if habia {
		// EL TTL DEPENDE DE LO RECORDADO: cinco minutos si hay tasa, veinte segundos si
		// lo recordado es un «no hay».
		dura := RecuerdoSinTasa
		if guardada.tasa != nil {
			dura = RecuerdoDeTasa
		}
		if c.ahora().Sub(guardada.cuando) < dura {
			return guardada.tasa // se devuelve lo guardado, INCLUIDO el nil
		}
	}

	if c.preguntar == nil {
		// Sin cliente de Accesos montado no hay tasa. No se inventa ninguna ni se echa
		// mano de la de otra sucursal.
		return nil
	}

	t, err := c.preguntar(ctx, clave)
	if err != nil {
		// SE DEVUELVE LO ÚLTIMO QUE SE SUPO, AUNQUE ESTÉ PASADO, Y SIN REFRESCAR LA MARCA
		// DE TIEMPO. *Una tasa de ayer convierte con un error pequeño, y sin ninguna no se
		// puede cotizar ni un pedido.* Lo que no se hace es guardarlo como si fuera
		// fresco: se devuelve tal cual, con su fecha, y quien lo enseñe puede avisar.
		if habia {
			return guardada.tasa
		}
		return nil
	}

	// Al pedir con éxito se cachea TAMBIÉN el nil: «esta sucursal no tiene» es una
	// respuesta, y repreguntarla por cada uno de los 200 pedidos del lote no cambia nada.
	c.mu.Lock()
	c.guardado[clave] = recuerdo{tasa: t, cuando: c.ahora()}
	c.mu.Unlock()
	return t
}
