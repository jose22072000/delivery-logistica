package espejo

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log/slog"
	"net/url"
	"strconv"
	"strings"
	"testing"
	"time"
)

// LOS DOBLES. El ciclo entero se prueba sin PEDIDO, sin la API del reparto y sin base de
// datos: por eso las tres puertas son interfaces. Así estas pruebas se corren en cada
// compilación y no «cuando haya un entorno a mano».

type pedidoFalso struct {
	// Los ids que se pidieron por `?ids=`.
	clientesPedidos []string
	// pedidos: qué contesta, por el filtro con el que se pidió.
	porSince  []PedidoDeFuera
	porTramo  []PedidoDeFuera
	fallo     error
	clientes  []ClienteDeFuera
	falloDeCl error

	// porTramoSegun manda sobre `porTramo` cuando esta puesta, y existe para poder contestar
	// distinto SEGUN EL `hasta` QUE SE PIDIO: es la unica forma de probar que un tramo que
	// vino lleno se sigue pidiendo, porque lo que se comprueba es justo que la segunda
	// peticion no es igual que la primera.
	porTramoSegun func(q url.Values) []PedidoDeFuera

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
	if p.porTramoSegun != nil {
		return p.porTramoSegun(q), nil
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
	// Lo que se quitó por un aviso de borrado.
	quitados     []string
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

// ---------------------------------------------------------------------------
// El barrido por tramos: que no se quede a medias, y que se diga cuando se queda
// ---------------------------------------------------------------------------

// montarConRegistro es `montar` pero guardando lo que se escribe en el registro. Los avisos
// de tramo truncado SON el arreglo —lo que fallaba no era cortarse, era cortarse
// callandoselo—, asi que hay que poder leerlos en una prueba.
func montarConRegistro(p *pedidoFalso, d *repartoFalso, b *baseFalsa) (*Espejo, *bytes.Buffer) {
	var buf bytes.Buffer
	e := montar(p, d, b)
	e.Reg = slog.New(slog.NewTextHandler(&buf, &slog.HandlerOptions{Level: slog.LevelDebug}))
	return e, &buf
}

// paginaLlena arma una tanda del tamano EXACTO del tope de PEDIDO, con el mas viejo en
// `diaViejo`: es lo que llega cuando la respuesta viene recortada.
func paginaLlena(diaNuevo, diaViejo string) []PedidoDeFuera {
	p := make([]PedidoDeFuera, TopeDePagina)
	for i := range p {
		p[i] = PedidoDeFuera{ID: strconv.Itoa(i), Fecha: diaNuevo}
	}
	p[TopeDePagina-1].Fecha = diaViejo
	return p
}

func TestUnTramoQueVinoLlenoSeSiguePidiendo(t *testing.T) {
	// EL FALLO QUE ESTO CIERRA: se pedia un tope, llegaba la pagina recortada y nadie
	// miraba cuantos habian venido. `/integration/orders` contesta 200 sin decir que falte
	// nada, asi que el tramo se daba por traido entero y el resto no lo volvia a pedir
	// nadie.
	p := &pedidoFalso{}
	p.porTramoSegun = func(q url.Values) []PedidoDeFuera {
		if q.Get("hasta") == "2026-09-14" {
			return paginaLlena("2026-09-14T10:00:00Z", "2026-09-13T08:00:00Z")
		}
		return []PedidoDeFuera{{ID: "elResto", Fecha: "2026-09-12T08:00:00Z"}}
	}
	e, reg := montarConRegistro(p, &repartoFalso{}, &baseFalsa{})

	e.porTramos(context.Background(), 2, 0, "prueba")

	// DOS peticiones exactas: la que vino llena y la que la continua. Ni una menos —seria
	// el fallo de antes— ni una mas: pedir sin mirar si la pagina venia llena es no tener
	// guarda ninguna.
	if len(p.pedidas) != 2 {
		t.Fatalf("tenian que ser dos peticiones (la llena y la que sigue); fueron %d: %+v", len(p.pedidas), p.pedidas)
	}
	if p.pedidas[0].Get("hasta") != "2026-09-14" || p.pedidas[0].Get("desde") != "2026-09-12" {
		t.Errorf("la primera peticion tenia que ser el tramo entero; fue %v", p.pedidas[0])
	}
	// Se estrecha por el dia del MAS VIEJO que llego, que es lo unico con lo que se puede
	// avanzar: ese endpoint no tiene cursor.
	if p.pedidas[1].Get("hasta") != "2026-09-13" || p.pedidas[1].Get("desde") != "2026-09-12" {
		t.Errorf("la segunda tenia que arrancar del dia del mas viejo; fue %v", p.pedidas[1])
	}
	// Y no se le pide a PEDIDO mas de lo que sirve: pidiendo de mas, una pagina recortada
	// no se distingue de una pagina corta.
	if p.pedidas[0].Get("limit") != strconv.Itoa(TopeDePagina) {
		t.Errorf("se pidio limit=%q y tenia que ser el tope de PEDIDO (%d)", p.pedidas[0].Get("limit"), TopeDePagina)
	}
	// Un tramo que SI se acaba de traer no deja aviso: si avisara siempre, el aviso no
	// significaria nada.
	if strings.Contains(reg.String(), "truncado") {
		t.Errorf("el tramo se trajo entero y aun asi aviso de truncado: %s", reg.String())
	}
}

func TestUnTramoQueSeCortaDeVerdadDejaUnAvisoConElTramoDentro(t *testing.T) {
	// Un solo dia con mas pedidos de los que PEDIDO sirve: el borde ya no se puede
	// estrechar. Aqui no hay nada que arreglar desde este lado, pero callarselo deja al
	// logistico viendo menos de lo que hay sin ninguna senal. Y el aviso tiene que NOMBRAR
	// el tramo: uno que no lo nombra no sirve para ir a buscar lo que falta.
	p := &pedidoFalso{}
	p.porTramoSegun = func(url.Values) []PedidoDeFuera {
		return paginaLlena("2026-09-14T10:00:00Z", "2026-09-14T01:00:00Z")
	}
	e, reg := montarConRegistro(p, &repartoFalso{}, &baseFalsa{})

	e.porTramos(context.Background(), 2, 0, "prueba")

	// Una sola peticion: sin poder estrechar, volver a pedir traeria exactamente lo mismo.
	if len(p.pedidas) != 1 {
		t.Fatalf("sin poder estrechar tenia que pararse en la primera; dio %d vueltas", len(p.pedidas))
	}
	salida := reg.String()
	if !strings.Contains(salida, "level=WARN") || !strings.Contains(salida, "truncado") {
		t.Fatalf("tenia que quedar un WARN de truncado; el registro dice: %s", salida)
	}
	if !strings.Contains(salida, "2026-09-12..2026-09-14") {
		t.Errorf("el aviso tiene que nombrar el tramo; dice: %s", salida)
	}
}

func TestUnTramoQueSiempreVineLlenoNoGiraParaSiempre(t *testing.T) {
	// PEDIDO puede contestar cualquier cosa —una pagina llena con fechas que no dejan de
	// bajar—, y eso no puede dejar al ciclo aqui toda la noche sin llegar al barrido. Se
	// para en el tope de vueltas y se dice.
	pagina := paginaLlena("2026-09-14T10:00:00Z", "2026-09-14T01:00:00Z")
	p := &pedidoFalso{}
	p.porTramoSegun = func(q url.Values) []PedidoDeFuera {
		// Cada vuelta baja un dia, asi que el borde SIEMPRE avanza y nunca hay motivo para
		// pararse: lo unico que corta es el tope.
		dia, err := time.Parse(FormatoDeFecha, q.Get("hasta"))
		if err != nil {
			t.Fatalf("el tramo pidio un hasta ilegible: %q", q.Get("hasta"))
		}
		pagina[TopeDePagina-1].Fecha = dia.AddDate(0, 0, -1).Format(time.RFC3339)
		return pagina
	}
	e, reg := montarConRegistro(p, &repartoFalso{}, &baseFalsa{})

	e.porTramos(context.Background(), 2, 0, "prueba")

	if len(p.pedidas) != TopeDeVueltas {
		t.Fatalf("tenia que cortarse en el tope de %d vueltas; dio %d", TopeDeVueltas, len(p.pedidas))
	}
	if !strings.Contains(reg.String(), "todas las vueltas") {
		t.Errorf("cortarse por el tope tambien se dice; el registro dice: %s", reg.String())
	}
}

// QuitarPedidos: los que PEDIDO avisó como borrados. Se apunta para poder comprobar que el
// aviso de borrado llega hasta aquí — es el único de los cuatro motivos que no va a pedir
// nada, y si se ignorara el pedido se queda en el reparto para siempre.
func (b *baseFalsa) QuitarPedidos(_ context.Context, ids []string) error {
	b.quitados = append(b.quitados, ids...)
	return nil
}

// ClientesPorID: los que se movieron de sitio, pedidos por su id.
//
// Se apuntan los ids para poder comprobar que un aviso de `cliente` pide ESE cliente y no
// el padrón entero — que es la diferencia entre una fila y 8.673.
func (p *pedidoFalso) ClientesPorID(_ context.Context, ids []string) ([]ClienteDeFuera, error) {
	p.clientesPedidos = append(p.clientesPedidos, ids...)
	var salida []ClienteDeFuera
	for _, c := range p.clientes {
		for _, id := range ids {
			if c.ID == id {
				salida = append(salida, c)
			}
		}
	}
	return salida, nil
}
