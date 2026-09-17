package api

// LA MITAD IZQUIERDA SE PUEDE PAGINAR ENTERA.
//
// `TopeSinColocar` son 200, `limite` sólo podía BAJAR, y la consulta terminaba en `LIMIT`
// sin `OFFSET`, sin cursor y sin `desde_km`. Medido en producción el 17/09/2026, La Habana
// tenía 300 pedidos sin colocar: el logístico veía los 200 más cercanos y LOS 100 MÁS
// LEJANOS NO SE PODÍAN PEDIR DE NINGUNA MANERA. `Truncated` avisaba y no llevaba a ningún
// sitio.
//
// Es el §3 del CLAUDE.md —pedir un tope y no comprobar el resultado— y el fallo que más
// caro sale en este proyecto, porque no se ve: la pantalla se queda perfectamente normal.
//
// Estas pruebas recorren la lista ENTERA a tandas pequeñas y comprueban las tres cosas que
// tienen que cumplirse a la vez: que se llega al último, que no se repite ninguno, y que
// no se salta ninguno.

import (
	"fmt"
	"net/http"
	"net/url"
	"testing"
	"time"

	"github.com/google/uuid"
)

// sembrar deja `n` pedidos sin colocar en Santiago, cada uno un poco más lejos del almacén
// que el anterior. El tablero de base ya trae tres (Ana, Beto y Ana otra vez).
func sembrar(q *tableroFalso, n int) {
	ayer := time.Date(2026, 9, 16, 10, 0, 0, 0, time.UTC)
	for i := 0; i < n; i++ {
		id := uuid.MustParse(fmt.Sprintf("5e000000-0000-0000-0000-%012d", i+1))
		f := ayer
		q.pedidos[id] = pedidoFalso{
			id: id, sucursal: sucStg, nombre: fmt.Sprintf("Cliente %02d", i+1),
			peso: 1, lat: 20.0247 + float64(i+1)*0.01, lng: -75.8219, fecha: &f,
		}
	}
}

// recorrerLaLista pide tanda tras tanda siguiendo el cursor y devuelve los ids en el orden
// en que salieron, más el total de la primera tanda.
//
// Con un tope de vueltas: si el cursor no avanza —el fallo clásico de un desempate mal
// hecho— esto se quedaría dando vueltas para siempre en vez de fallar, y una prueba
// colgada no dice nada.
func recorrerLaLista(t *testing.T, h http.Handler, jwt string, limite int) ([]string, float64) {
	t.Helper()
	var ids []string
	var total float64
	desde := ""
	for vuelta := 0; ; vuelta++ {
		if vuelta > 50 {
			t.Fatalf("el cursor no avanza: 50 vueltas y todavía queda.\n"+
				"Salieron %d filas y las tres primeras son %v — si se repiten, el "+
				"«desde» no está llegando a la consulta y cada tanda devuelve la misma.",
				len(ids), ids[:min(3, len(ids))])
		}
		ruta := fmt.Sprintf("/api/board/unplaced?limite=%d", limite)
		if desde != "" {
			ruta += "&desde=" + url.QueryEscape(desde)
		}
		w := pedirTab(t, h, http.MethodGet, ruta, jwt, "")
		if w.Code != http.StatusOK {
			t.Fatalf("vuelta %d: código %d — %s", vuelta, w.Code, w.Body.String())
		}
		m := leerTab(t, w)
		if vuelta == 0 {
			total, _ = m["total"].(float64)
		}
		for _, cruda := range m["pedidos"].([]any) {
			ids = append(ids, cruda.(map[string]any)["id"].(string))
		}
		truncado, _ := m["truncated"].(bool)
		siguiente, hay := m["siguiente"].(string)
		if !truncado {
			if hay && siguiente != "" {
				t.Fatalf("vuelta %d: dice que no hay más y manda cursor igual: %q", vuelta, siguiente)
			}
			return ids, total
		}
		if !hay || siguiente == "" {
			t.Fatalf("vuelta %d: dice que hay más tandas y NO manda por dónde seguir. "+
				"Eso es exactamente el fallo que se está arreglando: un aviso de "+
				"truncado que no lleva a ningún sitio — %s", vuelta, w.Body.String())
		}
		desde = siguiente
	}
}

