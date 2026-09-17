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
	// EL TABLERO. Es el que más falta hacía y el que no estaba: es la pantalla que dos
	// personas miran a la vez —una arma zonas en el teléfono y otra las ve desde el
	// navegador— y la única donde el trabajo de uno aparece encima del del otro.
	CambioTablero = "tablero"
)

// FrenoAvisos: como mucho UN aviso cada quince segundos por tipo.
//
// POR QUÉ: el espejo importa por lotes de doscientos y avisaba por cada lote — veinte
// avisos seguidos y la pantalla recargándose veinte veces. Lo que pasa en ese rato viaja
// en el siguiente aviso, así que no se pierde nada: se pierde el parpadeo.
//
// ## Y POR ESO HAY FLANCO DE BAJADA — 17/09/2026
//
// «Lo que pasa en ese rato viaja en el siguiente aviso» era cierto para el espejo, que
// siempre tiene un lote detrás. **Para un gesto humano es falso**: doce tarjetas
// arrastradas en doce segundos mandaban UN aviso —el de la primera, o sea el momento en
// que menos hay que contar— y las once siguientes se descartaban sin dejar rastro. La otra
// pantalla refrescaba tras la tarjeta 1 y se quedaba once atrás hasta el temporizador: dos
// minutos en la web, cinco en la APK. La queja que esto venía a arreglar, arreglada a un
// doceavo.
//
// Ahora lo que llega dentro del freno **se anota como pendiente** y sale solo al vencer.
// Se sigue mandando un aviso cada quince segundos como mucho —que es lo que evita el
// parpadeo— pero el último cambio siempre llega.
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
	// pendiente: lo que llegó DENTRO del freno y todavía no ha salido. Es el flanco de
	// bajada; sin esto, lo que pasa en esos quince segundos no se dice nunca.
	pendiente map[string]Cambio
	cerrado   bool
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
		pendiente:   map[string]Cambio{},
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
// ## El tablero no avisaba, y es la pantalla que más falta hacía — 17/09/2026
//
// Publicaban dos: `CambioRutas` desde el armador y `CambioPedidos` desde el lote del espejo.
// Del tablero, nada — y es justamente la pantalla que dos personas miran a la vez: una arma
// zonas en el teléfono y otra las ve desde el navegador.
//
// Lo que se notaba: una zona creada en el móvil no aparecía en la web hasta que pasaba el
// temporizador —dos minutos— o alguien refrescaba a mano. Jose, 16/09/2026: «hice un tablero
// en el móvil, moví cosas, y en la web no salió en tiempo real, ¿por qué razón si eso debe
// pasar?».
//
// ## AQUÍ HABÍA UN COMENTARIO QUE MENTÍA — corregido el 17/09/2026
//
// Decía que `CambioCatalogo` y `CambioClientes` podían quedarse sin publicar porque «ésos
// cambian cuando el espejo importa, que ya avisa por `CambioPedidos`». **Ya no es verdad**,
// y la parte de catálogo no lo fue nunca: el catálogo se toca a mano desde Productos
// (`PATCH`/`DELETE /api/products`) y se trae aparte con `POST /api/products/sync`, sin que
// eso escriba un solo pedido. Un aviso de `pedidos` no invalida el catálogo de nadie.
//
// Jose, 17/09/2026: «¿y por qué probamos con tableros solamente? Son todas, porque todos
// deben ser en tiempo real como el tablero cuando las cosas tienen conexión».
//
// Así que ahora avisan TODAS las puertas que escriben algo que una pantalla enseña:
// pedidos, catálogo, vehículos (con sus tipos), almacenes, sucursales y ajustes, cada una
// con SU tipo. El tipo importa: quien lo recibe vuelve a pedir lo suyo, y mandar
// `pedidos` por un cambio de camión es hacer que ocho navegadores se bajen la lista de
// pedidos entera por nada, con la conexión de allá.
//
// **`CambioClientes` sigue sin tener quien lo publique, y no es un olvido**: en esta API
// NO HAY ninguna puerta que escriba `customers`. El único que los escribe es el proceso
// del espejo (`cmd/espejo`, `internal/espejo/ciclo.go`, `clientes()`), que va contra
// Postgres directamente y **corre en otro proceso** — y este bus vive en la memoria de
// éste (ver arriba). Desde allí no hay forma de publicar sin volver a un bus de verdad o
// sin abrirle una puerta al espejo. Queda dicho aquí, y la constante se deja declarada
// porque el cliente ya sabe leerla el día que haya quien la mande.
//
// Se enganchan aquí, en el fichero del bus, y no en cada manejador: quien escribe una zona
// —o un camión— no tiene por qué saber cómo se reparten los avisos, y el día que esto
// vuelva a ser Redis no hay que tocar ni el tablero ni los demás.
func init() {
	avisarCambioDeRutas = func(_ context.Context) { busEventos.Avisar(CambioRutas, nil) }
	avisarCambioDelTablero = func(_ context.Context) { busEventos.Avisar(CambioTablero, nil) }
	avisarCambioDePedidos = func(_ context.Context) { busEventos.Avisar(CambioPedidos, nil) }
	avisarCambioDelCatalogo = func(_ context.Context) { busEventos.Avisar(CambioCatalogo, nil) }
	avisarCambioDeVehiculos = func(_ context.Context) { busEventos.Avisar(CambioVehiculos, nil) }
	avisarCambioDeAlmacenes = func(_ context.Context) { busEventos.Avisar(CambioAlmacenes, nil) }
	avisarCambioDeSucursales = func(_ context.Context) { busEventos.Avisar(CambioSucursales, nil) }
	avisarCambioDeAjustes = func(_ context.Context) { busEventos.Avisar(CambioAjustes, nil) }
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
	c := Cambio{Tipo: tipo, Cuando: ahora, Detalle: detalle}

	if visto, hay := d.ultimo[tipo]; hay && ahora.Sub(visto) < d.freno {
		// DENTRO DEL FRENO: no sale ahora, pero **se guarda**. Sale solo al vencer, con
		// `soltarPendientes`. Antes se descartaba, y de doce gestos seguidos llegaba uno
		// —el primero— y once se perdían para siempre.
		//
		// Se queda el ÚLTIMO: es el que describe cómo está el tablero ahora, y quien lo
		// reciba va a pedir la lista entera de todos modos.
		d.pendiente[tipo] = c
		return false
	}
	d.ultimo[tipo] = ahora
	delete(d.pendiente, tipo)

	d.repartir(c)
	return true
}

