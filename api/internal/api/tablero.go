// EL TABLERO DE PREPARACIÓN. La pantalla nueva, especificada entera en `docs/tablero.md`.
//
// En una línea: entre «me han llegado 180 pedidos» y «sale este camión con estas 14
// paradas» hay un trabajo que hoy se hace en la cabeza del logístico y en un papel —
// agrupar por zona—. El tablero es ese paso: columnas que él pone, tarjetas que él
// arrastra, y de cada columna sale una ruta.
//
// LO QUE NO SE REINVENTA AQUÍ, porque ya lo decide la base y decidirlo dos veces es
// tenerlo decidido de dos maneras:
//
//   - «un pedido está en una columna o en ninguna» lo sostiene la clave primaria de
//     `board_placements`, que ES el pedido. No hay ningún `findFirst` que lo compruebe.
//   - «no se borra una columna con pedidos dentro» lo sostiene el `ON DELETE RESTRICT`.
//     Lo que pone este fichero es el mensaje que se entiende, no la prohibición.
//   - «este pedido ya va en un camión» lo comprueba el `WHERE` del propio INSERT, en el
//     mismo instante en que escribe. Mirarlo antes en Go es mirar una foto vieja.
//
// Y LO QUE SÍ ES DE AQUÍ: que el exceso de peso AVISE y no impida (§7.3 de la spec), que
// las escrituras sean REAPLICABLES —el tablero se usa sin red y sus órdenes suben en
// lotes que se reintentan (`docs/sincronizacion.md`)—, y que ninguna tarjeta desaparezca
// sola: se marca, no se esconde.
package api