// LA PRUEBA QUE IMPORTA: se llega hasta el último, sin repetidos y sin saltos.
func TestSePuedePedirLaListaEnteraATandas(t *testing.T) {
	q := nuevoTablero()
	sembrar(q, 9) // 9 + los 3 de siempre = 12 sin colocar
	h := montarTab(t, q)

	ids, total := recorrerLaLista(t, h, tokenTab(t, sucStg.String()), 2)

	if total != 12 {
		t.Fatalf("el total dice %v y sin colocar hay 12", total)
	}
	if len(ids) != 12 {
		t.Fatalf("paginando entero salieron %d pedidos de los 12 que hay.\n"+
			"Los que faltan son los MÁS LEJANOS, y son justo los que no se podían pedir "+
			"de ninguna manera: %v", len(ids), ids)
	}
	vistos := map[string]bool{}
	for _, id := range ids {
		if vistos[id] {
			t.Fatalf("el pedido %s salió dos veces: el cursor se está quedando corto en "+
				"el desempate y repite la última fila de cada tanda", id)
		}
		vistos[id] = true
	}
}

// Con tanda de UNO se aprieta el desempate al máximo: cada corte cae entre dos filas.
func TestPaginarDeUnoEnUnoTampocoSeSaltaNingunPedido(t *testing.T) {
	q := nuevoTablero()
	sembrar(q, 5)
	h := montarTab(t, q)

	ids, total := recorrerLaLista(t, h, tokenTab(t, sucStg.String()), 1)
	if int(total) != len(ids) {
		t.Fatalf("el total dice %v y paginando de uno en uno salieron %d: %v",
			total, len(ids), ids)
	}
}

// DOS PEDIDOS A LA MISMA DISTANCIA ES EL CASO QUE ROMPE UN CURSOR MAL HECHO.
//
// Dos clientes del mismo edificio dan exactamente los mismos kilómetros. Un cursor que
// sólo mirara los km o se quedaría pegado —devolviendo siempre los mismos— o se saltaría
// al vecino. Por eso la terna es la del `ORDER BY` entera, con la fecha y el id dentro.
func TestDosPedidosALaMismaDistanciaNoSePierdenAlPaginar(t *testing.T) {
	q := nuevoTablero()
	// Tres en el mismo edificio: dos con fechas distintas y uno SIN fecha, que va al
	// final del desempate (`DESC NULLS LAST`) y es donde más fácil se cuela un salto.
	viejo := time.Date(2026, 9, 10, 8, 0, 0, 0, time.UTC)
	nuevoDia := time.Date(2026, 9, 15, 8, 0, 0, 0, time.UTC)
	mismoEdificio := []struct {
		id    string
		fecha *time.Time
	}{
		{"6e000000-0000-0000-0000-000000000001", &viejo},
		{"6e000000-0000-0000-0000-000000000002", &nuevoDia},
		{"6e000000-0000-0000-0000-000000000003", nil},
	}
	for i, m := range mismoEdificio {
		id := uuid.MustParse(m.id)
		q.pedidos[id] = pedidoFalso{
			id: id, sucursal: sucStg, nombre: fmt.Sprintf("Vecino %d", i+1),
			peso: 1, lat: 20.0447, lng: -75.8219, fecha: m.fecha,
		}
	}
	h := montarTab(t, q)

	ids, total := recorrerLaLista(t, h, tokenTab(t, sucStg.String()), 1)
	if int(total) != len(ids) {
		t.Fatalf("total %v, salieron %d: %v", total, len(ids), ids)
	}
	for _, m := range mismoEdificio {
		hay := false
		for _, id := range ids {
			if id == m.id {
				hay = true
			}
		}
		if !hay {
			t.Fatalf("el vecino %s no salió en ninguna tanda: el desempate del cursor se "+
				"lo saltó — %v", m.id, ids)
		}
	}
}

