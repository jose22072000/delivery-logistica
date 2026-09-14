package espejo

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/url"
	"strings"
	"testing"
	"time"
)

// LOS DOBLES. El ciclo entero se prueba sin PEDIDO, sin la API del reparto y sin base de
// datos: por eso las tres puertas son interfaces. Así estas pruebas se corren en cada
// compilación y no «cuando haya un entorno a mano».

type pedidoFalso struct {
	// pedidos: qué contesta, por el filtro con el que se pidió.
	porSince  []PedidoDeFuera
	porTramo  []PedidoDeFuera
	fallo     error
	clientes  []ClienteDeFuera
	falloDeCl error

	pedidas []url.Values
}

func (p *pedidoFalso) Pedidos(_ context.Context, q url.Values) ([]PedidoDeFuera, error) {
	p.pedidas = append(p.pedidas, q)
	if p.fallo != nil {
		return nil, p.fallo
	}
	if q.Get("since") != "" {
		// Sólo la primera vuelta trae algo: si no, el incremental pagina para siempre.
		devuelve := p.porSince
		p.porSince = nil
		return devuelve, nil
	}
	return p.porTramo, nil
}

func (p *pedidoFalso) Clientes(_ context.Context, cursor string, _ int) ([]ClienteDeFuera, string, error) {
	if p.falloDeCl != nil {
		return nil, "", p.falloDeCl
	}
	return p.clientes, "", nil
}

type repartoFalso struct {
	lotes      [][]PedidoDeFuera
	respuesta  RespuestaDelLote
	fallo      error
	catalogo   *RespuestaDelCatalogo
	falloDeCat error
	catalogos  int
}

func (d *repartoFalso) Cotizar(_ context.Context, pedidos []PedidoDeFuera) (RespuestaDelLote, error) {
	d.lotes = append(d.lotes, pedidos)
	if d.fallo != nil {
		return RespuestaDelLote{}, d.fallo
	}
	r := d.respuesta
	if r.Persisted == 0 && r.Results == nil {
		r.Persisted = len(pedidos) // por defecto, entran todos
	}
	return r, nil
}

func (d *repartoFalso) SincronizarCatalogo(context.Context) (*RespuestaDelCatalogo, error) {
	d.catalogos++
	return d.catalogo, d.falloDeCat
}

type baseFalsa struct {
	marca        *time.Time
	falloDeMarca error
	posicion     int
	fijado       []int
	clientes     []ClienteDeFuera
	borrados     []string
	falloAlFijar error
}

func (b *baseFalsa) MarcaDeAgua(context.Context) (*time.Time, error) {
	return b.marca, b.falloDeMarca
}
func (b *baseFalsa) PosicionDelBarrido(context.Context) (int, error) { return b.posicion, nil }
func (b *baseFalsa) FijarBarrido(_ context.Context, dia int) error {
	b.fijado = append(b.fijado, dia)
	return b.falloAlFijar
}
func (b *baseFalsa) GuardarCliente(_ context.Context, c ClienteDeFuera) error {
	b.clientes = append(b.clientes, c)
	return nil
}
func (b *baseFalsa) BorrarClientesQueYaNoVienen(_ context.Context, ids []string) (int64, error) {
	b.borrados = ids
	return 0, nil
}

func montar(p *pedidoFalso, d *repartoFalso, b *baseFalsa) *Espejo {
	o := PorDefecto()
	o.Clave = "k"
	return &Espejo{
		Opciones: o,
		Pedido:   p,
		Reparto:  d,
		Base:     b,
		Reg:      slog.New(slog.NewTextHandler(io.Discard, nil)),
		Ahora:    func() time.Time { return hoy },
		Pausa:    0, // en las pruebas no se espera a nadie
	}
}

