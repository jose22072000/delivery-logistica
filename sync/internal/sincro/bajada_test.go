package sincro

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/identidad"
	"procovar/reparto-sync/internal/store/sqlc"
)

// 5 · LA MARCA DE TIEMPO LA PONE EL SERVIDOR
//
// El reloj de un teléfono se mueve: se cambia a mano, se va con la batería, salta de zona
// horaria. Si el aparato dijera desde cuándo pedir, uno adelantado se saltaría para siempre
// todo lo que cambió en medio y nadie se enteraría hasta que faltara un pedido.
func TestLaMarcaDeLaBajadaLaPoneElServidorYNoElAparato(t *testing.T) {
	b := montar(t)

	// El servidor le dio esta marca la última vez. Es la única válida.
	entregada := enPunto(t, "2026-09-14T08:00:00Z")
	b.base.estados[b.aparato.ID] = sqlc.AparatoEstado{
		AparatoID:   b.aparato.ID,
		BajadaHasta: marca(entregada),
	}

	// El aparato pide desde dos horas MÁS TARDE: su reloj va adelantado, o alguien lo
	// cambió a mano.
	adelantado := enPunto(t, "2026-09-14T10:00:00Z")
	w := b.pedir(http.MethodGet,
		"/sync/bajada?aparato="+b.aparato.ID.String()+"&desde="+adelantado.Format(time.RFC3339Nano),
		nil, b.quien)
	if w.Code != http.StatusOK {
		t.Fatalf("tenía que contestar 200, contestó %d (%s)", w.Code, w.Body.String())
	}

	if len(b.origen.ventanas) != 1 {
		t.Fatalf("tenía que pedirle las diferencias al reparto una vez")
	}
	v := b.origen.ventanas[0]
	if v.Desde == nil || !v.Desde.Equal(entregada) {
		t.Fatalf("se bajó desde %v; tenía que ser desde la marca que dio el servidor (%v)", v.Desde, entregada)
	}

	var salida bajadaSalida
	if err := json.Unmarshal(w.Body.Bytes(), &salida); err != nil {
		t.Fatalf("la respuesta no se entiende: %v", err)
	}
	// El `hasta` es el reloj del servidor, ni el del aparato ni nada que él haya mandado.
	if !salida.Hasta.Equal(enPuntoFijo()) {
		t.Fatalf("el `hasta` tenía que ser la hora del servidor (%v), fue %v", enPuntoFijo(), salida.Hasta)
	}
	if !v.Hasta.Equal(salida.Hasta) {
		t.Fatalf("al reparto se le pide la misma ventana que se contesta")
	}
	// Y es la que se guarda para la próxima vez, aquí, porque el aparato la puede perder.
	if len(b.bajadasAnotadas()) != 1 || !b.bajadasAnotadas()[0].Equal(salida.Hasta) {
		t.Fatalf("la marca guardada tenía que ser la del servidor: %v", b.bajadasAnotadas())
	}
	if salida.Completa {
		t.Fatalf("no era una carga inicial")
	}
}

// Y si pide desde ANTES de lo que se le dio, se le hace caso: repetir un cambio no rompe
// nada, perderlo sí.
func TestSiElAparatoPideDesdeAntesSeLeHaceCaso(t *testing.T) {
	b := montar(t)
	b.base.estados[b.aparato.ID] = sqlc.AparatoEstado{
		AparatoID:   b.aparato.ID,
		BajadaHasta: marca(enPunto(t, "2026-09-14T08:00:00Z")),
	}

	atrasado := enPunto(t, "2026-09-13T22:00:00Z")
	w := b.pedir(http.MethodGet,
		"/sync/bajada?aparato="+b.aparato.ID.String()+"&desde="+atrasado.Format(time.RFC3339Nano),
		nil, b.quien)
	if w.Code != http.StatusOK {
		t.Fatalf("contestó %d", w.Code)
	}
	if v := b.origen.ventanas[0]; v.Desde == nil || !v.Desde.Equal(atrasado) {
		t.Fatalf("tenía que bajar desde %v, bajó desde %v", atrasado, v.Desde)
	}
}

// Una marca que este servidor no recuerda haber dado no vale: carga completa. Es preferible
// bajar de más una vez a dar por bueno un `desde` inventado y perder lo de en medio.
func TestSinMarcaGuardadaLaCargaEsCompleta(t *testing.T) {
	b := montar(t)

	inventada := enPunto(t, "2026-09-14T10:00:00Z")
	w := b.pedir(http.MethodGet,
		"/sync/bajada?aparato="+b.aparato.ID.String()+"&desde="+inventada.Format(time.RFC3339Nano),
		nil, b.quien)
	if w.Code != http.StatusOK {
		t.Fatalf("contestó %d (%s)", w.Code, w.Body.String())
	}
	if v := b.origen.ventanas[0]; v.Desde != nil {
		t.Fatalf("tenía que ser carga completa, pidió desde %v", v.Desde)
	}
	var salida bajadaSalida
	_ = json.Unmarshal(w.Body.Bytes(), &salida)
	if !salida.Completa {
		t.Fatalf("`completa` tenía que venir puesto")
	}
	// Los ocho conjuntos, aunque vengan vacíos: la aplicación recorre lo que llega sin
	// preguntarse si una clave que falta es «no cambió nada» o «el servidor es más viejo».
	for _, nombre := range Colecciones {
		conjunto, hay := salida.Cambios[nombre]
		if !hay || conjunto.Puestos == nil || conjunto.Quitados == nil {
			t.Fatalf("falta el conjunto %q o viene en null: %+v", nombre, conjunto)
		}
	}
}