import (
	"errors"
	"fmt"
	"math"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// rutasTablero monta el tablero. Lo llama `Rutas()` en servidor.go.
//
// Todas con sesión y con alcance —aquí el alcance es SEGURIDAD y va dentro del SQL— y
// ninguna con `admin`: el tablero es la herramienta diaria del logístico de la sucursal,
// no una pantalla de administración. `admin` se recibe igual para que la firma sea la
// misma que la de los demás grupos de rutas y no haya que recordar cuál la lleva.
func (s *Servidor) rutasTablero(rt *httpx.Router, sesion, admin []httpx.Medio) {
	_ = admin

	rt.ManejarFunc(http.MethodGet, "/api/board", s.tablero, sesion...)
	rt.ManejarFunc(http.MethodGet, "/api/board/unplaced", s.tableroSinColocar, sesion...)

	rt.ManejarFunc(http.MethodPost, "/api/board/columns", s.crearColumna, sesion...)
	// `PUT /api/board/columns/orden` va por el MISMO patrón que `{id}` y se reparte
	// dentro, no como una ruta propia. No es un capricho: este router monta, por cada
	// patrón, una entrada sin método que recoge los 405, y `ServeMux` rechaza de plano
	// registrar `/api/board/columns/{id}` sin método junto a `/api/board/columns/orden`
	// —el proceso se cae AL ARRANCAR, con un pánico—. Repartir dentro deja la URL del
	// contrato intacta y el router con un patrón solo.
	rt.ManejarFunc(http.MethodPut, "/api/board/columns/{id}", s.putColumna, sesion...)
	rt.ManejarFunc(http.MethodPatch, "/api/board/columns/{id}", s.actualizarColumna, sesion...)
	rt.ManejarFunc(http.MethodDelete, "/api/board/columns/{id}", s.borrarColumna, sesion...)
	rt.ManejarFunc(http.MethodPost, "/api/board/columns/{id}/route", s.armarRutaDeColumna, sesion...)

	rt.ManejarFunc(http.MethodPut, "/api/board/placements/{id}", s.colocarPedido, sesion...)
	rt.ManejarFunc(http.MethodDelete, "/api/board/placements/{id}", s.quitarPedidoDelTablero, sesion...)
}

// ---------------------------------------------------------------------------
// Mensajes literales del tablero
// ---------------------------------------------------------------------------
//
// Van aquí, juntos y como constantes, por lo mismo que los de `httpx`: salen en la
// pantalla del logístico y están inventariados en la spec. Escritos a mano dentro del
// manejador acaban diciendo tres cosas parecidas en tres sitios.
const (
	msgElijeSucursal   = "Elige una sucursal para ver su tablero"
	msgYaVaEnUnaRuta   = "Ese pedido ya está en una ruta"
	msgColumnaSinNada  = "La columna no tiene ningún pedido que se pueda repartir hoy"
	msgNombreRequerido = "La columna necesita un nombre"
)

// TopeSinColocar es el tope por defecto de la mitad izquierda. Se puede bajar por query,
// no subir: la conexión de allá no da para más y el `total` que va al lado ya dice
// cuántos hay de verdad.
const TopeSinColocar = 200

// ---------------------------------------------------------------------------
// La respuesta
// ---------------------------------------------------------------------------

type ColumnaSalida struct {
	ID        uuid.UUID  `json:"id"`
	BranchID  uuid.UUID  `json:"branchId"`
	Nombre    string     `json:"nombre"`
	Posicion  int32      `json:"posicion"`
	VehicleID *uuid.UUID `json:"vehiculoId"`
	// Del camión previsto se enseña lo que hace falta para entender el aviso de peso.
	VehiculoNombre    *string  `json:"vehiculoNombre,omitempty"`
	VehiculoMatricula *string  `json:"vehiculoMatricula,omitempty"`
	VehiculoCapacidad *float64 `json:"vehiculoCapacidad,omitempty"`
	// Los totales los da la BASE, no la suma de lo pintado: la pantalla pagina y el
	// camión no. Con 60 pedidos puestos, sumar lo que se ve da el peso de los 20
	// primeros y el aviso de que no cabe no aparecería nunca.
	Pedidos  int64   `json:"pedidos"`
	PesoKg   float64 `json:"pesoKg"`
	CostoUsd float64 `json:"costoUsd"`
	// PUNTERO Y NO bool: sin camión previsto esto es NULL, que NO es `false`. Significa
	// «todavía no se sabe», y pintar «cabe» cuando nadie ha dicho en qué va es peor que
	// no pintar nada.
	ExcedeCamion *bool      `json:"excedeCamion"`
	CreatedAt    *time.Time `json:"createdAt"`
	UpdatedAt    *time.Time `json:"updatedAt"`
}

// TarjetaSalida es un pedido YA COLOCADO.
//
// Lleva `facturaEstado`, `archivado` y `rutaId` crudos a propósito: la tarjeta que dejó
// de servir SE MARCA, NO SE ESCONDE. Quitarla sola es hacer desaparecer el trabajo de
// alguien sin decírselo — el logístico vuelve a la columna, ve once paradas donde puso
// doce y no tiene manera de saber cuál falta ni por qué.
type TarjetaSalida struct {
	PedidoID        uuid.UUID  `json:"pedidoId"`
	ColumnaID       uuid.UUID  `json:"columnaId"`
	Posicion        int32      `json:"posicion"`
	ColumnaNombre   string     `json:"columnaNombre"`
	OperationNumber *string    `json:"operationNumber"`
	CustomerName    string     `json:"customerName"`
	CustomerPhone   *string    `json:"customerPhone"`
	Address         string     `json:"address"`
	EndAddress      *string    `json:"endAddress"`
	Weight          float64    `json:"weight"`
	PedidoCosto     *float64   `json:"pedidoCosto"`
	Municipio       *string    `json:"municipio"`
	Vendedor        *string    `json:"vendedor"`
	KmAlAlmacen     float64    `json:"kmAlAlmacen"`
	FacturaEstado   *string    `json:"facturaEstado"`
	Archivado       bool       `json:"archivado"`
	RutaID          *uuid.UUID `json:"rutaId"`
	Resultado       *string    `json:"resultado"`
	ColocadoAt      *time.Time `json:"colocadoAt"`
	// MismoCliente marca «2 pedidos de este cliente hoy». NO se funden las tarjetas: el
	// sufijo del folio es nuestro y X-2992 y X-2992-2 son dos pedidos, con su peso y su
	// domicilio cada uno. Juntarlos porque coincide el cliente es repetir el error de
	// julio: dos facturas, un solo bulto cargado.
	MismoCliente int `json:"mismoCliente"`
}

// SinColocarSalida es una tarjeta de la mitad izquierda. `kmAlAlmacen` es el campo por el
// que existe media pantalla.
type SinColocarSalida struct {
	ID              uuid.UUID  `json:"id"`
	OperationNumber *string    `json:"operationNumber"`
	CustomerName    string     `json:"customerName"`
	CustomerPhone   *string    `json:"customerPhone"`
	Address         string     `json:"address"`
	EndAddress      *string    `json:"endAddress"`
	Weight          float64    `json:"weight"`
	PedidoCosto     *float64   `json:"pedidoCosto"`
	Municipio       *string    `json:"municipio"`
	Vendedor        *string    `json:"vendedor"`
	OrderDate       *time.Time `json:"orderDate"`
	FacturaEstado   *string    `json:"facturaEstado"`
	KmAlAlmacen     float64    `json:"kmAlAlmacen"`
	MismoCliente    int        `json:"mismoCliente"`
}

// AvisosSalida son los tres contadores de arriba. TRES y no uno: «lo archivaron en
// PEDIDO», «se lo llevó otra ruta» y «no está facturado» se arreglan de tres maneras
// distintas, y un número único obligaría a abrir las doce columnas para saber cuál es.
type AvisosSalida struct {
	Archivados int64 `json:"archivados"`
	EnOtraRuta int64 `json:"enOtraRuta"`
	SinFactura int64 `json:"sinFactura"`
	Cambiados  int64 `json:"cambiados"`
	Colocados  int64 `json:"colocados"`
}

type AlmacenSalida struct {
	Nombre string  `json:"nombre"`
	Lat    float64 `json:"lat"`
	Lng    float64 `json:"lng"`
}

type SucursalDelTablero struct {
	ID     uuid.UUID `json:"id"`
	Nombre string    `json:"nombre"`
}

type MitadIzquierda struct {
	Total     int64              `json:"total"`
	Count     int                `json:"count"`
	Truncated bool               `json:"truncated"`
	Pedidos   []SinColocarSalida `json:"pedidos"`
}

// TableroSalida: el tablero entero en UNA ida y vuelta. Cinco peticiones para pintar una
// pantalla no caben en la conexión de allá.
type TableroSalida struct {
	Sucursal   SucursalDelTablero `json:"sucursal"`
	Almacen    AlmacenSalida      `json:"almacen"`
	Columnas   []ColumnaSalida    `json:"columnas"`
	Colocados  []TarjetaSalida    `json:"colocados"`
	Avisos     AvisosSalida       `json:"avisos"`
	SinColocar MitadIzquierda     `json:"sinColocar"`
	// VistoAt es la hora del servidor al contestar. Es lo que la pantalla enseña como
	// «visto por última vez a las 9:14» cuando se queda sin señal: un tablero que parece
	// vivo y lleva seis horas congelado es peor que uno que avisa.
	VistoAt time.Time `json:"vistoAt"`
}

// ---------------------------------------------------------------------------
// De dónde se mide la cercanía
// ---------------------------------------------------------------------------

// tableroDe resuelve las dos cosas sin las que no hay tablero: QUÉ sucursal se mira y
// DESDE DÓNDE se mide.
//
// `branchId` es obligatorio y no es redundante con el alcance: no existe «el tablero de
// todas». Las columnas son de una sucursal y la cercanía se mide desde el almacén de una
// sucursal — con diez mezcladas, el «más cercano primero» sale midiendo Holguín desde
// Santiago. Quien tiene alcance no necesita decirlo (se usa el suyo); el Super Admin, que
// no lo tiene, TIENE que elegir, y si no elige no se le enseña «todo», que es lo que
// parecería razonable y sería lo peor.
type tableroCtx struct {
	sucursal uuid.UUID
	nombre   string
	almacen  AlmacenSalida
}

func (s *Servidor) tableroDe(w http.ResponseWriter, r *http.Request, a *alcance.Acotado) (tableroCtx, bool) {
	var ctx tableroCtx

	crudo := strings.TrimSpace(r.URL.Query().Get("branchId"))
	if crudo == "" {
		if id := a.Sucursal(); id != nil {
			crudo = id.String()
		}
	}
	if crudo == "" {
		httpx.Error(w, r, http.StatusBadRequest, msgElijeSucursal)
		return ctx, false
	}
	id, err := uuid.Parse(crudo)
	if err != nil {
		// Un id que ni siquiera es un uuid es el mismo caso que uno que ya no está: los
		// de delivery eran cuid. 404, no 400.
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return ctx, false
	}

	// Que la sucursal EXISTA y esté dentro del alcance. Sin esto, un `branchId` ajeno
	// devolvería un tablero vacío con 200, que es indistinguible de «todavía no hay
	// columnas»: el modo de fallo que este proyecto ya vio en producción.
	suc, err := a.ObtenerSucursal(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return ctx, false
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return ctx, false
	}

	origen, ok := s.almacenDe(w, r, a, id, suc.Name)
	if !ok {
		return ctx, false
	}
	return tableroCtx{sucursal: id, nombre: suc.Name, almacen: origen}, true
}

// almacenDe resuelve el punto desde el que se mide, y NO se inventa ninguno.
//
// La spec manda resolverlo igual que `/api/quote/home-delivery`: el almacén principal con
// coordenadas, si no el primero que las tenga, y si no hay ninguno NO HAY TABLERO. Se
// ordena desde el sitio del que sale la mercancía o no se ordena — medir desde las
// coordenadas de la sucursal da un orden que parece bueno y no lo es, y con esas mismas
// coordenadas se le cobra el domicilio al cliente.
//
// DE DÓNDE SALE HOY: de `saved_origins`, los puntos de partida de esta base, que es lo
// que hay. Los almacenes de verdad viven en Accesos y se piden por HTTP; este servicio
// todavía no tiene por dónde preguntarles (no hay ni cliente ni variable de entorno para
// Accesos), así que se usa el punto de partida de la sucursal, que es exactamente el sitio
// del que sale el camión. `saved_origins` no tiene marca de `principal`, así que se toma
// EL MÁS ANTIGUO: es el que se crea junto con la sucursal y el que nadie ha tocado.
func (s *Servidor) almacenDe(w http.ResponseWriter, r *http.Request, a *alcance.Acotado, sucursal uuid.UUID, nombre string) (AlmacenSalida, bool) {
	origenes, err := a.TableroOrigenes(r.Context())
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return AlmacenSalida{}, false
	}

	elegido := AlmacenSalida{}
	var cuando time.Time
	hay := false
	for _, o := range origenes {
		if !o.BranchID.Valid || uuid.UUID(o.BranchID.Bytes) != sucursal {
			continue
		}
		// (0,0) es el golfo de Guinea, no Santiago: un origen así no tiene coordenadas,
		// las tiene sin poner. Ordenar desde ahí pondría el pedido más lejano el primero.
		if o.Lat == 0 && o.Lng == 0 {
			continue
		}
		if hay && o.CreatedAt.Valid && !cuando.IsZero() && !o.CreatedAt.Time.Before(cuando) {
			continue
		}
		elegido = AlmacenSalida{Nombre: o.Name, Lat: o.Lat, Lng: o.Lng}
		if o.CreatedAt.Valid {
			cuando = o.CreatedAt.Time
		}
		hay = true
	}
	if !hay {
		httpx.Error(w, r, http.StatusConflict,
			fmt.Sprintf("%s no tiene ningún almacén con coordenadas", nombre))
		return AlmacenSalida{}, false
	}
	return elegido, true
}