func TestLaPrimeraPasadaLlenaElEspejoSinMarcaDeAgua(t *testing.T) {
	// La primerísima vez no hay nada guardado, así que no hay `since` posible: lo que llena
	// el espejo es el repaso corto y el barrido del histórico.
	p := &pedidoFalso{porTramo: []PedidoDeFuera{{ID: "a", UpdatedAt: "2026-09-13T10:00:00Z"}}}
	d := &repartoFalso{}
	b := &baseFalsa{}
	e := montar(p, d, b)

	if err := e.Ciclo(context.Background()); err != nil {
		t.Fatalf("el ciclo falló: %v", err)
	}
	for _, q := range p.pedidas {
		if q.Get("since") != "" && q.Get("conCosto") == "" {
			t.Errorf("sin marca de agua no puede haber incremental; se pidió %v", q)
		}
	}
	if len(d.lotes) == 0 {
		t.Fatal("no se mandó ni un lote: el espejo no habría traído nada")
	}
}

func TestConMarcaDeAguaElCicloPideSoloLoQueSeMovio(t *testing.T) {
	// Es lo que hace que un ciclo cueste nada: lo incremental casi siempre trae cero filas.
	marca := time.Date(2026, 9, 13, 10, 0, 0, 0, time.UTC)
	p := &pedidoFalso{porSince: []PedidoDeFuera{{ID: "a", UpdatedAt: "2026-09-13T12:00:00Z"}}}
	e := montar(p, &repartoFalso{}, &baseFalsa{marca: &marca})

	if err := e.Ciclo(context.Background()); err != nil {
		t.Fatalf("el ciclo falló: %v", err)
	}
	visto := false
	for _, q := range p.pedidas {
		if q.Get("since") == "2026-09-13T10:00:00Z" {
			visto = true
		}
	}
	if !visto {
		t.Errorf("tenía que pedirse since=2026-09-13T10:00:00Z; se pidió %+v", p.pedidas)
	}
}

func TestElIncrementalAvanzaConLoQueLlegaYNoGiraEnElSitio(t *testing.T) {
	// Sin avanzar la marca por el `updatedAt` más nuevo de la tanda, una tanda de más de
	// `limit` pedidos devolvería siempre los mismos y el bucle no terminaría nunca.
	marca := time.Date(2026, 9, 13, 10, 0, 0, 0, time.UTC)
	p := &pedidoFalso{porSince: []PedidoDeFuera{{ID: "a", UpdatedAt: "2026-09-13T12:00:00Z"}}}
	e := montar(p, &repartoFalso{}, &baseFalsa{marca: &marca})

	n, err := e.porCambios(context.Background(), marca)
	if err != nil {
		t.Fatalf("falló: %v", err)
	}
	if n != 1 {
		t.Errorf("tenía que guardar 1; guardó %d", n)
	}
	if len(p.pedidas) != 2 {
		t.Fatalf("tenían que ser dos vueltas (la que trae y la que ya no trae nada); fueron %d", len(p.pedidas))
	}
	if p.pedidas[1].Get("since") != "2026-09-13T12:00:00Z" {
		t.Errorf("la segunda vuelta tenía que arrancar del más nuevo; arrancó de %q", p.pedidas[1].Get("since"))
	}
}

func TestElIncrementalSeParaSiLaMarcaNoAvanza(t *testing.T) {
	// PEDIDO puede no mandar `updatedAt`. Sin esta salida, el ciclo se queda dando las 200
	// vueltas del tope pidiendo siempre lo mismo.
	marca := time.Date(2026, 9, 13, 10, 0, 0, 0, time.UTC)
	p := &pedidoFalso{porSince: []PedidoDeFuera{{ID: "a"}}}
	e := montar(p, &repartoFalso{}, &baseFalsa{marca: &marca})

	if _, err := e.porCambios(context.Background(), marca); err != nil {
		t.Fatalf("falló: %v", err)
	}
	if len(p.pedidas) != 1 {
		t.Errorf("tenía que pararse en la primera vuelta; dio %d", len(p.pedidas))
	}
}

func TestQueVentraNoContesteNoParaLosPedidos(t *testing.T) {
	// El catálogo se llega por VPN y se cae. Si eso parara el ciclo, un enlace caído
	// dejaría al logístico sin pedidos nuevos, que es mucho peor que un catálogo viejo.
	p := &pedidoFalso{porTramo: []PedidoDeFuera{{ID: "a"}}}
	d := &repartoFalso{falloDeCat: errors.New("la VPN está caída")}
	e := montar(p, d, &baseFalsa{})

	if err := e.Ciclo(context.Background()); err != nil {
		t.Fatalf("el ciclo tenía que seguir: %v", err)
	}
	if len(d.lotes) == 0 {
		t.Error("los pedidos tenían que entrar igual")
	}
}

