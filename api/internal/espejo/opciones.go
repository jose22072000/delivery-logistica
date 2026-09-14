// EL ESPEJO DE PEDIDO: la pieza que trae los datos.
//
// Sin esto, la base del reparto no tiene ni un pedido. Aquí dentro no se da de alta nada a
// mano: los pedidos y los clientes son de PEDIDO, y este proceso los copia.
//
// Antes esto era una COLA (una tabla de trabajos) que procesaba los pedidos de uno en uno
// con una pausa entre cada uno. Esa lentitud era a propósito: alimentaba una pantalla de
// sincronización que enseñaba el progreso en vivo. Quitada la pantalla, la cola no servía a
// nadie — sólo hacía que traerse 600 pedidos tardara quince minutos en vez de unos segundos.
//
// EL COSTO DEL DOMICILIO NO SE TOCA. Lo pone la APK de Entrega directamente en PEDIDO, y
// este proceso NO le escribe nada a PEDIDO. Nunca. Eso está borrado y no detrás de un
// interruptor a propósito: mientras existiera la forma de reactivarlo, existía la forma de
// que dos sistemas escribieran el mismo campo y que el último en pasar pisara al otro sin
// que nadie se enterara.
package espejo

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

// Opciones es todo lo que el espejo necesita saber. Sale del entorno UNA vez al arrancar,
// por lo mismo que `internal/config`: una variable que falta y se descubre a mitad de la
// primera pasada deja el espejo dando vueltas sin traer nada y con el proceso "sano".
type Opciones struct {
	// A quién se le piden los pedidos y a dónde se meten.
	PedidoURL   string
	DeliveryURL string
	// La llave de servicio. Es la MISMA en las dos puntas: con ella se firma la petición a
	// PEDIDO y con ella se entra a `/api/quote/batch`.
	Clave string
	// Si se pone, el espejo trae SÓLO esa sucursal. Vacío = las ocho.
	SucursalCodigo string

	// Cada cuánto se repasa.
	//
	// UN MINUTO, NO CINCO. El costo del domicilio lo pone el repartidor desde Entrega y
	// hasta que el espejo no pasa, aquí sigue diciendo «sin cotizar». Cinco minutos mirando
	// una pantalla que no cambia se leen como que está roto. El ciclo es barato —lo
	// incremental casi siempre trae cero filas—, y lo caro (el barrido del histórico) tiene
	// su propio freno en `BarridoCada`.
	Poll time.Duration

	// TramoDias: cuántos días por petición al recorrer el histórico.
	TramoDias int
	// HistoricoDias: hasta dónde atrás llega el histórico.
	HistoricoDias int
	// HistoricoPorCiclo: cuánto histórico se recupera POR CICLO.
	//
	// El histórico no se trae de una sentada: se va estirando hacia atrás un poco en cada
	// vuelta. Así lo reciente está disponible desde el primer ciclo —que es lo que hace
	// falta para trabajar hoy— y el año entero acaba de llenarse solo al cabo de un rato,
	// sin un proceso de una hora que si se corta hay que volver a empezar.
	HistoricoPorCiclo int
	// RepasoDias: y además, SIEMPRE, una repasada a los últimos días.
	//
	// `since` se fía de que PEDIDO toque `updatedAt` en cada cambio. Si alguna vez no lo
	// hace —una carga masiva, una corrección por SQL— ese pedido no vuelve a aparecer
	// nunca. Un repaso corto de los últimos días lo recoge igual. Cuesta poco y tapa el
	// único agujero que tiene el sincronizado incremental.
	RepasoDias int
	// BarridoCada: cada cuánto toca estirar el histórico. El barrido es lo caro y el ciclo
	// pasa cada minuto: pedirle a PEDIDO treinta días de histórico cada minuto es cargarlo
	// por gusto, porque lo viejo no se mueve.
	BarridoCada time.Duration

	// SoloRepartibles: SÓLO LO QUE PUEDE SUBIR A UN CAMIÓN. Encendido por defecto.
	//
	// Antes el espejo traía el catálogo entero de PEDIDO —todos los estados, archivados
	// incluidos, de todo el año— y se filtraba en la pantalla. Los números: 54.077 pedidos
	// copiados, 49.590 archivados, y de todos ellos 1.277 que podían repartirse. Quien
	// abría el reparto veía el 100 % para trabajar con el 2 %, y se perdía entre filtros.
	//
	// Se apaga con `SYNC_TODOS=1` si alguna vez hace falta el catálogo entero. Los pedidos
	// que ya están copiados NO se borran: dejan de refrescarse y se quedan como historia.
	SoloRepartibles bool
	// SoloDomicilio: sólo los pedidos que LLEVAN domicilio. Apagado por defecto — los que
	// no llevan también valen: se ven en el mapa, cuentan para la capacidad del camión, y
	// un pedido puede pasar a llevarlo.
	SoloDomicilio bool
	// SoloCotizados: y de ésos, sólo los que YA tienen el costo puesto. También apagado, y
	// por un número: de los 1.243 pedidos con domicilio y geolocalización de los últimos
	// quince días, los que la APK ya cotizó eran SEIS. Con esto puesto, el reparto se queda
	// con seis pedidos y parece roto.
	SoloCotizados bool

	// CotizadosMin: la ventana de «los recién cotizados», en minutos. Es lo único que la
	// gente mira esperando a que cambie.
	CotizadosMin int

	// Lote: cuántos pedidos por POST a `/api/quote/batch`. 200 es un tamaño realista de
	// camión, y mandar miles en un solo POST es lo que reventó la memoria la vez anterior.
	Lote int
	// PaginaClientes: cuántos clientes por página. Traerlos todos de golpe eran 2,17 MB en
	// una sola respuesta; por páginas la memoria se mantiene plana y una respuesta cortada a
	// medias no deja el proceso con datos incompletos.
	PaginaClientes int
}

