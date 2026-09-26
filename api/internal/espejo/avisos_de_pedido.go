package espejo

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

// PEDIDO AVISA Y EL ESPEJO ENTRA. Sin sondeo.
//
// Hasta el 26/09/2026 el espejo preguntaba cada minuto, sucursal por sucursal, y además
// repasaba siempre los últimos tres días: unas diez vueltas por minuto para enterarse de
// que casi nunca había novedades. Ese es el origen de los 98 millones de escrituras sobre
// 8.673 clientes.
//
// Ahora PEDIDO deja un aviso en un stream de Redis cada vez que un pedido pasa a
// importarle al reparto, y esto lo lee **bloqueado**: entra en cuanto lo sueltan. Jose,
// 26/09/2026: «que notifique ya cada vez que salga uno, así entra directo, que compruebe y
// ya envíe; no que espere cada 15 min, nada de polling».
//
// El contrato entero lo escribió la otra sesión en `procovar/docs/para-delivery-logistica.md`.
//
// # Por qué un stream y no el pub/sub que ya existía
//
// Con pub/sub, un aviso que sale mientras el reparto se está reiniciando **no llega nunca y
// no hay forma de notarlo**. El stream espera a que alguien lo lea.
//
// # Las tres reglas del grupo de consumidores, y ninguna es opcional
//
//  1. **`XACK` sólo DESPUÉS de guardar.** Reconocer antes y fallar el guardado es perder
//     ese pedido sin que nadie se entere.
//  2. **Llega al menos una vez, y a veces dos.** Tras un reinicio el mismo aviso puede
//     repetirse: el guardado es un upsert, así que aplicarlo dos veces deja lo mismo.
//  3. **Los colgados se recogen.** `XAUTOCLAIM` de vez en cuando para lo que un consumidor
//     cogió y no llegó a reconocer porque se cayó.
//
// # Y el ciclo NO se quita
//
// Es la red debajo del trapecio: si Redis se cae, si un aviso se pierde, o si alguien
// corrige la base por SQL sin tocar `updatedAt`, el ciclo lo recoge igual. Lo que hace es
// ir mucho más despacio.

const (
	// StreamPorDefecto es el que escribe PEDIDO. Se cambia con `DELIVERY_STREAM`, y tiene
	// que ser EL MISMO nombre en los dos lados o cada uno habla solo.
	StreamPorDefecto = "procovar-delivery:in:orders"

	// GrupoDelEspejo es el nombre del grupo de consumidores. Es lo que hace que dos
	// réplicas del espejo no se pisen y que se sepa qué queda por leer.
	//
	// Mientras este grupo no exista, la pantalla de PEDIDO dice «el reparto todavía no ha
	// creado su grupo de lectura: los avisos se acumulan esperándolo». Crearlo es lo
	// primero que hace esto al arrancar.
	GrupoDelEspejo = "espejo"

	// CuantoSeEspera es lo que la lectura se queda bloqueada esperando.
	//
	// NO ES UN SONDEO: `XReadGroup` con `BLOCK` devuelve EN CUANTO entra un aviso. El
	// plazo sólo existe para poder mirar si nos están parando y para recoger los colgados
	// de vez en cuando; sin él, un `Correr` no se enteraría de que hay que salir.
	CuantoSeEspera = 5 * time.Second

	// CuantosDeUnaVez: cuántos avisos se cogen por lectura.
	//
	// Agrupar importa: si en dos segundos llegan cien avisos de la misma sucursal, se
	// piden en un lote y no de uno en uno, que es volver al problema por el otro lado.
	CuantosDeUnaVez = 200

	// CadaCuantoSeRecogenLosColgados: cada cuánto se mira si un consumidor caído dejó
	// avisos cogidos y sin reconocer.
	CadaCuantoSeRecogenLosColgados = time.Minute

	// CuantoAguantaUnColgado: a partir de cuándo un aviso cogido y sin reconocer se
	// considera abandonado. Generoso a propósito: un lote grande con la conexión de allá
	// puede tardar, y robárselo a quien lo está trabajando es duplicar el trabajo.
	CuantoAguantaUnColgado = 5 * time.Minute
)