func TestQueFallenLosClientesNoParaLosPedidos(t *testing.T) {
	p := &pedidoFalso{porTramo: []PedidoDeFuera{{ID: "a"}}, falloDeCl: errors.New("timeout")}
	d := &repartoFalso{}
	b := &baseFalsa{}
	e := montar(p, d, b)

	if err := e.Ciclo(context.Background()); err != nil {
		t.Fatalf("el ciclo tenía que seguir: %v", err)
	}
	// Y SOBRE TODO: no se borra nada. Vaciar el espejo de clientes por una página perdida
	// sería el peor final posible, con un 200 y sin un solo error.
	if b.borrados != nil {
		t.Errorf("con el recorrido a medias no se puede borrar nada; se intentó con %+v", b.borrados)
	}
}

func TestSoloSeCopianLosClientesConCoordenadas(t *testing.T) {
	// Sin coordenadas no hay parada que visitar ni distancia que medir, y la columna no
	// admite nulos.
	p := &pedidoFalso{clientes: []ClienteDeFuera{
		{ID: "c1", Nombre: "Con geo", Latitud: numero(20), Longitud: numero(-75)},
		{ID: "c2", Nombre: "Sin geo"},
	}}
	b := &baseFalsa{}
	e := montar(p, &repartoFalso{}, b)

	e.clientes(context.Background())
	if len(b.clientes) != 1 || b.clientes[0].ID != "c1" {
		t.Fatalf("sólo tenía que copiarse el geolocalizado; se copiaron %+v", b.clientes)
	}
	if len(b.borrados) != 1 || b.borrados[0] != "c1" {
		t.Errorf("la lista de los que se quedan tenía que ser [c1]; fue %+v", b.borrados)
	}
}

func TestElBarridoNoPasaEnCadaVuelta(t *testing.T) {
	// El ciclo pasa cada minuto para que el costo del domicilio aparezca pronto. Pedirle a
	// PEDIDO treinta días de histórico cada minuto es cargarlo por gusto: lo viejo no se
	// mueve.
	p := &pedidoFalso{}
	b := &baseFalsa{}
	e := montar(p, &repartoFalso{}, b)

	e.Ciclo(context.Background())
	primeras := len(p.pedidas)
	e.Ciclo(context.Background())

	if len(b.fijado) != 1 {
		t.Errorf("el barrido tenía que correr una sola vez; corrió %d", len(b.fijado))
	}
	if len(p.pedidas) >= primeras*2 {
		t.Errorf("la segunda vuelta pidió tanto como la primera (%d y %d): el freno del barrido no está",
			primeras, len(p.pedidas)-primeras)
	}
}

func TestElBarridoGuardaPorDondeVaYDaLaVueltaAlAno(t *testing.T) {
	p := &pedidoFalso{}
	b := &baseFalsa{posicion: 400}
	e := montar(p, &repartoFalso{}, b)
	e.Opciones.HistoricoDias = 420
	e.Opciones.HistoricoPorCiclo = 30

	e.barrido(context.Background())
	if len(b.fijado) != 1 || b.fijado[0] != 0 {
		t.Fatalf("al llegar al final tenía que volver a 0; quedó %+v", b.fijado)
	}
}

func TestUnTramoQueFallaNoTumbaElResto(t *testing.T) {
	// El histórico se repasa en bucle: lo que falló hoy se recoge en la pasada siguiente.
	// Rendirse al primer fallo sería no recuperar nunca el resto del año.
	p := &pedidoFalso{fallo: errors.New("PEDIDO 500")}
	b := &baseFalsa{}
	e := montar(p, &repartoFalso{}, b)

	if err := e.Ciclo(context.Background()); err != nil {
		t.Fatalf("el ciclo no podía fallar entero: %v", err)
	}
	if len(b.fijado) != 1 {
		t.Error("el barrido tenía que avanzar la posición aunque los tramos fallaran")
	}
}

