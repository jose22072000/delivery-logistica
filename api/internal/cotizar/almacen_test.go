package cotizar

import "testing"

func num(v float64) *float64 { return &v }

// La regla de selección del origen. Es de dónde sale la mercancía y por tanto de dónde se
// mide lo que se cobra: elegir mal el almacén cambia el importe de todos los domicilios de
// esa sucursal sin que nada falle.
//
// ESTA PRUEBA ES LA DE ESTE LADO. La que ata este lado con el del aparato es
// `almacen_casos_compartidos_test.go`, contra `docs/almacen-de-origen.casos.json`: aquí se
// pueden cambiar la regla y los casos a la vez y salir verde, que es exactamente lo que
// pasó hasta el 24/09/2026 (ver más abajo).
func TestElegirAlmacen(t *testing.T) {
	conCoords := func(id string, principal bool) Almacen {
		return Almacen{ID: id, Nombre: id, Latitud: num(20.02), Longitud: num(-75.82), Principal: principal, Activo: true}
	}
	sinCoords := func(id string, principal bool) Almacen {
		return Almacen{ID: id, Nombre: id, Principal: principal, Activo: true}
	}

	casos := []struct {
		nombre    string
		almacenes []Almacen
		esperado  string // "" = nil
	}{
		// CASO LÍMITE: sin almacenes. nil, y quien llama contesta el 409. No se usan las
		// coordenadas de la sucursal como apaño: no son el sitio del que sale la carga.
		{"sin almacenes", nil, ""},
		{"lista vacía", []Almacen{}, ""},
		// CASO LÍMITE: hay almacenes pero ninguno tiene coordenadas.
		{"ninguno con coordenadas", []Almacen{sinCoords("A", true), sinCoords("B", false)}, ""},
		{"1) el principal con coordenadas gana", []Almacen{conCoords("A", false), conCoords("B", true)}, "B"},
		{"1) entre dos principales desempata el NOMBRE", []Almacen{conCoords("B", true), conCoords("A", true)}, "A"},
		// El principal SIN coordenadas no sirve: se pasa al primero que las tenga.
		{"2) el principal sin coordenadas cede al primero que las tenga", []Almacen{sinCoords("P", true), conCoords("A", false), conCoords("B", false)}, "A"},
		{"2) ninguno principal: desempata el NOMBRE, no el orden de la lista", []Almacen{conCoords("Z", false), conCoords("A", false)}, "A"},
		// Media coordenada no es un punto: hace falta latitud Y longitud.
		{"media coordenada no cuenta", []Almacen{{ID: "M", Nombre: "M", Latitud: num(20), Principal: true, Activo: true}, conCoords("A", false)}, "A"},

		// ────────────────────────────────────────────────────────────────────────────
		// AQUÍ PONÍA LO CONTRARIO HASTA EL 24/09/2026.
		//
		// El caso se llamaba «un almacén inactivo con coordenadas sigue sirviendo» y
		// esperaba "I", con este razonamiento al lado: «`activo` NO filtra: la regla del
		// pliego mira principal y coordenadas, nada más. Filtrar por activo cambiaría el
		// almacén elegido —y el importe— en las sucursales que tienen uno dado de baja con
		// coordenadas buenas».
		//
		// Estaba verde, y el aparato tenía la suya —«un almacén inactivo y uno en (0,0) no
		// cuentan en NINGUNA», en `las_tres_pantallas_contestan_igual_test.dart`— también
		// verde, diciendo lo contrario. Dos pruebas del mismo lote afirmando cada una lo que
		// la otra negaba, y nada que las comparara: `CLAUDE.md` §3-bis.
		//
		// Lo que se veía: en la web «Armar la ruta de esta zona» salía por
		// `POST /board/columns/{id}/route` y el origen se calculaba aquí → el de baja; en la
		// APK la misma acción se resuelve en local → el activo. Dos kilometrajes para el
		// mismo botón, y esos km son los del cobro. Jose, 24/09/2026: «no puede dar
		// distinto, debe dar igual. ¿Cómo que distinto si es la misma API los dos? No tienen
		// que elegir distinto, eso debe dar igual en todos los datos. Es un lugar distinto
		// pero ya más nada.»
		//
		// Gana la regla de los otros tres consumidores (Panel, Tablero y Clientes): un
		// almacén dado de baja NO cuenta. Y es el caso más caro precisamente porque sus
		// coordenadas son buenas: la cuenta sale, el número es creíble y ninguna pantalla lo
		// desmiente.
		{"un almacén dado de baja NO sirve, aunque tenga coordenadas buenas",
			[]Almacen{{ID: "I", Nombre: "I", Latitud: num(20), Longitud: num(-75), Principal: true, Activo: false}}, ""},
		{"el de baja cede al activo, aunque el de baja sea el principal",
			[]Almacen{
				{ID: "BAJA", Nombre: "A", Latitud: num(20), Longitud: num(-75), Principal: true, Activo: false},
				conCoords("VIVO", false),
			}, "VIVO"},

		// (0,0) ES EL GOLFO DE GUINEA, NO SANTIAGO. Un almacén así no tiene coordenadas: las
		// tiene sin poner. `internal/api` lo descartaba antes de llamar aquí —pero sólo en el
		// camino del tablero (`almacenesConPunto`), no en el de la cotización—, así que la
		// condición se bajó a `SirveParaMedir` y vale para los dos.
		{"el (0,0) no cuenta, aunque sea el principal",
			[]Almacen{
				{ID: "CERO", Nombre: "A", Latitud: num(0), Longitud: num(0), Principal: true, Activo: true},
				conCoords("B", false),
			}, "B"},
		{"el (0,0) solo es el mismo 409 que no tener coordenadas",
			[]Almacen{{ID: "CERO", Nombre: "A", Latitud: num(0), Longitud: num(0), Principal: true, Activo: true}}, ""},
		// Lo que se descarta es el PAR (0,0), no un cero suelto: latitud 0 con longitud
		// puesta es un punto del ecuador. Raro para Cuba, pero es un punto.
		{"latitud 0 con longitud buena SÍ es un punto",
			[]Almacen{{ID: "ECU", Nombre: "A", Latitud: num(0), Longitud: num(-75.82), Principal: true, Activo: true}}, "ECU"},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			got := ElegirAlmacen(c.almacenes)
			if c.esperado == "" {
				if got != nil {
					t.Fatalf("se esperaba nil, salió %q", got.ID)
				}
				return
			}
			if got == nil {
				t.Fatalf("salió nil, se esperaba %q", c.esperado)
			}
			if got.ID != c.esperado {
				t.Fatalf("salió %q, se esperaba %q", got.ID, c.esperado)
			}
		})
	}
}