// ---------------------------------------------------------------------------
// GET /api/board
// ---------------------------------------------------------------------------

func (s *Servidor) tablero(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	t, ok := s.tableroDe(w, r, a)
	if !ok {
		return
	}

	columnas, err := a.ListarColumnasDelTablero(r.Context(), t.sucursal)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	colocados, err := a.ListarPedidosColocados(r.Context(), sqlc.ListarPedidosColocadosParams{
		OrigenLat: t.almacen.Lat, OrigenLng: t.almacen.Lng, BranchID: t.sucursal,
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	avisos, err := a.AvisosDelTablero(r.Context(), t.sucursal)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	izquierda, ok := s.mitadIzquierda(w, r, a, t)
	if !ok {
		return
	}

	salida := TableroSalida{
		Sucursal:   SucursalDelTablero{ID: t.sucursal, Nombre: t.nombre},
		Almacen:    t.almacen,
		Columnas:   deColumnas(columnas),
		Colocados:  deTarjetas(colocados),
		Avisos:     AvisosSalida(avisos),
		SinColocar: izquierda,
		VistoAt:    time.Now().UTC(),
	}
	httpx.JSON(w, r, http.StatusOK, salida)
}

// GET /api/board/unplaced — sólo la mitad izquierda, para paginar y filtrar sin recargar
// las doce columnas enteras.
func (s *Servidor) tableroSinColocar(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	t, ok := s.tableroDe(w, r, a)
	if !ok {
		return
	}
	izquierda, ok := s.mitadIzquierda(w, r, a, t)
	if !ok {
		return
	}
	httpx.JSON(w, r, http.StatusOK, izquierda)
}

func (s *Servidor) mitadIzquierda(w http.ResponseWriter, r *http.Request, a *alcance.Acotado, t tableroCtx) (MitadIzquierda, bool) {
	q := r.URL.Query()
	limite := int32(TopeSinColocar)
	if n, err := strconv.Atoi(strings.TrimSpace(q.Get("limite"))); err == nil && n > 0 && n < TopeSinColocar {
		limite = int32(n)
	}
	desde, hasta := diaDelPedido(q.Get("dia"))

	arg := sqlc.ListarPedidosSinColocarParams{
		OrigenLat: t.almacen.Lat,
		OrigenLng: t.almacen.Lng,
		BranchID:  t.sucursal,
		Q:         textoOpcional(q.Get("q")),
		Municipio: textoOpcional(q.Get("municipio")),
		Vendedor:  textoOpcional(q.Get("vendedor")),
		DiaDesde:  desde,
		DiaHasta:  hasta,
		KmMax:     numeroOpcional(q.Get("kmMax")),
		Limite:    limite,
	}
	filas, err := a.ListarPedidosSinColocar(r.Context(), arg)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return MitadIzquierda{}, false
	}
	// El contador lleva EL MISMO `WHERE` sin tope: si contara otra cosa diría «358»
	// encima de una lista de 120.
	total, err := a.ContarPedidosSinColocar(r.Context(), sqlc.ContarPedidosSinColocarParams{
		BranchID: arg.BranchID, Q: arg.Q, Municipio: arg.Municipio, Vendedor: arg.Vendedor,
		DiaDesde: arg.DiaDesde, DiaHasta: arg.DiaHasta, KmMax: arg.KmMax,
		OrigenLat: arg.OrigenLat, OrigenLng: arg.OrigenLng,
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return MitadIzquierda{}, false
	}

	pedidos := make([]SinColocarSalida, 0, len(filas))
	repes := porCliente(filas)
	for _, f := range filas {
		pedidos = append(pedidos, SinColocarSalida{
			ID: f.ID, OperationNumber: f.OperationNumber, CustomerName: f.CustomerName,
			CustomerPhone: f.CustomerPhone, Address: f.Address, EndAddress: f.EndAddress,
			Weight: f.Weight, PedidoCosto: f.PedidoCosto, Municipio: f.Municipio,
			Vendedor: f.Vendedor, OrderDate: hora(f.OrderDate),
			FacturaEstado: facturaEstado(f.FacturaEstado), KmAlAlmacen: f.KmAlAlmacen,
			MismoCliente: repes[strings.ToLower(strings.TrimSpace(f.CustomerName))],
		})
	}
	return MitadIzquierda{
		Total: total, Count: len(pedidos),
		Truncated: total > int64(len(pedidos)), Pedidos: pedidos,
	}, true
}

// ---------------------------------------------------------------------------
// Las columnas
// ---------------------------------------------------------------------------

type cuerpoColumna struct {
	Nombre     httpx.Opcional[string] `json:"nombre"`
	VehiculoID httpx.Opcional[string] `json:"vehiculoId"`
}

// POST /api/board/columns — va al final; la posición la calcula la base.
//
// La posición NO la manda la pantalla a propósito: dos aparatos sin conexión propondrían
// el mismo número, y entonces hay dos «tercera» y ninguna «quinta».
func (s *Servidor) crearColumna(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	t, ok := s.tableroDe(w, r, a)
	if !ok {
		return
	}
	var c cuerpoColumna
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	nombre := strings.TrimSpace(c.Nombre.Con(""))
	if nombre == "" {
		httpx.Error(w, r, http.StatusBadRequest, msgNombreRequerido)
		return
	}
	veh, ok := vehiculoDelCuerpo(w, r, c.VehiculoID)
	if !ok {
		return
	}

	fila, err := a.CrearColumna(r.Context(), sqlc.CrearColumnaParams{
		Nombre: nombre, VehicleID: veh, BranchID: t.sucursal,
	})
	// Dos «Vista Alegre» en el mismo tablero es colocar la mitad de los pedidos en la
	// equivocada y no enterarse hasta que salen dos camiones al mismo barrio. Lo impide
	// el índice único; aquí se traduce a algo que se entiende.
	if esClaveRepetida(err) {
		httpx.Error(w, r, http.StatusConflict,
			fmt.Sprintf("Ya hay una columna «%s» en este tablero", nombre))
		return
	}
	if errors.Is(err, pgx.ErrNoRows) {
		// El `FROM branches` de la consulta no casó: la sucursal no existe o no es del
		// alcance. Ya se comprobó arriba, así que llegar aquí es una carrera.
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, http.StatusCreated, deColumnaPelada(fila))
}

// PATCH /api/board/columns/{id} — renombrar y elegir camión.
func (s *Servidor) actualizarColumna(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNotFound)
	if !ok {
		return
	}
	var c cuerpoColumna
	if !httpx.LeerJSON(w, r, &c) {
		return
	}

	arg := sqlc.ActualizarColumnaParams{ID: id}
	if c.Nombre.Presente && c.Nombre.Valor != nil {
		nombre := strings.TrimSpace(*c.Nombre.Valor)
		if nombre == "" {
			httpx.Error(w, r, http.StatusBadRequest, msgNombreRequerido)
			return
		}
		arg.Nombre = &nombre
	}
	// `tocar_vehiculo` existe porque «no me lo toques» y «quítamelo» son dos órdenes
	// distintas y las dos llegan con el campo vacío. Sin la bandera, renombrar la
	// columna le desasignaría el camión de paso.
	if c.VehiculoID.Presente {
		arg.TocarVehiculo = true
		veh, ok := vehiculoDelCuerpo(w, r, c.VehiculoID)
		if !ok {
			return
		}
		arg.VehicleID = veh
	}

	fila, err := a.ActualizarColumna(r.Context(), arg)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return
	}
	if esClaveRepetida(err) {
		httpx.Error(w, r, http.StatusConflict,
			fmt.Sprintf("Ya hay una columna «%s» en este tablero", strings.TrimSpace(c.Nombre.Con(""))))
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, http.StatusOK, deColumnaPelada(fila))
}

