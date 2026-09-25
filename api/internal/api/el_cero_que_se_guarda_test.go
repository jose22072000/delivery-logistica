package api

// EL CERO QUE SE GUARDA EN `routes.total_price`, QUE ES EL QUE NO DESMIENTE NADIE.
//
// El 22/09/2026 se tapó el `$0.00` de la tarjeta de una ruta en el aparato: el importe ya
// no se lee de `routes.total_price` sino que se suma de las paradas, que sí saben decir
// que no lo saben (`app/lib/pantallas/rutas/datos/importe_de_la_ruta.dart`). Pero la
// columna del servidor sigue siendo `double precision NOT NULL DEFAULT 0`, así que **quien
// la consulte por SQL o la exporte sigue viendo un cero indistinguible de un cero de
// verdad**. La ruta RT-20260921-007 decía `$0.00` con sus dos paradas sin cotizar y el
// camión a 1,50 USD/km.
//
// La decisión (00007_lo_que_no_se_sabe.sql) no fue anular la columna —eso rompería a todo
// el que ya la lee, empezando por las APK instaladas— sino guardar A SU LADO cuántas
// paradas entraron sin cotizar. Un total con ese número al lado ya no puede mentir.
//
// LAS PRUEBAS VAN EN PAREJA, y ésa es la mitad del valor: una guarda que sólo se prueba
// por el lado que falla no distingue entre «avisa cuando toca» y «avisa siempre»
// (`CLAUDE.md` §3-quinquies). Así que se comprueba que sale 2 cuando faltan dos Y que sale
// **0, no nulo**, cuando no falta ninguna: si en ese caso se dejara el nulo, una ruta
// entera bien cotizada diría «no consta» y el número dejaría de servir para nada.

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/google/uuid"
)

