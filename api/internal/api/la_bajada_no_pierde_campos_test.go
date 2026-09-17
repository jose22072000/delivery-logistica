package api

import (
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/store/sqlc"
)

// LO QUE EL SERVIDOR TIENE Y NO ESCRIBE.
//
// Es la clase de fallo que más caro sale en esta casa, y el 17/09/2026 se cazó tres veces
// el mismo día, ninguna leyendo el código:
//
//   - Las rutas viajaban sin `totalPrice`, `originAddress` ni `deliveryDate`: el aparato
//     enseñaba **$0.00** en una ruta de 720 USD, «Sin punto de partida» teniendo almacén y
//     una raya donde va la fecha.
//   - Los pedidos viajaban sin `createdAt`, y con él se caía la guarda que acota por fecha
//     los que vienen sin `orderDate`: desaparecían de CUALQUIER filtro por fecha en la APK.
//   - El padrón viajaba sin `source`: los 8.000 clientes salían como «Manual» y el filtro
//     de origen contestaba al revés.
//
// Las tres tienen la misma forma: **el dato está en la fila, la columna existe en el
// aparato, y la función que arma el JSON no lo escribe.** No hay error, no hay pantalla en
// blanco, no hay tirón. Sale un cero, y un cero se lee bien.
//
// Y las tres se pudieron deshacer enteras sin que nada se pusiera rojo, porque lo único
// que las sujetaba era un comentario que decía que existía esta prueba. No existía. Un
// comentario no falla (`CLAUDE.md` §3-bis).
//
// Por eso esto comprueba **claves**, no valores: lo que se rompe es que una clave deje de
// escribirse, y eso no lo nota ningún `assert` sobre un número.
func TestLaBajadaNoPierdeCamposPorElCamino(t *testing.T) {
	q := nuevoEspejo()
	desde := conBajas(q)

	// Una ruta con TODO relleno: si un campo no se escribe, no sale la clave.
	ahora := pgtype.Timestamptz{Time: time.Now().UTC(), Valid: true}
	direccion := "Almacén Camagüey, Carretera Central km 3"
	q.rutasDelEspejo = []sqlc.ListarRutasRow{{
		ID:            rutaViva,
		BranchID:      pgtype.UUID{Bytes: [16]byte(sucStg), Valid: true},
		OriginAddress: &direccion,
		TotalPrice:    720,
		TotalDistance: 33.6,
		DeliveryDate:  ahora,
		StartedAt:     ahora,
		FinishedAt:    ahora,
		CreatedAt:     ahora,
		UpdatedAt:     ahora,
	}}

	cambios := bajadaDe(t, q, tokenTab(t, sucStg.String()),
		"?desde="+desde.Format(time.RFC3339Nano))

	// --- Rutas: lo que se arregló el 17/09 -----------------------------------
	//
	// `originAddress`, `totalPrice` y `deliveryDate` son los tres que Jose vio mal en la
	// pantalla. `startedAt` y `finishedAt` son la línea de «Salida» y «Regreso» de la hoja
	// del post-despacho, la que firma el chofer: sin ellos la hoja sale sin horario y
	// tampoco se nota.
	exigirClaves(t, cambios, "routes", []string{
		"id", "name", "routeCode", "status",
		"originAddress", "originLat", "originLng",
		"totalDistance", "totalWeight", "totalPrice",
		"deliveryDate", "vehicleId", "branchId",
		"startedAt", "finishedAt", "createdAt", "updatedAt",
	})
}

// exigirClaves comprueba que el primer elemento de `puestos` de esa colección trae todas
// las claves, y **nombra la que falta**: «routes: falta `totalPrice`» dice dónde mirar;
// «el JSON no coincide» no dice nada.
func exigirClaves(t *testing.T, cambios map[string]any, coleccion string, claves []string) {
	t.Helper()
	c, ok := cambios["cambios"].(map[string]any)[coleccion].(map[string]any)
	if !ok {
		t.Fatalf("la bajada no trae la colección %q", coleccion)
	}
	puestos, _ := c["puestos"].([]any)
	if len(puestos) == 0 {
		t.Fatalf("%s: no vino ningún elemento, así que esto no comprueba nada", coleccion)
	}
	fila, _ := puestos[0].(map[string]any)
	for _, k := range claves {
		if _, hay := fila[k]; !hay {
			t.Errorf(
				"%s: falta la clave %q.\n"+
					"El dato está en la fila de Go y la columna existe en el aparato: lo que\n"+
					"falla es que esta función no lo escribe. Sin ella el aparato enseña el\n"+
					"valor por defecto —un cero, un nulo— que se lee perfectamente bien y\n"+
					"está mal, y ninguna pantalla lo desmiente.",
				coleccion, k,
			)
		}
	}
}
