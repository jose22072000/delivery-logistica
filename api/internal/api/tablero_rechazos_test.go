package api

// LOS DOS RECHAZOS DEL TABLERO QUE NO SE PODÍAN ARREGLAR DESDE LA PANTALLA.
//
//  1. El 409 de armar la ruta MENTÍA y no tenía salida. Restaba las tarjetas puestas
//     menos los candidatos y le echaba la diferencia entera a «ya están en otra ruta»,
//     cuando la consulta descarta además `source <> 'pedido'` y los pedidos SIN
//     COORDENADAS. Con una tarjeta así contestaba, para siempre:
//     `409 {"error":"1 de los 2 pedidos ya están en otra ruta. Vuelve a elegirlos."}`
//     — motivo falso, tarjeta sin nombrar, y «vuelve a elegirlos» no arreglaba nada.
//
//  2. Un choque de posiciones al colocar contestaba 500. La única de
//     `(column_id, posicion)` es `DEFERRABLE INITIALLY DEFERRED` y salta en el COMMIT;
//     `colocarPedido` sólo traducía `pgx.ErrNoRows`, así que el 23505 salía como «Error
//     interno». El tablero sube en LOTES que se reintentan: un 500 corta el lote entero.

import (
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
)

// descartadoPorNombre busca en la respuesta el descarte de una tarjeta.
func descartadoPorNombre(t *testing.T, cuerpo map[string]any, cliente string) map[string]any {
	t.Helper()
	lista, _ := cuerpo["descartados"].([]any)
	for _, cruda := range lista {
		d, _ := cruda.(map[string]any)
		if d != nil && d["customerName"] == cliente {
			return d
		}
	}
	t.Fatalf("no se nombra la tarjeta de %q entre los descartados: %v", cliente, cuerpo["descartados"])
	return nil
}

// ---------------------------------------------------------------------------
// 1. Armar la ruta
// ---------------------------------------------------------------------------

// LA TARJETA SIN COORDENADAS NO BLOQUEA LA RUTA, SE NOMBRA.
//
// El mecanismo es real: `db/queries/orders.sql:718` hace `end_lat = excluded.end_lat` SIN
// `coalesce`, así que una bajada de PEDIDO puede dejar sin punto de entrega un pedido que
// ya estaba colocado en el tablero.
func TestUnaTarjetaSinCoordenadasSeNombraYLaRutaSaleIgual(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.capacidad = 1000
	// A Beto se le fueron las coordenadas en la última bajada.
	p := q.pedidos[ped2]
	p.lat, p.lng = 0, 0
	p.folio = "X-2992"
	q.pedidos[ped2] = p
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)

	if w.Code != http.StatusCreated {
		t.Fatalf("código %d, se esperaba 201: una tarjeta sin coordenadas no puede dejar "+
			"la zona entera sin poder salir — %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	if n, _ := m["paradas"].(float64); n != 2 {
		t.Fatalf("paradas %v, se esperaban 2: %s", m["paradas"], w.Body.String())
	}

	d := descartadoPorNombre(t, m, "Beto")
	if d["motivo"] != "sin coordenadas de entrega" {
		t.Errorf("el motivo es %q y tenía que decir que se quedó sin coordenadas.\n"+
			"Antes decía «ya están en otra ruta», que era FALSO: quien lo leía iba a "+
			"buscar una ruta que no existe.", d["motivo"])
	}
	if d["operationNumber"] != "X-2992" {
		t.Errorf("no se nombra el folio de la tarjeta: %v", d)
	}
	que, _ := d["queHacer"].(string)
	if !strings.Contains(que, "PEDIDO") {
		t.Errorf("no se dice qué hacer, y lo que hay que hacer es ponerle el punto de "+
			"entrega en PEDIDO: %q", que)
	}

	// Y LO QUE NO PUEDE VOLVER A SALIR NUNCA: el mensaje que no llevaba a ningún sitio.
	if strings.Contains(w.Body.String(), "Vuelve a elegirlos") {
		t.Errorf("sigue el «Vuelve a elegirlos», que es un rechazo permanente disfrazado "+
			"de reintento: %s", w.Body.String())
	}
	if strings.Contains(w.Body.String(), "ya están en otra ruta") {
		t.Errorf("sigue atribuyéndose todo a «otra ruta»: %s", w.Body.String())
	}
}

// Y LA QUE SÍ SE LLEVÓ OTRA RUTA se nombra con SU motivo, que es distinto y se arregla de
// otra manera. Juntar los dos en un número es lo que obligaba a abrir la zona a ver cuál
// era.
func TestLaTarjetaQueSeLlevoOtraRutaSeNombraConSuMotivo(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.capacidad = 1000
	// `pedRuta` ya tiene `route_id`: alguien la armó por otro lado con la tarjeta puesta.
	q.colocadas[pedRuta] = colocacion{colCentro, 4}
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)

	if w.Code != http.StatusCreated {
		t.Fatalf("código %d, se esperaba 201: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	if n, _ := m["paradas"].(float64); n != 3 {
		t.Fatalf("paradas %v, se esperaban 3: %s", m["paradas"], w.Body.String())
	}
	d := descartadoPorNombre(t, m, "Ya salió")
	if d["motivo"] != "ya va en otra ruta" {
		t.Errorf("motivo %q", d["motivo"])
	}
	if que, _ := d["queHacer"].(string); que == "" {
		t.Error("se dice cuál es, pero no qué hacer con ella")
	}
}

