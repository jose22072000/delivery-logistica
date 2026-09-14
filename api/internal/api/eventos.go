// LOS EVENTOS EN VIVO  (GET /api/eventos) — SSE.
//
// Para qué sirve: que la pantalla del logístico se entere de que algo cambió sin estar
// preguntando cada pocos segundos. El aviso dice QUÉ cambió —`pedidos`, `catalogo`,
// `rutas` o `clientes`— y no «algo»: invalidarlo todo en cada cambio significa volver a
// bajar el catálogo entero cada vez que alguien cotiza un domicilio, por la conexión de
// allá (`../docs/reglas-negocio.md` §14).
//
// # El bus va EN MEMORIA DEL PROCESO, no en Redis
//
// En delivery esto se publicaba en Redis y `/api/eventos` repartía lo que llegaba por el
// canal. Aquí el bus es del proceso y se explica solo: quien avisa y quien reparte son el
// mismo servicio —los cambios los escriben estos mismos manejadores—, así que Redis sólo
// añadiría una pieza más que puede estar caída para llevar un mensaje de una gorutina a
// otra. Si algún día la API corre en dos réplicas hay que volver a un bus de verdad: lo
// único que cambia es `Difusor`, porque el manejador no sabe de dónde le llegan los
// cambios. Queda dicho aquí para que ese día se vea.
//
// # Lo que NO se puede tocar de este fichero sin romper algo que ya costó una vuelta
//
//  1. **El latido.** Una conexión callada la corta el proxy de delante al minuto o dos, y
//     desde el navegador eso se ve como «los avisos dejaron de llegar» sin ningún error.
//  2. **`X-Accel-Buffering: no`.** Sin esa cabecera, nginx guarda los eventos en su propio
//     colchón y los suelta en bloque: la pantalla se entera de todo cuarenta segundos
//     tarde, o cuando se cierra la conexión.
//  3. **NUNCA `Connection: keep-alive`.** HTTP/2 y HTTP/3 lo prohíben, y con Cloudflare
//     por delante da `ERR_QUIC_PROTOCOL_ERROR`. No se pone: en HTTP/1.1 ya es lo implícito.
//  4. **El plazo de escritura.** El servidor va con `WriteTimeout` (30 s por defecto); sin
//     renovarlo en cada escritura, TODA conexión de eventos se muere a los treinta
//     segundos, pase lo que pase.
//  5. **El apagado.** Ver `registrarApagado`: una conexión abierta para siempre deja el
//     `Shutdown` esperándola hasta que se le acaba el plazo.
package api

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"sync"
	"time"

	"procovar/reparto-api/internal/httpx"
)

// Los cuatro tipos de cambio. Son los del contrato y los conoce la pantalla: uno nuevo que
// ella no espere se recibe y se ignora, así que añadir aquí no rompe nada, pero renombrar
// sí.
const (
	CambioPedidos  = "pedidos"
	CambioCatalogo = "catalogo"
	CambioRutas    = "rutas"
	CambioClientes = "clientes"
)

// FrenoAvisos: como mucho UN aviso cada quince segundos por tipo.
//
// POR QUÉ: el espejo importa por lotes de doscientos y avisaba por cada lote — veinte
// avisos seguidos y la pantalla recargándose veinte veces. Lo que pasa en ese rato viaja
// en el siguiente aviso, así que no se pierde nada: se pierde el parpadeo.
const FrenoAvisos = 15 * time.Second

// El latido, y el plazo de cada escritura. Son variables y no constantes para que las
// pruebas no tarden veinte segundos en comprobar que el latido sale.
var (
	latidoSSE   = 20 * time.Second
	plazoEnvio  = 10 * time.Second
	colaAbonado = 16 // avisos en vuelo que se le guardan a un abonado lento
)

// Cambio es lo que se publica. `Detalle` es libre —`{"pedidos": 42}`, `{"productos": 300}`—
// y lo pone quien avisa.
type Cambio struct {
	Tipo    string
	Cuando  time.Time
	Detalle map[string]any
}

