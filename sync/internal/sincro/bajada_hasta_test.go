package sincro

// LA MARCA QUE SE ANOTA ES LA QUE DIJO EL REPARTO, NO LA QUE SE MANDÓ.
//
// Este servicio propone una ventana y el reparto la sirve hasta donde le cabe. Cuando no le
// cabe entera lo dice con `truncado` y devuelve la marca de la ÚLTIMA FILA SERVIDA. Hasta
// el 21/09/2026 aquí se decodificaban sólo `cambios` y `truncado` y se anotaba el reloj
// propio, cortada o no: lo que va de la última fila servida al reloj quedaba por debajo del
// próximo `desde` y **no lo volvía a pedir nadie nunca más**. Sin error, sin aviso y sin una
// línea en ningún registro (`CLAUDE.md` §3).
//
// Estas pruebas encadenan tandas con MÁS FILAS QUE EL TOPE, que es lo único que enseña el
// fallo: con pocos datos la primera tanda cabe entera y todo sale verde.

import (
	"encoding/json"
	"fmt"
	"net/http"
	"testing"
	"time"
)

// repartoPorTandas es un reparto de mentira que sirve `filas` ordenadas por su marca,
// `tope` cada vez, y contesta como contesta el de verdad: con `truncado` y con la marca de
// la última fila servida.
type repartoPorTandas struct {
	marcas []time.Time // una por fila, en orden y todas distintas
	tope   int
	techo  time.Time
}

func (f *repartoPorTandas) responder(v Ventana) Bajada {
	servidas := []time.Time{}
	for _, m := range f.marcas {
		if v.Desde != nil && !m.After(*v.Desde) {
			continue
		}
		if m.After(v.Hasta) {
			continue
		}
		servidas = append(servidas, m)
	}
	truncado := len(servidas) > f.tope
	if truncado {
		servidas = servidas[:f.tope]
	}
	puestos := []json.RawMessage{}
	for _, m := range servidas {
		puestos = append(puestos, json.RawMessage(
			fmt.Sprintf(`{"id":%q}`, m.Format(time.RFC3339Nano))))
	}
	// LA MARCA DE LA ÚLTIMA FILA SERVIDA. Sin truncar, el techo de la ventana.
	hasta := f.techo
	if truncado && len(servidas) > 0 {
		hasta = servidas[len(servidas)-1]
	}
	return Bajada{
		Cambios:  Cambios{"customers": {Puestos: puestos}},
		Hasta:    hasta,
		Truncado: truncado,
	}
}

// LA PRUEBA QUE CIERRA EL AGUJERO: doce clientes, tope de cinco, encadenando de verdad.
//
// El aparato NO manda `desde`: lo coge de lo que este servicio le anotó la vez anterior
// (`desdeDeVerdad`). Así que si aquí se anota el reloj en vez de lo servido, la segunda
// vuelta pide «a partir de ahora» y los siete que faltaban dejan de existir.
func TestEncadenarTandasTruncadasNoPierdeNiUnaFila(t *testing.T) {
	b := montar(t)
	const total, tope = 12, 5

	base := enPuntoFijo().Add(-time.Hour)
	falso := &repartoPorTandas{tope: tope, techo: enPuntoFijo()}
	for i := 0; i < total; i++ {
		falso.marcas = append(falso.marcas, base.Add(time.Duration(i)*time.Minute))
	}
	b.origen.responder = falso.responder

	vistas := map[string]bool{}
	for vuelta := 1; ; vuelta++ {
		if vuelta > 10 {
			t.Fatalf("la cadena no termina: %d filas de %d", len(vistas), total)
		}
		w := b.pedir(http.MethodGet, "/sync/bajada?aparato="+b.aparato.ID.String(), nil, b.quien)
		if w.Code != http.StatusOK {
			t.Fatalf("vuelta %d: código %d (%s)", vuelta, w.Code, w.Body.String())
		}
		var salida bajadaSalida
		if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
			t.Fatalf("la respuesta no se entiende: %v", err)
		}
		for _, p := range salida.Cambios["customers"].Puestos {
			var fila struct {
				ID string `json:"id"`
			}
			_ = json.Unmarshal(p, &fila)
			if vistas[fila.ID] {
				t.Fatalf("vuelta %d: la fila %s vino dos veces; la cadena da vueltas sobre "+
					"lo mismo en vez de avanzar", vuelta, fila.ID)
			}
			vistas[fila.ID] = true
		}
		if !salida.Truncado {
			break
		}
	}

	if len(vistas) != total {
		t.Fatalf("SE PERDIERON FILAS EN SILENCIO: bajaron %d de %d.\n"+
			"Con «truncado», la marca que se anota y se devuelve tiene que ser la que dijo "+
			"el reparto —la de la última fila servida—, no el `hasta` que mandó este "+
			"servicio. Con el nuestro, lo que no cupo en la tanda queda por debajo del "+
			"próximo «desde» y no lo vuelve a pedir nadie (CLAUDE.md §3).",
			len(vistas), total)
	}
}

