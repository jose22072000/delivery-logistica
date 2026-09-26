package espejo

import (
	"context"
	"net/url"
	"strconv"
	"strings"
)

// ATENDER LO QUE PEDIDO AVISA: traer lo que hace falta y quitar lo que ya no está.
//
// Esto es lo que corre cuando entra una tanda de avisos por el stream. Lo que decide QUÉ
// hay que traer es [AgruparAvisos]; esto va a buscarlo.
//
// NO SE INVENTA NINGUNA PUERTA NUEVA: se piden por donde ya se piden hoy —el mismo
// `/integration/orders` con sus filtros— y se guardan por donde ya se guardan. El aviso
// dice QUÉ MIRAR; los datos salen de la misma fuente de siempre, así que se ve el estado de
// PEDIDO **cuando se lee**, no la foto de hace diez minutos.

// TopeDeIDsPorTanda: cuántos ids caben en una petición.
//
// Los avisos vienen agrupados, así que cien de la misma sucursal son UNA petición y no
// cien. Pero una lista de ids no puede crecer sin fin: va en la URL, y una URL demasiado
// larga la corta el proxy sin decir nada — que es el fallo que no se ve.
const TopeDeIDsPorTanda = 100

// Atender trae lo que los avisos dicen que hay que traer.
//
// DEVUELVE ERROR A PROPÓSITO, y es lo que sujeta la regla del `XACK`: si esto falla, el
// escuchador NO reconoce la tanda y esos avisos se vuelven a leer. Tragarse el error aquí
// haría que se reconocieran igual y esos pedidos se perderían sin que nadie se entere.
func (e *Espejo) Atender(ctx context.Context, q QueHaceFaltaTraer) error {
	// 1. LO QUE SE FUE, PRIMERO. Un pedido borrado en PEDIDO que siga aquí acaba en un
	//    camión y nadie lo echa en falta; y si además viniera en la lista de traer, ya lo
	//    quitó `AgruparAvisos` — el borrado manda.
	if len(q.Borrados) > 0 {
		if err := e.Base.QuitarPedidos(ctx, q.Borrados); err != nil {
			return err
		}
		e.Reg.Info("pedidos quitados por aviso de PEDIDO", "cuantos", len(q.Borrados))
	}

	// 2. LOS PEDIDOS CONCRETOS, por tandas.
	for _, tanda := range enTandas(q.Pedidos, TopeDeIDsPorTanda) {
		p := e.parametrosBase()
		p.Set("ids", strings.Join(tanda, ","))
		p.Set("limit", strconv.Itoa(TopeDePagina))
		if err := e.traerYGuardar(ctx, p, "aviso de PEDIDO"); err != nil {
			return err
		}
	}

	// 3. LAS SUCURSALES QUE ACABAN DE IMPORTAR. Sin `id`: entró una tanda de CSV y hay
	//    que repasar esa sucursal entera.
	for _, suc := range q.Sucursales {
		p := e.parametrosBase()
		p.Set("sucursalId", suc)
		p.Set("limit", strconv.Itoa(TopeDePagina))
		if err := e.traerYGuardar(ctx, p, "importación en "+suc); err != nil {
			return err
		}
	}

	// 4. EL PADRÓN, si algún cliente se movió de sitio.
	//
	// El reparto ordena las paradas por la coordenada del cliente: si alguien la corrige y
	// esto no se entera, la ruta se arma hacia el sitio de antes, con números y todo y sin
	// un solo error. Va UNA vez por tanda aunque se hayan movido veinte.
	if len(q.Clientes) > 0 {
		if err := e.clientesPorID(ctx, q.Clientes); err != nil {
			return err
		}
	}

	// 5. Y SI ALGUNO VINO SIN SUCURSAL, se mira todo. Debería ser raro, y por eso se dice
	//    en vez de callarlo: si pasa a menudo, es que al otro lado falta el dato.
	if q.TodasLasSucursales {
		e.Reg.Warn("llegó un aviso sin sucursal: se repasa todo, que es lo caro")
		p := e.parametrosBase()
		p.Set("limit", strconv.Itoa(TopeDePagina))
		if err := e.traerYGuardar(ctx, p, "aviso sin sucursal"); err != nil {
			return err
		}
	}
	return nil
}

func (e *Espejo) traerYGuardar(ctx context.Context, q url.Values, de string) error {
	pedidos, err := e.Pedido.Pedidos(ctx, q)
	if err != nil {
		return err
	}
	// UNA RESPUESTA VACÍA NO ES UNA RESPUESTA BUENA (`CLAUDE.md` §3), pero aquí sí puede
	// serlo: PEDIDO filtra por `soloRepartibles`, así que un pedido que avisó y todavía no
	// cumple el filtro no vuelve. Se dice y se sigue — devolver error haría que la tanda
	// no se reconociera nunca y se releyera en bucle para siempre.
	if len(pedidos) == 0 {
		e.Reg.Info("el aviso no trajo ningún pedido: puede que aún no sea repartible",
			"de", de)
		return nil
	}
	e.guardar(ctx, pedidos, de)
	return nil
}

// enTandas parte una lista en trozos. Con la lista vacía devuelve nada, no una tanda vacía:
// una petición sin ids se lleva TODO lo que haya, que es justo lo contrario de lo que se
// pedía.
func enTandas(ids []string, tope int) [][]string {
	if len(ids) == 0 || tope <= 0 {
		return nil
	}
	var salida [][]string
	for i := 0; i < len(ids); i += tope {
		fin := i + tope
		if fin > len(ids) {
			fin = len(ids)
		}
		salida = append(salida, ids[i:fin])
	}
	return salida
}

// clientesPorID trae y guarda los clientes que se movieron.
//
// UNA FILA POR CLIENTE, no el padrón entero: PEDIDO abrió `?ids=` para esto. Antes esto
// repasaba los 8.673 por cada aviso, que era correcto y carísimo.
//
// Sólo los GEOLOCALIZADOS se guardan —lo mismo que el repaso completo—: sin coordenadas no
// hay parada que visitar y la columna no admite nulos.
func (e *Espejo) clientesPorID(ctx context.Context, ids []string) error {
	clientes, err := e.Pedido.ClientesPorID(ctx, ids)
	if err != nil {
		return err
	}
	// QUE NO VUELVA NINGUNO NO ES UN FALLO: el cliente pudo quedarse sin coordenadas, o
	// PEDIDO lo archivó entre el aviso y esta llamada. Se dice y se sigue — devolver error
	// haría que la tanda no se reconociera nunca y se releyera en bucle.
	if len(clientes) == 0 {
		e.Reg.Info("el aviso de cliente no trajo ninguno", "pedidos", len(ids))
		return nil
	}
	puestos := 0
	for _, c := range clientes {
		if c.Latitud == nil || c.Longitud == nil {
			continue
		}
		if err := e.Base.GuardarCliente(ctx, c); err != nil {
			// Un cliente que no entra no se lleva por delante a los otros de la tanda.
			e.Reg.Warn("un cliente movido no se pudo copiar", "cliente", c.ID, "err", err)
			continue
		}
		puestos++
	}
	e.Reg.Info("clientes movidos de sitio, al día", "avisados", len(ids), "puestos", puestos)
	return nil
}
