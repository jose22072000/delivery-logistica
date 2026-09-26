package store

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Gemela de la de la api (api/internal/store/planes_a_medida_test.go). Hasta que existió,
// quitar el `force_custom_plan` de este `Abrir` dejaba todo el sincronizador en verde:
// lo cazó la auditoría del 26/09/2026.
func TestPlanesAMedidaPideElPlanDeCadaVez(t *testing.T) {
	cfg, err := pgxpool.ParseConfig("postgres://u:p@localhost/procovar_reparto_sync?application_name=sync")
	if err != nil {
		t.Fatal(err)
	}
	PlanesAMedida(cfg)
	if got := cfg.ConnConfig.RuntimeParams["plan_cache_mode"]; got != "force_custom_plan" {
		t.Fatalf("plan_cache_mode = %q; sin `force_custom_plan` Postgres vuelve a los planes "+
			"genéricos, que no usan el índice de la sucursal", got)
	}
	if got := cfg.ConnConfig.RuntimeParams["application_name"]; got != "sync" {
		t.Fatalf("application_name = %q; PlanesAMedida pisó los parámetros de DATABASE_URL", got)
	}
}

// Que `Abrir` lo aplique de verdad. Necesita un Postgres: sólo corre con
// REPARTO_PRUEBA_PG puesto, y sin él se salta diciéndolo.
func TestAbrirDejaLaSesionConPlanesAMedida(t *testing.T) {
	url := os.Getenv("REPARTO_PRUEBA_PG")
	if url == "" {
		t.Skip("REPARTO_PRUEBA_PG vacío: esta prueba necesita un Postgres de verdad")
	}
	ctx, cancelar := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancelar()

	b, err := Abrir(ctx, Opciones{URL: url, MaxConexiones: 2})
	if err != nil {
		t.Fatal(err)
	}
	defer b.pool.Close()

	var modo string
	if err := b.pool.QueryRow(ctx, "SHOW plan_cache_mode").Scan(&modo); err != nil {
		t.Fatal(err)
	}
	if modo != "force_custom_plan" {
		t.Fatalf("la sesión tiene plan_cache_mode = %q; Abrir no llamó a PlanesAMedida", modo)
	}
}