// LA LISTA DE QUIEN LLAMA NO SE TOCA. `ElegirAlmacen` ordena para desempatar, y si ordenara
// la rebanada de quien llama le cambiaría el orden por debajo a un código que no espera
// nada de eso —`almacenesDeCotizacion` la reutiliza— y devolvería además un puntero a una
// posición que ya no es la misma fila.
func TestElegirAlmacenNoReordenaLaListaDeQuienLlama(t *testing.T) {
	lista := []Almacen{
		{ID: "Z", Nombre: "Zona sur", Latitud: num(20.05), Longitud: num(-75.8), Activo: true},
		{ID: "A", Nombre: "Almacén norte", Latitud: num(20.02), Longitud: num(-75.82), Activo: true},
	}

	elegido := ElegirAlmacen(lista)
	if elegido == nil || elegido.ID != "A" {
		t.Fatalf("se esperaba A, salió %v", elegido)
	}
	if lista[0].ID != "Z" || lista[1].ID != "A" {
		t.Fatalf("la lista de quien llama salió reordenada: %q, %q", lista[0].ID, lista[1].ID)
	}
	// Y el puntero apunta a la fila de verdad, no a otra posición.
	if elegido != &lista[1] {
		t.Fatal("el puntero devuelto no es el de la fila elegida dentro de la lista original")
	}
}
