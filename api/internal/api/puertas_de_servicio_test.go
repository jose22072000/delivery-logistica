package api

import (
	"os"
	"regexp"
	"strings"
	"testing"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/auth"
)

// TODA PERSONA SINTÉTICA DE SERVICIO TIENE QUE VER LAS OCHO SUCURSALES.
//
// Hay tres puertas que no abre una persona sino la llave de servicio: el lote de PEDIDO
// (`/api/quote/batch`), el espejo de productos y el alta de pedidos. Las tres cuelgan del
// contexto un `auth.Usuario` inventado, porque la portería necesita alguien de quien
// partir, y las tres traen datos de LAS OCHO sucursales por definición.
//
// El 16/09/2026 `VeTodasLasSucursales` dejó de ser «no tiene sucursal» y pasó a mirar el
// ROL — que es como tenía que haber sido siempre: «sin sucursal no es por el tipo de
// usuario… un usuario sin sucursal ve todas, eso está malísimo». Dos de las tres puertas
// se actualizaron. La tercera, la de `cotizacion.go`, se quedó sin rol y desde ese momento
// no veía ninguna sucursal: **84 rechazos con 403 en quince minutos**, el lote de PEDIDO
// sin entrar, y ni una línea en la aplicación que lo dijera. Se encontró leyendo el
// registro del servidor.
//
// Esta prueba mira el CÓDIGO y no una petición, a propósito: lo que hay que impedir es que
// alguien añada una cuarta puerta y se le olvide el rol. Montar las tres rutas no cazaría
// la cuarta.
func TestLasPersonasSinteticasDeServicioLlevanSuRol(t *testing.T) {
	// `ID: "servicio…"` es la marca: sólo las inventadas se llaman así.
	patron := regexp.MustCompile(`auth\.Usuario\{[^}]*\}`)
	ficheros := []string{
		"cotizacion.go",
		"espejo.go",
		"pedidos.go",
	}
	encontradas := 0
	for _, nombre := range ficheros {
		crudo, err := os.ReadFile(nombre)
		if err != nil {
			t.Fatalf("no se pudo leer %s: %v", nombre, err)
		}
		for _, hallado := range patron.FindAllString(string(crudo), -1) {
			if !strings.Contains(hallado, `"servicio`) {
				continue
			}
			encontradas++
			if !strings.Contains(hallado, "Rol:") {
				t.Errorf("%s: esta persona de servicio no lleva Rol, así que "+
					"VeTodasLasSucursales dice que no y la portería contesta 403 a "+
					"todo lo que entre por ahí:\n  %s", nombre, hallado)
				continue
			}
			if !strings.Contains(hallado, "SUPER ADMIN") &&
				!strings.Contains(hallado, "DESARROLLADOR") {
				t.Errorf("%s: el rol de esta persona de servicio no es de los que ven "+
					"las ocho:\n  %s", nombre, hallado)
			}
		}
	}
	if encontradas < 3 {
		t.Fatalf("se encontraron %d puertas de servicio y hay 3: o se borró una sin "+
			"quitar su ruta, o cambió la forma de escribirlas y esta prueba dejó de "+
			"mirar lo que cree", encontradas)
	}
}

// Y la otra mitad: que el rol que llevan puesto SIRVA de verdad. Una prueba que sólo mire
// el texto se quedaría verde el día que `VeTodasLasSucursales` cambie de criterio.
func TestElRolDeServicioAbreLasOchoSucursales(t *testing.T) {
	// Escritos a mano y no importados: `auth` los tiene en minúscula y sin exportar, y lo
	// que hay que comprobar es LA CADENA que viaja en el token, tal como la escribe
	// Accesos. Una constante compartida taparía el día en que una de las dos se cambie.
	for _, rol := range []string{"SUPER ADMIN", "DESARROLLADOR"} {
		u := &auth.Usuario{ID: "servicio:pedido", Nombre: "servicio", Rol: rol}
		if !alcance.VeTodasLasSucursales(u) {
			t.Errorf("con el rol %q la persona de servicio no ve las ocho: el lote de "+
				"PEDIDO entraría con 403", rol)
		}
	}
	// Y sin rol NO, que es justo el fallo: sin esto la prueba de arriba no significa nada.
	sinRol := &auth.Usuario{ID: "servicio:pedido", Nombre: "servicio"}
	if alcance.VeTodasLasSucursales(sinRol) {
		t.Error("una persona sin rol y sin sucursal NO puede ver las ocho: es la regla 1 " +
			"de la casa, y que la de servicio pase tiene que ser por su rol")
	}
}