type cuerpoOrden struct {
	Ids []string `json:"ids"`
}

// putColumna reparte el PUT: `/orden` reordena el tablero entero y cualquier otra cosa es
// un id de columna, que por PUT no se admite (se renombra por PATCH).
func (s *Servidor) putColumna(w http.ResponseWriter, r *http.Request) {
	if strings.EqualFold(r.PathValue("id"), "orden") {
		s.reordenarColumnas(w, r)
		return
	}
	w.Header().Set("Allow", "PATCH, DELETE, OPTIONS")
	httpx.Error(w, r, http.StatusMethodNotAllowed, httpx.MsgMetodoNoValido)
}

// PUT /api/board/columns/orden — el tablero entero de una vez.
//
// UNA SOLA SENTENCIA, no una por columna: el aparato que se queda sin señal a la mitad
// dejaría el tablero con dos «tercera» y ninguna «quinta». Aquí, o entran todas o no
// entra ninguna. Es también la razón de que la única de `posicion` sea DEFERRABLE: a
// mitad del baile hay posiciones repetidas y la comprobación tiene que esperar al final.
func (s *Servidor) reordenarColumnas(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	t, ok := s.tableroDe(w, r, a)
	if !ok {
		return
	}
	var c cuerpoOrden
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	ids := make([]uuid.UUID, 0, len(c.Ids))
	for _, crudo := range c.Ids {
		id, err := uuid.Parse(strings.TrimSpace(crudo))
		if err != nil {
			httpx.Error(w, r, http.StatusBadRequest,
				fmt.Sprintf("«%s» no es el id de una columna", crudo))
			return
		}
		ids = append(ids, id)
	}
	if len(ids) == 0 {
		httpx.Error(w, r, http.StatusBadRequest, "No vino ninguna columna que reordenar")
		return
	}

	n, err := a.ReordenarColumnas(r.Context(), t.sucursal, ids)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	// Se devuelve el tablero recolocado y no un `{"ok":true}`: quien reordena quiere ver
	// el resultado, y si alguno de los ids no era de este tablero (`n` < los mandados)
	// la lista de vuelta lo enseña sin tener que pedirla otra vez.
	columnas, err := a.ListarColumnasDelTablero(r.Context(), t.sucursal)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, http.StatusOK, map[string]any{
		"reordenadas": n,
		"columnas":    deColumnas(columnas),
	})
}

