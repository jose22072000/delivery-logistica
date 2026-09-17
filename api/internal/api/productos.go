package api

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// El CATÁLOGO. Se llena solo —PEDIDO sondea Ventra y aquí se copia lo que él tiene— y no
// hay alta manual: dos catálogos escritos por separado discrepan sin que nadie lo vea.
//
// DOS PUERTAS DISTINTAS, Y NO SE MEZCLAN:
//
//  1. LEER va por sucursal. En Ventra el PRECIO y las EXISTENCIAS varían por sucursal, así
//     que enseñar el catálogo de otra no es sólo ver de más: es ofrecer en Camagüey un
//     producto que sólo hay en La Habana, y al precio de La Habana. Eso se copia en un
//     pedido y no lo desmiente nadie hasta que llega la factura.
//  2. CORREGIR va por rol, y sólo el Super Admin. La fila es de toda la empresa —una
//     corrección la ven las ocho sucursales a la vez—, así que no es cosa de quien manda
//     en una. Por eso esas dos consultas van a propósito SIN alcance.

// avisarCambioDelCatalogo publica «algo cambió en el catálogo» para que las pantallas
// abiertas se enteren sin esperar al temporizador.
//
// Vacío por defecto y lo engancha el fichero del bus (`eventos.go`), igual que el de rutas
// y el del tablero. **No devuelve error y no se mira lo que conteste**: una corrección del
// catálogo no se deshace porque el aviso no salga.
//
// `CambioCatalogo` estaba declarado desde el principio y NO LO PUBLICABA NADIE, con un
// comentario en `eventos.go` que lo justificaba diciendo que el catálogo cambia «cuando el
// espejo importa, que ya avisa por `CambioPedidos`». Eso nunca fue verdad: el catálogo se
// corrige a mano desde aquí y se trae aparte con `POST /api/products/sync`, y ninguna de
// las dos cosas escribe un solo pedido.
var avisarCambioDelCatalogo = func(_ context.Context) {}

// TopeCatalogo: 500 productos por consulta, como en el contrato. El buscador no enseña
// más de una pantalla; el resto se encuentra escribiendo, no bajando.
const TopeCatalogo = 500

// PedidosParaElUso: sobre cuántos pedidos recientes se cuenta «lo más movido».
//
// Se corta a propósito. Lo que se movía hace ocho meses no dice nada de lo que hay que
// tener a mano hoy, y sin tope la cuenta crece sola con la base hasta que el buscador
// tarda.
const PedidosParaElUso = 2000

type ProductoSalida struct {
	ID              uuid.UUID  `json:"id"`
	Name            string     `json:"name"`
	Weight          float64    `json:"weight"`
	Packaging       *string    `json:"packaging"`
	UnitsPerPackage *float64   `json:"unitsPerPackage"`
	Category        *string    `json:"category"`
	Sku             *string    `json:"sku"`
	SucursalCodigo  *string    `json:"sucursalCodigo"`
	Price           *float64   `json:"price"`
	Stock           *float64   `json:"stock"`
	Unit            *string    `json:"unit"`
	TraidoAt        *time.Time `json:"traidoAt"`
	CreatedAt       *time.Time `json:"createdAt"`
	UpdatedAt       *time.Time `json:"updatedAt"`
	// UsageCount: cuántas unidades se han pedido últimamente. Sirve para ordenar el
	// buscador por lo que la gente usa de verdad y no por orden alfabético.
	UsageCount float64 `json:"usageCount"`
}

func deProducto(p sqlc.Product, uso float64) ProductoSalida {
	return ProductoSalida{
		ID: p.ID, Name: p.Name, Weight: p.Weight, Packaging: p.Packaging,
		UnitsPerPackage: p.UnitsPerPackage, Category: p.Category, Sku: p.Sku,
		SucursalCodigo: p.SucursalCodigo, Price: p.Price, Stock: p.Stock, Unit: p.Unit,
		TraidoAt: hora(p.TraidoAt), CreatedAt: hora(p.CreatedAt), UpdatedAt: hora(p.UpdatedAt),
		UsageCount: uso,
	}
}