// Los cuatro motivos. Son los cuatro momentos en que un pedido pasa a importarle al
// reparto, y cada uno lleva a una acción distinta — un aviso que no lleva a ninguna acción
// es volver a llenar la cola por gusto.
const (
	// MotivoFactura: apareció la factura o cambió. Ya se puede cargar: se trae.
	MotivoFactura = "factura"
	// MotivoDomicilio: le pusieron el precio del domicilio. Es repartible: se trae.
	MotivoDomicilio = "domicilio"
	// MotivoImportacion: entró una tanda de CSV. Viene SIN `id`: se repasa esa sucursal.
	MotivoImportacion = "importacion"
	// MotivoYaNoVa: este pedido DEJÓ de ser repartible. Se quita, igual que un borrado.
	//
	// Es el agujero que abría el filtro y que PEDIDO tapó el 26/09/2026 a petición de
	// este lado. Desde que sólo avisan de lo que ya lleva domicilio y factura, a un
	// pedido al que le quitan el domicilio o le anulan la factura **no le llegaba ningún
	// aviso**: se quedaba aquí para siempre, en la lista de disponibles, y alguien acaba
	// metiéndolo en un camión. Antes lo arreglaba solo el barrido; con avisos filtrados,
	// no.
	//
	// **Viene SIN el pedido dentro, y es a propósito**: lo que dice es «quítalo», y
	// mandarlo con sus datos invita a guardarlo otra vez.
	MotivoYaNoVa = "ya_no_va"
	// MotivoCliente: un cliente se movió de sitio. **El `id` es el del CLIENTE, no el de
	// un pedido**, y la entidad viene como `cliente`.
	//
	// Lo añadió PEDIDO el 26/09/2026 porque el reparto ordena las paradas por la
	// coordenada del cliente: si alguien corrige dónde vive y el reparto no se entera, la
	// ruta se arma hacia el sitio de antes — con números y todo, sin un solo error.
	MotivoCliente = "cliente"
	// MotivoBorrado: se borró el pedido. **Se quita**, o se queda en un camión y nadie lo
	// echa en falta. Es el único que no requiere ir a pedir nada.
	MotivoBorrado = "borrado"
)

// AvisoDePedido es una entrada del stream, ya leída.
type AvisoDePedido struct {
	ID         string // el id de la entrada en el stream, para el XACK
	Entidad    string
	Motivo     string
	Accion     string
	PedidoID   string // vacío en los avisos de tanda
	SucursalID string // vacío = no se sabe, hay que mirar todas
	Ts         string
}

// LectorDeAvisos es lo que hace falta de Redis, y nada más.
//
// ES UNA INTERFAZ para que las pruebas no necesiten un Redis: se corren en cada
// compilación y no «cuando haya uno a mano». Es la misma razón por la que `FuenteDePedidos`
// lo es.
type LectorDeAvisos interface {
	CrearGrupo(ctx context.Context, stream, grupo string) error
	Leer(ctx context.Context, stream, grupo, consumidor string, cuantos int, espera time.Duration) ([]AvisoDePedido, error)
	Reconocer(ctx context.Context, stream, grupo string, ids ...string) error
	RecogerColgados(ctx context.Context, stream, grupo, consumidor string, desdeHace time.Duration, cuantos int) ([]AvisoDePedido, error)
}

// QuienConsume es el nombre de este consumidor dentro del grupo.
//
// El hostname, que en Swarm es el id del contenedor: así dos réplicas se distinguen y, si
// una se cae, se ve cuál dejó avisos colgados.
func QuienConsume() string {
	n, err := os.Hostname()
	if err != nil || strings.TrimSpace(n) == "" {
		return "espejo"
	}
	return n
}

// RedisDeAvisos es el lector de verdad.
type RedisDeAvisos struct{ c redis.UniversalClient }

// NuevoRedisDeAvisos monta el cliente contra el Redis de la casa.
//
// VA POR CENTINELA, que es como está montado el Redis de Procovar (`procovar-sentinel`):
// es la regla de la casa y las aplicaciones esperan esa forma de conexión. Si no se le dan
// centinelas, se conecta directo — que es lo que hace falta en local.
func NuevoRedisDeAvisos(o Opciones) *RedisDeAvisos {
	if len(o.RedisCentinelas) > 0 {
		return &RedisDeAvisos{c: redis.NewFailoverClient(&redis.FailoverOptions{
			MasterName:    o.RedisMaestro,
			SentinelAddrs: o.RedisCentinelas,
			Password:      o.RedisClave,
			DB:            o.RedisBase,
		})}
	}
	return &RedisDeAvisos{c: redis.NewClient(&redis.Options{
		Addr:     o.RedisDireccion,
		Password: o.RedisClave,
		DB:       o.RedisBase,
	})}
}

