package sincro

import "testing"

// LAS OCHO COLECCIONES SON UN CONTRATO, NO UN COMENTARIO.
//
// `Colecciones` lleva encima una promesa escrita —«se contestan SIEMPRE los ocho, aunque
// vengan vacíos»— y hasta el 17/09/2026 no la respaldaba nada: **borrar `"routes"` de esa
// lista dejaba toda la suite de `sync/` en verde** y, con ella, una colección entera sin
// sincronizar. El aparato hace `continue` sobre una clave que no viene, así que no hay
// error, ni aviso, ni lista vacía sospechosa: las rutas simplemente dejan de llegar y nadie
// se entera hasta que alguien echa de menos una.
//
// Es la misma familia que el §3-bis del `CLAUDE.md`: **un comentario no falla.**
//
// Se comprueba el conjunto Y el orden: el orden es el del protocolo
// (`docs/sincronizacion.md`) y el aparato aplica en ese orden por una razón —los pedidos
// antes que las rutas, porque una parada apunta a su ruta—.
func TestLasOchoColeccionesSonLasDelProtocolo(t *testing.T) {
	quiere := []string{
		"orders", "routes", "customers", "products",
		"vehicles", "branches", "warehouses", "settings",
	}

	if len(Colecciones) != len(quiere) {
		t.Fatalf(
			"la bajada contesta %d colecciones y el protocolo son %d: %v.\n"+
				"Una colección que desaparece de esta lista deja de sincronizarse EN "+
				"SILENCIO — el aparato no distingue «no cambió nada» de «no vino».",
			len(Colecciones), len(quiere), Colecciones,
		)
	}
	for i, c := range quiere {
		if Colecciones[i] != c {
			t.Errorf(
				"en el puesto %d se esperaba %q y hay %q.\n"+
					"El orden es el del protocolo y no es decorativo: el aparato aplica "+
					"en este orden, y los pedidos van antes que las rutas porque una "+
					"parada apunta a su ruta.",
				i, c, Colecciones[i],
			)
		}
	}
}