// Si el reparto no contesta, la marca NO se mueve: si se moviera, ese trozo de tiempo no lo
// volvería a pedir nadie y esos cambios no llegarían al aparato nunca.
func TestSiElRepartoFallaLaMarcaNoSeMueve(t *testing.T) {
	b := montar(t)
	b.origen.err = errCaida

	w := b.pedir(http.MethodGet, "/sync/bajada?aparato="+b.aparato.ID.String(), nil, b.quien)
	if w.Code != http.StatusBadGateway {
		t.Fatalf("tenía que contestar 502, contestó %d", w.Code)
	}
	if len(b.base.bajadas) != 0 {
		t.Fatalf("no se podía anotar la bajada: %+v", b.base.bajadas)
	}
}

// 6 · EL ALCANCE POR SUCURSAL
//
// Un aparato sólo baja lo de su sucursal, y el panel sólo enseña lo de la sucursal de quien
// mira. Sin esto, el logístico de Camagüey ve la cola y los rechazos de las otras nueve con
// sólo cambiar un parámetro.
func TestElAlcancePorSucursalTambienAqui(t *testing.T) {
	b := montar(t)

	// a) Otra persona, de otra sucursal, no maneja este aparato.
	otra := identidad.Identidad{Persona: "el-de-camaguey", Sucursal: uuid.New()}
	w := b.pedir(http.MethodGet, "/sync/bajada?aparato="+b.aparato.ID.String(), nil, otra)
	if w.Code != http.StatusForbidden {
		t.Fatalf("tenía que contestar 403, contestó %d", w.Code)
	}
	if len(b.origen.ventanas) != 0 {
		t.Fatalf("no se le pide nada al reparto")
	}

	// b) Ni el propio aparato puede pedir la sucursal de al lado.
	w = b.pedir(http.MethodGet,
		"/sync/bajada?aparato="+b.aparato.ID.String()+"&sucursal="+uuid.New().String(), nil, b.quien)
	if w.Code != http.StatusForbidden {
		t.Fatalf("tenía que contestar 403, contestó %d", w.Code)
	}
	if len(b.origen.ventanas) != 0 {
		t.Fatalf("no se le pide nada al reparto")
	}

	// c) La bajada buena va SIEMPRE con la sucursal del aparato, la que se guardó en su
	// alta, no la que venga en la petición.
	w = b.pedir(http.MethodGet, "/sync/bajada?aparato="+b.aparato.ID.String(), nil, b.quien)
	if w.Code != http.StatusOK {
		t.Fatalf("contestó %d (%s)", w.Code, w.Body.String())
	}
	if v := b.origen.ventanas[0]; v.Sucursal != b.sucursal {
		t.Fatalf("se pidieron las diferencias de %v en vez de las de %v", v.Sucursal, b.sucursal)
	}

	// d) El panel: quien no es Super Admin ve su sucursal aunque pida otra.
	pedida := uuid.New()
	w = b.pedir(http.MethodGet, "/sync/estado?sucursal="+pedida.String(), nil, b.quien)
	if w.Code != http.StatusOK {
		t.Fatalf("contestó %d", w.Code)
	}
	filtro := b.base.filtrosDePanel[len(b.base.filtrosDePanel)-1]
	if !filtro.Valid || uuid.UUID(filtro.Bytes) != b.sucursal {
		t.Fatalf("el panel se consultó con %v en vez de con la sucursal de quien mira (%v)", filtro, b.sucursal)
	}

	// e) El Super Admin es la única excepción: sin parámetro, las diez.
	jefe := identidad.Identidad{Persona: "el-jefe", EsSuperAdmin: true}
	w = b.pedir(http.MethodGet, "/sync/estado", nil, jefe)
	if w.Code != http.StatusOK {
		t.Fatalf("contestó %d", w.Code)
	}
	if filtro := b.base.filtrosDePanel[len(b.base.filtrosDePanel)-1]; filtro.Valid {
		t.Fatalf("el Super Admin ve todas: el filtro tenía que ir vacío")
	}
}

// bajadasAnotadas saca las marcas que se guardaron, que es lo que el aparato pedirá la
// próxima vez si perdió la suya.
func (b *banco) bajadasAnotadas() []time.Time {
	var marcas []time.Time
	for _, v := range b.base.bajadas {
		marcas = append(marcas, v.BajadaHasta.Time)
	}
	return marcas
}
