package cotizar

import "sort"

// EL ALMACÉN DE ORIGEN (§10 de reglas-negocio.md y la regla de selección de
// `/api/quote/home-delivery`).
//
// El almacén VIVE EN ACCESOS y no se copia aquí: un almacén copiado se separa del de
// verdad en cuanto alguien mueve unas coordenadas allá, y *con esas coordenadas se mide lo
// que se le cobra al cliente*.

// Almacen es lo que Accesos devuelve de cada almacén de una sucursal.
type Almacen struct {
	ID        string   `json:"id"`
	Nombre    string   `json:"nombre"`
	Direccion *string  `json:"direccion"`
	Latitud   *float64 `json:"latitud"`
	Longitud  *float64 `json:"longitud"`
	Principal bool     `json:"principal"`
	Activo    bool     `json:"activo"`
}

// TieneCoordenadas: las dos, no una. Media coordenada no es un punto.
func (a Almacen) TieneCoordenadas() bool { return a.Latitud != nil && a.Longitud != nil }

// Punto del almacén. Sólo tiene sentido con TieneCoordenadas() == true.
func (a Almacen) Punto() Punto { return Punto{Lat: *a.Latitud, Lng: *a.Longitud} }

// SirveParaMedir: las TRES condiciones para que de este almacén pueda salir una distancia.
//
//   - **Activo.** Ver el bloque de `ElegirAlmacen`.
//   - **Con las dos coordenadas.** Media coordenada no es un punto.
//   - **Que no sea (0,0).** Es el golfo de Guinea, no Santiago: un almacén así no tiene
//     coordenadas, las tiene SIN PONER. Medir desde ahí da ~8.600 km y un orden de tarjetas
//     que parece bueno y no lo es. `internal/api` ya lo descartaba antes de llamar aquí
//     (`almacenesConPunto`, del tablero) y la cotización NO, que es otra forma del mismo
//     agujero: la condición vive aquí y una sola vez.
func (a Almacen) SirveParaMedir() bool {
	if !a.Activo || !a.TieneCoordenadas() {
		return false
	}
	return !(*a.Latitud == 0 && *a.Longitud == 0)
}

// ElegirAlmacen aplica la regla de selección del origen, en este orden:
//
//  1. De los que SIRVEN PARA MEDIR (`SirveParaMedir`), el `principal`.
//  2. Si hay varios principales o ninguno, el primero por **nombre ascendente**.
//  3. Si no sirve ninguno, nil — y quien llama contesta
//     `409 «<Sucursal> no tiene ningún almacén con coordenadas»`.
//
// POR QUÉ EL 409 Y NO UN APAÑO: *es desde donde sale la mercancía, que es lo que mide la
// APK.* Sin almacén con coordenadas no se contesta un número aproximado —ni se usan las
// coordenadas de la sucursal, que no son el sitio del que sale la carga—: se dice que no
// se puede. Un número aproximado aquí se cobra igual que uno bueno.
//
// # POR QUÉ `activo` SÍ FILTRA — 24/09/2026
//
// AQUÍ PONÍA LO CONTRARIO, y estaba razonado: «`activo` NO filtra. La regla del pliego
// mira `principal` y las coordenadas, nada más; añadir aquí un filtro por activo cambiaría
// el almacén elegido en sucursales que tienen uno dado de baja con coordenadas buenas, y
// con él el importe». El aviso era cierto —cambia el importe— pero la conclusión era la
// mala: lo que había no era «no tocar esto», era que el servidor y el aparato elegían
// almacenes DISTINTOS, y ninguna prueba lo decía. `AlmacenDeReferencia` (el aparato) sí
// filtraba `activo`, y el Panel, el Tablero y Clientes con él: tres de los cuatro
// consumidores contra éste.
//
// LO QUE SE VEÍA. Una sucursal con dos almacenes, el principal dado de baja con
// coordenadas buenas y otro activo:
//
//   - el **Tablero** ordena las tarjetas midiendo desde el ACTIVO (lo resuelve en local);
//   - en la **web**, «Armar la ruta de esta zona» sale por `POST /board/columns/{id}/route`
//     y el servidor calculaba el origen aquí → el DE BAJA;
//   - en la **APK** esa misma acción se resuelve en local y escribe `origin_lat/lng` del
//     ACTIVO.
//
// El mismo botón, dos orígenes y **dos kilometrajes** según se pulse en el navegador o en
// el teléfono. Y esos km son los del cobro. Jose, 24/09/2026:
//
//	«no puede dar distinto, debe dar igual. ¿Cómo que distinto si es la misma API los
//	dos? No tienen que elegir distinto, eso debe dar igual en todos los datos. Es un
//	lugar distinto pero ya más nada.»
//
// Una sola regla, el mismo almacén elegido en todas partes, y la que gana es la de los
// tres: un almacén dado de baja NO cuenta. Es además el caso más caro que hay, porque sus
// coordenadas son buenas: la cuenta sale, el número es creíble y ninguna pantalla lo
// desmiente (`CLAUDE.md` §4, «el dato está y no se escribe» en su forma peor).
//
// LO QUE LO ATA, y no este comentario —un comentario no falla (`CLAUDE.md` §3-bis)—:
// `docs/almacen-de-origen.casos.json`, el MISMO fichero que leen
// `almacen_casos_compartidos_test.go` de aquí y
// `app/test/nucleo/almacenes/almacen_de_origen_casos_compartidos_test.dart` del aparato.
// Tocar un lado y no el otro pone en rojo la prueba del otro.
//
// # Y EL DESEMPATE POR NOMBRE, QUE TAMPOCO ERA EL MISMO
//
// Esto devolvía «el primero de la lista» y la lista la sirve Accesos por HTTP; el aparato
// lee la suya de SQLite con `ORDER BY principal DESC, nombre ASC`. Dos sucursales con dos
// almacenes buenos y ninguno principal elegían distinto sin que nada fallara, por el mismo
// motivo que el `activo`. El desempate va aquí dentro y no en quien llama: así no depende
// del orden en que a nadie se le ocurra servir la lista.
func ElegirAlmacen(almacenes []Almacen) *Almacen {
	sirven := make([]int, 0, len(almacenes))
	for i := range almacenes {
		if almacenes[i].SirveParaMedir() {
			sirven = append(sirven, i)
		}
	}
	if len(sirven) == 0 {
		return nil
	}
	// Se ordenan los ÍNDICES: la lista de quien llama no se toca. `sort.SliceStable` sobre
	// un criterio total (principal y luego nombre) para que dos lecturas seguidas den
	// siempre el mismo — si los km de la misma tarjeta bailan, nadie se fía de ninguno.
	// El `Nombre` desempata al `Principal` y el `ID` al `Nombre`, que es lo único que queda
	// cuando dos almacenes se llaman igual. Es el mismo criterio, en el mismo orden, que
	// `AlmacenDeReferencia.elegir` del aparato.
	sort.SliceStable(sirven, func(x, y int) bool {
		a, b := almacenes[sirven[x]], almacenes[sirven[y]]
		if a.Principal != b.Principal {
			return a.Principal
		}
		if a.Nombre != b.Nombre {
			return a.Nombre < b.Nombre
		}
		return a.ID < b.ID
	})
	return &almacenes[sirven[0]]
}