// GET /api/products
func (s *Servidor) listarProductos(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	p := r.URL.Query()

	// `sucursal` es el CÓDIGO (CAM, HAB...) y va en mayúsculas: así lo guarda el espejo.
	//
	// OJO: aquí NO manda sobre el alcance, al revés que en delivery. Allí el parámetro
	// tenía prioridad, o sea que un operador de Santiago veía el catálogo —y los precios—
	// de La Habana escribiendo `?sucursal=HAB` en la barra del navegador. Ahora sólo sirve
	// cuando no hay alcance: el Super Admin mirando «todas» que arma un pedido PARA una
	// sucursal concreta. Quien decide es `internal/alcance`.
	var pedida *string
	if v := strings.ToUpper(strings.TrimSpace(p.Get("sucursal"))); v != "" {
		pedida = &v
	}

	filas, err := a.ListarProductos(r.Context(), sqlc.ListarProductosParams{
		Sucursal: pedida,
		Q:        textoQuery(p, "q"),
		Limite:   TopeCatalogo,
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	// El uso se cuenta sobre los pedidos DE LA SUCURSAL de quien mira: «lo más movido»
	// tiene que significar algo aquí, no en la empresa entera.
	usos, err := a.UsoDeProductos(r.Context(), PedidosParaElUso)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	porProducto := make(map[uuid.UUID]float64, len(usos))
	for _, u := range usos {
		if u.ProductID.Valid {
			porProducto[uuid.UUID(u.ProductID.Bytes)] += u.Unidades
		}
	}

	// Las LÍNEAS DE SERVICIO («ENTREGA A DOMICILIO», categoría SERV) ya las quita el SQL:
	// no son mercancía, son el cobro del reparto facturado como una línea más. Metida en
	// un pedido no pesa nada y cobra el reparto dos veces.
	salida := make([]ProductoSalida, 0, len(filas))
	for _, f := range filas {
		salida = append(salida, deProducto(f, porProducto[f.ID]))
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// GET /api/products/{id}
//
// ACOTADO: la ficha de un producto de otra sucursal lleva un precio que aquí no se cobra
// y unas existencias que aquí no hay. Es 404 y no 403 porque desde fuera «no es de tu
// sucursal» y «no existe» tienen que ser lo mismo.
func (s *Servidor) obtenerProducto(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	var pedida *string
	if v := strings.ToUpper(strings.TrimSpace(r.URL.Query().Get("sucursal"))); v != "" {
		pedida = &v
	}
	f, err := a.ObtenerProductoDelAlcance(r.Context(), id, pedida)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, http.StatusOK, deProducto(f, 0))
}

type cuerpoProducto struct {
	Name            httpx.Opcional[string]  `json:"name"`
	Weight          httpx.Opcional[float64] `json:"weight"`
	Packaging       httpx.Opcional[string]  `json:"packaging"`
	UnitsPerPackage httpx.Opcional[float64] `json:"unitsPerPackage"`
	Category        httpx.Opcional[string]  `json:"category"`
}

// PATCH /api/products/{id}   (sólo Super Admin)
//
// Lo que se puede corregir a mano es sólo lo que Ventra no da bien: el nombre, el peso, el
// envase y la categoría. NI EL PRECIO NI LAS EXISTENCIAS, que son de Ventra y se vuelven a
// pisar en la siguiente pasada del espejo; dejarlos editar es prometer un cambio que dura
// doce horas y que nadie relaciona con la bajada del catálogo cuando desaparece.
func (s *Servidor) actualizarProducto(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	if !esSuperAdmin(w, r) {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	var c cuerpoProducto
	if !httpx.LeerJSON(w, r, &c) {
		return
	}

	// Se comprueba que exista ANTES de tocar: sin esto, un id que no está devolvería el
	// 404 del `RETURNING` vacío, que es el mismo, pero también lo devolvería un UPDATE que
	// no cambió nada. Mejor separar «no está» de «no cambió».
	if _, err := a.ObtenerProducto(r.Context(), id); errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	} else if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	arg := sqlc.ActualizarProductoParams{
		ID: id,
		// `tocar_*` es la diferencia entre «no me mandes esto» y «déjalo vacío». Ver
		// httpx.Opcional: sin esa distinción, un PATCH que sólo quería cambiar el peso
		// borra el envase.
		TocarPackaging: c.Packaging.Presente,
		TocarUnits:     c.UnitsPerPackage.Presente,
		TocarCategory:  c.Category.Presente,
	}
	if c.Name.Presente && c.Name.Valor != nil {
		if n := strings.TrimSpace(*c.Name.Valor); n != "" {
			arg.Name = &n
		}
	}
	if c.Weight.Presente {
		// El `Number(weight) || 0` del contrato: un peso que no se entiende es cero, no
		// un error. Un producto sin peso ya existe a montones —~70 de 111 vienen sin él
		// de Ventra— y la cuenta de carga ya sabe tratarlo.
		peso := c.Weight.Con(0)
		arg.Weight = &peso
	}
	if c.Packaging.Presente {
		arg.Packaging = aTexto(strings.TrimSpace(c.Packaging.Con("")))
	}
	if c.UnitsPerPackage.Presente {
		arg.UnitsPerPackage = c.UnitsPerPackage.Valor
	}
	if c.Category.Presente {
		arg.Category = aTexto(strings.TrimSpace(c.Category.Con("")))
	}

	f, err := a.ActualizarProducto(r.Context(), arg)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisarCambioDelCatalogo(r.Context())
	httpx.JSON(w, r, http.StatusOK, ProductoSalida{
		ID: f.ID, Name: f.Name, Weight: f.Weight, Packaging: f.Packaging,
		UnitsPerPackage: f.UnitsPerPackage, Category: f.Category, Sku: f.Sku,
		SucursalCodigo: f.SucursalCodigo, Price: f.Price, Stock: f.Stock, Unit: f.Unit,
		TraidoAt: hora(f.TraidoAt), UpdatedAt: hora(f.UpdatedAt),
	})
}

// DELETE /api/products/{id}   (sólo Super Admin)
//
// Borra la fila de UNA sucursal: la clave del catálogo es (`sucursal_codigo`, `sku`), así
// que el mismo producto en las ocho sucursales son ocho filas. Aun así lo toca sólo el
// Super Admin, porque desde una sucursal no se ve cuál de las ocho se está borrando.
func (s *Servidor) borrarProducto(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	if !esSuperAdmin(w, r) {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNoEncontrado)
	if !ok {
		return
	}
	filas, err := a.BorrarProducto(r.Context(), id)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if filas == 0 {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNoEncontrado)
		return
	}
	avisarCambioDelCatalogo(r.Context())
	httpx.JSON(w, r, http.StatusOK, map[string]bool{"success": true})
}

// POST /api/products — RETIRADO.
//
// Se contesta 410 con el porqué en vez de dejar que el router devuelva un 405 pelado: un
// cliente viejo que siga intentando dar de alta un producto tiene que leer por qué ya no
// puede, no un «método no permitido» que parece un fallo del servidor.
func (s *Servidor) altaDeProductoRetirada(w http.ResponseWriter, r *http.Request) {
	httpx.Error(w, r, http.StatusGone,
		"El catálogo se trae solo de Ventra (a través de PEDIDO). No hay alta manual de productos.")
}

// rutasProductos monta el catálogo.
//
// LEER va con `sesion`; CORREGIR también, y el rol se comprueba DENTRO del manejador y no
// con un middleware. No es una excepción por gusto: la puerta aquí no es «admin» sino
// «Super Admin» —administrador SIN sucursal—, que es otra comprobación y tiene otro
// mensaje literal. Montarlo con `admin` dejaría pasar al administrador de una sucursal a
// tocar el catálogo de las ocho.
func (s *Servidor) rutasProductos(rt *httpx.Router, sesion, admin []httpx.Medio) {
	_ = admin
	rt.ManejarFunc(http.MethodGet, "/api/products", s.listarProductos, sesion...)
	rt.ManejarFunc(http.MethodPost, "/api/products", s.altaDeProductoRetirada)
	rt.ManejarFunc(http.MethodGet, "/api/products/{id}", s.obtenerProducto, sesion...)
	rt.ManejarFunc(http.MethodPatch, "/api/products/{id}", s.actualizarProducto, sesion...)
	rt.ManejarFunc(http.MethodDelete, "/api/products/{id}", s.borrarProducto, sesion...)
}

// esSuperAdmin corta la petición si quien pide no lo es, con el literal del contrato.
//
// Super Admin es administrador SIN sucursal, y la distinción importa: un administrador de
// Holguín manda en Holguín, pero el catálogo es de las ocho.
func esSuperAdmin(w http.ResponseWriter, r *http.Request) bool {
	u := auth.De(r)
	if u == nil {
		// Fallo de montaje: falta `Exigir` delante. Se responde 401 y se deja constancia,
		// porque si no nadie lo ve.
		httpx.Registro(r).Error("comprobación de Super Admin sin sesión delante", "ruta", r.URL.Path)
		httpx.NoAutorizado(w, r)
		return false
	}
	if !u.EsSuperAdmin() {
		httpx.Error(w, r, http.StatusForbidden, "Solo el Super Admin puede tocar el catálogo")
		return false
	}
	return true
}