// Si NO QUEDA NINGUNA se sigue sin crear una ruta vacía — pero el 409 lleva los motivos
// dentro, que es lo que antes no llegaba nunca porque el otro 409 saltaba primero.
func TestSiTodasSeCayeronElConflictoLleVaLosMotivosDentro(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.capacidad = 1000
	for _, id := range []uuid.UUID{ped1, ped2, ped3} {
		p := q.pedidos[id]
		p.lat, p.lng = 0, 0 // las tres se quedaron sin punto de entrega
		q.pedidos[id] = p
	}
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)

	if w.Code != http.StatusConflict {
		t.Fatalf("código %d, se esperaba 409: %s", w.Code, w.Body.String())
	}
	m := leerTab(t, w)
	if m["error"] != msgColumnaSinNada {
		t.Fatalf("mensaje %q: %s", m["error"], w.Body.String())
	}
	desc, _ := m["descartados"].([]any)
	if len(desc) != 3 {
		t.Fatalf("el 409 tiene que decir por qué se cayó CADA una, y trae %d: %s",
			len(desc), w.Body.String())
	}
	if q.rutaCreada != nil {
		t.Fatal("se creó una ruta vacía")
	}
	if strings.Contains(w.Body.String(), "Vuelve a elegirlos") {
		t.Errorf("sigue el rechazo permanente disfrazado de reintento: %s", w.Body.String())
	}
}

// Una zona limpia no inventa descartes. Sin esto, «descartarlo todo» pasaría por arreglo.
func TestUnaZonaLimpiaNoTieneDescartados(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.capacidad = 1000
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if desc, _ := leerTab(t, w)["descartados"].([]any); len(desc) != 0 {
		t.Fatalf("se inventó descartes en una zona sin nada raro: %v", desc)
	}
}

// La carrera DE VERDAD —se lo llevan entre la validación y el enganche— sigue siendo un
// 409 que sí se arregla reintentando. Ése es el único sitio donde «vuelve a intentarlo»
// quiere decir algo.
func TestSiSeLoLlevanAMitadDeArmarSigueSiendoUn409Reintentable(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.capacidad = 1000
	q.seLoLlevan = ped2 // entre la validación y el `EngancharPedidoARuta`
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPost, "/api/board/columns/"+colCentro.String()+"/route",
		tokenTab(t, sucStg.String()), `{}`)

	if w.Code != http.StatusConflict {
		t.Fatalf("código %d, se esperaba 409: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "Vuelve a intentarlo") {
		t.Fatalf("aquí sí hay que reintentar, y no se dice: %s", w.Body.String())
	}
}

// ---------------------------------------------------------------------------
// 2. El choque de posiciones al colocar
// ---------------------------------------------------------------------------

// DOS APARATOS SOLTANDO TARJETA EN EL MISMO SITIO: 409 QUE SE REINTENTA, NO 500.
//
// La única es `DEFERRABLE INITIALLY DEFERRED`, así que el 23505 llega EN EL COMMIT —el
// doble lo devuelve desde `EnTx` justo por eso—. Con sólo `pgx.ErrNoRows` traducido, caía
// en `httpx.ErrorInterno` y salía «Error interno» con un 500. El tablero sube en lotes que
// se reintentan y un 500 corta el lote entero.
func TestElChoqueDePosicionAlColocarEs409YNo500(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.choqueAlCerrar = true
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPut, "/api/board/placements/"+ped1.String(),
		tokenTab(t, sucStg.String()), `{"columnaId":"`+colVista.String()+`","posicion":1}`)

	if w.Code == http.StatusInternalServerError {
		t.Fatalf("un choque de posiciones salió como 500: corta el lote entero de un "+
			"aparato que sube lo que hizo sin red — %s", w.Body.String())
	}
	if w.Code != http.StatusConflict {
		t.Fatalf("código %d, se esperaba 409: %s", w.Code, w.Body.String())
	}
	cuerpo := w.Body.String()
	if strings.Contains(cuerpo, "Error interno") || strings.Contains(cuerpo, "23505") {
		t.Fatalf("salió la jerga del motor: %s", cuerpo)
	}
	if !strings.Contains(cuerpo, "Vuelve a intentarlo") {
		t.Fatalf("no se dice que se reintente, que es lo único que hay que hacer: %s", cuerpo)
	}
}

// Y no se confunde con «ese pedido ya va en una ruta», que es el otro 409 de esta misma
// puerta y no se arregla reintentando.
func TestElChoqueDePosicionNoSeConfundeConElPedidoYaEnRuta(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	q.choqueAlCerrar = true
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPut, "/api/board/placements/"+ped1.String(),
		tokenTab(t, sucStg.String()), `{"columnaId":"`+colVista.String()+`","posicion":1}`)

	if strings.Contains(w.Body.String(), msgYaVaEnUnaRuta) {
		t.Fatalf("un choque de posiciones se contestó como si el pedido ya fuera en un "+
			"camión: %s", w.Body.String())
	}
}

// Comprobación de que el doble no miente: sin el choque, esa misma colocación va bien.
func TestSinChoqueLaMismaColocacionVaBien(t *testing.T) {
	q := nuevoTablero()
	q.tresPuestas()
	h := montarTab(t, q)

	w := pedirTab(t, h, http.MethodPut, "/api/board/placements/"+ped1.String(),
		tokenTab(t, sucStg.String()), `{"columnaId":"`+colVista.String()+`","posicion":1}`)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if q.colocadas[ped1] != (colocacion{colVista, 1}) {
		t.Fatalf("ped1 quedó en %+v", q.colocadas[ped1])
	}
}