// DELETE /api/board/columns/{id} — con `?vaciar=1`, con `?destino=<id>`, o 409.
//
// LA BASE SE NIEGA A BORRAR UNA COLUMNA CON PEDIDOS DENTRO (`ON DELETE RESTRICT`), y eso
// no se toca. Con CASCADE, las tarjetas volverían a «sin colocar» sin decir nada y quien
// borró «Centro» creyéndola vacía se entera al día siguiente, cuando a la ruta le faltan
// ocho paradas.
//
// Lo que hace este manejador es PREGUNTAR ANTES para poder decir «tiene 8 pedidos
// puestos» en vez de devolverle a la persona el error de clave ajena de Postgres, que no
// entiende nadie. Y si aun así la base se niega —porque alguien colocó una tarjeta entre
// la cuenta y el borrado—, ese error también se traduce: nunca sale un 500.
func (s *Servidor) borrarColumna(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNotFound)
	if !ok {
		return
	}
	q := r.URL.Query()
	vaciar := q.Get("vaciar") == "1" || q.Get("vaciar") == "true"
	var destino *uuid.UUID
	if crudo := strings.TrimSpace(q.Get("destino")); crudo != "" {
		d, err := uuid.Parse(crudo)
		if err != nil {
			httpx.Error(w, r, http.StatusBadRequest,
				fmt.Sprintf("«%s» no es el id de una columna", crudo))
			return
		}
		if d == id {
			httpx.Error(w, r, http.StatusBadRequest, "La columna de destino no puede ser la que se borra")
			return
		}
		destino = &d
	}

	columna, err := a.ObtenerColumna(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	var dentro int64
	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		var err error
		dentro, err = tx.ContarPedidosEnColumna(r.Context(), id)
		if err != nil {
			return err
		}
		if dentro > 0 {
			switch {
			case destino != nil:
				// Las tarjetas se van DETRÁS de lo que ya haya en la otra columna y en
				// su mismo orden relativo: quien junta dos zonas no quiere que se le
				// mezclen las paradas. Y las dos columnas tienen que ser de la misma
				// sucursal, cosa que comprueba el propio SQL.
				movidos, err := tx.MoverPedidosDeColumna(r.Context(), id, *destino)
				if err != nil {
					return err
				}
				if movidos != dentro {
					return errDestinoNoVale
				}
			case vaciar:
				if _, err := tx.VaciarColumna(r.Context(), id); err != nil {
					return err
				}
			default:
				return errColumnaConPedidos
			}
		}
		filas, err := tx.BorrarColumna(r.Context(), id)
		if err != nil {
			return err
		}
		if filas == 0 {
			return errColumnaNoEstaba
		}
		return nil
	})

	switch {
	case errors.Is(err, errColumnaConPedidos), esRestriccionDeColumna(err):
		// El 409 del contrato, con el número dentro: sin él, la persona no sabe si lo
		// que tiene que hacer es vaciar dos tarjetas o mover ochenta.
		httpx.JSON(w, r, http.StatusConflict, map[string]any{
			"error":   fmt.Sprintf("«%s» tiene %d pedidos puestos", columna.Nombre, dentro),
			"pedidos": dentro,
		})
		return
	case errors.Is(err, errDestinoNoVale):
		httpx.Error(w, r, http.StatusConflict,
			"La columna de destino no existe o es de otra sucursal")
		return
	case errors.Is(err, errColumnaNoEstaba):
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return
	case err != nil:
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, http.StatusOK, map[string]any{"success": true, "movidos": dentro})
}

// Los cortes de la transacción del borrado. Van como errores y no como banderas porque
// tienen que DESHACER lo ya movido: un borrado que falla no puede dejar las tarjetas en
// la otra columna y la columna vieja en pie.
var (
	errColumnaConPedidos = errors.New("la columna tiene pedidos puestos")
	errColumnaNoEstaba   = errors.New("la columna no existe en este alcance")
	errDestinoNoVale     = errors.New("la columna de destino no sirve")
)

// esRestriccionDeColumna reconoce el 23503 de Postgres (foreign_key_violation), que es lo
// que devuelve el `ON DELETE RESTRICT` de `board_placements.column_id`.
//
// Se mira el CÓDIGO y no el texto, igual que en `esClaveRepetida`: el texto lo traduce el
// servidor según su idioma y una comprobación por texto deja de funcionar el día que la
// base se levante con otro locale, sin que nada falle al compilar.
func esRestriccionDeColumna(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23503"
}

// ---------------------------------------------------------------------------
// Arrastrar
// ---------------------------------------------------------------------------

type cuerpoColocar struct {
	ColumnaID string `json:"columnaId"`
	Posicion  *int32 `json:"posicion"`
}

// PUT /api/board/placements/{id} — colocar O mover. Es la MISMA orden: soltar una tarjeta
// en una columna es decir «este pedido va aquí», venga de donde venga.
//
// REAPLICABLE, y eso es un requisito y no una casualidad: el tablero se usa sin red y sus
// escrituras suben en lotes que se reintentan (`docs/sincronizacion.md`). Colocar dos
// veces el mismo pedido en el mismo sitio tiene que dar el mismo tablero, no dos tarjetas
// ni un error. Se consigue con tres pasos que se anulan entre sí:
//
//  1. se SACA de donde estuviera (si estaba) y se cierra el hueco que deja;
//  2. se abre hueco en la posición de destino;
//  3. se inserta.
//
// Repetido sobre el tablero que ya quedó, el paso 1 y el paso 2 se cancelan y el
// resultado es idéntico. Hacer sólo el paso 2 + 3 correría una posición a los vecinos en
// cada reintento; hacer sólo el 3 chocaría con la única de `(column_id, posicion)`.
//
// Los tres van en UNA transacción, que es también lo que deja que la única sea DEFERRABLE:
// a mitad del corrimiento hay dos filas con la misma posición.
func (s *Servidor) colocarPedido(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	pedido, ok := idDeRuta(w, r, httpx.MsgNotFound)
	if !ok {
		return
	}
	var c cuerpoColocar
	if !httpx.LeerJSON(w, r, &c) {
		return
	}
	columna, err := uuid.Parse(strings.TrimSpace(c.ColumnaID))
	if err != nil {
		httpx.Error(w, r, http.StatusBadRequest, "Falta la columna donde se suelta la tarjeta")
		return
	}
	posicion := int32(1)
	if c.Posicion != nil && *c.Posicion > 0 {
		posicion = *c.Posicion
	}

	var puesto sqlc.BoardPlacement
	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		// 1. De donde estuviera. `pgx.ErrNoRows` aquí es lo NORMAL: el pedido venía de
		//    la mitad izquierda y no estaba puesto en ninguna parte.
		anterior, err := tx.QuitarPedidoDelTablero(r.Context(), pedido)
		switch {
		case err == nil:
			if _, err := tx.CerrarHuecoEnColumna(r.Context(), anterior.ColumnID, anterior.Posicion); err != nil {
				return err
			}
		case errors.Is(err, pgx.ErrNoRows):
		default:
			return err
		}

		// 2. Sitio en la de destino.
		if _, err := tx.AbrirHuecoEnColumna(r.Context(), columna, posicion); err != nil {
			return err
		}

		// 3. Y dentro. El `WHERE` de esta sentencia ES la validación —misma sucursal,
		//    sin ruta, dentro del alcance—, y va en el mismo instante en que escribe.
		puesto, err = tx.ColocarPedido(r.Context(), sqlc.ColocarPedidoParams{
			Posicion: posicion, PedidoID: pedido, ColumnaID: columna,
		})
		return err
	})

	if errors.Is(err, pgx.ErrNoRows) {
		s.porQueNoSePudoColocar(w, r, a, pedido)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, http.StatusOK, map[string]any{
		"pedidoId":   puesto.OrderID,
		"columnaId":  puesto.ColumnID,
		"posicion":   puesto.Posicion,
		"colocadoAt": hora(puesto.ColocadoAt),
	})
}

