package db

import "testing"

// LO QUE VIGILA ESTA PRUEBA, y por qué no es una tontería:
//
// La cuenta que decide si un despliegue levanta o se muere. Si `Faltan` se equivoca por
// arriba, la API no arranca nunca y nadie puede desplegar; si se equivoca por abajo, vuelve
// el 17/09/2026: la API arranca con la base atrasada y la flota se queda congelada mientras
// la web enseña todo verde.
func TestFaltanLasQueLaBaseNoTiene(t *testing.T) {
	esperadas := []Migracion{
		{Version: 1, Nombre: "00001_init.sql"},
		{Version: 2, Nombre: "00002_tablero.sql"},
		{Version: 6, Nombre: "00006_bajas_de_la_bajada.sql"},
	}

	casos := []struct {
		nombre   string
		enLaBase int64
		quiere   []string
	}{
		{"base sin migrar", 0, []string{"00001_init.sql", "00002_tablero.sql", "00006_bajas_de_la_bajada.sql"}},
		{"el caso del 17/09: sólo falta la última", 2, []string{"00006_bajas_de_la_bajada.sql"}},
		{"al día", 6, nil},
		// Volver a una imagen anterior NO puede impedir arrancar: es justo lo que se hace
		// para salir de un despliegue malo, y morirse ahí deja al equipo sin marcha atrás.
		{"la base va por delante del binario", 9, nil},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			faltan := Faltan(esperadas, c.enLaBase)
			if len(faltan) != len(c.quiere) {
				t.Fatalf("con la base en %d se esperaban %d migraciones pendientes y salieron %d: %v",
					c.enLaBase, len(c.quiere), len(faltan), faltan)
			}
			for i, m := range faltan {
				if m.Nombre != c.quiere[i] {
					t.Errorf("pendiente %d: se esperaba %q y salió %q", i, c.quiere[i], m.Nombre)
				}
			}
		})
	}
}

// Las migraciones DE VERDAD, las que van incrustadas en el binario. Sin esto, un fichero
// nuevo con un nombre raro —o una carpeta que no se incrusta— dejaría la comprobación
// mirando una lista vacía, que es exactamente lo mismo que no comprobar nada.
func TestLasMigracionesIncrustadasSeLeen(t *testing.T) {
	esperadas, err := Esperadas()
	if err != nil {
		t.Fatalf("no se pudieron leer las migraciones incrustadas: %v", err)
	}
	if len(esperadas) == 0 {
		t.Fatal("NO HAY NINGUNA MIGRACIÓN INCRUSTADA: la comprobación del arranque no comprueba nada")
	}
	for i := 1; i < len(esperadas); i++ {
		if esperadas[i].Version <= esperadas[i-1].Version {
			t.Fatalf("las migraciones no salen ordenadas ni son únicas: %v antes que %v",
				esperadas[i-1], esperadas[i])
		}
	}
	// La 00006 es la del incidente: si alguien la borra, que se entere aquí.
	if esperadas[len(esperadas)-1].Version < 6 {
		t.Errorf("falta la 00006 o alguna posterior; la última incrustada es %v", esperadas[len(esperadas)-1])
	}
}

func TestUnNombreRaroEsUnErrorYNoUnSalto(t *testing.T) {
	if _, err := deNombre("sin-guion-bajo.sql"); err == nil {
		t.Error("un fichero con nombre raro tiene que dar ERROR: saltárselo daría por buena una base a la que le falta")
	}
}
