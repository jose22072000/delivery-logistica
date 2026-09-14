package espejo

import (
	"strings"
	"testing"
	"time"
)

// entorno arma un `os.Getenv` de mentira: las pruebas no ensucian el del proceso.
func entorno(pares map[string]string) func(string) string {
	return func(k string) string { return pares[k] }
}

func TestLosValoresPorDefectoSonLosMedidos(t *testing.T) {
	// No son números elegidos al gusto: salen de los datos de verdad. El minuto de ciclo
	// existe porque cinco minutos mirando una pantalla que no cambia se leen como que está
	// roto; los 420 días, porque una ruta se arma también con pedidos ya completados.
	o, err := Cargar(entorno(map[string]string{"SERVICE_API_KEY": "k"}))
	if err != nil {
		t.Fatalf("con la llave puesta tenía que cargar: %v", err)
	}
	if o.Poll != time.Minute {
		t.Errorf("el ciclo por defecto es de un minuto; salió %v", o.Poll)
	}
	if o.HistoricoDias != 420 || o.HistoricoPorCiclo != 30 || o.RepasoDias != 3 {
		t.Errorf("el histórico por defecto salió %d/%d/%d", o.HistoricoDias, o.HistoricoPorCiclo, o.RepasoDias)
	}
	if !o.SoloRepartibles {
		t.Error("por defecto sólo se trae lo que puede subir a un camión: era el 2 % del catálogo")
	}
	if o.SoloDomicilio || o.SoloCotizados {
		t.Error("los dos filtros finos van apagados: con ellos el reparto se quedaba con seis pedidos")
	}
}

func TestSoloElUnoEnciendeElCatalogoEntero(t *testing.T) {
	// Comparar con «cualquier cosa que no sea vacío» haría que un `SYNC_TODOS=false`
	// heredado de otro sitio encendiera justo lo contrario de lo que dice.
	o, _ := Cargar(entorno(map[string]string{"SERVICE_API_KEY": "k", "SYNC_TODOS": "false"}))
	if !o.SoloRepartibles {
		t.Error("«false» no puede encender el catálogo entero")
	}
	o, _ = Cargar(entorno(map[string]string{"SERVICE_API_KEY": "k", "SYNC_TODOS": "1"}))
	if o.SoloRepartibles {
		t.Error("«1» sí tiene que encenderlo")
	}
}

func TestLaBarraFinalDeLasDireccionesSeQuita(t *testing.T) {
	// Con ella las rutas salen con `//` en medio, y hay quien contesta 404 a eso sin decir
	// por qué.
	o, _ := Cargar(entorno(map[string]string{
		"SERVICE_API_KEY": "k",
		"PEDIDO_API_URL":  "https://pedido.procovar.cloud/",
	}))
	if o.PedidoURL != "https://pedido.procovar.cloud" {
		t.Errorf("la dirección quedó %q", o.PedidoURL)
	}
}

func TestUnNumeroMalPuestoNoSeIgnora(t *testing.T) {
	// Un cero o una letra en un número de éstos no se puede tragar en silencio: el espejo
	// se quedaría dando vueltas sin recorrer nada y sin un solo error.
	_, err := Cargar(entorno(map[string]string{"SERVICE_API_KEY": "k", "SYNC_TRAMO_DIAS": "0"}))
	if err == nil || !strings.Contains(err.Error(), "SYNC_TRAMO_DIAS") {
		t.Fatalf("tenía que quejarse del tramo; se quejó de %v", err)
	}
}

func TestUnRepasoMasLargoQueElHistoricoNoSeAdmite(t *testing.T) {
	// Dejaría al barrido sin recorrido: giraría en el sitio marcando la misma posición una
	// y otra vez, y el año de en medio no se recuperaría nunca.
	_, err := Cargar(entorno(map[string]string{
		"SERVICE_API_KEY":     "k",
		"SYNC_REPASO_DIAS":    "30",
		"SYNC_HISTORICO_DIAS": "30",
	}))
	if err == nil || !strings.Contains(err.Error(), "SYNC_REPASO_DIAS") {
		t.Fatalf("tenía que quejarse del repaso; se quejó de %v", err)
	}
}
