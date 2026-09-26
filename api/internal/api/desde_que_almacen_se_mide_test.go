package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/cotizar"
	"procovar/reparto-api/internal/espejo"
	"procovar/reparto-api/internal/store/sqlc"
)

// DESDE QUÉ ALMACÉN SE MIDE CADA PEDIDO — 26/09/2026.
//
// # EL FALLO, con los números delante
//
// La distancia del domicilio se mide DESDE EL ALMACÉN y de esos kilómetros sale el costo que
// alguien cobra. Mientras cada sucursal tuvo UN almacén, «el de la sucursal» y «el del pedido»
// eran la misma frase. La sesión de PEDIDO contó sus renglones y dejaron de serlo:
//
//	SANTIAGO    2.185 líneas desde AURORA · 804 desde PV-STGO · 11 desde PTO MONEDERO
//	CAMAGÜEY    2.778 desde PV CAMAGÜEY   · 183 desde FLORIDA · 39 desde ALM CAMAGÜEY
//	GUANTÁNAMO  2.060 desde PV GTMO       · 940 desde ALM CENTRAL
//
// En Santiago **dos de cada tres pedidos salen de AURORA**. Y el lote, que es LA PUERTA de los
// pedidos, no medía ni desde el principal: medía desde el punto de la SUCURSAL, mientras
// `/api/quote/home-delivery`, el tablero y Clientes medían desde el almacén. Cuatro
// consumidores, dos orígenes, ninguna prueba comparándolos: `CLAUDE.md` §3-bis.
//
// # LA FORMA DE ESTAS PRUEBAS
//
// SE ENTRA POR LA PUERTA DE VERDAD —`POST /api/quote/batch` con su llave de servicio— y se
// mira lo que SALE (`distanceKm` de la respuesta) y lo que SE ESCRIBE (el `PedidoParaGuardar`
// que recibe el espejo, pasado además por `paraLaBase`, que es la fila). No se siembra por la
// columna por la que se pregunta: el almacén entra como JSON de PEDIDO y se pregunta por los
// kilómetros y por la fila.
//
// Y VAN EN PAREJA. Cada «mide desde el almacén del pedido» lleva su gemelo «y sigue midiendo
// desde el principal cuando el pedido no trae almacén». La segunda mitad es la que se olvida,
// y sin ella lo primero se cumple con un código que rompe los 5.480 pedidos que hay hoy en
// producción, que son todos sin almacén.

// --------------------------------------------------------------------------- el montaje

var stgDelAlmacen = uuid.MustParse("5a5a5a5a-0000-0000-0000-00000000000a")

// Los tres almacenes de Santiago, con PV-STGO como principal. AURORA está a ~20 km, que es lo
// que hace que la diferencia se vea en los kilómetros y no sólo en el campo guardado.
const (
	latPVSTGO, lngPVSTGO = 20.0200, -75.8200
	latAURORA, lngAURORA = 20.1500, -75.9500
	// El cliente, a un par de manzanas de PV-STGO.
	latCliente, lngCliente = 20.0250, -75.8150
)

func almacenesDeSantiagoDeAccesos() []SucursalConAlmacenes {
	cod1, cod2 := "1", "2"
	lat1, lng1 := latPVSTGO, lngPVSTGO
	lat2, lng2 := latAURORA, lngAURORA
	return []SucursalConAlmacenes{{
		Codigo: "STG", Nombre: "Santiago",
		Almacenes: []Almacen{
			{ID: &cod1, Codigo: &cod1, Nombre: "PV-STGO", Latitud: &lat1, Longitud: &lng1,
				Principal: true, Activo: true},
			{ID: &cod2, Codigo: &cod2, Nombre: "AURORA", Latitud: &lat2, Longitud: &lng2,
				Activo: true},
		},
	}}
}

// dobleDelOrigen contesta lo justo para que el lote entre, y GUARDA LO QUE SE ESCRIBE.
type dobleDelOrigen struct {
	sqlc.Querier
	recepciones []sqlc.ApuntarRecepcionDelWebhookParams
}

func (d *dobleDelOrigen) ListarSucursales(context.Context, pgtype.UUID) ([]sqlc.ListarSucursalesRow, error) {
	c := "STG"
	return []sqlc.ListarSucursalesRow{{
		ID: stgDelAlmacen, Name: "Santiago", ExternalID: &c,
		// El punto de la SUCURSAL, que es lo que se usaba antes y ahora es el último
		// recurso. Se pone LEJOS de los dos almacenes a propósito: si alguna prueba
		// acabara midiendo desde aquí, el número canta.
		Lat: 19.0000, Lng: -74.0000, OriginConfigured: true,
	}}, nil
}

func (d *dobleDelOrigen) ApuntarRecepcionDelWebhook(_ context.Context, p sqlc.ApuntarRecepcionDelWebhookParams) error {
	d.recepciones = append(d.recepciones, p)
	return nil
}