// porQueNoSePudoColocar traduce el «cero filas» del INSERT.
//
// Cero filas puede ser cuatro cosas —el pedido no existe, es de otra sucursal, la columna
// no es suya, o el pedido ya va en un camión— y las cuatro no se responden igual: que ya
// vaya en una ruta es un 409 que la persona puede arreglar; que sea de otra sucursal es
// un 404 y NO se dice que existe, porque decirlo ya es contar algo.
func (s *Servidor) porQueNoSePudoColocar(w http.ResponseWriter, r *http.Request, a *alcance.Acotado, pedido uuid.UUID) {
	p, err := a.TableroObtenerPedido(r.Context(), pedido)
	if err != nil {
		// Si no se puede leer —no existe, o es de otra sucursal—, 404 y punto.
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return
	}
	if p.RouteID.Valid {
		httpx.Error(w, r, http.StatusConflict, msgYaVaEnUnaRuta)
		return
	}
	// El pedido existe y está libre: entonces lo que no cuadra es la columna.
	httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
}

// DELETE /api/board/placements/{id} — de vuelta a «sin colocar», que es de donde salió.
//
// Reaplicable también: quitar dos veces lo que ya no está no es un error, es el mismo
// tablero. Un lote que se reintenta no puede empezar a fallar por eso.
func (s *Servidor) quitarPedidoDelTablero(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	pedido, ok := idDeRuta(w, r, httpx.MsgNotFound)
	if !ok {
		return
	}

	quitado := false
	err := a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		fila, err := tx.QuitarPedidoDelTablero(r.Context(), pedido)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		quitado = true
		// Cerrar el hueco no es imprescindible —el orden se lee, no se cuenta— pero sin
		// ello las posiciones se van separando hasta que un día alguien lee «la parada
		// número 47» de una columna de nueve.
		_, err = tx.CerrarHuecoEnColumna(r.Context(), fila.ColumnID, fila.Posicion)
		return err
	})
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	httpx.JSON(w, r, http.StatusOK, map[string]any{"success": true, "quitado": quitado})
}

// ---------------------------------------------------------------------------
// De una columna sale una ruta
// ---------------------------------------------------------------------------

type cuerpoArmar struct {
	Nombre     httpx.Opcional[string] `json:"nombre"`
	VehiculoID httpx.Opcional[string] `json:"vehiculoId"`
	// Optimizar reordena por cercanía (el greedy de siempre). Por defecto NO: el
	// logístico ya propuso un orden arrastrando y él conoce las calles de su distrito;
	// el vecino más próximo no. Lo que no puede pasar es que su orden se pierda sin que
	// nadie se lo diga.
	Optimizar httpx.Opcional[bool] `json:"optimizar"`
}

// DescartadoSalida nombra a cada pedido que se cayó y POR QUÉ. Una columna de doce que
// produce una ruta de nueve sin explicación es la manera más rápida de que el logístico
// deje de fiarse del tablero.
type DescartadoSalida struct {
	PedidoID        uuid.UUID `json:"pedidoId"`
	OperationNumber *string   `json:"operationNumber"`
	CustomerName    string    `json:"customerName"`
	Motivo          string    `json:"motivo"`
}

