package reparto

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/sincro"
)

// LA DIRECCIÓN A LA QUE SE REENVÍA UN APUNTE, que es lo que tiró el día entero.
//
// El aparato encola la ruta SIN prefijo —`/board/columns`— porque es la que usa contra su
// propia base. `reparto-api` las sirve todas bajo `/api`. Reenviarlas tal cual daba 404 en
// cada apunte, y un 4xx aquí es «rechazo de negocio»: acababan en la bandeja como si el
// reparto hubiera dicho que no.
//
// Y lo peor era el efecto dominó: el apunte rechazado era el que CREA la zona del tablero,
// así que los cinco que colocaban pedidos dentro se caían detrás con «el identificador
// provisional todavía no corresponde a nada». Seis apuntes de trabajo real, perdidos por
// una barra, el 16/09/2026.
//
// Este paquete no tenía NI UNA prueba. Por eso sobrevivió.
func TestElApunteSeReenviaBajoApi(t *testing.T) {
	var vistas []string
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			// La ruta ENTERA, con su query: si se perdiera el `branchId` el reparto no
			// sabría de qué sucursal es la zona.
			vistas = append(vistas, r.URL.RequestURI())
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"id":"` + uuid.NewString() + `"}`))
		}))
	defer servidor.Close()

	c := Nuevo(servidor.URL, "clave-de-prueba", 5*time.Second)

	casos := []struct {
		ruta     string
		esperada string
	}{
		{"/board/columns?branchId=abc", "/api/board/columns?branchId=abc"},
		{"/board/placements/p-1", "/api/board/placements/p-1"},
		{"/routes/r-1/results", "/api/routes/r-1/results"},
	}
	for _, caso := range casos {
		vistas = nil
		_, err := c.Aplicar(context.Background(), sincro.Peticion{
			Metodo:   http.MethodPost,
			Ruta:     caso.ruta,
			Cuerpo:   json.RawMessage(`{"nombre":"Vista"}`),
			Hecho:    time.Now(),
			Sucursal: uuid.New(),
			Persona:  "quien-sea",
			Clave:    "k",
		})
		if err != nil {
			t.Fatalf("%s: no tenía que fallar: %v", caso.ruta, err)
		}
		if len(vistas) != 1 || vistas[0] != caso.esperada {
			t.Errorf("se llamó a %v, se esperaba %q — sin el `/api` el reparto contesta "+
				"404 y el apunte acaba en la bandeja de rechazos", vistas, caso.esperada)
		}
	}
}

// Y el `/api` se pone UNA sola vez: si `REPARTO_URL` ya lo trajera, `/api/api/...` sería
// el mismo fallo por el otro lado. Es exactamente lo que le pasó al Tablero en la web.
func TestNoSeDuplicaElApi(t *testing.T) {
	var vista string
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			vista = r.URL.Path
			_, _ = w.Write([]byte(`{}`))
		}))
	defer servidor.Close()

	_, err := Nuevo(servidor.URL, "k", 5*time.Second).Aplicar(
		context.Background(), sincro.Peticion{
			Metodo: http.MethodPost, Ruta: "/board/columns",
			Hecho: time.Now(), Sucursal: uuid.New(), Persona: "x", Clave: "k",
		})
	if err != nil {
		t.Fatalf("no tenía que fallar: %v", err)
	}
	if vista != "/api/board/columns" {
		t.Errorf("ruta = %q, se esperaba /api/board/columns", vista)
	}
}

// UN 404 DE PUERTA EQUIVOCADA NO ES UN RECHAZO, y la diferencia se paga cara.
//
// El reparto contesta sus «no encontrado» con un JSON suyo. Un 404 con otra cosa dentro
// —el `404 page not found` del enrutador de Go— dice que se llamó a una puerta que no
// existe: un fallo de despliegue. Tratarlo como rechazo deja el apunte muerto en la
// bandeja pidiendo que una persona decida sobre algo que ninguna persona puede arreglar,
// y arrastra a todos los que dependían de lo que iba a crear.
func Test404DeRutaEsCaidaYNoRechazo(t *testing.T) {
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			// Exactamente lo que escribe el enrutador de Go.
			http.NotFound(w, r)
		}))
	defer servidor.Close()

	_, err := Nuevo(servidor.URL, "k", 5*time.Second).Aplicar(
		context.Background(), sincro.Peticion{
			Metodo: http.MethodPost, Ruta: "/board/columns",
			Hecho: time.Now(), Sucursal: uuid.New(), Persona: "x", Clave: "k",
		})
	if err == nil {
		t.Fatal("tenía que fallar")
	}
	var rechazo *sincro.Rechazo
	if errors.As(err, &rechazo) {
		t.Fatalf("un 404 de ruta NO puede ser un rechazo: se queda muerto en la bandeja "+
			"y arrastra a los que dependen de él. Salió: %v", err)
	}
}

// Y un 404 QUE SÍ VIENE DEL REPARTO sigue siendo un rechazo: «ese pedido ya no está» es
// una respuesta de negocio y la tiene que mirar una persona.
func Test404DelRepartoSigueSiendoRechazo(t *testing.T) {
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"error":"Ese pedido ya no existe"}`))
		}))
	defer servidor.Close()

	_, err := Nuevo(servidor.URL, "k", 5*time.Second).Aplicar(
		context.Background(), sincro.Peticion{
			Metodo: http.MethodPut, Ruta: "/board/placements/p-1",
			Hecho: time.Now(), Sucursal: uuid.New(), Persona: "x", Clave: "k",
		})
	var rechazo *sincro.Rechazo
	if !errors.As(err, &rechazo) {
		t.Fatalf("tenía que ser un rechazo con su motivo: %v", err)
	}
	if rechazo.Motivo != "Ese pedido ya no existe" {
		t.Errorf("motivo = %q: se enseña LITERAL lo que dijo el reparto", rechazo.Motivo)
	}
}