// repartir manda el cambio a todos los abonados. Con el candado ya cogido.
func (d *Difusor) repartir(c Cambio) {
	for ch := range d.abonados {
		select {
		case ch <- c:
		default:
			// Abonado lleno: se le pierde este aviso. Es lo correcto —el siguiente le
			// dirá lo mismo— y desde luego mejor que dejar la escritura de un pedido
			// esperando a que un navegador se despierte.
		}
	}
}

// SoltarPendientes manda lo que se quedó dentro del freno y ya venció.
//
// Lo llama el latido de cada conexión abierta (`eventos.go`, el `ticker`), que es lo único
// que corre solo en este servicio: montar un temporizador propio sería un hilo más vivo
// para algo que ya tiene quien lo despierte cada veinte segundos.
//
// Y por eso el retraso máximo de un aviso es el freno más un latido. Sigue siendo dos
// órdenes de magnitud menos que los dos minutos del temporizador de la pantalla.
func (d *Difusor) SoltarPendientes() {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.cerrado || len(d.pendiente) == 0 {
		return
	}
	ahora := d.ahora()
	for tipo, c := range d.pendiente {
		if visto, hay := d.ultimo[tipo]; hay && ahora.Sub(visto) < d.freno {
			continue
		}
		d.ultimo[tipo] = ahora
		delete(d.pendiente, tipo)
		d.repartir(c)
	}
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
			// LO QUE SE QUEDÓ DENTRO DEL FRENO y ya venció. Va aquí y no en un
			// temporizador propio: este latido ya corre por cada conexión abierta, y
			// montar otro hilo para algo que ya tiene quien lo despierte es hilo de más.
			//
			// Sin esto, doce gestos en doce segundos mandaban UNO —el primero— y los once
			// siguientes no se decían nunca: la otra pantalla se quedaba once tarjetas
			// atrás hasta el temporizador.
			bus.SoltarPendientes()

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

// ---------------------------------------------------------------------------
// Los tipos que faltaban — 17/09/2026
// ---------------------------------------------------------------------------
//
// Van al final del fichero y no en el bloque de arriba a propósito: ese bloque lo está
// leyendo más gente, y añadir aquí no mueve ni una línea de lo que ya hay. Añadir NO rompe
// nada —un tipo que la pantalla no espera se recibe y se ignora—; renombrar sí.
//
// Cada uno está porque hay UNA PANTALLA que lo enseña y que hoy no se entera de nada hasta
// que pasa el temporizador (dos minutos en la web, cinco en la APK):
//
//   - `vehiculos`  → la pantalla de Vehículos, que pide `GET /api/vehicles` y
//     `GET /api/vehicle-types` a la red y **no vive de la base**: el ciclo de
//     sincronización no la repinta, así que sin este aviso no hay nada que la repinte.
//   - `almacenes`  → la pantalla de Almacenes, igual: `GET /api/almacenes` a la red, y los
//     almacenes ni siquiera viajan en `GET /api/sync/cambios` (van en `faltan`).
//   - `sucursales` → el selector de sucursal de la barra y el de Rutas. Ésos sí salen de la
//     base, pero una sucursal recién creada no aparece hasta el siguiente ciclo.
//   - `ajustes`    → la tasa y la moneda. Con ellas se convierte TODO importe que se pinta;
//     una tasa vieja es un número creíble y equivocado, que es lo peor que le puede pasar a
//     algo que alguien va a cobrar.
//
// NO se añadió un tipo para los orígenes (`/api/origins`): ninguna pantalla de la
// aplicación los pide. Queda dicho para que nadie lo lea como un olvido.
const (
	CambioVehiculos  = "vehiculos"
	CambioAlmacenes  = "almacenes"
	CambioSucursales = "sucursales"
	CambioAjustes    = "ajustes"
)