// EL TOTAL ES EL TOTAL Y NO BAJA AL PAGINAR. Es el número de «Sin colocar (300)»: si
// bajara a 100 porque alguien arrastró el dedo, sería un número creíble y equivocado, que
// es lo peor que le puede pasar a un número en esta casa.
func TestElTotalNoBajaAlPedirLaTandaSiguiente(t *testing.T) {
	q := nuevoTablero()
	sembrar(q, 9)
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	primera := leerTab(t, pedirTab(t, h, http.MethodGet, "/api/board/unplaced?limite=2", jwt, ""))
	cursor, _ := primera["siguiente"].(string)
	if cursor == "" {
		t.Fatalf("sin cursor no hay tanda siguiente: %v", primera)
	}
	segunda := leerTab(t, pedirTab(t, h, http.MethodGet,
		"/api/board/unplaced?limite=2&desde="+url.QueryEscape(cursor), jwt, ""))

	if primera["total"] != segunda["total"] {
		t.Fatalf("el total cambió de %v a %v al pasar de tanda: el número de arriba es el "+
			"TOTAL, no lo que queda", primera["total"], segunda["total"])
	}
	if n, _ := segunda["count"].(float64); n != 2 {
		t.Fatalf("la segunda tanda trae %v pedidos y se pidieron 2", segunda["count"])
	}
}

// LA ÚLTIMA TANDA DICE QUE ES LA ÚLTIMA. Antes `truncated` se calculaba restando del
// total, así que en cuanto se paginaba salía `true` para siempre y la pantalla no tenía
// manera de saber cuándo parar.
func TestLaUltimaTandaNoDiceQueHayMas(t *testing.T) {
	q := nuevoTablero() // tres sin colocar
	h := montarTab(t, q)

	m := leerTab(t, pedirTab(t, h, http.MethodGet, "/api/board/unplaced?limite=3",
		tokenTab(t, sucStg.String()), ""))

	if truncado, _ := m["truncated"].(bool); truncado {
		t.Fatalf("caben los tres en la tanda y dice que hay más: %v", m)
	}
	if s, hay := m["siguiente"]; hay && s != nil {
		t.Fatalf("no hay más y manda cursor igual: %v", s)
	}
}

// UN CURSOR QUE NO SE ENTIENDE ES UN 400, NO UNA LISTA VACÍA.
//
// En la base, un cursor a medias deja la comparación en NULL y la consulta devuelve CERO
// filas con un 200 limpio. Eso se lee como «ya no queda nada» justo cuando quedan cien, y
// no deja ni una traza. «Una respuesta vacía no es una respuesta buena.»
func TestUnCursorRotoEs400YNoUnaListaVacia(t *testing.T) {
	q := nuevoTablero()
	sembrar(q, 5)
	h := montarTab(t, q)
	jwt := tokenTab(t, sucStg.String())

	for _, malo := range []string{
		"cualquier-cosa",
		"12.5|",
		"|2026-09-16T10:00:00Z|6e000000-0000-0000-0000-000000000001",
		"12.5|no-es-una-fecha|6e000000-0000-0000-0000-000000000001",
		"12.5|2026-09-16T10:00:00Z|no-es-un-uuid",
	} {
		w := pedirTab(t, h, http.MethodGet,
			"/api/board/unplaced?desde="+url.QueryEscape(malo), jwt, "")
		if w.Code != http.StatusBadRequest {
			t.Errorf("cursor %q: código %d, se esperaba 400 — %s", malo, w.Code, w.Body.String())
			continue
		}
		if m := leerTab(t, w); m["error"] == "" {
			t.Errorf("cursor %q: 400 sin decir qué hacer", malo)
		}
	}
}

// Y el cursor no amplía el alcance: sigue saliendo de quién pregunta. Un cursor es una
// posición en la lista propia, no una llave.
func TestElCursorNoSacaPedidosDeOtraSucursal(t *testing.T) {
	q := nuevoTablero()
	sembrar(q, 5)
	h := montarTab(t, q)

	ids, _ := recorrerLaLista(t, h, tokenTab(t, sucStg.String()), 2)
	for _, id := range ids {
		if id == pedHol.String() {
			t.Fatal("paginando apareció el pedido de Holguín")
		}
	}
}