// datos arma el `data:` del evento: `{tipo, ...detalle, cuando}`, tal cual el contrato.
//
// `tipo` y `cuando` se escriben DESPUÉS del detalle a propósito: si quien avisa mete un
// `tipo` en el detalle, el bueno es el del aviso y no el suyo. Un detalle que pueda pisar
// el tipo es un detalle que puede hacer que la pantalla invalide otra cosa.
func (c Cambio) datos() []byte {
	m := make(map[string]any, len(c.Detalle)+2)
	for k, v := range c.Detalle {
		m[k] = v
	}
	m["tipo"] = c.Tipo
	// Con milisegundos y en UTC, que es lo que lee la pantalla (`2026-09-14T10:00:00.000Z`).
	m["cuando"] = c.Cuando.UTC().Format("2006-01-02T15:04:05.000Z07:00")
	b, err := json.Marshal(m)
	if err != nil {
		// Un detalle que no se puede codificar —una función, un canal— no puede tumbar el
		// flujo de todos los abonados. Se manda el aviso pelado: la pantalla refresca
		// igual, que es para lo único que sirve.
		return []byte(`{"tipo":"` + c.Tipo + `"}`)
	}
	return b
}

// Difusor reparte los cambios entre las conexiones abiertas.
//
// Hace tres cosas y las tres tienen que pasar sin bloquear a quien avisa: un aviso es un
// aviso, no el trabajo. Una importación de mil pedidos no puede quedarse esperando a que
// un navegador con la pestaña en segundo plano lea su canal.
type Difusor struct {
	mu       sync.Mutex
	abonados map[chan Cambio]struct{}
	ultimo   map[string]time.Time // el freno, por tipo
	cerrado  bool
	// enganchados: los servidores HTTP a los que ya se les colgó el cierre. Ver
	// `registrarApagado`.
	enganchados map[*http.Server]struct{}

	freno time.Duration
	ahora func() time.Time // el reloj, por fuera, para poder probar el freno sin esperar
}

func NuevoDifusor() *Difusor {
	return &Difusor{
		abonados:    map[chan Cambio]struct{}{},
		ultimo:      map[string]time.Time{},
		enganchados: map[*http.Server]struct{}{},
		freno:       FrenoAvisos,
		ahora:       time.Now,
	}
}

// busEventos es el bus del proceso. Vive en el paquete y no en el `Servidor` porque es de
// TODO el proceso —un solo servicio, un solo bus—, igual que lo era el canal de Redis.
var busEventos = NuevoDifusor()

// El armador de rutas dejó preparado un gancho vacío (`avisarCambioDeRutas`, en `rutas.go`)
// para cuando hubiera un bus. Ya lo hay, así que se engancha aquí —desde el fichero del
// bus— y no allí: quien escribe rutas no tiene por qué saber cómo se reparten los avisos, y
// así el día que esto vuelva a ser Redis no hay que tocar el armador.
//
// El detalle va vacío a propósito: el aviso dice QUÉ cambió, no cuánto. La pantalla vuelve a
// pedir la lista, y esa sí va acotada a su sucursal.
func init() {
	avisarCambioDeRutas = func(_ context.Context) { busEventos.Avisar(CambioRutas, nil) }
}

// Avisar publica un cambio. Devuelve si salió o si lo paró el freno; nunca bloquea y nunca
// entra en pánico.
func (d *Difusor) Avisar(tipo string, detalle map[string]any) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.cerrado {
		return false
	}
	ahora := d.ahora()
	if visto, hay := d.ultimo[tipo]; hay && ahora.Sub(visto) < d.freno {
		// Se DESCARTA, no se encola ni se reprograma: lo que pasó en estos quince
		// segundos viaja en el siguiente aviso.
		return false
	}
	d.ultimo[tipo] = ahora

	c := Cambio{Tipo: tipo, Cuando: ahora, Detalle: detalle}
	for ch := range d.abonados {
		select {
		case ch <- c:
		default:
			// Abonado lleno: se le pierde este aviso. Es lo correcto —el siguiente le
			// dirá lo mismo— y desde luego mejor que dejar la escritura de un pedido
			// esperando a que un navegador se despierte.
		}
	}
	return true
}

// Suscribir abre un abono. El tercer valor es false cuando el bus está cerrado —el proceso
// se está parando—, y entonces no hay canal que escuchar.
func (d *Difusor) Suscribir() (<-chan Cambio, func(), bool) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.cerrado {
		return nil, func() {}, false
	}
	ch := make(chan Cambio, colaAbonado)
	d.abonados[ch] = struct{}{}
	// El corte NO cierra el canal: sólo lo saca del reparto. Cerrarlo aquí y cerrarlo en
	// `Cerrar` es cerrarlo dos veces el día que las dos cosas pasen a la vez.
	return ch, func() {
		d.mu.Lock()
		delete(d.abonados, ch)
		d.mu.Unlock()
	}, true
}