// PorDefecto son los valores con los que arranca si el entorno no dice otra cosa. Son los
// mismos números que llevaba el espejo de Node, y están medidos contra los datos de verdad.
func PorDefecto() Opciones {
	return Opciones{
		PedidoURL:         "http://localhost:8400",
		DeliveryURL:       "http://localhost:3002",
		Poll:              time.Minute,
		TramoDias:         3,
		HistoricoDias:     420,
		HistoricoPorCiclo: 30,
		RepasoDias:        3,
		BarridoCada:       10 * time.Minute,
		SoloRepartibles:   true,
		CotizadosMin:      30,
		Lote:              200,
		PaginaClientes:    1000,
	}
}

// Cargar lee el entorno. `entorno` se pasa como función para que las pruebas no tengan que
// ensuciar el del proceso.
//
// Sólo la clave es obligatoria: sin ella no se puede ni preguntar ni escribir, y el proceso
// se pasaría el día dando vueltas contra un 401 que nadie mira.
func Cargar(entorno func(string) string) (Opciones, error) {
	o := PorDefecto()

	o.PedidoURL = urlOTal(entorno("PEDIDO_API_URL"), o.PedidoURL)
	o.DeliveryURL = urlOTal(entorno("DELIVERY_URL"), o.DeliveryURL)
	o.Clave = strings.TrimSpace(entorno("SERVICE_API_KEY"))
	o.SucursalCodigo = strings.TrimSpace(entorno("SUCURSAL_CODIGO"))

	var errs []string
	entero := func(nombre string, destino *int) {
		crudo := strings.TrimSpace(entorno(nombre))
		if crudo == "" {
			return
		}
		n, err := strconv.Atoi(crudo)
		if err != nil || n <= 0 {
			errs = append(errs, fmt.Sprintf("%s vale %q: hace falta un número entero mayor que cero", nombre, crudo))
			return
		}
		*destino = n
	}
	milis := func(nombre string, destino *time.Duration) {
		crudo := strings.TrimSpace(entorno(nombre))
		if crudo == "" {
			return
		}
		n, err := strconv.Atoi(crudo)
		if err != nil || n <= 0 {
			errs = append(errs, fmt.Sprintf("%s vale %q: hace falta un número de milisegundos mayor que cero", nombre, crudo))
			return
		}
		*destino = time.Duration(n) * time.Millisecond
	}

	milis("SYNC_POLL_MS", &o.Poll)
	entero("SYNC_TRAMO_DIAS", &o.TramoDias)
	entero("SYNC_HISTORICO_DIAS", &o.HistoricoDias)
	entero("SYNC_HISTORICO_POR_CICLO", &o.HistoricoPorCiclo)
	entero("SYNC_REPASO_DIAS", &o.RepasoDias)
	milis("SYNC_BARRIDO_CADA_MS", &o.BarridoCada)
	entero("SYNC_COTIZADOS_MIN", &o.CotizadosMin)
	entero("SYNC_LOTE", &o.Lote)
	entero("SYNC_PAGINA_CLIENTES", &o.PaginaClientes)

	// Los tres interruptores comparan con "1" como el espejo de Node, y no con «cualquier
	// cosa que no sea vacío»: un `SYNC_TODOS=false` heredado de otro sitio no puede
	// encender el catálogo entero por leerse como verdadero.
	o.SoloDomicilio = entorno("SYNC_SOLO_DOMICILIO") == "1"
	o.SoloCotizados = entorno("SYNC_SOLO_COTIZADOS") == "1"
	o.SoloRepartibles = entorno("SYNC_TODOS") != "1"

	if o.Clave == "" {
		errs = append(errs, "falta SERVICE_API_KEY: sin ella PEDIDO contesta 401 y el espejo no trae nada")
	}
	// Un repaso más largo que el histórico deja al barrido sin nada que recorrer, y se
	// quedaría girando en el sitio marcando la posición una y otra vez.
	if o.RepasoDias >= o.HistoricoDias {
		errs = append(errs, fmt.Sprintf(
			"SYNC_REPASO_DIAS (%d) no puede llegar tan atrás como SYNC_HISTORICO_DIAS (%d): el barrido se quedaría sin recorrido",
			o.RepasoDias, o.HistoricoDias))
	}
	if len(errs) > 0 {
		return o, fmt.Errorf("configuración no válida:\n  - %s", strings.Join(errs, "\n  - "))
	}
	return o, nil
}

// urlOTal quita la barra final. Con ella, las rutas salen con `//` en medio y hay quien
// contesta 404 a eso sin decir por qué.
func urlOTal(v, porDefecto string) string {
	v = strings.TrimRight(strings.TrimSpace(v), "/")
	if v == "" {
		return porDefecto
	}
	return v
}
