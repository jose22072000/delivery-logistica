package espejo

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// EL CLIENTE DE PEDIDO. Dos preguntas y ninguna respuesta: este proceso NO le escribe nada
// a PEDIDO.
//
//	GET /integration/orders    los pedidos, filtrados y por tramos
//	GET /integration/clients   los clientes geolocalizados, por páginas
//
// Las dos van con la llave de servicio en `x-api-key`.

// FuenteDePedidos es por dónde se le pregunta a PEDIDO.
//
// ES UNA INTERFAZ para que las pruebas del ciclo no necesiten ni PEDIDO ni red: se corren
// en cada compilación y no «cuando haya un PEDIDO a mano». La implementación de verdad es
// `ClientePedido`, aquí abajo.
type FuenteDePedidos interface {
	// Pedidos pide un tramo o una tanda de cambios. `q` ya lleva los filtros armados.
	Pedidos(ctx context.Context, q url.Values) ([]PedidoDeFuera, error)
	// Clientes devuelve una página y el cursor de la siguiente («» cuando no hay más).
	Clientes(ctx context.Context, cursor string, limite int) ([]ClienteDeFuera, string, error)
	// ClientesPorID trae unos clientes concretos. Es lo que hace que un aviso de
	// `cliente` cueste UNA fila y no el padrón entero. PEDIDO abrió `?ids=` el
	// 26/09/2026 justo para esto; su tope es 200 por llamada, porque la lista va en la
	// URL y sin tope es un 414 el día que alguien pida mil.
	ClientesPorID(ctx context.Context, ids []string) ([]ClienteDeFuera, error)
}

// PedidoDeFuera es un pedido tal como lo da PEDIDO.
//
// Se leen los campos que hacen falta y NO se guarda el documento entero: el esquema nuevo
// no tiene columnas JSON (decisión 0 de la migración). Lo que no está aquí es que no se
// usa, y un campo que nadie lee es un campo que nadie mantiene.
type PedidoDeFuera struct {
	ID     string `json:"id"`
	Folio  string `json:"folio"`
	Fecha  string `json:"fecha"`
	Estado string `json:"estado"`

	SucursalCodigo string `json:"sucursalCodigo"`
	Direccion      string `json:"direccion"`
	Telefono       string `json:"telefono"`
	Encargado      string `json:"encargado"`

	Cliente  *ClienteDelPedido  `json:"cliente"`
	Vendedor *VendedorDelPedido `json:"vendedor"`
	Items    []RenglonDeFuera   `json:"items"`

	// UpdatedAt es la MARCA DE AGUA: cuándo se tocó por última vez EN PEDIDO. De aquí sale
	// el `since` de la próxima bajada, y por eso este campo no es uno más.
	UpdatedAt string `json:"updatedAt"`

	Archivado         bool   `json:"archivado"`
	FechaComprometida string `json:"fechaComprometida"`
	RequiereDomicilio bool   `json:"requiereDomicilio"`
	// CostoDomicilio es el costo que la APK de Entrega escribió EN PEDIDO. Es lo que se
	// cobra; el reparto no calcula ninguno propio.
	CostoDomicilio *float64 `json:"costoDomicilio"`

	FacturaEstado      string   `json:"facturaEstado"`
	FacturaNumero      string   `json:"facturaNumero"`
	FacturaAt          string   `json:"facturaAt"`
	FacturaDomicilio   *float64 `json:"facturaDomicilio"`
	FacturaCorregidoAt string   `json:"facturaCorregidoAt"`
	// ItemsOrigen dice si los renglones de arriba son los del PEDIDO o los de la FACTURA.
	//
	// PEDIDO manda las de la factura en cuanto hay uno cotejado —descartando las que se
	// pidieron y no se facturaron, para que nadie cargue un hueco—, asi que los kg y las
	// unidades que ve el reparto ya son los que van a subir al camion. Lo que faltaba era
	// **decirlo**: en pantalla salia «Cambio en la factura» y nada mas, y quien lo mira no
	// sabe si el numero que tiene delante es lo que se pidio o lo que se facturo.
	//
	// Jose, 26/09/2026: «cuando la factura cambio el pedido, el pedido en delivery debe
	// mostrar la factura no el pedido, por que cambio, se facturo otra cosa, ese pedido ya
	// no representa la cantidad total». Y como se resuelve: «mantenemos el pedido y solo
	// le añadimos una factura a ese pedido para saber si cambio o no».
	ItemsOrigen string `json:"itemsOrigen"`
}

type ClienteDelPedido struct {
	Nombre    string   `json:"nombre"`
	Direccion string   `json:"direccion"`
	Municipio string   `json:"municipio"`
	Latitud   *float64 `json:"latitud"`
	Longitud  *float64 `json:"longitud"`
}

type VendedorDelPedido struct {
	Nombre string `json:"nombre"`
	Codigo string `json:"codigo"`
}

// RenglonDeFuera es una línea del pedido.
//
// EL PESO VA TAL CUAL VIENE DE PEDIDO, que lo cruza contra Ventra con los vínculos que ató
// una persona. Antes se tiraba aquí y el reparto lo volvía a resolver con su propio
// catálogo: el mismo dato dos veces, y discrepando sin que nadie lo viera.
//
// `pesoKg` y `pesoLineaKg` llegan los dos a la vez a propósito: mandar sólo uno obliga a
// acordarse de multiplicar por los bultos, y el día que se olvide el domicilio sale
// dividido entre veinticuatro sin que falle nada.
type RenglonDeFuera struct {
	Codigo      string   `json:"codigo"`
	Producto    string   `json:"producto"`
	Descripcion string   `json:"descripcion"`
	Unidades    *float64 `json:"unidades"`
	Packs       *float64 `json:"packs"`
	PesoKg      *float64 `json:"pesoKg"`
	PesoLineaKg *float64 `json:"pesoLineaKg"`
}

