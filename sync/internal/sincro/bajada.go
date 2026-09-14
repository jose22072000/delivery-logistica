package sincro

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/httpx"
	"procovar/reparto-sync/internal/identidad"
	"procovar/reparto-sync/internal/store"
	"procovar/reparto-sync/internal/store/sqlc"
)

// GET /sync/bajada?aparato=<uuid>&desde=<marca>&sucursal=<uuid>
//
// Devuelve lo que cambió desde `desde`. Sin `desde`, la primera carga completa.

type bajadaSalida struct {
	// La marca para la próxima vez. LA PONE EL SERVIDOR.
	Hasta time.Time `json:"hasta"`
	// true si fue carga inicial.
	Completa bool    `json:"completa"`
	Cambios  Cambios `json:"cambios"`
	// Hay más: repetir con el `hasta` devuelto.
	Truncado bool `json:"truncado"`
}

func (s *Servicio) bajada(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	quien, hay := identidad.De(ctx)
	if !hay {
		httpx.Fallo(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	aparato, ok := s.aparatoDeLaPeticion(w, r, quien, r.URL.Query().Get("aparato"))
	if !ok {
		return
	}

	// Si el aparato dice de qué sucursal cree que es, tiene que coincidir con la que se
	// guardó en su alta. No es una comprobación de cortesía: el alcance por sucursal es
	// LA regla de seguridad del reparto, y aquí es donde un aparato podría pedir el día
	// entero de otra sucursal con sólo cambiar un parámetro.
	if v := r.URL.Query().Get("sucursal"); v != "" {
		pedida, err := uuid.Parse(v)
		if err != nil || pedida != aparato.BranchID {
			httpx.Fallo(w, http.StatusForbidden, "Ese aparato no es de esa sucursal")
			return
		}
	}

	// La señal de vida se toca en CADA petición, baje o suba: es lo que distingue «el
	// teléfono está apagado en un cajón» de «el teléfono trabaja pero no sube».
	if err := s.datos.TocarAparato(ctx, aparato.ID); err != nil {
		s.log.Warn("no se pudo tocar el aparato", "aparato", aparato.ID, "err", err)
	}

	desde, ok := s.desdeDeVerdad(w, r, aparato.ID)
	if !ok {
		return
	}

	// REGLA 5. La marca la pone el reloj del SERVIDOR, y se coge ANTES de preguntarle al
	// reparto: si se cogiera después, lo que cambiara mientras se responde caería dentro
	// de la ventana devuelta sin haber salido en ella, y la próxima bajada no lo traería.
	hasta := s.ahora().UTC()

	cambios, truncado, err := s.origen.Diferencias(ctx, Ventana{
		Sucursal: aparato.BranchID,
		Desde:    desde,
		Hasta:    hasta,
		Tope:     s.tope,
	})
	if err != nil {
		s.log.Error("el reparto no pudo dar las diferencias", "aparato", aparato.ID, "err", err)
		httpx.Fallo(w, http.StatusBadGateway, "No se pudieron traer los cambios del reparto")
		return
	}

	// La marca se anota DESPUÉS de tener los cambios en la mano. Al revés, un fallo del
	// reparto dejaría la marca movida sin que el aparato se llevara nada, y ese trozo de
	// tiempo no lo volvería a pedir nadie.
	if err := s.datos.AnotarBajada(ctx, sqlc.AnotarBajadaParams{
		AparatoID:   aparato.ID,
		BajadaHasta: marca(hasta),
	}); err != nil {
		s.log.Error("no se pudo anotar la bajada", "aparato", aparato.ID, "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo anotar la bajada")
		return
	}

	httpx.JSON(w, http.StatusOK, bajadaSalida{
		Hasta:    hasta,
		Completa: desde == nil,
		Cambios:  completar(cambios),
		Truncado: truncado,
	})
}

// desdeDeVerdad decide desde cuándo se baja, y es donde se cumple la otra mitad de la
// regla 5.
//
// El aparato manda el `desde`, pero lo único que puede mandar es una marca QUE LE DIO ESTE
// SERVIDOR. Por eso se compara con la última que se le entregó (`bajada_hasta`, guardada
// aquí precisamente porque el aparato la puede perder: se reinstala, se limpian los datos,
// se cierra sesión y se borra lo local):
//
//   - si pide desde antes, se le hace caso y baja de más. Repetir un cambio no rompe nada.
//   - si pide desde DESPUÉS, no se le hace caso. Un reloj adelantado —o una marca inventada—
//     se saltaría para siempre todo lo que cambió en medio, sin que nadie se entere.
//   - si el servidor no le ha dado ninguna todavía, no hay marca válida posible: carga
//     completa.
func (s *Servicio) desdeDeVerdad(w http.ResponseWriter, r *http.Request, aparato uuid.UUID) (*time.Time, bool) {
	ctx := r.Context()

	var pedido *time.Time
	if v := r.URL.Query().Get("desde"); v != "" {
		t, err := time.Parse(time.RFC3339Nano, v)
		if err != nil {
			httpx.Fallo(w, http.StatusBadRequest, "La marca `desde` no tiene el formato de fecha esperado")
			return nil, false
		}
		t = t.UTC()
		pedido = &t
	}

	estado, err := s.datos.EstadoDeAparato(ctx, aparato)
	if err != nil {
		if store.SinFilas(err) {
			// El aparato existe pero no tiene fila de estado: se abre ahora y se baja
			// entero. Es preferible una carga completa de más a dar por buena una marca
			// que este servidor no recuerda haber dado.
			if err := s.datos.AbrirEstado(ctx, aparato); err != nil {
				s.log.Warn("no se pudo abrir el estado del aparato", "aparato", aparato, "err", err)
			}
			return nil, true
		}
		s.log.Error("no se pudo leer el estado del aparato", "aparato", aparato, "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo leer el estado del aparato")
		return nil, false
	}

	entregada := hora(estado.BajadaHasta)
	if entregada == nil {
		return nil, true
	}
	if pedido == nil || pedido.After(*entregada) {
		return entregada, true
	}
	return pedido, true
}

// completar deja los ocho conjuntos puestos aunque el reparto sólo haya contestado los que
// cambiaron, y cambia los nil por listas vacías: `null` y `[]` no son lo mismo para quien
// recorre la respuesta en Dart.
func completar(c Cambios) Cambios {
	if c == nil {
		c = Cambios{}
	}
	for _, nombre := range Colecciones {
		conjunto := c[nombre]
		if conjunto.Puestos == nil {
			conjunto.Puestos = []json.RawMessage{}
		}
		if conjunto.Quitados == nil {
			conjunto.Quitados = []string{}
		}
		c[nombre] = conjunto
	}
	return c
}

// aparatoDeLaPeticion busca el aparato y comprueba que quien llama puede hablar por él.
func (s *Servicio) aparatoDeLaPeticion(w http.ResponseWriter, r *http.Request, quien identidad.Identidad, crudo string) (sqlc.Aparato, bool) {
	if crudo == "" {
		httpx.Fallo(w, http.StatusBadRequest, "Falta el aparato")
		return sqlc.Aparato{}, false
	}
	id, err := uuid.Parse(crudo)
	if err != nil {
		httpx.Fallo(w, http.StatusBadRequest, "El aparato no es un identificador válido")
		return sqlc.Aparato{}, false
	}

	aparato, err := s.datos.AparatoPorId(r.Context(), id)
	if err != nil {
		if store.SinFilas(err) {
			// 404 y no 401: el aparato tiene que poder distinguir «me borraron del
			// registro, hay que darse de alta otra vez» de «se me caducó la sesión».
			httpx.Fallo(w, http.StatusNotFound, "Ese aparato no está registrado. Vuelve a darlo de alta.")
			return sqlc.Aparato{}, false
		}
		s.log.Error("no se pudo leer el aparato", "aparato", id, "err", err)
		httpx.Fallo(w, http.StatusInternalServerError, "No se pudo leer el aparato")
		return sqlc.Aparato{}, false
	}

	// REGLA 6, del lado de la persona: un aparato sólo lo maneja quien puede ver su
	// sucursal.
	if !quien.Ve(aparato.BranchID) {
		httpx.Fallo(w, http.StatusForbidden, "Ese aparato no es de tu sucursal")
		return sqlc.Aparato{}, false
	}
	return aparato, true
}
