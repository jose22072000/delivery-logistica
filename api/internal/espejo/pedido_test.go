package espejo

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

func TestSePideAPedidoConLaLlaveDeServicio(t *testing.T) {
	// Sin la llave, PEDIDO contesta 401 y el espejo se pasa el día dando vueltas sin traer
	// nada — y desde fuera parece que PEDIDO no manda nada.
	var vistaLaLlave, vistaLaRuta string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		vistaLaLlave = r.Header.Get("X-Api-Key")
		vistaLaRuta = r.URL.Path + "?" + r.URL.RawQuery
		w.Write([]byte(`{"orders":[{"id":"a","updatedAt":"2026-09-13T10:00:00Z"}]}`))
	}))
	defer srv.Close()

	c := NuevoClientePedido(srv.URL+"/", "la-llave")
	q := url.Values{}
	q.Set("desde", "2026-09-01")
	pedidos, err := c.Pedidos(context.Background(), q)
	if err != nil {
		t.Fatalf("falló: %v", err)
	}
	if vistaLaLlave != "la-llave" {
		t.Errorf("la llave no llegó en x-api-key; llegó %q", vistaLaLlave)
	}
	if vistaLaRuta != "/integration/orders?desde=2026-09-01" {
		t.Errorf("se pidió %q", vistaLaRuta)
	}
	if len(pedidos) != 1 || pedidos[0].ID != "a" {
		t.Errorf("no se leyeron los pedidos: %+v", pedidos)
	}
}

func TestUnFalloDePedidoSeCuentaConSuCodigo(t *testing.T) {
	// El código y el cuerpo van en el mensaje a propósito: un «PEDIDO no contesta» a secas
	// obliga a entrar al servidor a mirar qué pasó.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "sucursal desconocida", http.StatusBadRequest)
	}))
	defer srv.Close()

	_, err := NuevoClientePedido(srv.URL, "k").Pedidos(context.Background(), url.Values{})
	if err == nil || !strings.Contains(err.Error(), "400") || !strings.Contains(err.Error(), "sucursal desconocida") {
		t.Fatalf("el error tenía que llevar el código y el motivo; llevó %v", err)
	}
}

func TestLosClientesSeTraenPorPaginas(t *testing.T) {
	// Traerlos todos de golpe eran 2,17 MB en una sola respuesta. Por páginas la memoria se
	// mantiene plana y una respuesta cortada a medias no deja el proceso con datos a medias.
	var cursores []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cursores = append(cursores, r.URL.Query().Get("cursor"))
		if r.URL.Query().Get("cursor") == "" {
			w.Write([]byte(`{"clients":[{"id":"c1"}],"nextCursor":"c1"}`))
			return
		}
		w.Write([]byte(`{"clients":[{"id":"c2"}]}`))
	}))
	defer srv.Close()

	c := NuevoClientePedido(srv.URL, "k")
	primera, siguiente, err := c.Clientes(context.Background(), "", 1000)
	if err != nil || len(primera) != 1 || siguiente != "c1" {
		t.Fatalf("primera página: %+v, cursor %q, err %v", primera, siguiente, err)
	}
	segunda, siguiente, err := c.Clientes(context.Background(), siguiente, 1000)
	if err != nil || len(segunda) != 1 {
		t.Fatalf("segunda página: %+v, err %v", segunda, err)
	}
	// Sin `nextCursor` se acabó. Un PEDIDO anterior a la paginación no lo manda y devuelve
	// todo de una vez: el recorrido se corta y funciona igual.
	if siguiente != "" {
		t.Errorf("sin nextCursor el recorrido tenía que acabarse; quedó %q", siguiente)
	}
	if len(cursores) != 2 || cursores[1] != "c1" {
		t.Errorf("los cursores pedidos fueron %+v", cursores)
	}
}