// POST /api/board/columns/{id}/route
func (s *Servidor) armarRutaDeColumna(w http.ResponseWriter, r *http.Request) {
	a, ok := acotado(w, r)
	if !ok {
		return
	}
	id, ok := idDeRuta(w, r, httpx.MsgNotFound)
	if !ok {
		return
	}
	var c cuerpoArmar
	if !httpx.LeerJSON(w, r, &c) {
		return
	}

	columna, err := a.ObtenerColumna(r.Context(), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, r, http.StatusNotFound, httpx.MsgNotFound)
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	suc, err := a.ObtenerSucursal(r.Context(), columna.BranchID)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	almacen, ok := s.almacenDe(w, r, a, columna.BranchID, suc.Name)
	if !ok {
		return
	}

	// ESTA CONSULTA ES LA VALIDACIÓN, no una lectura previa a ella. Si vuelven menos de
	// los que hay puestos, alguien se los llevó entre que se pintó el tablero y se pulsó
	// el botón —con el Super Admin y el armador de siempre por medio eso pasa de verdad—
	// y de ahí sale el 409.
	candidatos, err := a.PedidosDeColumnaParaArmarRuta(r.Context(), id)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	puestos, err := a.ContarPedidosEnColumna(r.Context(), id)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	if faltan := puestos - int64(len(candidatos)); faltan > 0 {
		httpx.Error(w, r, http.StatusConflict,
			fmt.Sprintf("%d de los %d pedidos ya están en otra ruta. Vuelve a elegirlos.", faltan, puestos))
		return
	}

	// El corte por factura se hace AQUÍ y no en el SQL, para poder nombrar cuál falla y
	// por qué. Un WHERE que los descartara en la consulta deja el mismo rechazo sin nada
	// que decir.
	var buenos []sqlc.PedidosDeColumnaParaArmarRutaRow
	descartados := []DescartadoSalida{}
	for _, p := range candidatos {
		motivo := ""
		switch {
		case p.Archivado:
			motivo = "archivado en PEDIDO"
		case p.FacturaEstado == nil:
			// NULL NO ES «cuadra». Con un NULL colado se armó una ruta sin facturar el
			// 2/09; por eso se nombra distinto de `sin_factura`.
			motivo = "sin cotejar"
		case *p.FacturaEstado == sqlc.FacturaEstadoSinFactura:
			motivo = "sin factura"
		case *p.FacturaEstado == sqlc.FacturaEstadoCambiado:
			motivo = "cambió en la factura"
		}
		if motivo == "" {
			buenos = append(buenos, p)
			continue
		}
		descartados = append(descartados, DescartadoSalida{
			PedidoID: p.ID, OperationNumber: p.OperationNumber,
			CustomerName: p.CustomerName, Motivo: motivo,
		})
	}
	if len(buenos) == 0 {
		// No se crea una ruta vacía, y se dice por qué se cayó cada uno.
		httpx.JSON(w, r, http.StatusConflict, map[string]any{
			"error":       msgColumnaSinNada,
			"descartados": descartados,
		})
		return
	}

	// El camión: el que venga en el cuerpo, si no el PREVISTO de la columna. Puede no
	// haber ninguno; la ruta se arma igual y el camión se elige después.
	vehiculo := columna.VehicleID
	if c.VehiculoID.Presente {
		v, ok := vehiculoDelCuerpo(w, r, c.VehiculoID)
		if !ok {
			return
		}
		vehiculo = v
	}

	// El orden de visita. Por defecto se RESPETA el del logístico —ya vienen ordenados
	// por `p.posicion`—; el greedy sólo si lo pide.
	if c.Optimizar.Con(false) {
		buenos = porCercania(buenos, almacen.Lat, almacen.Lng)
	}

	pesoTotal := 0.0
	costoTotal := 0.0
	for _, p := range buenos {
		pesoTotal += p.Weight
		if p.PedidoCosto != nil {
			costoTotal += *p.PedidoCosto
		}
	}

	// La capacidad se comprueba AL ARMAR, que es donde importa. En el tablero el exceso
	// sólo avisa (§7.3): el tablero es un borrador y el camión previsto es una intención.
	// Aquí ya no: lo que no cabe, no sube.
	if vehiculo.Valid {
		v, err := a.TableroVehiculoParaCapacidad(r.Context(), uuid.UUID(vehiculo.Bytes))
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			httpx.ErrorInterno(w, r, err)
			return
		}
		if err == nil && v.Capacity > 0 && pesoTotal > v.Capacity {
			httpx.Error(w, r, http.StatusBadRequest,
				fmt.Sprintf("Peso total (%.1f kg) supera la capacidad del vehículo (%g kg)", pesoTotal, v.Capacity))
			return
		}
	}

	codigo, err := s.codigoDeRuta(r, a)
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}
	nombre := strings.TrimSpace(c.Nombre.Con(columna.Nombre))

	var ruta sqlc.CrearRutaRow
	var enganchados int64
	distancia := 0.0
	err = a.EnTx(r.Context(), func(tx *alcance.Acotado) error {
		var err error
		ruta, err = tx.TableroCrearRuta(r.Context(), sqlc.CrearRutaParams{
			Name:          &nombre,
			RouteCode:     &codigo,
			OriginAddress: aTexto(almacen.Nombre),
			OriginLat:     &almacen.Lat,
			OriginLng:     &almacen.Lng,
			VehicleID:     vehiculo,
			BranchID:      pgDe(columna.BranchID),
		})
		if err != nil {
			return err
		}

		anteriorLat, anteriorLng := almacen.Lat, almacen.Lng
		for i, p := range buenos {
			orden := int32(i + 1)
			// `segment_km` es la distancia RADIAL desde el origen y no la del tramo: se
			// hereda así de delivery porque es el número con el que se repartió la carga
			// hasta hoy. Cambiarlo aquí descuadraría los informes viejos.
			radial := kmHaversine(almacen.Lat, almacen.Lng, coord(p.EndLat), coord(p.EndLng))
			n, err := tx.TableroEngancharPedidoARuta(r.Context(), sqlc.EngancharPedidoARutaParams{
				RutaID:    pgDe(ruta.ID),
				StopOrder: &orden,
				SegmentKm: &radial,
				PedidoID:  p.ID,
			})
			if err != nil {
				return err
			}
			if n == 0 {
				// Se lo llevaron entre la validación y el enganche. Se deshace todo: una
				// ruta a la que le falta una parada es peor que ninguna ruta.
				return errSeLoLlevaron
			}
			enganchados += n
			distancia += kmHaversine(anteriorLat, anteriorLng, coord(p.EndLat), coord(p.EndLng))
			anteriorLat, anteriorLng = coord(p.EndLat), coord(p.EndLng)
		}
		// El CIRCUITO CERRADO: los tramos más el regreso al origen. El camión vuelve, y
		// no contar la vuelta subestima el viaje justo a la mitad de las rutas largas.
		distancia += kmHaversine(anteriorLat, anteriorLng, almacen.Lat, almacen.Lng)

		if _, err := tx.TableroFijarTotalesDeRuta(r.Context(), sqlc.FijarTotalesDeRutaParams{
			TotalDistance: distancia, TotalWeight: pesoTotal, TotalPrice: costoTotal,
			ID: ruta.ID,
		}); err != nil {
			return err
		}

		// Y las tarjetas de esa columna se vacían, EN LA MISMA TRANSACCIÓN. La columna se
		// queda: el distrito sigue existiendo mañana. Lo que se vacía es lo que llevaba
		// dentro hoy.
		_, err = tx.QuitarDelTableroLosDeRuta(r.Context(), ruta.ID)
		return err
	})
	if errors.Is(err, errSeLoLlevaron) {
		httpx.Error(w, r, http.StatusConflict,
			"Uno de los pedidos se subió a otra ruta mientras se armaba ésta. Vuelve a intentarlo.")
		return
	}
	if err != nil {
		httpx.ErrorInterno(w, r, err)
		return
	}

	httpx.JSON(w, r, http.StatusCreated, map[string]any{
		"id":          ruta.ID,
		"routeCode":   ruta.RouteCode,
		"name":        ruta.Name,
		"status":      string(ruta.Status),
		"branchId":    columna.BranchID,
		"columnaId":   columna.ID,
		"paradas":     enganchados,
		"totalWeight": pesoTotal,
		"totalPrice":  costoTotal,
		"distanciaKm": distancia,
		"origen":      almacen,
		// Quién se cayó y por qué, siempre, aunque esté vacío: la pantalla tiene que
		// poder decir «de doce salieron nueve, y éstos tres son los que faltan».
		"descartados": descartados,
	})
}

var errSeLoLlevaron = errors.New("un pedido se subió a otra ruta mientras se armaba")

// codigoDeRuta arma el `RT-YYYYMMDD-NNN`.
//
// OJO: no es atómico, y se hereda así. Dos armados a la vez leen el mismo número y salen
// con el mismo código; delivery tenía la misma carrera. Se mantiene para no cambiar el
// formato, que es lo que la gente se dice por teléfono. Si empieza a chocar, la salida es
// una secuencia por día, no un reintento.
func (s *Servidor) codigoDeRuta(r *http.Request, a *alcance.Acotado) (string, error) {
	prefijo := "RT-" + time.Now().Format("20060102")
	n, err := a.TableroContarRutasDelDia(r.Context(), prefijo)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%s-%03d", prefijo, n+1), nil
}

// ---------------------------------------------------------------------------
// Ayudas
// ---------------------------------------------------------------------------

