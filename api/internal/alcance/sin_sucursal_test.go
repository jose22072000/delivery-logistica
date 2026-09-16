package alcance_test

import (
	"context"
	"testing"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
)

// SIN SUCURSAL **NO** SIGNIFICA «TODAS». Sólo lo significa para quien administra.
//
// Esto decía «Super Admin: todas» y NO MIRABA EL ROL: cualquiera cuyo token llegara sin
// sucursal —alguien a quien todavía no le han dado la suya, o mal dado de alta— veía las
// ocho. Es la regla 1 de la casa al revés, y ya costó dinero una vez: «un operador de
// Santiago vio los precios de La Habana».
//
// Jose lo cazó el 16/09/2026 leyendo el código: «sin sucursal no es por el tipo de usuario
// no hagas eso por q entonces un usuario sin sucursal ve todas eso esta malisimo».
//
// El fallo barato es dejar fuera a quien no tiene sucursal: se arregla dándosela. El caro
// es enseñarle las ocho, que no se ve.
func TestSinSucursalSoloVenTodasLosDosDeArriba(t *testing.T) {
	// Los SIETE roles de la tabla `role` de Accesos, leída el 16/09/2026.
	casos := []struct {
		rol     string
		veTodas bool
	}{
		{"SUPER ADMIN", true},
		{"DESARROLLADOR", true},
		{"GERENTE", false},
		{"ADMINISTRADOR", false}, // administra LO SUYO: una sucursal
		{"SUPERVISOR", false},
		{"GESTOR", false},
		{"OPERADOR", false},
		{"", false}, // sin rol tampoco: un hueco no es un permiso
	}

	for _, c := range casos {
		u := &auth.Usuario{ID: "quien-sea", Rol: c.rol}
		if got := alcance.VeTodasLasSucursales(u); got != c.veTodas {
			t.Errorf("rol %q: veTodas = %v, se esperaba %v", c.rol, got, c.veTodas)
		}
		if got := u.EsSuperAdmin(); got != c.veTodas {
			t.Errorf("rol %q: EsSuperAdmin = %v, se esperaba %v", c.rol, got, c.veTodas)
		}
	}
}

// «¿Contiene admin?» es la comprobación que parece razonable y abre la puerta:
// `ADMINISTRADOR` la pasaría y se llevaría las ocho.
func TestAdministradorNoSeCuelaPorParecerseAAdmin(t *testing.T) {
	u := &auth.Usuario{ID: "x", Rol: "ADMINISTRADOR"}
	if u.EsSuperAdmin() {
		t.Fatal("ADMINISTRADOR es de UNA sucursal: no puede ver las ocho")
	}
	if !u.EsAdmin() {
		t.Fatal("pero SÍ administra: `/api/branches` le tiene que dejar")
	}
}

// El `admin` heredado de la web vieja conserva su regla de siempre. Cambiársela lo dejaría
// fuera de su propio sistema mientras esa puerta siga abierta.
func TestElAdminHeredadoConservaSuRegla(t *testing.T) {
	sinSucursal := &auth.Usuario{ID: "viejo", Rol: "admin"}
	if !sinSucursal.EsSuperAdmin() {
		t.Error("el admin de la web vieja, sin sucursal, era Super Admin")
	}
	conSucursal := &auth.Usuario{ID: "viejo", Rol: "admin", Sucursal: "una"}
	if conSucursal.EsSuperAdmin() {
		t.Error("con sucursal sigue viendo sólo la suya")
	}
}

// Y el `Resolver` lo aplica de verdad: no basta con que la función diga que no.
func TestResolverNiegaAQuienNoTieneSucursalNiRol(t *testing.T) {
	p, _ := porteria(&querierFalso{})
	_, err := p.Resolver(context.Background(), &auth.Usuario{ID: "x", Rol: "OPERADOR"}, "")
	if err == nil {
		t.Fatal("un operador sin sucursal no puede pasar: vería las ocho")
	}
	if err != alcance.ErrSinAlcance {
		t.Fatalf("y se dice QUÉ le falta, no «error interno»: %v", err)
	}
}
