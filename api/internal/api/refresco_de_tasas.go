// EL REFRESCO DE LA TASA DE CAMBIO DE CADA SUCURSAL.
//
// Una tarea de fondo que le pregunta a Accesos la tasa de las ocho sucursales y la deja
// escrita en `branches.cup_rate*`. De ahí la recoge la bajada del día
// (`GET /api/sync/cambios`, colección `branches`) y llega al aparato, que es lo único que
// importa: **esta aplicación tiene que funcionar sin conexión**, y una tasa que hay que ir
// a buscar por la red no sirve para pintar un importe a las cuatro de la tarde en el patio
// de un almacén de Granma.
//
// # Por qué una tarea de fondo y no al servir las sucursales
//
// Se consideró refrescar dentro del manejador de la bajada, apoyándose en la caché que ya
// hay (`recuerdoDeTasas`, 5 min con tasa / 20 s sin ella). Se descartó por dos razones,
// y cualquiera de las dos basta:
//
//  1. **Metería la red de Accesos DENTRO de la bajada del día.** La bajada es la petición
//     de la mañana, la que se hace con la peor conexión del día y la que no puede
//     tardar: ocho llamadas a Accesos en serie delante de ella son ocho formas nuevas de
//     que se quede colgada. Y si Accesos tarda, lo que se retrasa no es la tasa — es el
//     día entero del logístico.
//  2. **El TTL corto de la caché se vuelve en contra.** Los veinte segundos del «no hay
//     tasa» existen para que la pantalla web se entere enseguida de que alguien acaba de
//     poner la tasa en Entrega. Aquí, con SEIS sucursales sin tasa (el dato de
//     producción de hoy), eso serían seis llamadas a Accesos cada veinte segundos por
//     cada aparato que baje: más de mil por hora. Eso es justamente lo que no vale.
//
// # Cada cuánto, y por qué no las 12 h de PEDIDO
//
// PEDIDO refresca cada 12 h (`PEDIDO/api/src/lib/tasaCambio.ts`) y tiene razón para ello,
// pero tiene además algo que aquí no hay: cuando la tasa cambia, `emitEvent('tasa')` va
// por Redis al SSE y las pantallas abiertas se enteran al momento. Las 12 h son sólo la
// red por si el aviso no llega.
//
// Aquí no hay ese canal, y quien consume esto no es una pantalla abierta: es un aparato
// que baja el día una o dos veces. Si refrescáramos cada 12 h, una tasa puesta en Entrega
// a las nueve de la mañana podría no entrar en la bajada de mañana por la mañana — un día
// entero de retraso para un número con el que se cobra.
//
// Una hora acota eso a una hora y cuesta OCHO llamadas a Accesos por hora. Es
// intencionadamente mucho más barato que lo que se descartó arriba: allí eran ocho por
// aparato y por bajada, aquí son ocho en total, las bajen diez aparatos o ninguno.
package api

