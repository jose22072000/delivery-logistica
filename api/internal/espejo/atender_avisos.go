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

	// 4. Y SI ALGUNO VINO SIN SUCURSAL, se mira todo. Debería ser raro, y por eso se dice
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
