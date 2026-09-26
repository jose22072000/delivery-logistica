package store

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// Dos guardas de 00008_indices_medidos.sql que no fallan nunca por sí solas: si se
// rompen, la migración sigue aplicándose y la api sigue contestando. Lo único que pasa es
// que un despliegue se queda encallado, o que una pantalla vuelve a tardar 10 veces más.

func leerMigracionDeIndices(t *testing.T) string {
	t.Helper()
	ruta := filepath.Join("..", "..", "db", "migrations", "00008_indices_medidos.sql")
	b, err := os.ReadFile(ruta)
	if err != nil {
		t.Fatalf("no se pudo leer %s: %v", ruta, err)
	}
	s := string(b)
	// Sólo el Up: el Down tiene sus propios `CREATE ... IF NOT EXISTS`.
	if i := strings.Index(s, "-- +goose Down"); i >= 0 {
		s = s[:i]
	}
	return s
}

// CADA CREATE CONCURRENTLY CON SU DROP DELANTE.
//
// Un `CREATE INDEX CONCURRENTLY` cortado a medias —y con el `lock_timeout=5s` de la URL de
// migraciones basta una transacción del espejo abierta más de 5 s— deja el índice creado
// pero INVÁLIDO. goose no apunta la migración, y al relanzarla ese CREATE choca con
// «relation already exists» para siempre. El DROP previo es lo que la hace relanzable.
// Comprobado de verdad en la auditoría del 26/09/2026: sin el DROP, no se autorrepara.
func TestCadaIndiceSePuedeRehacerSiSeCortaAMedias(t *testing.T) {
	up := leerMigracionDeIndices(t)
	crear := regexp.MustCompile(`CREATE INDEX CONCURRENTLY (\w+)`)
	nombres := crear.FindAllStringSubmatch(up, -1)
	if len(nombres) == 0 {
		t.Fatal("no encuentro ningún CREATE INDEX CONCURRENTLY en el Up de 00008")
	}
	for _, m := range nombres {
		nombre := m[1]
		drop := "DROP INDEX CONCURRENTLY IF EXISTS " + nombre + ";"
		iDrop := strings.Index(up, drop)
		iCrear := strings.Index(up, m[0]+"\n")
		if iCrear < 0 {
			iCrear = strings.Index(up, m[0]+" ")
		}
		if iDrop < 0 || iDrop > iCrear {
			t.Errorf("%s no lleva `%s` DELANTE: si su CREATE CONCURRENTLY se corta, "+
				"queda inválido y la migración ya no se puede relanzar", nombre, drop)
		}
	}
}

// LA CONDICIÓN DEL ÍNDICE PARCIAL LA TIENEN QUE PEDIR LAS CUATRO CONSULTAS.
//
// Postgres sólo usa `orders_repartibles_idx` si el WHERE de la consulta implica el del
// índice. Si una consulta deja de pedir una de las cuatro condiciones, deja de usarlo; si
// al índice se le quita una, sigue usándose pero con las 50.800 archivadas dentro. En los
// dos casos todo sigue en verde y sólo tarda más. Por eso se comparan los dos lados.
func TestElIndiceDeRepartiblesCasaConSusConsultas(t *testing.T) {
	up := leerMigracionDeIndices(t)
	re := regexp.MustCompile(`(?s)CREATE INDEX CONCURRENTLY orders_repartibles_idx.*?WHERE (.*?);`)
	m := re.FindStringSubmatch(up)
	if m == nil {
		t.Fatal("no encuentro el WHERE de orders_repartibles_idx en 00008")
	}
	var condiciones []string
	for _, c := range strings.Split(m[1], " AND ") {
		condiciones = append(condiciones, strings.Join(strings.Fields(c), " "))
	}
	quiere := []string{"source = 'pedido'", "route_id IS NULL", "delivered_at IS NULL", "NOT archivado"}
	if strings.Join(condiciones, "|") != strings.Join(quiere, "|") {
		t.Errorf("el índice parcial filtra %q y esta prueba espera %q: si cambió a propósito, "+
			"cambia también las cuatro consultas y esta lista", condiciones, quiere)
	}

	for fichero, consultas := range map[string][]string{
		"orders.sql":  {"ListarPedidosDisponibles", "ContarPedidosDisponibles"},
		"tablero.sql": {"ListarPedidosSinColocar", "ContarPedidosSinColocar"},
	} {
		b, err := os.ReadFile(filepath.Join("..", "..", "db", "queries", fichero))
		if err != nil {
			t.Fatal(err)
		}
		for _, nombre := range consultas {
			cuerpo := strings.Join(strings.Fields(sinComentarios(cuerpoDe(t, string(b), nombre))), " ")
			for _, c := range quiere {
				conAlias := "o." + c
				if strings.HasPrefix(c, "NOT ") {
					conAlias = "NOT o." + strings.TrimPrefix(c, "NOT ")
				}
				if !strings.Contains(cuerpo, conAlias) {
					t.Errorf("%s ya no pide `%s`: Postgres deja de poder usar "+
						"orders_repartibles_idx y la lista vuelve a leerse los 55.600 pedidos",
						nombre, conAlias)
				}
			}
		}
	}
}