// loteDeUnPedido manda UN pedido por la puerta y devuelve su resultado y lo que se escribió.
//
// `GuardarPedidoDelEspejo` se sustituye para quedarse con el `PedidoParaGuardar`: es
// exactamente lo que el espejo recibe, así que de ahí sale la fila sin necesitar un Postgres.
func loteDeUnPedido(t *testing.T, sucursales []SucursalConAlmacenes, cuerpo string) (baseDelLote, PedidoParaGuardar) {
	t.Helper()
	conAccesos(t, &accesosFalso{sucursales: sucursales})

	var escrito PedidoParaGuardar
	visto := false
	antes := GuardarPedidoDelEspejo
	t.Cleanup(func() { GuardarPedidoDelEspejo = antes })
	GuardarPedidoDelEspejo = func(_ context.Context, _ *alcance.Acotado, p PedidoParaGuardar) (uuid.UUID, error) {
		escrito, visto = p, true
		return uuid.New(), nil
	}

	h := montarCotizacion(t, &dobleDelOrigen{})
	r := httptest.NewRequest(http.MethodPost, "/api/quote/batch", strings.NewReader(cuerpo))
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("X-Api-Key", claveDeServicioDePrueba)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("la puerta contestó %d: %s", w.Code, w.Body.String())
	}
	var salida struct {
		Results []baseDelLote `json:"results"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatalf("la respuesta no se entiende: %v — %s", err, w.Body.String())
	}
	if len(salida.Results) != 1 {
		t.Fatalf("se esperaba 1 resultado y hubo %d: %s", len(salida.Results), w.Body.String())
	}
	if !visto {
		t.Fatalf("el pedido NO se escribió: %s", w.Body.String())
	}
	return salida.Results[0], escrito
}

// pedidoConAlmacen arma el cuerpo del lote con el bloque `almacen` puesto o sin él.
//
// Se escribe como JSON A MANO y no construyendo las estructuras de Go: lo que hay que probar
// es que el campo se LEE del cuerpo que manda PEDIDO. Con structs, un `json:"..."` mal escrito
// —o cambiado mañana— dejaría la prueba verde y el campo sin llegar nunca.
func pedidoConAlmacen(almacen string) string {
	renglon := `{"code":"PARR0004","name":"Malta","quantity":120,"packs":20,` +
		`"pesoKg":1.2,"pesoLineaKg":24,"almacenCodigo":"2","almacenNombre":"AURORA"}`
	if almacen == "" {
		almacen = "null"
	}
	return fmt.Sprintf(`{"orders":[{
		"externalId":"ped-1","operationNumber":"X-2992","sucursalExternalId":"STG",
		"customerName":"Bodega La Esquina","address":"Calle 4",
		"lat":%v,"lng":%v,"requiereDomicilio":true,
		"items":[%s],"almacen":%s
	}]}`, latCliente, lngCliente, renglon, almacen)
}

// --------------------------------------------------------------------------- la pareja

// LA PAREJA COMPLETA: con almacén se mide desde él, y SIN almacén desde el principal.
func TestSeMideDesdeElAlmacenDelPedidoYSinElDesdeElPrincipal(t *testing.T) {
	kmDesde := func(lat, lng float64) float64 {
		return cotizar.DistanciaHaversineKm(lat, lng, latCliente, lngCliente)
	}

	casos := []struct {
		nombre  string
		almacen string
		quiere  float64
		desde   string
		motivo  cotizar.MotivoDelOrigen
		porQue  string
	}{
		{
			nombre:  "el pedido sale de AURORA: se mide desde AURORA",
			almacen: `{"codigo":"2","nombre":"AURORA","sucursalCodigo":"STG","mezclado":false}`,
			quiere:  kmDesde(latAURORA, lngAURORA), desde: "AURORA",
			motivo: cotizar.MotivoAlmacenDelPedido,
			porQue: "es el fallo del 26/09/2026: en Santiago dos de cada tres pedidos salen " +
				"de AURORA y se medían desde PV-STGO",
		},
		{
			nombre:  "el pedido no trae almacén: se sigue midiendo desde el PRINCIPAL",
			almacen: "",
			quiere:  kmDesde(latPVSTGO, lngPVSTGO), desde: "PV-STGO",
			motivo: cotizar.MotivoPedidoSinAlmacen,
			porQue: "son los 5.480 pedidos que hay hoy en producción. Esta mitad es la que " +
				"se olvida, y sin ella «mide desde el almacén» se cumple rompiéndolos todos",
		},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			res, escrito := loteDeUnPedido(t, almacenesDeSantiagoDeAccesos(),
				pedidoConAlmacen(c.almacen))

			// 1. LO QUE SALE: los kilómetros de la respuesta.
			if !cercaDe(res.DistanceKm, c.quiere) {
				t.Errorf("distanceKm = %.4f y tenía que ser %.4f (desde %s)\n"+
					"  por qué importa: %s", res.DistanceKm, c.quiere, c.desde, c.porQue)
			}
			// Y NO desde el punto de la sucursal, que es lo que hacía antes. Está puesto a
			// 19,-74 en el doble: unos 200 km, así que un despiste aquí no pasa inadvertido.
			if cercaDe(res.DistanceKm, kmDesde(19.0, -74.0)) {
				t.Errorf("se midió desde el punto de la SUCURSAL (%.1f km): eso es el último "+
					"recurso, y aquí había almacenes con coordenadas", res.DistanceKm)
			}
			// 2. QUÉ DICE QUE HIZO. Sin el motivo, un kilometraje medido desde el principal
			//    es indistinguible de uno bueno.
			if res.AlmacenMotivo != string(c.motivo) {
				t.Errorf("almacenMotivo = %q, se esperaba %q", res.AlmacenMotivo, c.motivo)
			}
			if res.AlmacenDesde == nil || *res.AlmacenDesde != c.desde {
				t.Errorf("almacenDesde = %v, se esperaba %q", res.AlmacenDesde, c.desde)
			}
			// 3. LO QUE SE ESCRIBE. La fila, por `paraLaBase`, que es la que va a Postgres.
			fila := paraLaBase(escrito)
			if fila.AlmacenSalidaMotivo == nil || *fila.AlmacenSalidaMotivo != string(c.motivo) {
				t.Errorf("almacen_salida_motivo en la fila = %v, se esperaba %q",
					fila.AlmacenSalidaMotivo, c.motivo)
			}
			if fila.DeliveryDistanceKm == nil || !cercaDe(*fila.DeliveryDistanceKm, c.quiere) {
				t.Errorf("delivery_distance_km de la fila = %v y la respuesta dijo %.4f: "+
					"la pantalla y la base contarían cosas distintas",
					fila.DeliveryDistanceKm, res.DistanceKm)
			}
		})
	}
}

// --------------------------------------------------------------------------- lo que se guarda

// EL ALMACÉN SE GUARDA, Y POR RENGLÓN TAMBIÉN.
//
// Y NO EN `almacen_nombre`: esa columna existe desde la 00004 y, a pesar del nombre, lleva
// `RenglonPesado.WhName`, o sea el nombre del PRODUCTO con el que casó el catálogo local de
// pesos. Meter un almacén ahí dejaría a quien busca un producto leyendo «AURORA». Esta prueba
// fija las dos cosas: que lo nuevo se escribe en `almacen_salida_*` y que lo viejo NO se pisa.
func TestElAlmacenSeGuardaEnSusColumnasYNoEnLaDelProducto(t *testing.T) {
	_, escrito := loteDeUnPedido(t, almacenesDeSantiagoDeAccesos(),
		pedidoConAlmacen(`{"codigo":"2","nombre":"AURORA","sucursalCodigo":"STG","mezclado":true}`))

	fila := paraLaBase(escrito)
	for nombre, par := range map[string][2]any{
		"almacen_salida_codigo":   {fila.AlmacenSalidaCodigo, "2"},
		"almacen_salida_nombre":   {fila.AlmacenSalidaNombre, "AURORA"},
		"almacen_salida_sucursal": {fila.AlmacenSalidaSucursal, "STG"},
	} {
		v, _ := par[0].(*string)
		if v == nil || *v != par[1].(string) {
			t.Errorf("%s = %v, se esperaba %q", nombre, v, par[1])
		}
	}
	// `mezclado` es la señal de que ese pedido son DOS recogidas: si se pierde, quien
	// despacha va a AURORA y se deja media carga en PV-STGO.
	if fila.AlmacenSalidaMezclado == nil || !*fila.AlmacenSalidaMezclado {
		t.Errorf("almacen_salida_mezclado = %v y el pedido venía mezclado",
			fila.AlmacenSalidaMezclado)
	}

	// EL RENGLÓN. Con sólo el del pedido, las 804 líneas de PV-STGO de Santiago quedarían
	// apuntadas como de AURORA, que es el que más renglones pone.
	renglones := renglonesParaLaBase(escrito.Renglones)
	if len(renglones) != 1 {
		t.Fatalf("se esperaba 1 renglón y hubo %d", len(renglones))
	}
	r := renglones[0]
	if r.AlmacenSalidaCodigo == nil || *r.AlmacenSalidaCodigo != "2" {
		t.Errorf("el renglón perdió su almacén: %v", r.AlmacenSalidaCodigo)
	}
	if r.AlmacenSalidaNombre == nil || *r.AlmacenSalidaNombre != "AURORA" {
		t.Errorf("el renglón perdió el nombre de su almacén: %v", r.AlmacenSalidaNombre)
	}
	// Y LA COLUMNA VIEJA SIGUE SIENDO DEL PRODUCTO. Aquí no hubo catálogo local —PEDIDO
	// mandó los pesos—, así que `WhName` es nil y `almacen_nombre` tiene que quedar nula.
	// Si algún día sale «AURORA» de aquí, es que se reutilizó la columna equivocada.
	if r.AlmacenNombre != nil {
		t.Errorf("almacen_nombre = %q: esa columna es el nombre del PRODUCTO del catálogo, "+
			"no un almacén", *r.AlmacenNombre)
	}
}

// --------------------------------------------------------------------------- el desconocido

// UN ALMACÉN QUE NO ESTÁ DADO DE ALTA NO SE DESCARTA NI SE SUSTITUYE A ESCONDIDAS.
//
// `28 · PTO MONEDERO` existe de verdad: el 26/09/2026 tenía 11 líneas en Santiago. Es la regla
// dura de la casa (`CLAUDE.md` §4) y se cumple con TRES cosas a la vez, no con una:
//
//  1. el pedido entra (no se pierde);
//  2. su código Y su nombre quedan guardados tal cual, que es lo único con lo que alguien
//     puede darlo de alta después;
//  3. queda dicho que se midió desde el principal Y POR QUÉ.
//
// Guardar el código sin el motivo es descartarlo en silencio con el dato puesto: el
// kilometraje sale del principal, es creíble, y nada lo desmiente.
func TestUnAlmacenDesconocidoSeGuardaYSeDice(t *testing.T) {
	res, escrito := loteDeUnPedido(t, almacenesDeSantiagoDeAccesos(),
		pedidoConAlmacen(`{"codigo":"28","nombre":"PTO MONEDERO","sucursalCodigo":"STG","mezclado":false}`))

	fila := paraLaBase(escrito)
	// 1. No se perdió, y se midió desde el principal — que es lo único que se puede hacer.
	quiere := cotizar.DistanciaHaversineKm(latPVSTGO, lngPVSTGO, latCliente, lngCliente)
	if !cercaDe(res.DistanceKm, quiere) {
		t.Errorf("distanceKm = %.4f, se esperaba %.4f (desde el principal)",
			res.DistanceKm, quiere)
	}
	// 2. El código y el nombre, tal cual llegaron.
	if fila.AlmacenSalidaCodigo == nil || *fila.AlmacenSalidaCodigo != "28" {
		t.Errorf("se perdió el código del almacén desconocido: %v", fila.AlmacenSalidaCodigo)
	}
	if fila.AlmacenSalidaNombre == nil || *fila.AlmacenSalidaNombre != "PTO MONEDERO" {
		t.Errorf("se perdió el nombre del almacén desconocido: %v — sin él lo que queda "+
			"apuntado es un «28» que no le dice nada a nadie", fila.AlmacenSalidaNombre)
	}
	// 3. Y el motivo lo dice, en la fila y en la respuesta que lee PEDIDO.
	if fila.AlmacenSalidaMotivo == nil ||
		*fila.AlmacenSalidaMotivo != string(cotizar.MotivoAlmacenNoDadoDeAlta) {
		t.Errorf("almacen_salida_motivo = %v, se esperaba %q: sin el motivo, este "+
			"kilometraje es indistinguible de uno bueno",
			fila.AlmacenSalidaMotivo, cotizar.MotivoAlmacenNoDadoDeAlta)
	}
	if res.AlmacenMotivo != string(cotizar.MotivoAlmacenNoDadoDeAlta) {
		t.Errorf("la respuesta no se lo dice a PEDIDO: almacenMotivo = %q", res.AlmacenMotivo)
	}
}

// --------------------------------------------------------------------------- sin coordenadas

// UN ALMACÉN SIN COORDENADAS SE SALTA Y SE MIDE CON EL QUE LAS TENGA, Y NO REVIENTA NADA.
//
// ES EL CAMINO DE ESTA SEMANA Y NO UN CASO RARO: los 6 almacenes nuevos se dieron de alta SIN
// punto a propósito —los ponen los logísticos— así que durante unos días el dato llega antes
// que las coordenadas. Eso es lo normal.
func TestUnAlmacenSinCoordenadasNoRompeNada(t *testing.T) {
	cod1, cod2 := "1", "2"
	lat1, lng1 := latPVSTGO, lngPVSTGO
	sucursales := []SucursalConAlmacenes{{
		Codigo: "STG", Nombre: "Santiago",
		Almacenes: []Almacen{
			{ID: &cod1, Codigo: &cod1, Nombre: "PV-STGO", Latitud: &lat1, Longitud: &lng1,
				Principal: true, Activo: true},
			// AURORA recién dada de alta y todavía sin punto.
			{ID: &cod2, Codigo: &cod2, Nombre: "AURORA", Activo: true},
		},
	}}

	res, escrito := loteDeUnPedido(t, sucursales,
		pedidoConAlmacen(`{"codigo":"2","nombre":"AURORA","sucursalCodigo":"STG","mezclado":false}`))

	quiere := cotizar.DistanciaHaversineKm(latPVSTGO, lngPVSTGO, latCliente, lngCliente)
	if !cercaDe(res.DistanceKm, quiere) {
		t.Errorf("distanceKm = %.4f, se esperaba %.4f: un almacén sin punto se salta y se "+
			"mide desde el que lo tenga", res.DistanceKm, quiere)
	}
	if res.AlmacenMotivo != string(cotizar.MotivoAlmacenSinCoordenadas) {
		t.Errorf("almacenMotivo = %q, se esperaba %q", res.AlmacenMotivo,
			cotizar.MotivoAlmacenSinCoordenadas)
	}
	// Y el almacén que trae el pedido se guarda IGUAL: mañana le ponen el punto y hace falta
	// saber cuáles eran suyos.
	fila := paraLaBase(escrito)
	if fila.AlmacenSalidaCodigo == nil || *fila.AlmacenSalidaCodigo != "2" {
		t.Errorf("se perdió el almacén del pedido por no tener punto: %v",
			fila.AlmacenSalidaCodigo)
	}
}

// Y CUANDO NO HAY NI UN ALMACÉN CON PUNTO, el pedido entra igual y se dice con otras palabras.
//
// Aquí NO se puede contestar 409 como hace `/api/quote/home-delivery`: esto es LA PUERTA de los
// pedidos y rechazar uno es perderlo. Se mide desde el punto de la sucursal —que no es el sitio
// del que sale la carga— y el motivo lo dice COMPUESTO, porque son dos preguntas: desde dónde
// se midió, y qué pasó con el almacén que traía el pedido.
func TestSinNingunAlmacenConPuntoElPedidoEntraYSeDice(t *testing.T) {
	cod1 := "1"
	sucursales := []SucursalConAlmacenes{{
		Codigo: "STG", Nombre: "Santiago",
		Almacenes: []Almacen{
			{ID: &cod1, Codigo: &cod1, Nombre: "PV-STGO", Principal: true, Activo: true},
		},
	}}

	res, escrito := loteDeUnPedido(t, sucursales,
		pedidoConAlmacen(`{"codigo":"28","nombre":"PTO MONEDERO","sucursalCodigo":"STG","mezclado":false}`))

	// Se midió desde el punto de la sucursal (19,-74 en el doble), que es el último recurso.
	quiere := cotizar.DistanciaHaversineKm(19.0, -74.0, latCliente, lngCliente)
	if !cercaDe(res.DistanceKm, quiere) {
		t.Errorf("distanceKm = %.4f, se esperaba %.4f (el punto de la sucursal)",
			res.DistanceKm, quiere)
	}
	if res.AlmacenDesde != nil {
		t.Errorf("dice que midió desde el almacén %q y no había ninguno con punto",
			*res.AlmacenDesde)
	}
	// EL MOTIVO COMPUESTO. Con sólo «la sucursal no tiene almacén», el `28` desconocido no
	// aparecería como desconocido en ninguna parte y nadie lo daría de alta.
	fila := paraLaBase(escrito)
	quiereMotivo := string(cotizar.MotivoSucursalSinAlmacen) + "+" +
		string(cotizar.MotivoAlmacenNoDadoDeAlta)
	if fila.AlmacenSalidaMotivo == nil || *fila.AlmacenSalidaMotivo != quiereMotivo {
		t.Errorf("almacen_salida_motivo = %v, se esperaba %q: el motivo tiene que decir las "+
			"DOS cosas o se pierde el almacén desconocido", fila.AlmacenSalidaMotivo, quiereMotivo)
	}
}

// ACCESOS CAÍDO NO TUMBA EL LOTE, y tampoco miente sobre por qué.
//
// `/api/quote/home-delivery` trata el fallo de Accesos como lista vacía y acaba en un 409: ahí
// es lo correcto, porque un importe aproximado se cobra igual que uno bueno. Aquí no: un lote
// rechazado son pedidos perdidos.
func TestAccesosCaidoNoTumbaElLote(t *testing.T) {
	conAccesos(t, &accesosFalso{fallo: errAccesosCaido})

	var escrito PedidoParaGuardar
	antes := GuardarPedidoDelEspejo
	t.Cleanup(func() { GuardarPedidoDelEspejo = antes })
	GuardarPedidoDelEspejo = func(_ context.Context, _ *alcance.Acotado, p PedidoParaGuardar) (uuid.UUID, error) {
		escrito = p
		return uuid.New(), nil
	}

	h := montarCotizacion(t, &dobleDelOrigen{})
	r := httptest.NewRequest(http.MethodPost, "/api/quote/batch",
		strings.NewReader(pedidoConAlmacen(
			`{"codigo":"2","nombre":"AURORA","sucursalCodigo":"STG","mezclado":false}`)))
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("X-Api-Key", claveDeServicioDePrueba)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("con Accesos caído la puerta contestó %d: un lote rechazado son pedidos "+
			"perdidos — %s", w.Code, w.Body.String())
	}
	if escrito.ExternalID == nil {
		t.Fatal("con Accesos caído el pedido no se escribió")
	}
	// Y el almacén que traía queda guardado: cuando Accesos vuelva, el espejo repasa y se
	// vuelve a medir bien. Lo que no puede pasar es que ese dato se tire por el camino.
	fila := paraLaBase(escrito)
	if fila.AlmacenSalidaCodigo == nil || *fila.AlmacenSalidaCodigo != "2" {
		t.Errorf("se perdió el almacén del pedido porque Accesos no contestó: %v",
			fila.AlmacenSalidaCodigo)
	}
}

// --------------------------------------------------------------------------- el filtro de km

// MOVER EL ORIGEN CAMBIA QUÉ SE VE, no sólo cuánto mide. Es la consecuencia que no se ve venir.
//
// `GET /api/orders` descarta los pedidos que pasan de `kmMax` (`pasaElTopeDeKm`, en
// `pedidos.go`). Al medir desde AURORA en vez de desde PV-STGO, un pedido de Santiago se mueve
// ~20 km, así que **cruza el umbral**: un pedido que hoy sale en la lista del armador puede
// dejar de salir tras el despliegue, y al revés. Eso no es «el número mejoró»: es una lista que
// cambia de contenido, y quien la mire no va a tener nada que se lo diga.
//
// LO QUE ESTA PRUEBA NO CUBRE, y hay que saberlo: que la pantalla lo avise. No lo avisa. Queda
// escrito como pendiente.
func TestElFiltroDeKmSeMueveConElOrigen(t *testing.T) {
	desdePrincipal, _ := loteDeUnPedido(t, almacenesDeSantiagoDeAccesos(), pedidoConAlmacen(""))
	desdeAurora, _ := loteDeUnPedido(t, almacenesDeSantiagoDeAccesos(), pedidoConAlmacen(
		`{"codigo":"2","nombre":"AURORA","sucursalCodigo":"STG","mezclado":false}`))

	// El mismo cliente, el mismo pedido, y veinte kilómetros de diferencia.
	if desdeAurora.DistanceKm-desdePrincipal.DistanceKm < 15 {
		t.Fatalf("la diferencia es de %.2f km: el origen no se movió",
			desdeAurora.DistanceKm-desdePrincipal.DistanceKm)
	}

	// Y AHORA EL FILTRO DE VERDAD, el mismo que usa `GET /api/orders`. Con «Hasta 10 km» el
	// pedido medido desde el principal sale en la lista y el medido desde AURORA no.
	const tope = 10.0
	if !pasaElTopeDeKm(&desdePrincipal.DistanceKm, tope, true) {
		t.Errorf("medido desde el principal (%.2f km) el pedido ya no pasaba el tope de %.0f: "+
			"revisa las coordenadas de la prueba", desdePrincipal.DistanceKm, tope)
	}
	if pasaElTopeDeKm(&desdeAurora.DistanceKm, tope, true) {
		t.Errorf("medido desde AURORA (%.2f km) el pedido sigue pasando el tope de %.0f: "+
			"entonces esta prueba no está comprobando el cambio de lista",
			desdeAurora.DistanceKm, tope)
	}

	// LA OTRA MITAD DEL FILTRO, que es la que se olvida: sin tope y sin distancia medida, el
	// pedido SIEMPRE sale. No saber cuánto hay no es estar lejos, y dejarlo fuera esconde
	// justo los que hay que mirar a mano.
	if !pasaElTopeDeKm(nil, tope, true) {
		t.Error("un pedido SIN distancia medida se quedó fuera del «Hasta N km»")
	}
	if !pasaElTopeDeKm(&desdeAurora.DistanceKm, 0, false) {
		t.Error("sin tope puesto se filtró igual")
	}
}

// --------------------------------------------------------------------------- lo que viaja

// EL CAMPO LLEGA DESDE PEDIDO HASTA LA PUERTA, por el traductor de verdad.
//
// `espejo.ArmarLote` es el MISMO traductor que usan el ciclo y el webhook (`webhook_de_pedido.go`
// lo dice: la puerta de los pedidos es una sola). Si el almacén se cayera ahí, todo lo de arriba
// seguiría verde —esas pruebas entran por la puerta con el JSON ya hecho— y en producción no
// llegaría nunca. Ésta es la otra mitad del camino.
func TestElAlmacenLlegaDesdePedidoHastaLaPuerta(t *testing.T) {
	mezclado := true
	lote := espejo.ArmarLote([]espejo.PedidoDeFuera{{
		ID: "ped-1", SucursalCodigo: "STG",
		Cliente: &espejo.ClienteDelPedido{Nombre: "Bodega", Latitud: num64(latCliente),
			Longitud: num64(lngCliente)},
		Almacen: &espejo.AlmacenDelPedido{
			Codigo: "2", Nombre: "AURORA", SucursalCodigo: "STG", Mezclado: &mezclado,
		},
		Items: []espejo.RenglonDeFuera{{
			Codigo: "PARR0004", Producto: "Malta",
			AlmacenCodigo: "2", AlmacenNombre: "AURORA",
		}},
	}})

	crudo, err := json.Marshal(lote)
	if err != nil {
		t.Fatalf("no se pudo serializar el lote: %v", err)
	}
	// Se lee con la estructura DE LA PUERTA, no con la del espejo: lo que importa es que los
	// nombres de los campos cuadren entre los dos lados. Con la misma estructura en los dos
	// extremos, un `json:"..."` cambiado a la vez en ambos pasaría inadvertido.
	var puerta struct {
		Orders []pedidoDelLote `json:"orders"`
	}
	if err := json.Unmarshal(crudo, &puerta); err != nil {
		t.Fatalf("la puerta no entiende el lote: %v — %s", err, crudo)
	}
	p := puerta.Orders[0]
	if p.Almacen == nil {
		t.Fatalf("el almacén no llegó a la puerta: %s", crudo)
	}
	if p.Almacen.Codigo != "2" || p.Almacen.Nombre != "AURORA" || p.Almacen.SucursalCodigo != "STG" {
		t.Errorf("el almacén llegó cambiado: %+v", *p.Almacen)
	}
	if p.Almacen.Mezclado == nil || !*p.Almacen.Mezclado {
		t.Errorf("se perdió el `mezclado`: %v", p.Almacen.Mezclado)
	}
	if len(p.Items) != 1 || p.Items[0].AlmacenCodigo != "2" || p.Items[0].AlmacenNombre != "AURORA" {
		t.Errorf("el almacén del renglón no llegó: %+v", p.Items)
	}
}

// --------------------------------------------------------------------------- ayudas

func num64(v float64) *float64 { return &v }

// cercaDe compara kilómetros con una tolerancia de un metro. Se comparan flotantes que han
// pasado por JSON, así que la igualdad exacta es una prueba que falla un día cualquiera por
// el último bit — y entonces nadie se la cree y se borra.
func cercaDe(a, b float64) bool {
	d := a - b
	return d > -0.001 && d < 0.001
}

// ---------------------------------------------------------------------------
// EL IMPORTE: `POST /api/quote/home-delivery`
// ---------------------------------------------------------------------------

// LA ÚNICA CUENTA DE DINERO DE ESTA API, y hasta el 26/09/2026 medía siempre desde el
// principal de la sucursal.
//
// # Por qué esto era lo más grave del cambio
//
// El lote arregla `delivery_distance_km`, que es lo que se ENSEÑA. El importe que se COBRA sale
// de aquí: la APK de Entrega pide esta ruta, se queda con el número y lo guarda en PEDIDO como
// `costoDomicilio`; el espejo lo trae de vuelta a `orders.pedido_costo` y acaba **en la misma
// tarjeta** que el kilometraje. Si esta ruta se hubiera quedado midiendo desde el principal, en
// Santiago los 2.185 renglones de AURORA tendrían un kilometraje bueno al lado de un importe
// calculado desde PV-STGO: dos números que no se pueden conciliar y ninguna pantalla diciendo
// cuál mandar. Antes del cambio los dos estaban mal y al menos coincidían — eso es PEOR de
// leer que el fallo original, y es el §3-bis del `CLAUDE.md` en su forma más cara.
//
// # Y SIN `almacenCodigo` NO CAMBIA NADA
//
// El campo es opcional: quien no lo mande —la APK de Entrega instalada hoy— sigue recibiendo
// exactamente lo de siempre. Por eso esta prueba va EN PAREJA, y la segunda mitad es la que
// impide que este despliegue cambie los importes de nadie por sorpresa.
func TestElImporteSeMideDesdeElAlmacenQueSePideYSiNoDesdeElPrincipal(t *testing.T) {
	casos := []struct {
		nombre  string
		almacen string // el `almacenCodigo` del cuerpo; "" = no se manda
		desde   string
		codigo  string
		motivo  cotizar.MotivoDelOrigen
		lat     float64
		lng     float64
		porQue  string
	}{
		{
			nombre: "con almacenCodigo se cobra desde ESE almacén", almacen: `,"almacenCodigo":"2"`,
			desde: "AURORA", codigo: "2", motivo: cotizar.MotivoAlmacenDelPedido,
			lat: latAURORA, lng: lngAURORA,
			porQue: "en Santiago dos de cada tres pedidos salen de AURORA y se cobraban " +
				"desde PV-STGO",
		},
		{
			nombre: "sin almacenCodigo se cobra desde el principal, como siempre", almacen: "",
			desde: "PV-STGO", codigo: "1", motivo: cotizar.MotivoPedidoSinAlmacen,
			lat: latPVSTGO, lng: lngPVSTGO,
			porQue: "la APK de Entrega instalada hoy no manda el campo: este despliegue NO " +
				"puede cambiarle los importes por sorpresa",
		},
		{
			nombre:  "un almacén que no está dado de alta se cobra desde el principal Y SE DICE",
			almacen: `,"almacenCodigo":"28"`,
			desde:   "PV-STGO", codigo: "1", motivo: cotizar.MotivoAlmacenNoDadoDeAlta,
			lat: latPVSTGO, lng: lngPVSTGO,
			porQue: "es el `28 · PTO MONEDERO` de Santiago. No se contesta 409 —hay un número " +
				"que dar, sólo que peor— pero el que cobra tiene que poder saber cuál tiene delante",
		},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			res := domicilioDePrueba(t, c.almacen)

			quiere := cotizar.DistanciaHaversineKm(c.lat, c.lng, latCliente, lngCliente)
			if !cercaDe(res.DistanciaKm, quiere) {
				t.Errorf("distanciaKm = %.4f y tenía que ser %.4f (desde %s)\n"+
					"  por qué importa: %s", res.DistanciaKm, quiere, c.desde, c.porQue)
			}
			if res.Almacen == nil || *res.Almacen != c.desde {
				t.Errorf("almacen = %v, se esperaba %q", res.Almacen, c.desde)
			}
			if res.AlmacenCodigo == nil || *res.AlmacenCodigo != c.codigo {
				t.Errorf("almacenCodigo = %v, se esperaba %q", res.AlmacenCodigo, c.codigo)
			}
			if res.AlmacenMotivo != string(c.motivo) {
				t.Errorf("almacenMotivo = %q, se esperaba %q: sin el motivo, un importe "+
					"cobrado desde el principal es indistinguible de uno bueno",
					res.AlmacenMotivo, c.motivo)
			}
			// EL `desde` TIENE QUE DISTINGUIR LOS DOS ORÍGENES. Su propio comentario prometía
			// que «si mañana se midiera desde otro punto, los importes viejos siguen
			// explicándose solos», y decía `almacen:STG` para los dos: dos importes medidos
			// desde PV-STGO y desde AURORA quedaban indistinguibles en el histórico de PEDIDO,
			// que es donde viven los importes cobrados.
			quiereDesde := "almacen:" + codigoDeLaSucursalDePrueba + ":" + c.codigo
			if res.Desde != quiereDesde {
				t.Errorf("desde = %q, se esperaba %q", res.Desde, quiereDesde)
			}
		})
	}
}

// Y EL IMPORTE SE MUEVE DE VERDAD. Lo de arriba comprueba los kilómetros y las etiquetas; esto
// comprueba que el número que alguien cobra sale distinto, que es todo el motivo del cambio.
func TestElImporteCambiaSegunElAlmacen(t *testing.T) {
	desdePrincipal := domicilioDePrueba(t, "")
	desdeAurora := domicilioDePrueba(t, `,"almacenCodigo":"2"`)

	if !(desdeAurora.CUP > desdePrincipal.CUP) {
		t.Fatalf("desde el principal %.2f CUP y desde AURORA %.2f CUP: el importe no se movió, "+
			"así que se está cobrando desde el mismo sitio las dos veces",
			desdePrincipal.CUP, desdeAurora.CUP)
	}
	// Los dos almacenes están a más de 15 km: con la misma tarifa y el mismo peso, el importe
	// tiene que subir en proporción. Si la diferencia fuera de céntimos, es que se midió casi
	// desde el mismo punto.
	if desdeAurora.CUP/desdePrincipal.CUP < 2 {
		t.Fatalf("el importe sólo pasó de %.2f a %.2f CUP con veinte kilómetros de diferencia",
			desdePrincipal.CUP, desdeAurora.CUP)
	}
}

// domicilioDePrueba pide un domicilio y devuelve la respuesta ya leída.
//
// Usa un código de sucursal PROPIO (`HDX`) y no `STG`: `recuerdoDeTasas` es una caché de
// paquete que vive entre pruebas, así que compartir el código con otra prueba haría que ésta
// pasara o fallara según el orden en que se corran — que es la peor clase de prueba que hay.
func domicilioDePrueba(t *testing.T, almacen string) domicilioSalida {
	t.Helper()
	conAccesos(t, &accesosFalso{sucursales: almacenesDePruebaDelImporte()})
	conTasaDePrueba(t)

	h := montarCotizacion(t, &dobleDelImporte{})
	cuerpo := fmt.Sprintf(`{"sucursalCodigo":%q,"lat":%v,"lng":%v,"pesoKg":10%s}`,
		codigoDeLaSucursalDePrueba, latCliente, lngCliente, almacen)
	r := httptest.NewRequest(http.MethodPost, "/api/quote/home-delivery", strings.NewReader(cuerpo))
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("X-Api-Key", claveDeServicioDePrueba)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, r)

	if w.Code != http.StatusOK {
		t.Fatalf("el domicilio contestó %d: %s", w.Code, w.Body.String())
	}
	var res domicilioSalida
	if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
		t.Fatalf("la respuesta no se entiende: %v — %s", err, w.Body.String())
	}
	return res
}

const codigoDeLaSucursalDePrueba = "HDX"

func almacenesDePruebaDelImporte() []SucursalConAlmacenes {
	s := almacenesDeSantiagoDeAccesos()
	s[0].Codigo = codigoDeLaSucursalDePrueba
	return s
}

// conTasaDePrueba pone una tasa y una tarifa fijas para esa sucursal.
//
// SIN TASA LA RUTA CONTESTA 409 y no se llega a medir nada: la tasa es POR SUCURSAL y no se cae
// a la de otra ni a un número por defecto (`CLAUDE.md` §4).
func conTasaDePrueba(t *testing.T) {
	t.Helper()
	antes := Tasas
	t.Cleanup(func() { Tasas = antes })
	Tasas = tasaFijaDePrueba{}
	// El recuerdo de tasas es de paquete y guarda 5 minutos; se apunta al doble para que no
	// conteste con lo que dejó otra prueba.
	antesRec := recuerdoDeTasas
	t.Cleanup(func() { recuerdoDeTasas = antesRec })
	recuerdoDeTasas = cotizar.NuevoRecuerdoDeTasas(func(ctx context.Context, codigo string) (*cotizar.Tasa, error) {
		return Tasas.TasaDeSucursal(ctx, codigo)
	}, nil)
}

type tasaFijaDePrueba struct{}

func (tasaFijaDePrueba) TasaDeSucursal(_ context.Context, codigo string) (*cotizar.Tasa, error) {
	tarifa := 15.0
	return &cotizar.Tasa{
		Codigo: codigo, CupPorUsd: 400, TarifaBase: &tarifa,
		Fuente: nil, TraidoAt: "2026-09-26T10:00:00Z", Fresca: true,
	}, nil
}

// dobleDelImporte: la sucursal de la cuenta de dinero, con su código propio.
type dobleDelImporte struct{ sqlc.Querier }

func (d *dobleDelImporte) ListarSucursales(context.Context, pgtype.UUID) ([]sqlc.ListarSucursalesRow, error) {
	c := codigoDeLaSucursalDePrueba
	return []sqlc.ListarSucursalesRow{{
		ID: stgDelAlmacen, Name: "Sucursal de pruebas", ExternalID: &c,
		Lat: 19.0, Lng: -74.0, OriginConfigured: true,
	}}, nil
}

// UN `mezclado` QUE NO LLEGA SE GUARDA VACÍO, NO EN «NO».
//
// Es la otra punta de `TestUnAlmacenSinMezcladoNoAfirmaQueNoLoEsta` (en `internal/espejo`): allí
// se fija que el espejo no lo INVENTA, y aquí que la puerta no lo RELLENA. Las dos hacen falta,
// porque un `false` puesto en cualquiera de los dos sitios acaba igual en la base.
//
// LO QUE ESO CUESTA: un pedido de Santiago con seis renglones de AURORA y seis de PV-STGO.
// PEDIDO resuelve el desempate y manda `codigo: "2"`, pero una versión suya que todavía no mande
// `mezclado` dejaría guardado «no está mezclado». Nadie sabe que son DOS recogidas, ninguna
// pantalla lo desmiente, y el que despacha va a AURORA y se deja media carga en PV-STGO. Un NULL
// dice «no se sabe»; un `false` dice «comprobado que no», y es mentira.
//
// LA PAREJA: ausente es NULL, y presente viaja tal cual — los dos valores, porque «no afirma de
// más» también se cumple tirando el campo siempre, y entonces un pedido de dos recogidas nunca
// se marca.
func TestUnMezcladoQueNoLlegaSeGuardaVacio(t *testing.T) {
	casos := []struct {
		nombre  string
		almacen string
		quiere  *bool
	}{
		{
			nombre:  "sin `mezclado` la columna queda VACÍA",
			almacen: `{"codigo":"2","nombre":"AURORA","sucursalCodigo":"STG"}`,
			quiere:  nil,
		},
		{
			nombre:  "con `mezclado: true` se guarda que sí",
			almacen: `{"codigo":"2","nombre":"AURORA","sucursalCodigo":"STG","mezclado":true}`,
			quiere:  siDePrueba(),
		},
		{
			nombre:  "con `mezclado: false` se guarda que no",
			almacen: `{"codigo":"2","nombre":"AURORA","sucursalCodigo":"STG","mezclado":false}`,
			quiere:  noDePrueba(),
		},
		{
			nombre:  "y sin bloque `almacen` tampoco se afirma nada",
			almacen: "",
			quiere:  nil,
		},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			_, escrito := loteDeUnPedido(t, almacenesDeSantiagoDeAccesos(),
				pedidoConAlmacen(c.almacen))
			fila := paraLaBase(escrito)

			switch {
			case c.quiere == nil && fila.AlmacenSalidaMezclado != nil:
				t.Fatalf("almacen_salida_mezclado = %v y nadie lo dijo: eso AFIRMA algo que "+
					"nadie comprobó, y si es `false` manda al que despacha a UN almacén a por "+
					"mercancía que está en dos", *fila.AlmacenSalidaMezclado)
			case c.quiere != nil && fila.AlmacenSalidaMezclado == nil:
				t.Fatalf("PEDIDO dijo mezclado=%v y la columna quedó vacía: un pedido de dos "+
					"recogidas no se marca nunca", *c.quiere)
			case c.quiere != nil && *fila.AlmacenSalidaMezclado != *c.quiere:
				t.Fatalf("almacen_salida_mezclado = %v, se esperaba %v",
					*fila.AlmacenSalidaMezclado, *c.quiere)
			}
		})
	}
}

func siDePrueba() *bool { v := true; return &v }
func noDePrueba() *bool { v := false; return &v }