// EL APUNTE VIAJA FIRMADO POR LA PERSONA QUE LO HIZO, no por este servicio.
//
// Segundo acto del mismo día. Con el `/api` ya puesto, la zona creada desde la web seguía
// sin llegar: `reparto-api` registraba **401 «no viene token» en POST /api/board/columns**.
// Este servicio reenviaba con la clave de servicio más `X-Persona` y `X-Sucursal`, y ahí
// había dos agujeros: el reparto **no lee esas dos cabeceras** —las ponía éste y no las
// miraba nadie— y las rutas del aparato exigen sesión de persona, que la clave no abre.
//
// Resultado: el apunte que crea la zona se quedaba en la cola para siempre. Es lo que dejó
// la zona «Vista» dentro de un teléfono, con sus cinco pedidos colocados, sin que la viera
// nadie más. Comprobado contra producción el 16/09/2026: `board_columns` estaba a 0.
func TestElApunteViajaConElTokenDeLaPersona(t *testing.T) {
	var autorizacion, clave string
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			autorizacion = r.Header.Get("Authorization")
			clave = r.Header.Get("x-api-key")
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"id":"` + uuid.NewString() + `"}`))
		}))
	defer servidor.Close()

	c := Nuevo(servidor.URL, "clave-de-prueba", 5*time.Second)
	_, err := c.Aplicar(context.Background(), sincro.Peticion{
		Metodo:   http.MethodPost,
		Ruta:     "/board/columns?branchId=abc",
		Cuerpo:   json.RawMessage(`{"nombre":"Vista"}`),
		Hecho:    time.Now(),
		Sucursal: uuid.New(),
		Persona:  "u-1",
		Clave:    "k",
		Token:    "el.token.de.la.persona",
	})
	if err != nil {
		t.Fatalf("no tenía que fallar: %v", err)
	}

	if autorizacion != "Bearer el.token.de.la.persona" {
		t.Errorf("se reenvió con Authorization %q: sin el token de la persona, "+
			"/api/board/columns contesta 401 «no viene token» y el apunte se queda en la "+
			"cola para siempre", autorizacion)
	}
	// Y la clave de servicio SE QUITA. En el reparto hay rutas que, al ver `x-api-key`,
	// se cuelgan un Super Admin sin sucursal: correcto para su temporizador, inaceptable
	// para el trabajo de una persona. Mandar las dos sería dejar que un apunte de
	// Camagüey se ejecutara con permiso sobre las ocho.
	if clave != "" {
		t.Errorf("se reenvió además la clave de servicio (%q): un apunte de una persona "+
			"no puede llevar con qué convertirse en Super Admin", clave)
	}
}

// Sin token —el modo viejo de `SYNC_IDENTIDAD=cabeceras`, donde la identidad viene de una
// cabecera y no hay token que reenviar— se sigue mandando la clave. Es lo único que queda
// ahí, y quitarla dejaría ese modo sin ninguna credencial.
func TestSinTokenSeSigueMandandoLaClave(t *testing.T) {
	var autorizacion, clave string
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			autorizacion = r.Header.Get("Authorization")
			clave = r.Header.Get("x-api-key")
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{}`))
		}))
	defer servidor.Close()

	c := Nuevo(servidor.URL, "clave-de-prueba", 5*time.Second)
	if _, err := c.Aplicar(context.Background(), sincro.Peticion{
		Metodo: http.MethodPost, Ruta: "/board/columns", Hecho: time.Now(),
		Sucursal: uuid.New(), Persona: "u-1", Clave: "k",
	}); err != nil {
		t.Fatalf("no tenía que fallar: %v", err)
	}
	if clave != "clave-de-prueba" {
		t.Errorf("sin token hay que mandar la clave, y se mandó %q", clave)
	}
	if autorizacion != "" {
		t.Errorf("sin token no se inventa un Authorization: %q", autorizacion)
	}
}