// La misma regla, dicha sobre la marca y no sobre las filas: se ANOTA lo servido.
func TestSeAnotaLaMarcaQueDijoElRepartoYNoLaQueSeMando(t *testing.T) {
	b := montar(t)
	servido := enPuntoFijo().Add(-20 * time.Minute)
	b.origen.truncado = true
	b.origen.hasta = servido

	w := b.pedir(http.MethodGet, "/sync/bajada?aparato="+b.aparato.ID.String(), nil, b.quien)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var salida bajadaSalida
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatalf("la respuesta no se entiende: %v", err)
	}
	if !salida.Hasta.Equal(servido) {
		t.Fatalf("se devolvió %v y el reparto sirvió hasta %v: el trozo que va de una a "+
			"otra no lo vuelve a pedir nadie", salida.Hasta, servido)
	}
	anotadas := b.bajadasAnotadas()
	if len(anotadas) != 1 || !anotadas[0].Equal(servido) {
		t.Fatalf("se anotó %v y el reparto sirvió hasta %v: la próxima bajada empezaría por "+
			"encima de lo que falta", anotadas, servido)
	}
}

// Y AL REVÉS NO: una marca POR DELANTE de la ventana no se acepta.
//
// Retrasar la marca repite trabajo y no rompe nada; adelantarla se salta para siempre todo
// lo que cambió en medio. Un reparto con el reloj adelantado, o una respuesta de otra
// ventana, no puede hacernos saltar ese trozo.
func TestUnaMarcaPorDelanteDeLaVentanaNoSeAcepta(t *testing.T) {
	b := montar(t)
	b.origen.hasta = enPuntoFijo().Add(2 * time.Hour)

	w := b.pedir(http.MethodGet, "/sync/bajada?aparato="+b.aparato.ID.String(), nil, b.quien)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	var salida bajadaSalida
	_ = json.Unmarshal(w.Body.Bytes(), &salida)
	if !salida.Hasta.Equal(enPuntoFijo()) {
		t.Fatalf("se aceptó una marca del reparto (%v) por delante de la ventana pedida "+
			"(%v): lo que cambie en medio no lo pide nadie", salida.Hasta, enPuntoFijo())
	}
}

// UN REPARTO QUE NO MANDA `hasta` SIGUE FUNCIONANDO, con la marca de este servicio.
//
// No es cortesía: es lo que evita que un despliegue a medias —el sincronizador nuevo contra
// un reparto viejo— anote la marca cero y le mande al aparato la carga entera cada vuelta.
func TestSinMarcaDelRepartoValeLaDelServicio(t *testing.T) {
	b := montar(t)
	w := b.pedir(http.MethodGet, "/sync/bajada?aparato="+b.aparato.ID.String(), nil, b.quien)
	var salida bajadaSalida
	_ = json.Unmarshal(w.Body.Bytes(), &salida)
	if !salida.Hasta.Equal(enPuntoFijo()) {
		t.Fatalf("sin marca del reparto tenía que valer la del servicio (%v), fue %v",
			enPuntoFijo(), salida.Hasta)
	}
}

// EL CURSOR VIAJA EN LAS DOS DIRECCIONES Y NADIE LO MIRA POR DENTRO.
//
// Es lo único que puede continuar el catálogo y el padrón cuando miles de filas comparten
// la misma marca, que es lo que hay en producción desde el traspaso: los 7.975 clientes
// entraron en una transacción y comparten `synced_at` al microsegundo.
func TestElCursorDeLaTandaViajaEnLasDosDirecciones(t *testing.T) {
	b := montar(t)
	b.origen.truncado = true
	b.origen.continuar = "eyJwIjp7fX0"

	w := b.pedir(http.MethodGet,
		"/sync/bajada?aparato="+b.aparato.ID.String()+"&continuar=loQueMandoElAparato",
		nil, b.quien)
	if w.Code != http.StatusOK {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	if len(b.origen.ventanas) != 1 {
		t.Fatalf("se le tenía que pedir al reparto una vez")
	}
	if b.origen.ventanas[0].Continuar != "loQueMandoElAparato" {
		t.Fatalf("el cursor del aparato no llegó al reparto: %q. Sin él, un grupo de filas "+
			"con la misma marca no se puede continuar y la cadena repite la primera tanda",
			b.origen.ventanas[0].Continuar)
	}
	var salida bajadaSalida
	_ = json.Unmarshal(w.Body.Bytes(), &salida)
	if salida.Continuar != "eyJwIjp7fX0" {
		t.Fatalf("el cursor del reparto no llegó al aparato: %q", salida.Continuar)
	}
}