func deColumnas(filas []sqlc.ListarColumnasDelTableroRow) []ColumnaSalida {
	salida := make([]ColumnaSalida, 0, len(filas))
	for _, f := range filas {
		salida = append(salida, ColumnaSalida{
			ID: f.ID, BranchID: f.BranchID, Nombre: f.Nombre, Posicion: f.Posicion,
			VehicleID:         idOpcional(f.VehicleID),
			VehiculoNombre:    f.VehiculoNombre,
			VehiculoMatricula: f.VehiculoMatricula,
			VehiculoCapacidad: f.VehiculoCapacidad,
			Pedidos:           f.Pedidos, PesoKg: f.PesoKg, CostoUsd: f.CostoUsd,
			ExcedeCamion: f.ExcedeCamion,
			CreatedAt:    hora(f.CreatedAt), UpdatedAt: hora(f.UpdatedAt),
		})
	}
	return salida
}

// deColumnaPelada es la columna recién creada o recién tocada, sin totales: no los tiene
// todavía, y devolver ceros diría «esta columna está vacía» de una que puede no estarlo.
func deColumnaPelada(c sqlc.BoardColumn) ColumnaSalida {
	return ColumnaSalida{
		ID: c.ID, BranchID: c.BranchID, Nombre: c.Nombre, Posicion: c.Posicion,
		VehicleID: idOpcional(c.VehicleID),
		CreatedAt: hora(c.CreatedAt), UpdatedAt: hora(c.UpdatedAt),
	}
}

func deTarjetas(filas []sqlc.ListarPedidosColocadosRow) []TarjetaSalida {
	repes := map[string]int{}
	for _, f := range filas {
		repes[strings.ToLower(strings.TrimSpace(f.CustomerName))]++
	}
	salida := make([]TarjetaSalida, 0, len(filas))
	for _, f := range filas {
		salida = append(salida, TarjetaSalida{
			PedidoID: f.OrderID, ColumnaID: f.ColumnID, Posicion: f.Posicion,
			ColumnaNombre: f.ColumnaNombre, OperationNumber: f.OperationNumber,
			CustomerName: f.CustomerName, CustomerPhone: f.CustomerPhone,
			Address: f.Address, EndAddress: f.EndAddress, Weight: f.Weight,
			PedidoCosto: f.PedidoCosto, Municipio: f.Municipio, Vendedor: f.Vendedor,
			KmAlAlmacen:   f.KmAlAlmacen,
			FacturaEstado: facturaEstado(f.FacturaEstado),
			Archivado:     f.Archivado,
			RutaID:        idOpcional(f.RouteID),
			Resultado:     resultado(f.Resultado),
			ColocadoAt:    hora(f.ColocadoAt),
			MismoCliente:  repes[strings.ToLower(strings.TrimSpace(f.CustomerName))],
		})
	}
	return salida
}

// porCliente cuenta cuántas tarjetas tiene cada cliente en la lista. NO se funden: lo
// único que hace la pantalla es marcarlas para que el logístico las meta en la misma
// columna a propósito y no por casualidad.
func porCliente(filas []sqlc.ListarPedidosSinColocarRow) map[string]int {
	m := map[string]int{}
	for _, f := range filas {
		m[strings.ToLower(strings.TrimSpace(f.CustomerName))]++
	}
	return m
}

// porCercania es el greedy del vecino más próximo, el mismo del armador de siempre. Sólo
// se aplica si lo piden: el orden por defecto es el del logístico.
func porCercania(pedidos []sqlc.PedidosDeColumnaParaArmarRutaRow, lat, lng float64) []sqlc.PedidosDeColumnaParaArmarRutaRow {
	// Copia estable primero, para que dos llamadas con los mismos datos den lo mismo.
	quedan := append([]sqlc.PedidosDeColumnaParaArmarRutaRow(nil), pedidos...)
	sort.SliceStable(quedan, func(i, j int) bool { return quedan[i].Posicion < quedan[j].Posicion })

	orden := make([]sqlc.PedidosDeColumnaParaArmarRutaRow, 0, len(quedan))
	curLat, curLng := lat, lng
	for len(quedan) > 0 {
		mejor, mejorKm := 0, math.MaxFloat64
		for i, p := range quedan {
			km := kmHaversine(curLat, curLng, coord(p.EndLat), coord(p.EndLng))
			if km < mejorKm {
				mejor, mejorKm = i, km
			}
		}
		p := quedan[mejor]
		orden = append(orden, p)
		curLat, curLng = coord(p.EndLat), coord(p.EndLng)
		quedan = append(quedan[:mejor], quedan[mejor+1:]...)
	}
	return orden
}

func coord(v *float64) float64 {
	if v == nil {
		return 0
	}
	return *v
}

// vehiculoDelCuerpo traduce el `vehiculoId` del cuerpo. Vacío o null es «quítamelo»; un
// id que no es un uuid es un 400, porque aquí sí se sabe que el que escribe es el cliente.
func vehiculoDelCuerpo(w http.ResponseWriter, r *http.Request, v httpx.Opcional[string]) (pgtype.UUID, bool) {
	crudo := strings.TrimSpace(v.Con(""))
	if crudo == "" {
		return pgtype.UUID{}, true
	}
	id, err := uuid.Parse(crudo)
	if err != nil {
		httpx.Error(w, r, http.StatusBadRequest,
			fmt.Sprintf("«%s» no es el id de un vehículo", crudo))
		return pgtype.UUID{}, false
	}
	return pgDe(id), true
}

// diaDelPedido convierte `dia=2026-09-14` en el intervalo MEDIO ABIERTO del día, igual
// que en el armador. Medio abierto y no `<=` del último segundo: con `<=` se pierde lo
// que cae en el mismo segundo del corte, que con marcas de microsegundos pasa.
func diaDelPedido(crudo string) (pgtype.Timestamptz, pgtype.Timestamptz) {
	crudo = strings.TrimSpace(crudo)
	if crudo == "" {
		return pgtype.Timestamptz{}, pgtype.Timestamptz{}
	}
	d, err := time.Parse("2006-01-02", crudo)
	if err != nil {
		return pgtype.Timestamptz{}, pgtype.Timestamptz{}
	}
	return pgtype.Timestamptz{Time: d, Valid: true},
		pgtype.Timestamptz{Time: d.AddDate(0, 0, 1), Valid: true}
}

func textoOpcional(v string) *string {
	v = strings.TrimSpace(v)
	if v == "" {
		return nil
	}
	return &v
}

func numeroOpcional(v string) *float64 {
	v = strings.TrimSpace(v)
	if v == "" {
		return nil
	}
	n, err := strconv.ParseFloat(v, 64)
	if err != nil || n <= 0 {
		return nil
	}
	return &n
}

func facturaEstado(v *sqlc.FacturaEstado) *string {
	if v == nil {
		return nil
	}
	s := string(*v)
	return &s
}

func resultado(v *sqlc.StopResult) *string {
	if v == nil {
		return nil
	}
	s := string(*v)
	return &s
}