func TestLaTandaSeTroceaAntesDeMandarla(t *testing.T) {
	// Mandar miles de pedidos en un solo POST es lo que reventó la memoria la vez anterior,
	// y además el reparto de carga se calcula por envío: 200 es un tamaño de camión.
	muchos := make([]PedidoDeFuera, 450)
	for i := range muchos {
		muchos[i] = PedidoDeFuera{ID: string(rune('a' + i%26))}
	}
	d := &repartoFalso{}
	e := montar(&pedidoFalso{}, d, &baseFalsa{})

	e.guardar(context.Background(), muchos, "prueba")
	if len(d.lotes) != 3 || len(d.lotes[0]) != 200 || len(d.lotes[2]) != 50 {
		t.Fatalf("450 pedidos tenían que ir en 3 lotes de 200/200/50; fueron %d lotes", len(d.lotes))
	}
}

func TestUnLoteQueFallaNoSeLlevaALosDemas(t *testing.T) {
	d := &repartoFalso{fallo: errors.New("502")}
	e := montar(&pedidoFalso{}, d, &baseFalsa{})

	if n := e.guardar(context.Background(), make([]PedidoDeFuera, 400), "prueba"); n != 0 {
		t.Errorf("no entró nada, tenía que contar 0; contó %d", n)
	}
	if len(d.lotes) != 2 {
		t.Errorf("los dos lotes tenían que intentarse; se intentaron %d", len(d.lotes))
	}
}

func TestLosQueNoEntranSeCuentanPorMotivo(t *testing.T) {
	// Un lote que contesta 200 y guarda cero es lo más parecido que hay a que todo vaya
	// bien. `espejo-no-montado` salía así: cotizaba y no guardaba, y la base seguía vacía.
	no := false
	r := RespuestaDelLote{Results: []ResultadoDelPedido{
		{Reason: "espejo-no-montado", Persisted: &no},
		{Reason: "espejo-no-montado", Persisted: &no},
		{Reason: "sucursal-no-mapeada"},
		{Reason: ""},
	}}
	cuenta := motivosDeNoEntrar(r)
	if cuenta["espejo-no-montado"] != 2 || cuenta["sucursal-no-mapeada"] != 1 {
		t.Errorf("el recuento salió %+v", cuenta)
	}
	if len(cuenta) != 2 {
		t.Errorf("los que no traen motivo no se cuentan; salió %+v", cuenta)
	}
}

func TestLosFiltrosBaseViajanEnTodasLasPeticiones(t *testing.T) {
	e := montar(&pedidoFalso{}, &repartoFalso{}, &baseFalsa{})
	e.Opciones.SucursalCodigo = "STG"
	q := e.parametrosBase()
	if q.Get("soloRepartibles") != "1" {
		t.Error("por defecto sólo se trae lo que puede subir a un camión")
	}
	if q.Get("sucursalCodigo") != "STG" {
		t.Error("la sucursal tiene que viajar en todas las peticiones")
	}
	// Apagados por defecto, y por un número: de 1.243 pedidos con domicilio y geo de los
	// últimos quince días, los que la APK ya había cotizado eran SEIS.
	if q.Get("conCosto") != "" || q.Get("soloDomicilio") != "" {
		t.Errorf("los dos filtros finos van apagados por defecto; salió %v", q)
	}
}

func TestElCicloSeParaCuandoLoParan(t *testing.T) {
	// Apagado ordenado: se sale entre vueltas, no a mitad de una.
	ctx, cancelar := context.WithCancel(context.Background())
	cancelar()
	e := montar(&pedidoFalso{}, &repartoFalso{}, &baseFalsa{})
	if err := e.Correr(ctx); err != nil {
		t.Errorf("parar no es un error; devolvió %v", err)
	}
}

func TestSinLlaveDeServicioElEspejoNoArranca(t *testing.T) {
	_, err := Cargar(func(string) string { return "" })
	if err == nil || !strings.Contains(err.Error(), "SERVICE_API_KEY") {
		t.Fatalf("tenía que quejarse de la llave; se quejó de %v", err)
	}
}
