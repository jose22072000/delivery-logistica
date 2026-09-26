package api

import (
	"context"
	"log/slog"
	"net/http"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
	"procovar/reparto-api/internal/store/sqlc"
)

// LA PANTALLA DEL WEBHOOK ES DEL DESARROLLADOR Y DE NADIE MÁS.
//
// Jose, 26/09/2026: «esto es para administración, esta vista no la puede ver nadie» y, más
// claro todavía: «que sólo lo pueda ver yo, eso no lo puede ver más nadie, sólo yo, el
// desarrollador».
//
// POR QUÉ NO VALE `ExigirAdmin`, que era lo primero que se puso: `EsAdmin` deja pasar a
// SUPER ADMIN, ADMINISTRADOR y al `admin` heredado de la web vieja. Un ADMINISTRADOR
// administra SU SUCURSAL —es uno de los cinco roles de una sola— y ninguno de los tres
// tiene nada que hacer en una pantalla de colas, reintentos, códigos HTTP y motivos de
// error de otro sistema.
//
// LA FORMA: se prueban los SIETE roles de la casa, uno a uno, y no sólo «un admin sí y un
// operador no». Con dos casos, cambiar `EsDesarrollador` por `EsSuperAdmin` sale verde y la
// pantalla se le abre a medio Procovar sin que nada falle.

func TestSoloElDesarrolladorVeElEstadoDelWebhook(t *testing.T) {
	// Los siete de `procovar/CLAUDE.md`, escritos EXACTAMENTE así: PEDIDO los compara
	// como texto y aquí también.
	losOtrosSeis := []string{
		"SUPER ADMIN", "GERENTE", "ADMINISTRADOR", "SUPERVISOR", "GESTOR", "OPERADOR",
	}

	h, _ := montarRutasDelWebhook(t)

	for _, rol := range losOtrosSeis {
		t.Run(rol, func(t *testing.T) {
			w := llamarRutas(t, h, http.MethodGet, "/api/admin/webhook",
				tokenConRol(t, rol), "")
			if w.Code != http.StatusForbidden {
				t.Fatalf(
					"%s entró en la pantalla del webhook: %d %s",
					rol, w.Code, w.Body.String(),
				)
			}
		})
	}

	t.Run("DESARROLLADOR", func(t *testing.T) {
		w := llamarRutas(t, h, http.MethodGet, "/api/admin/webhook",
			tokenConRol(t, "DESARROLLADOR"), "")
		if w.Code != http.StatusOK {
			t.Fatalf(
				"el desarrollador NO pudo entrar en su propia pantalla: %d %s",
				w.Code, w.Body.String(),
			)
		}
	})
}

// Y SIN SESIÓN, NI ESO. Va aparte porque es otro middleware el que lo para —`Exigir`, no
// `ExigirDesarrollador`— y por tanto otra cosa que se puede romper por su cuenta.
func TestSinSesionElEstadoDelWebhookNoSeSirve(t *testing.T) {
	h, _ := montarRutasDelWebhook(t)

	w := llamarRutas(t, h, http.MethodGet, "/api/admin/webhook", "", "")

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("se sirvió sin sesión: %d %s", w.Code, w.Body.String())
	}
}

// --------------------------------------------------------------------------- el montaje

// montarRutasDelWebhook monta SÓLO las del espejo, que es donde vive la del webhook.
//
// Se monta con los mismos middlewares que en producción —`sesion` y `admin` armados
// igual—, porque lo que se prueba es justo cuál de los dos acaba delante de esta ruta.
func montarRutasDelWebhook(t *testing.T) (http.Handler, *Servidor) {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://x:y@localhost:5432/z")
	t.Setenv("JWT_SECRET", secretoDeRutas)
	cfg, err := config.Cargar("v-pruebas")
	if err != nil {
		t.Fatalf("configuración: %v", err)
	}
	reg := slog.New(slog.DiscardHandler)
	q := &dobleDelWebhook{}
	porteria := alcance.NuevaPorteria(fuenteDelWebhook{q: q}, reg)
	verif := auth.NuevoVerificador([]byte(secretoDeRutas))
	s := NuevoServidor(cfg, reg, porteria, verif, func(context.Context) error { return nil })

	rt := httpx.NuevoRouter(httpx.IDDePeticion, httpx.ConRegistro(reg),
		httpx.RecuperarPanico, httpx.SinCache)
	sesion := []httpx.Medio{verif.Exigir, porteria.Exigir}
	admin := []httpx.Medio{verif.Exigir, auth.ExigirAdmin, porteria.Exigir}
	s.rutasEspejo(rt, sesion, admin)
	return rt.Handler(), s
}

func tokenConRol(t *testing.T, rol string) string {
	t.Helper()
	// SIN SUCURSAL a propósito: lo que se prueba es el ROL, y darle una metería además el
	// alcance en la ecuación. Los cinco roles de una sola sucursal se quedan fuera por
	// `ErrSinAlcance` antes de llegar al rol… así que se les da la suya, y a los dos que
	// ven las ocho, ninguna.
	carga := map[string]any{"sub": "p-" + rol, "role": rol}
	if rol != "SUPER ADMIN" && rol != "DESARROLLADOR" {
		carga["branchId"] = stgDeRutas.String()
	}
	return tokenDeRutas(t, carga)
}

type fuenteDelWebhook struct{ q sqlc.Querier }

func (f fuenteDelWebhook) Consultas() sqlc.Querier { return f.q }
func (f fuenteDelWebhook) EnTx(ctx context.Context, fn func(sqlc.Querier) error) error {
	return fn(f.q)
}

// dobleDelWebhook contesta lo justo para que la pantalla se pinte: lo que se prueba aquí
// es quién entra, no qué ve.
type dobleDelWebhook struct{ sqlc.Querier }

func (d *dobleDelWebhook) ResumenDelWebhook(context.Context) (sqlc.ResumenDelWebhookRow, error) {
	return sqlc.ResumenDelWebhookRow{}, nil
}

func (d *dobleDelWebhook) ListarEnviosDelWebhook(context.Context, int32) ([]sqlc.EnviosDelWebhook, error) {
	return nil, nil
}

func (d *dobleDelWebhook) ListarRecepcionesDelWebhook(context.Context, int32) ([]sqlc.RecepcionesDelWebhook, error) {
	return nil, nil
}

func (d *dobleDelWebhook) ListarAvisosAPedido(context.Context, sqlc.ListarAvisosAPedidoParams) ([]sqlc.ListarAvisosAPedidoRow, error) {
	return nil, nil
}

func (d *dobleDelWebhook) ResolverSucursal(context.Context, uuid.UUID) (sqlc.ResolverSucursalRow, error) {
	return sqlc.ResolverSucursalRow{}, pgx.ErrNoRows
}