// armarYLeer arma la ruta con los tres pedidos de Santiago y devuelve lo guardado y lo
// devuelto, que tienen que decir lo mismo.
func armarYLeer(t *testing.T, d *dobleDeRutas, h http.Handler, ids ...uuid.UUID) (*rutaDeRutas, RutaSalida, int) {
	t.Helper()
	w := llamarRutas(t, h, http.MethodPost, "/api/routes", deSantiagoEnRutas(t),
		cuerpoDeArmado(camionStg.String(), ids...))
	if w.Code != http.StatusCreated {
		t.Fatalf("código %d: %s", w.Code, w.Body.String())
	}
	// El armado contesta de DOS formas: la ruta pelada, o `{ruta, avisos}` cuando hay
	// domicilios sin costear. Las dos llevan la misma ruta dentro.
	var conAvisos struct {
		Ruta   *RutaSalida `json:"ruta"`
		Avisos struct {
			SinCosto int `json:"sinCosto"`
		} `json:"avisos"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &conAvisos); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	var ruta RutaSalida
	if conAvisos.Ruta != nil {
		ruta = *conAvisos.Ruta
	} else if err := json.Unmarshal(w.Body.Bytes(), &ruta); err != nil {
		t.Fatalf("respuesta ilegible: %v", err)
	}
	guardada, hay := d.rutas[ruta.ID]
	if !hay {
		t.Fatal("la ruta no quedó guardada")
	}
	return guardada, ruta, conAvisos.Avisos.SinCosto
}

// 1. CON ALGUNA SIN COTIZAR: el total sale corto y la columna lo dice.
func TestLaRutaGuardaCuantasParadasEntraronSinCotizar(t *testing.T) {
	d, stg, _ := datosDeReparto()
	// Dos de los tres se quedan sin `pedidoCosto`: es el caso real, con 657 de 686
	// domicilios sin costo porque la APK de Entrega todavía no está encendida.
	d.pedidos[stg[0]].costo = nil
	d.pedidos[stg[1]].costo = nil
	h := montarRutas(t, d)

	guardada, ruta, _ := armarYLeer(t, d, h, stg[0], stg[1], stg[2])

	if guardada.sinCotizar == nil {
		t.Fatal("se guardó NULL en paradas_sin_cotizar teniendo dos paradas sin costo: " +
			"ese nulo dice «no consta», y aquí sí consta")
	}
	if *guardada.sinCotizar != 2 {
		t.Fatalf("entraron 2 paradas sin cotizar y se guardó %d", *guardada.sinCotizar)
	}
	// Y el total es el de la que SÍ estaba cotizada: 10. Los dos números van juntos o el
	// de arriba vuelve a parecer completo.
	if guardada.precio != 10 {
		t.Fatalf("total_price tiene que sumar sólo lo cotizado (10) y sumó %v", guardada.precio)
	}
	if ruta.ParadasSinCotizar == nil || *ruta.ParadasSinCotizar != 2 {
		t.Fatalf("la respuesta tiene que llevar paradasSinCotizar=2 y llevó %v", ruta.ParadasSinCotizar)
	}
}

// 2. CON TODAS COTIZADAS: **0, no nulo**. Es la otra mitad de la pareja.
func TestUnaRutaConTodoCotizadoGuardaCeroYNoUnNulo(t *testing.T) {
	d, stg, _ := datosDeReparto()
	h := montarRutas(t, d) // los tres traen costo 10

	guardada, ruta, _ := armarYLeer(t, d, h, stg[0], stg[1], stg[2])

	if guardada.sinCotizar == nil {
		t.Fatal("con las tres paradas cotizadas se guardó NULL: «no consta» y «ninguna» no " +
			"son lo mismo, y dejarlo en nulo hace inservible el número en el caso bueno")
	}
	if *guardada.sinCotizar != 0 {
		t.Fatalf("no faltaba ninguna y se guardó %d", *guardada.sinCotizar)
	}
	if guardada.precio != 30 {
		t.Fatalf("total_price tenía que ser 30 y fue %v", guardada.precio)
	}
	if ruta.ParadasSinCotizar == nil || *ruta.ParadasSinCotizar != 0 {
		t.Fatalf("la respuesta tiene que llevar paradasSinCotizar=0 y llevó %v", ruta.ParadasSinCotizar)
	}
}

// 3. EL CONTADOR CUENTA LO MISMO QUE LA SUMA, no lo que cuenta el aviso.
//
// Hay DOS números parecidos y no son el mismo: `sinCosto` cuenta los que LLEVAN DOMICILIO
// y no tienen costo —de eso avisa el armador— y `paradas_sin_cotizar` cuenta los que no
// aportaron nada al total, lleven domicilio o no. Si se confundieran, el número de al lado
// del total explicaría OTRA cosa y nadie lo notaría: las dos cifras salen creíbles.
//
// Es además el criterio de `ImporteDeRuta.deLasParadas` en el aparato, que cuenta toda
// parada con `pedidoCosto == null`. Servidor y aparato tienen que decir lo mismo de la
// misma ruta.
func TestElContadorSigueALaSumaYNoAlAviso(t *testing.T) {
	d, stg, _ := datosDeReparto()
	si := true
	// Uno CON domicilio y sin costo: cuenta para los dos números.
	d.pedidos[stg[0]].costo, d.pedidos[stg[0]].requiereDomicilio = nil, &si
	// Y otro SIN domicilio y sin costo: no dispara el aviso del armador, pero tampoco
	// suma nada al total, así que tiene que contar aquí. Éste es el que separa las dos
	// cuentas: con `sinCosto` saldría 1 en vez de 2.
	d.pedidos[stg[1]].costo = nil
	h := montarRutas(t, d)

	guardada, _, avisoSinCosto := armarYLeer(t, d, h, stg[0], stg[1], stg[2])

	if guardada.sinCotizar == nil || *guardada.sinCotizar != 2 {
		t.Fatalf("dos paradas no sumaron al total y se contaron %v.\n"+
			"Casi seguro que el contador se tomó de `sinCosto`, que sólo mira los que "+
			"llevan domicilio y aquí daría 1; tiene que contar lo mismo que suma `total_price`",
			guardada.sinCotizar)
	}
	if guardada.precio != 10 {
		t.Fatalf("total_price tenía que ser 10 y fue %v", guardada.precio)
	}
	// Y el aviso sigue contando LO SUYO, que es 1. Los dos números conviven en la misma
	// respuesta y dicen cosas distintas a propósito; si algún día salen iguales en este
	// caso, es que uno de los dos se tomó del otro.
	if avisoSinCosto != 1 {
		t.Fatalf("el aviso cuenta los que llevan domicilio sin costo y tenía que ser 1, y fue %d",
			avisoSinCosto)
	}
}