// ClienteDeFuera es un cliente de PEDIDO. Sólo se copian los GEOLOCALIZADOS: sin
// coordenadas no hay parada que visitar ni distancia que medir.
type ClienteDeFuera struct {
	ID             string             `json:"id"`
	Codigo         string             `json:"codigo"`
	Nombre         string             `json:"nombre"`
	Telefono       string             `json:"telefono"`
	Direccion      string             `json:"direccion"`
	Municipio      string             `json:"municipio"`
	Zona           string             `json:"zona"`
	Latitud        *float64           `json:"latitud"`
	Longitud       *float64           `json:"longitud"`
	SucursalCodigo string             `json:"sucursalCodigo"`
	Vendedor       *VendedorDelPedido `json:"vendedor"`
}

// ClientePedido habla con PEDIDO de verdad.
type ClientePedido struct {
	Base    string
	Clave   string
	Cliente *http.Client
}

// NuevoClientePedido arma el cliente CON PLAZO, que el de por defecto no tiene: una
// petición sin plazo contra la VPN de allá se queda colgada para siempre y el ciclo no
// vuelve a pasar nunca — el espejo parece vivo y no trae nada.
func NuevoClientePedido(base, clave string) *ClientePedido {
	return &ClientePedido{
		Base:  strings.TrimRight(base, "/"),
		Clave: clave,
		// Dos minutos: un tramo de tres días de una sucursal grande son miles de pedidos
		// con sus líneas, y por la conexión de Cuba eso no baja en diez segundos.
		Cliente: &http.Client{Timeout: 120 * time.Second},
	}
}

func (c *ClientePedido) Pedidos(ctx context.Context, q url.Values) ([]PedidoDeFuera, error) {
	crudo, err := c.pedir(ctx, "/integration/orders?"+q.Encode())
	if err != nil {
		return nil, err
	}
	var cuerpo struct {
		Orders []PedidoDeFuera `json:"orders"`
	}
	if err := json.Unmarshal(crudo, &cuerpo); err != nil {
		return nil, fmt.Errorf("PEDIDO contestó algo que no se entiende: %w", err)
	}
	return cuerpo.Orders, nil
}

// TopeDeClientesPorID es el de PEDIDO: 200 por llamada. Ir por encima es un 414 y el
// cliente se queda sin actualizar sin que nadie vea un error de verdad.
const TopeDeClientesPorID = 200

// ClientesPorID trae los que se le digan y nada más.
func (c *ClientePedido) ClientesPorID(ctx context.Context, ids []string) ([]ClienteDeFuera, error) {
	if len(ids) == 0 {
		return nil, nil
	}
	var todos []ClienteDeFuera
	for i := 0; i < len(ids); i += TopeDeClientesPorID {
		fin := i + TopeDeClientesPorID
		if fin > len(ids) {
			fin = len(ids)
		}
		q := url.Values{}
		q.Set("ids", strings.Join(ids[i:fin], ","))
		crudo, err := c.pedir(ctx, "/integration/clients?"+q.Encode())
		if err != nil {
			return nil, err
		}
		var cuerpo struct {
			Clients []ClienteDeFuera `json:"clients"`
		}
		if err := json.Unmarshal(crudo, &cuerpo); err != nil {
			return nil, err
		}
		todos = append(todos, cuerpo.Clients...)
	}
	return todos, nil
}

func (c *ClientePedido) Clientes(ctx context.Context, cursor string, limite int) ([]ClienteDeFuera, string, error) {
	q := url.Values{}
	q.Set("limit", strconv.Itoa(limite))
	if cursor != "" {
		q.Set("cursor", cursor)
	}
	crudo, err := c.pedir(ctx, "/integration/clients?"+q.Encode())
	if err != nil {
		return nil, "", err
	}
	var cuerpo struct {
		Clients    []ClienteDeFuera `json:"clients"`
		NextCursor string           `json:"nextCursor"`
	}
	if err := json.Unmarshal(crudo, &cuerpo); err != nil {
		return nil, "", fmt.Errorf("PEDIDO contestó algo que no se entiende: %w", err)
	}
	// Si el PEDIDO de enfrente es anterior a la paginación no manda `nextCursor` y devuelve
	// todo de una: el bucle de arriba se corta y funciona igual.
	return cuerpo.Clients, cuerpo.NextCursor, nil
}

func (c *ClientePedido) pedir(ctx context.Context, ruta string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.Base+ruta, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("X-Api-Key", c.Clave)
	req.Header.Set("Accept", "application/json")
	// `no-store` explícito: por el medio hay proxies, y una respuesta guardada de hace una
	// hora es exactamente lo que el espejo no puede creerse.
	req.Header.Set("Cache-Control", "no-store")

	res, err := c.Cliente.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	// Tope de lectura: una respuesta enorme de un servicio que se volvió loco no puede
	// tumbar este proceso por memoria. Fue así como murió la vez anterior.
	leido, err := io.ReadAll(io.LimitReader(res.Body, 64<<20))
	if err != nil {
		return nil, err
	}
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return nil, fmt.Errorf("PEDIDO %d: %s", res.StatusCode, recorte(leido, 200))
	}
	return leido, nil
}

func recorte(b []byte, n int) string {
	s := strings.TrimSpace(string(b))
	if len(s) <= n {
		return s
	}
	return s[:n]
}