import (
	"context"
	"log/slog"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

// RefrescoCada es cada cuánto se le pregunta a Accesos por defecto. Se puede mover con
// `TASA_REFRESCO_MS`; ver el porqué de la hora en la cabecera del fichero.
const RefrescoCada = time.Hour

// FuenteDeTasas es por dónde llega el Querier.
//
// **Sí, aquí hay un Querier y en un manejador no lo habría.** La regla de `servidor.go`
// —«el manejador NO recibe un `sqlc.Querier`, recibe `*alcance.Acotado`»— existe para que
// no se pueda consultar sin alcance por sucursal. Esto no es un manejador: no hay petición,
// no hay token y no hay persona, así que no hay alcance que resolver. Al revés: acotar esto
// sería el fallo, porque dejaría sin tasa a las siete sucursales que no fueran la del
// último que entró. Lo que sí se respeta es que las dos consultas que usa están escritas y
// explicadas en `db/queries/branches.sql`, no armadas aquí a mano.
type FuenteDeTasas interface {
	Consultas() sqlc.Querier
}

// RefrescoDeTasas es la tarea. Una por proceso.
type RefrescoDeTasas struct {
	fuente FuenteDeTasas
	tasas  ClienteTasas
	reg    *slog.Logger
	cada   time.Duration
}

// NuevoRefrescoDeTasas lo construye. `tasas` nil coge el cliente de paquete, que es el que
// habla con Accesos de verdad; las pruebas pasan el suyo.
func NuevoRefrescoDeTasas(f FuenteDeTasas, tasas ClienteTasas, reg *slog.Logger, cada time.Duration) *RefrescoDeTasas {
	if reg == nil {
		reg = slog.Default()
	}
	if tasas == nil {
		tasas = Tasas
	}
	if cada <= 0 {
		cada = RefrescoCada
	}
	return &RefrescoDeTasas{fuente: f, tasas: tasas, reg: reg, cada: cada}
}

// Correr da una vuelta AL ARRANCAR y luego una cada `cada`, hasta que se cancele el
// contexto.
//
// La primera vuelta va al arrancar y no cuando venza el primer plazo: un despliegue a las
// ocho de la mañana con la tasa nueva ya puesta en Entrega tiene que servirla en la bajada
// de las ocho y cinco, no en la de las nueve.
func (t *RefrescoDeTasas) Correr(ctx context.Context) {
	t.UnaVuelta(ctx)

	reloj := time.NewTicker(t.cada)
	defer reloj.Stop()
	for {
		select {
		case <-ctx.Done():
			t.reg.Info("refresco de tasas parado")
			return
		case <-reloj.C:
			t.UnaVuelta(ctx)
		}
	}
}

// UnaVuelta pregunta por todas las sucursales y guarda lo que venga. Exportada para poder
// probarla sin esperar a un tic.
//
// Devuelve cuántas sucursales quedaron con la tasa cambiada — 0 es lo NORMAL en la segunda
// vuelta y en todas las demás del día, porque la tasa se mueve a diario y no por hora.
func (t *RefrescoDeTasas) UnaVuelta(ctx context.Context) int {
	q := t.fuente.Consultas()
	filas, err := q.CodigosParaRefrescarLaTasa(ctx)
	if err != nil {
		t.reg.Error("no se pudo listar las sucursales para refrescar la tasa", "err", err)
		return 0
	}

	cambiadas := 0
	sinTasa := make([]string, 0, len(filas))
	for _, f := range filas {
		if ctx.Err() != nil {
			return cambiadas // nos están parando: se deja a medias y no se insiste
		}
		codigo := strings.ToUpper(strings.TrimSpace(*f.ExternalID))

		tasa, err := t.tasas.TasaDeSucursal(ctx, codigo)
		if err != nil {
			// ACCESOS NO CONTESTÓ. No se toca nada: lo que hay guardado sigue siendo lo
			// último que se supo, con su fecha puesta al lado para que quien lo mire sepa
			// de cuándo es. Escribir aquí sería convertir un tropiezo de red en una
			// sucursal que se queda sin poder ver CUP.
			t.reg.Warn("Accesos no dio la tasa: se deja la guardada",
				"sucursal", codigo, "err", err)
			continue
		}
		if tasa == nil {
			// «ESTA SUCURSAL NO TIENE TASA» — un estado normal, no un error: hoy, en
			// producción, seis de las ocho están así, y Accesos lo dice con un 200.
			//
			// TAMPOCO SE BORRA LO QUE HUBIERA. Es la decisión que menos se ve venir de
			// todo esto, así que va escrita: un `null` de Accesos y un «nunca la tuvo» se
			// parecen desde aquí, y el precio de equivocarse no es simétrico. Si nos
			// equivocamos borrando, un aparato que está en la calle pierde el CUP con una
			// tasa que sigue siendo buena y no hay forma de devolvérselo hasta la próxima
			// bajada. Si nos equivocamos NO borrando, se sigue enseñando una tasa con su
			// fecha delante — y la fecha es lo que cuenta la verdad (regla 3).
			//
			// La tasa de una sucursal la quita quien la puso, en Entrega. Aquí no.
			sinTasa = append(sinTasa, codigo)
			continue
		}

		filasTocadas, err := q.GuardarTasaDeSucursal(ctx, sqlc.GuardarTasaDeSucursalParams{
			ExternalID:      f.ExternalID,
			CupRate:         tasa.CupPorUsd,
			CupRateFuente:   tasa.Fuente,
			CupRateTraidoAt: marcaDeTasa(tasa.TraidoAt),
			CupRateFresca:   tasa.Fresca,
		})
		if err != nil {
			t.reg.Error("no se pudo guardar la tasa", "sucursal", codigo, "err", err)
			continue
		}
		if filasTocadas > 0 {
			cambiadas++
			t.reg.Info("tasa de cambio actualizada",
				"sucursal", codigo, "cupPorUsd", tasa.CupPorUsd,
				"traidoAt", tasa.TraidoAt, "fresca", tasa.Fresca)
		}
	}

	if len(sinTasa) > 0 {
		// Se dice UNA vez por vuelta y con los códigos dentro. «No hay tasa» a secas
		// obliga a adivinar cuál de las ocho falta, que es lo que no se puede arreglar.
		t.reg.Info("sucursales sin tasa en Accesos: sus importes se quedan en USD",
			"sucursales", strings.Join(sinTasa, ","))
	}
	return cambiadas
}

// marcaDeTasa lee el `traidoAt` de Accesos, que viene en texto ISO.
//
// Una fecha que no se entienda se guarda como NULL, y eso NO es un detalle: la marca es lo
// único que demuestra que la tasa existe de verdad (el esquema viejo traía 320 por defecto,
// así que el número no demuestra nada). Guardar la tasa sin fecha la deja inutilizable a
// propósito, que es mucho mejor que guardarla con una fecha inventada.
func marcaDeTasa(iso string) pgtype.Timestamptz {
	t, err := time.Parse(time.RFC3339, strings.TrimSpace(iso))
	if err != nil {
		return pgtype.Timestamptz{}
	}
	return pgtype.Timestamptz{Time: t, Valid: true}
}
