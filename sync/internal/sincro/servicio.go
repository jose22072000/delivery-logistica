// Package sincro es el protocolo de `docs/sincronizacion.md`, y nada más.
//
// Los datos del reparto —los pedidos, las rutas, los clientes— NO son de aquí. Este
// servicio reparte diferencias y recibe lotes; quien los guarda es `reparto-api`. Lo único
// que vive en la base de este servicio es la contabilidad de la sincronización: quién bajó,
// quién subió, qué se le aplicó y qué se le rechazó.
//
// Por eso el dueño de los datos entra por dos interfaces, `Origen` y `Aplicador`: son la
// frontera con el reparto, y son lo que permite probar aquí las seis cosas que no pueden
// salir mal sin levantar medio sistema.
package sincro

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/store"
)

// Los ocho conjuntos de la bajada, en el orden del protocolo. Se contestan SIEMPRE los
// ocho, aunque vengan vacíos: así la aplicación recorre lo que llega sin preguntarse si
// una clave que falta quiere decir «no cambió nada» o «el servidor es más viejo».
var Colecciones = []string{
	"orders", "routes", "customers", "products",
	"vehicles", "branches", "warehouses", "settings",
}

// Conjunto es lo que cambió en una colección.
//
// `quitados` hace falta de verdad: sin él, un pedido archivado o una ruta borrada se quedan
// en el aparato para siempre y la lista local sólo crece.
type Conjunto struct {
	Puestos  []json.RawMessage `json:"puestos"`
	Quitados []string          `json:"quitados"`
}

type Cambios map[string]Conjunto

// Ventana es lo que se le pide al reparto: qué sucursal y qué trozo de tiempo.
//
// `Hasta` va SIEMPRE puesto y lo pone este servicio con su propio reloj. No es un detalle
// de implementación: es la regla 5 del protocolo.
type Ventana struct {
	Sucursal uuid.UUID
	Desde    *time.Time
	Hasta    time.Time
	Tope     int32
}

// Origen es el dueño de los datos, del lado de la lectura.
type Origen interface {
	// Diferencias devuelve lo que cambió en esa ventana y si quedó cortado por el tope.
	Diferencias(ctx context.Context, v Ventana) (Cambios, bool, error)
}

// Peticion es un apunte del aparato ya traducido y listo para mandárselo al reparto.
type Peticion struct {
	Metodo string
	Ruta   string
	Cuerpo json.RawMessage
	// La hora del APARATO. Lo que se marcó a las cuatro llega como las cuatro aunque suba
	// a las siete: en PEDIDO el vendedor tiene que ver cuándo recibió su cliente, no
	// cuándo pilló señal el teléfono.
	Hecho    time.Time
	Sucursal uuid.UUID
	Persona  string
	Clave    string
}

// Aplicador es el dueño de los datos, del lado de la escritura.
//
// Devuelve el id de lo que se creó —o nil si el apunte no creaba nada—. Un `*Rechazo`
// significa que el reparto dijo que no por una razón de negocio y que NO hay que
// reintentarlo; cualquier otro error es una caída y el apunte se queda en la cola.
type Aplicador interface {
	Aplicar(ctx context.Context, p Peticion) (*uuid.UUID, error)
}

// Rechazo es el «no» del servidor, con la frase que va a leer una persona.
//
// Es un tipo de error aparte justamente para no confundirlo con una caída: un rechazo se
// guarda con su motivo y sale en el panel; una caída se reintenta. Tratar el segundo como
// el primero llenaría la bandeja de rechazos falsos el día que el reparto se reinicie.
type Rechazo struct {
	Motivo string
}

func (r *Rechazo) Error() string { return r.Motivo }

type Opciones struct {
	Datos     store.Datos
	Origen    Origen
	Aplicador Aplicador
	// El reloj del SERVIDOR. Es un campo y no `time.Now` a secas porque la regla 5 —la
	// marca de la bajada la pone el servidor— hay que poder probarla.
	Ahora      func() time.Time
	TopeBajada int32
	Log        *slog.Logger
}

type Servicio struct {
	datos     store.Datos
	origen    Origen
	aplicador Aplicador
	ahora     func() time.Time
	tope      int32
	log       *slog.Logger
}

func Nuevo(o Opciones) *Servicio {
	s := &Servicio{
		datos:     o.Datos,
		origen:    o.Origen,
		aplicador: o.Aplicador,
		ahora:     o.Ahora,
		tope:      o.TopeBajada,
		log:       o.Log,
	}
	if s.ahora == nil {
		s.ahora = func() time.Time { return time.Now().UTC() }
	}
	if s.tope <= 0 {
		s.tope = 500
	}
	if s.log == nil {
		s.log = slog.Default()
	}
	return s
}

// Rutas son las cuatro del protocolo. Los patrones con método son de `net/http`: no hace
// falta un enrutador de fuera para cuatro rutas sin parámetros en el camino.
func (s *Servicio) Rutas(mux *http.ServeMux) {
	mux.HandleFunc("POST /sync/aparato", s.alta)
	mux.HandleFunc("GET /sync/bajada", s.bajada)
	mux.HandleFunc("POST /sync/subida", s.subida)
	mux.HandleFunc("GET /sync/estado", s.estado)
}
