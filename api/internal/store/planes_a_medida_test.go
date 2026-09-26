package store

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"procovar/reparto-api/internal/config"
)

// Sin esto, una consulta con filtros opcionales pasa a plan genérico a la sexta vez y lee
// la tabla entera (ver `PlanesAMedida`). No falla: tarda, y sólo a ratos.
func TestPlanesAMedidaPideElPlanDeCadaVez(t *testing.T) {
	cfg, err := pgxpool.ParseConfig("postgres://u:p@localhost/procovar_reparto?application_name=reparto")
	if err != nil {
		t.Fatal(err)
	}
	PlanesAMedida(cfg)

	if got := cfg.ConnConfig.RuntimeParams["plan_cache_mode"]; got != "force_custom_plan" {
		t.Fatalf("plan_cache_mode = %q; sin `force_custom_plan` Postgres vuelve a los planes "+
			"genéricos y ListarPedidos pasa de 0,4 ms a 646 ms", got)
	}
	// Y no se come lo que ya traía la dirección de la base.
	if got := cfg.ConnConfig.RuntimeParams["application_name"]; got != "reparto" {
		t.Fatalf("application_name = %q; PlanesAMedida pisó los parámetros de DATABASE_URL", got)
	}
}

// La de verdad: que `Abrir` lo aplique y que llegue a la sesión. Necesita un Postgres, así
// que sólo corre con REPARTO_PRUEBA_PG puesto (p. ej. el de docker-compose); sin él se
// salta y lo dice.
func TestAbrirDejaLaSesionConPlanesAMedida(t *testing.T) {
	url := os.Getenv("REPARTO_PRUEBA_PG")
	if url == "" {
		t.Skip("REPARTO_PRUEBA_PG vacío: esta prueba necesita un Postgres de verdad")
	}
	ctx, cancelar := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancelar()

	a, err := Abrir(ctx, &config.Config{
		DatabaseURL: url, PoolMaxConns: 2, PoolMinConns: 0, PoolMaxIdleTime: time.Minute,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer a.pool.Close()

	var modo string
	if err := a.pool.QueryRow(ctx, "SHOW plan_cache_mode").Scan(&modo); err != nil {
		t.Fatal(err)
	}
	if modo != "force_custom_plan" {
		t.Fatalf("la sesión tiene plan_cache_mode = %q; Abrir no llamó a PlanesAMedida", modo)
	}
}