// Cerrar echa a todos los abonados y deja el bus cerrado para siempre.
//
// ES LO QUE PERMITE QUE EL SERVIDOR SE PARE. `http.Server.Shutdown` espera a que terminen
// las peticiones en vuelo, y una conexión de eventos no termina nunca por su cuenta: sin
// esto, el apagado se queda esperando el plazo entero y luego corta a lo bruto, con el
// mensaje de «no dio tiempo a terminar las peticiones en vuelo» que hace pensar en un
// problema que no existe.
func (d *Difusor) Cerrar() {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.cerrado {
		return
	}
	d.cerrado = true
	for ch := range d.abonados {
		close(ch)
		delete(d.abonados, ch)
	}
}

// Abonados: cuántas conexiones hay abiertas. Para las pruebas y para el registro.
func (d *Difusor) Abonados() int {
	d.mu.Lock()
	defer d.mu.Unlock()
	return len(d.abonados)
}

// AvisarCambio es por donde avisan los demás manejadores: `s.AvisarCambio(CambioPedidos,
// map[string]any{"pedidos": n})` después de escribir. Se llama SIEMPRE fuera de la
// transacción y sin mirar lo que devuelve: un aviso perdido no puede tumbar una
// importación de mil pedidos.
func (s *Servidor) AvisarCambio(tipo string, detalle map[string]any) {
	busEventos.Avisar(tipo, detalle)
}

// CerrarEventos cierra a mano las conexiones en vivo. No hace falta llamarla en el arranque
// normal —`registrarApagado` la engancha sola al `Shutdown` del servidor—; está para quien
// pare el servicio de otra manera.
func (s *Servidor) CerrarEventos() { busEventos.Cerrar() }

// rutasEventos monta el flujo. VA SIN `sesion` Y SIN `admin`, y no es un olvido:
//
//   - la sesión se comprueba DENTRO porque el 401 de esta ruta es `Unauthorized` en TEXTO
//     PLANO y no el `{"error":...}` de todas las demás. Es lo que espera el `EventSource`
//     del navegador, que no lee JSON;
//   - el alcance no se monta porque aquí no se consulta nada y porque el aviso no lleva
//     datos: dice «los pedidos cambiaron», no cuáles. Quien lo reciba volverá a pedir la
//     lista, y ESA sí va acotada. Un aviso no puede enseñar la sucursal de nadie porque no
//     enseña nada.
func (s *Servidor) rutasEventos(rt *httpx.Router, sesion, admin []httpx.Medio) {
	rt.ManejarFunc(http.MethodGet, "/api/eventos", s.eventos)
}

// GET /api/eventos
func (s *Servidor) eventos(w http.ResponseWriter, r *http.Request) {
	s.servirEventos(w, r, busEventos)
}