// CrearGrupo lo crea si no está. `MKSTREAM` crea también el stream: si el espejo arranca
// antes de que PEDIDO haya escrito el primer aviso, sin eso fallaría con «no such key».
//
// Que ya exista NO es un error: es lo normal en el segundo arranque.
func (r *RedisDeAvisos) CrearGrupo(ctx context.Context, stream, grupo string) error {
	err := r.c.XGroupCreateMkStream(ctx, stream, grupo, "0").Err()
	if err != nil && strings.Contains(err.Error(), "BUSYGROUP") {
		return nil
	}
	return err
}

func (r *RedisDeAvisos) Leer(
	ctx context.Context, stream, grupo, consumidor string, cuantos int, espera time.Duration,
) ([]AvisoDePedido, error) {
	res, err := r.c.XReadGroup(ctx, &redis.XReadGroupArgs{
		Group:    grupo,
		Consumer: consumidor,
		Streams:  []string{stream, ">"},
		Count:    int64(cuantos),
		Block:    espera,
	}).Result()
	// `redis.Nil` es «se acabó el plazo y no entró nada». Es lo NORMAL en un rato tranquilo
	// y no un fallo: devolverlo como error llenaría el registro de errores que no lo son.
	if errors.Is(err, redis.Nil) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return deLosMensajes(res), nil
}

func (r *RedisDeAvisos) Reconocer(ctx context.Context, stream, grupo string, ids ...string) error {
	if len(ids) == 0 {
		return nil
	}
	return r.c.XAck(ctx, stream, grupo, ids...).Err()
}

// RecogerColgados se lleva lo que otro consumidor cogió y no reconoció.
//
// Pasa cuando una réplica se cae a mitad de un lote: sus avisos quedan «cogidos» y nadie
// los volvería a leer con `>`. Sin esto, un reinicio en mal momento pierde pedidos en
// silencio, que es justo lo que el stream venía a evitar.
func (r *RedisDeAvisos) RecogerColgados(
	ctx context.Context, stream, grupo, consumidor string, desdeHace time.Duration, cuantos int,
) ([]AvisoDePedido, error) {
	msgs, _, err := r.c.XAutoClaim(ctx, &redis.XAutoClaimArgs{
		Stream:   stream,
		Group:    grupo,
		Consumer: consumidor,
		MinIdle:  desdeHace,
		Start:    "0-0",
		Count:    int64(cuantos),
	}).Result()
	if err != nil {
		return nil, err
	}
	return deMensajes(msgs), nil
}

func deLosMensajes(flujos []redis.XStream) []AvisoDePedido {
	var salida []AvisoDePedido
	for _, f := range flujos {
		salida = append(salida, deMensajes(f.Messages)...)
	}
	return salida
}

func deMensajes(msgs []redis.XMessage) []AvisoDePedido {
	salida := make([]AvisoDePedido, 0, len(msgs))
	for _, m := range msgs {
		salida = append(salida, AvisoDePedido{
			ID:         m.ID,
			Entidad:    campo(m.Values, "entidad"),
			Motivo:     campo(m.Values, "motivo"),
			Accion:     campo(m.Values, "accion"),
			PedidoID:   campo(m.Values, "id"),
			SucursalID: campo(m.Values, "sucursalId"),
			Ts:         campo(m.Values, "ts"),
		})
	}
	return salida
}

// campo lee un campo del aviso. Todos llegan como TEXTO —así los escribe PEDIDO— y lo que
// no venga se queda vacío: un aviso al que le falte un campo no puede tumbar la lectura de
// los otros ciento noventa y nueve de la tanda.
func campo(v map[string]any, nombre string) string {
	if s, vale := v[nombre].(string); vale {
		return strings.TrimSpace(s)
	}
	return ""
}

// Registro corto para saber que el canal está vivo sin llenar el log.
func (a AvisoDePedido) Registrar(reg *slog.Logger) {
	reg.Debug("aviso de PEDIDO", "motivo", a.Motivo, "accion", a.Accion,
		"pedido", a.PedidoID, "sucursal", a.SucursalID)
}