// UN 401 ES CAÍDA, NO RECHAZO. Y un 403 sí es rechazo.
//
// Tercer acto del 16/09/2026, y el que explica por qué los dos arreglos anteriores no
// rescataron nada por sí solos. `POST /api/board/columns` contestaba 401; este servicio
// metía todo 4xx en el mismo saco («el reparto dijo que no»), así que el apunte que CREA
// la zona se marcó RECHAZADO y detrás se cayeron los cinco que colocaban pedidos dentro.
// Seis apuntes de trabajo real esperando a que «una persona decida» sobre una credencial
// que no viajó — que es algo que ninguna persona delante de un teléfono puede decidir.
//
// Y un rechazo no se reintenta solo: arreglado el reenvío del token, los seis SEGUÍAN
// muertos en la bandeja. El segundo fallo tapaba al primero.
//
// La línea es si el reparto entendió QUIÉN preguntaba. Con 401 no lo sabía: es nuestro y
// se reintenta. Con 403 sí lo sabía y dijo que no puede: eso lo decide una persona, y
// reintentarlo para siempre sería un bucle.
func TestUn401EsCaidaYUn403EsRechazo(t *testing.T) {
	var codigo int
	servidor := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(codigo)
			_, _ = w.Write([]byte(`{"error":"Unauthorized"}`))
		}))
	defer servidor.Close()

	c := Nuevo(servidor.URL, "clave-de-prueba", 5*time.Second)
	aplicar := func() error {
		_, err := c.Aplicar(context.Background(), sincro.Peticion{
			Metodo: http.MethodPost, Ruta: "/board/columns", Hecho: time.Now(),
			Sucursal: uuid.New(), Persona: "u-1", Clave: "k", Token: "t",
		})
		return err
	}

	codigo = http.StatusUnauthorized
	err := aplicar()
	var rechazo *sincro.Rechazo
	if errors.As(err, &rechazo) {
		t.Errorf("un 401 se trató como rechazo (%q): el apunte se queda muerto en la "+
			"bandeja pidiendo que alguien decida sobre una credencial que no viajó, y "+
			"detrás se caen todos los que dependen de lo que iba a crear",
			rechazo.Motivo)
	}
	if err == nil {
		t.Error("un 401 tampoco es un éxito: el apunte no se escribió")
	}

	codigo = http.StatusForbidden
	if err := aplicar(); !errors.As(err, &rechazo) {
		t.Errorf("un 403 SÍ es rechazo —el reparto supo quién preguntaba y dijo que no—, "+
			"y salió %v: reintentarlo para siempre es un bucle", err)
	}
}