// servirEventos es el manejador de verdad, con el bus por parámetro para poder probarlo
// sin tocar el del proceso.
//
// NO ABRE NI UNA GORUTINA. Todo pasa en la de la petición: el `select` espera a la vez al
// corte del cliente, al siguiente cambio y al latido. Una gorutina aparte por conexión es
// lo que se queda viva cuando el navegador cierra la pestaña sin avisar, y con doscientas
// pestañas al día eso es un proceso que crece hasta que alguien lo reinicia.
func (s *Servidor) servirEventos(w http.ResponseWriter, r *http.Request, bus *Difusor) {
	if _, err := s.verif.DelaPeticion(r); err != nil {
		httpx.Registro(r).Warn("eventos sin sesión", "motivo", err)
		// TEXTO PLANO, no JSON: es lo que dice el contrato y lo que sabe leer el cliente.
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = io.WriteString(w, "Unauthorized")
		return
	}

	// Se engancha ANTES de abrir nada: si el servidor se para justo ahora, esta conexión
	// tiene que poder cerrarse sola.
	registrarApagado(r, bus)

	w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
	// Pisa el `no-store, must-revalidate` que pone `httpx.SinCache`. `no-transform` es la
	// parte que importa aquí: sin ella, un proxy que comprime al vuelo puede juntar los
	// bloques y la pantalla no recibe nada hasta que hay bastante que comprimir.
	w.Header().Set("Cache-Control", "no-store, no-transform")
	w.Header().Set("X-Accel-Buffering", "no")

	rc := http.NewResponseController(w)

	canal, cortar, vivo := bus.Suscribir()
	if !vivo {
		// El bus está cerrado: el proceso se está parando. Se contesta y se cierra, que es
		// mejor que dejar al navegador con una conexión que no le va a traer nada. La
		// pantalla lo entiende y pasa a refrescar sola cada treinta segundos.
		enviarSSE(w, r, rc, "event: sin-vivo\ndata: {}\n\n")
		return
	}
	defer cortar()

	// El `listo` va SIEMPRE el primero. Además de decir que hay avisos en vivo, obliga a
	// vaciar el colchón: hasta que no sale el primer byte, el navegador no da la conexión
	// por abierta y algunos proxys ni siquiera mandan las cabeceras.
	if !enviarSSE(w, r, rc, "event: listo\ndata: {\"vivo\":true}\n\n") {
		return
	}

	tic := time.NewTicker(latidoSSE)
	defer tic.Stop()

	for {
		select {
		case <-r.Context().Done():
			// El navegador cerró, o se acabó el plazo. No hay nada que limpiar salvo lo
			// que ya está en los `defer`.
			return

		case c, abierto := <-canal:
			if !abierto {
				// El bus se cerró: el servidor se está parando. Se sale para que el
				// `Shutdown` pueda terminar.
				return
			}
			if !enviarSSE(w, r, rc, "event: cambio\ndata: "+string(c.datos())+"\n\n") {
				return
			}

		case <-tic.C:
			// Un comentario SSE (`:`), que no es un evento: el cliente lo descarta y el
			// proxy ve tráfico. Es lo único que impide que la conexión se corte sola.
			if !enviarSSE(w, r, rc, ": latido\n\n") {
				return
			}
		}
	}
}

// enviarSSE escribe un bloque y lo vacía. Devuelve false cuando ya no se puede escribir
// —el cliente se fue—, que es la señal de salir del bucle.
func enviarSSE(w http.ResponseWriter, r *http.Request, rc *http.ResponseController, bloque string) bool {
	// EL PLAZO SE RENUEVA EN CADA ESCRITURA. El servidor arranca con `WriteTimeout`
	// puesto —y tiene que estarlo, es lo que impide que un cliente lento se quede con una
	// conexión para siempre—, pero ese plazo cuenta desde que empezó la petición: sin
	// renovarlo, toda conexión de eventos se muere a los treinta segundos. Que el escritor
	// no lo admita (una prueba con `httptest.ResponseRecorder`) no es un fallo.
	_ = rc.SetWriteDeadline(time.Now().Add(plazoEnvio))
	if _, err := io.WriteString(w, bloque); err != nil {
		httpx.Registro(r).Debug("se cortó el flujo de eventos", "err", err)
		return false
	}
	// Sin el vaciado no sale nada hasta que se llena el colchón de Go, que para líneas de
	// veinte bytes es nunca.
	if err := rc.Flush(); err != nil {
		httpx.Registro(r).Debug("no se pudo vaciar el flujo de eventos", "err", err)
		return false
	}
	return true
}

// registrarApagado cuelga el cierre del bus del `Shutdown` del servidor HTTP.
//
// EL PORQUÉ: `Shutdown` deja de aceptar conexiones nuevas y ESPERA a que terminen las que
// hay. Una conexión de eventos no termina nunca —para eso está—, así que sin esto el
// apagado se come el plazo entero (8 s) y acaba cortando a lo bruto; por el camino se
// pierden de verdad las peticiones normales que sí estaban a medias, que es justo lo que el
// apagado ordenado venía a evitar.
//
// El servidor se saca del contexto de la petición (`http.ServerContextKey`) y no de una
// variable del arranque a propósito: así esto funciona sin que `cmd/api` tenga que acordarse
// de nada. Lo que no se ve en el montaje no se puede olvidar al cambiarlo.
func registrarApagado(r *http.Request, bus *Difusor) {
	srv, _ := r.Context().Value(http.ServerContextKey).(*http.Server)
	if srv == nil {
		// Una prueba con el manejador pelado, o un montaje que no es un http.Server. No
		// hay apagado del que colgarse.
		return
	}
	bus.mu.Lock()
	defer bus.mu.Unlock()
	if _, ya := bus.enganchados[srv]; ya {
		return
	}
	bus.enganchados[srv] = struct{}{}
	srv.RegisterOnShutdown(bus.Cerrar)
}
