package api

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"testing"
)

// LOS TIPOS DE AVISO SON UN CONTRATO ENTRE DOS FICHEROS QUE NO SE VEN.
//
// El servidor publica el tipo de cambio en `eventos.go` (`CambioPedidos`,
// `CambioVehiculos`…) y la aplicación lo espera en
// `app/lib/nucleo/refresco_en_vivo.dart` (`CambioEnVivo.pedidos`,
// `CambioEnVivo.vehiculos`…). Son **dos listas escritas a mano, en dos lenguajes
// distintos, y hasta hoy no había nada que las comparara**.
//
// Comprobado el 17/09/2026: cambiar `CambioVehiculos = "vehiculos"` por
// `"vehiculo"` dejaba `go build`, `go vet` y `go test ./...` en verde, y Flutter
// ni se enteraba. En producción eso es la pantalla de Vehículos que deja de
// refrescarse en vivo — y **Vehículos y Almacenes no viven de la base local**
// (`estado_vehiculos.dart`, `estado_almacenes.dart`), así que el ciclo de
// sincronización tampoco las repinta: se quedan clavadas hasta salir y volver a
// entrar. Sin un error, sin un registro, sin nada.
//
// Es el fallo de la casa: **medio protocolo**. Una cabecera que se escribe y
// nadie lee, un canal que existe y nadie escucha. Añadir un tipo no rompe nada
// —el que no lo espera lo ignora—; **renombrar un extremo sí**, y ésa es la
// única puerta que esto cierra: no se puede renombrar un lado sin que el otro se
// entere.
//
// # Por qué en Go y leyendo el Dart, y no al revés
//
// Porque este lado corre en todas partes sin SDK, sin emulador y en segundos, y
// porque `deploy/Dockerfile.api` ya hace `go vet && go test` antes de construir
// —que es el último portón antes de producción, y el que faltó el 16/09/2026—.
// Por eso ese Dockerfile copia también el fichero Dart: sin él esta prueba no
// puede correr, y una prueba que se salta sola no vigila nada. Hay precedente de
// prueba que lee un fichero fuente en `internal/store/contador_y_lista_test.go`.
//
// # LO QUE ESTA PRUEBA **NO** ATA, y hay que saberlo
//
// Ata las dos LISTAS: los tipos de `eventos.go` y los de `CambioEnVivo`. Lo que
// no puede ver es a quien no use la constante: un `.where((t) => t == 'tablero')`
// escrito a mano seguiría compilando aunque se arreglaran los dos extremos.
// Hoy no queda ninguno —el Tablero pasó a `CambioEnVivo.tablero` el 17/09/2026—
// y por eso esto se queda escrito: el día que alguien escriba otro, esta prueba
// NO lo va a cazar.
//
// Y el `assert` de `refrescarConElAviso` no es red de nada: valida contra la
// propia lista de Dart, así que un tipo mal escrito en los DOS sitios de Dart
// pasa por él sin decir ni pío.

// El nombre de las constantes del servidor es lo que las hace reconocibles:
// `Cambio` + lo que cambió. Un tipo nuevo que no siga esto no lo ve esta prueba,
// así que **no se sale del convenio**.
const prefijoDeLosTipos = "Cambio"

// Qué se queda sin enterarse si un tipo se pierde por el camino. Es para que el
// mensaje de esta prueba diga algo que se pueda hacer, en vez de un nombre.
var quienSeQuedaSinEnterarse = map[string]string{
	"pedidos":  "la lista de Pedidos y su detalle",
	"catalogo": "el catálogo y los precios",
	"rutas":    "la pantalla de Rutas",
	"clientes": "la lista de Clientes",
	"tablero":  "el Tablero, que es la pantalla que dos personas miran a la vez",
	"vehiculos": "la pantalla de Vehículos, que NO vive de la base local " +
		"(el ciclo tampoco la repinta)",
	"almacenes": "la pantalla de Almacenes, que NO vive de la base local " +
		"(el ciclo tampoco la repinta)",
	"sucursales": "el selector de sucursal de la barra y el de Rutas",
	"ajustes":    "la tasa y la moneda, con las que se convierte TODO importe que se pinta",
}

func TestLosTiposDeAvisoSonLosMismosEnGoYEnDart(t *testing.T) {
	enGo := tiposDeAvisoEnGo(t)
	enDart := tiposDeAvisoEnDart(t)

	for _, nombre := range clavesOrdenadas(enGo) {
		valor := enGo[nombre]
		if _, hay := enDart[valor]; !hay {
			t.Errorf(
				"el servidor publica el aviso %q (%s%s, api/internal/api/eventos.go) y la "+
					"aplicación NO lo espera.\n"+
					"  Nadie se entera en vivo: %s.\n"+
					"  No falla, no hay error y no sale en ningún registro: el aviso llega y se "+
					"tira.\n"+
					"  Arréglalo en app/lib/nucleo/refresco_en_vivo.dart (CambioEnVivo), y "+
					"acuérdate de meterlo también en la lista `todos`.\n"+
					"  Tipos que espera hoy la aplicación: %v",
				valor, prefijoDeLosTipos, nombre, aQuienLeDuele(valor),
				clavesOrdenadas(enDart),
			)
		}
	}

	for _, valor := range clavesOrdenadas(enDart) {
		if _, hay := porValor(enGo)[valor]; !hay {
			t.Errorf(
				"la aplicación espera el aviso %q (CambioEnVivo.%s, "+
					"app/lib/nucleo/refresco_en_vivo.dart) y el servidor NO lo publica.\n"+
					"  Ese aviso no llega nunca: %s se queda con lo que pintó al abrirse.\n"+
					"  Arréglalo en api/internal/api/eventos.go, o quítalo entero de Dart "+
					"(tipo, `todos` y quien lo use).\n"+
					"  Tipos que publica hoy el servidor: %v",
				valor, enDart[valor], aQuienLeDuele(valor), clavesOrdenadas(porValor(enGo)),
			)
		}
	}
}

// Y TIENEN QUE ESTAR EN `todos`, porque es contra esa lista contra la que valida
// el `assert` de `refrescarConElAviso`. Un tipo declarado y fuera de `todos` es
// una pantalla que se lleva un fallo de aserción en depuración y nada en
// producción — o sea, otra vez la pantalla vieja y nadie sabiendo por qué.
func TestCadaTipoDeDartEstaEnLaListaTodos(t *testing.T) {
	enDart := tiposDeAvisoEnDart(t)
	todos := laListaTodosDeDart(t)

	for _, valor := range clavesOrdenadas(enDart) {
		nombre := enDart[valor]
		if !todos[nombre] {
			t.Errorf(
				"CambioEnVivo.%s (%q) no está en `CambioEnVivo.todos`.\n"+
					"  `refrescarConElAviso` valida contra esa lista: la pantalla que lo pida "+
					"salta en depuración y en producción se queda con el temporizador.",
				nombre, valor,
			)
		}
	}
}

// Los tipos que publica el servidor: toda constante `Cambio…` del paquete cuyo
// valor sea un texto. Se lee con el analizador de Go y no con una expresión
// regular a propósito — un `Cambio…` dentro de un comentario o de una cadena no
// es una constante, y ya pasó que un comentario apagara una prueba parecida
// (`internal/store/contador_y_lista_test.go`).
func tiposDeAvisoEnGo(t *testing.T) map[string]string {
	t.Helper()

	entradas, err := os.ReadDir(".")
	if err != nil {
		t.Fatalf("no se pudo leer el paquete: %v", err)
	}

	tipos := map[string]string{}
	fset := token.NewFileSet()
	for _, e := range entradas {
		nombre := e.Name()
		if e.IsDir() || !strings.HasSuffix(nombre, ".go") || strings.HasSuffix(nombre, "_test.go") {
			continue
		}
		fichero, err := parser.ParseFile(fset, nombre, nil, parser.SkipObjectResolution)
		if err != nil {
			t.Fatalf("no se pudo leer %s: %v", nombre, err)
		}
		for _, decl := range fichero.Decls {
			gen, ok := decl.(*ast.GenDecl)
			if !ok || gen.Tok != token.CONST {
				continue
			}
			for _, spec := range gen.Specs {
				valores, ok := spec.(*ast.ValueSpec)
				if !ok {
					continue
				}
				for i, ident := range valores.Names {
					if !strings.HasPrefix(ident.Name, prefijoDeLosTipos) || i >= len(valores.Values) {
						continue
					}
					lit, ok := valores.Values[i].(*ast.BasicLit)
					if !ok || lit.Kind != token.STRING {
						continue
					}
					texto, err := strconv.Unquote(lit.Value)
					if err != nil {
						continue
					}
					tipos[strings.TrimPrefix(ident.Name, prefijoDeLosTipos)] = texto
				}
			}
		}
	}

	if len(tipos) == 0 {
		t.Fatalf(
			"no se encontró ni una constante %q… en el paquete api. O se renombraron todas, "+
				"o esta prueba dejó de mirar donde hay que mirar: en cualquiera de los dos "+
				"casos el contrato se quedó sin vigilar.",
			prefijoDeLosTipos,
		)
	}
	return tipos
}

// El cuerpo de la clase `CambioEnVivo` del fichero Dart, sin comentarios.
func cuerpoDeCambioEnVivo(t *testing.T) string {
	t.Helper()

	crudo, err := os.ReadFile(rutaDelRefrescoEnVivo)
	if err != nil {
		t.Fatalf(
			"no se pudo leer %s: %v\n"+
				"Esta prueba compara los tipos de aviso del servidor con los que espera la "+
				"aplicación, así que necesita el fichero de Dart. Si esto salta dentro de una "+
				"imagen, es que el Dockerfile dejó de copiarlo (ver deploy/Dockerfile.api): "+
				"sin él el contrato se queda sin vigilante justo antes de desplegar.",
			rutaDelRefrescoEnVivo, err,
		)
	}

	dart := sinComentariosDeDart(string(crudo))
	i := strings.Index(dart, "class CambioEnVivo")
	if i < 0 {
		t.Fatalf("no está la clase CambioEnVivo en %s", rutaDelRefrescoEnVivo)
	}
	abre := strings.Index(dart[i:], "{")
	if abre < 0 {
		t.Fatalf("la clase CambioEnVivo de %s no abre llave", rutaDelRefrescoEnVivo)
	}
	inicio := i + abre
	nivel := 0
	for j := inicio; j < len(dart); j++ {
		switch dart[j] {
		case '{':
			nivel++
		case '}':
			nivel--
			if nivel == 0 {
				return dart[inicio+1 : j]
			}
		}
	}
	t.Fatalf("la clase CambioEnVivo de %s no cierra llave", rutaDelRefrescoEnVivo)
	return ""
}

var rutaDelRefrescoEnVivo = filepath.Join(
	"..", "..", "..", "app", "lib", "nucleo", "refresco_en_vivo.dart",
)

// `valor` -> `nombre de la constante en Dart`. Se indexa por valor porque es el
// valor lo que viaja por el cable; el nombre sólo sirve para el mensaje.
func tiposDeAvisoEnDart(t *testing.T) map[string]string {
	t.Helper()

	tipos := map[string]string{}
	for _, m := range constanteDeDart.FindAllStringSubmatch(cuerpoDeCambioEnVivo(t), -1) {
		valor := m[2] + m[3] // una de las dos comillas; la otra viene vacía
		if otro, repetido := tipos[valor]; repetido {
			t.Errorf(
				"el tipo %q está dos veces en CambioEnVivo (%s y %s): uno de los dos sobra",
				valor, otro, m[1],
			)
		}
		tipos[valor] = m[1]
	}

	if len(tipos) == 0 {
		t.Fatalf(
			"no se encontró ni un tipo en CambioEnVivo (%s). O se vació la clase, o esta "+
				"prueba dejó de entender cómo está escrita: en los dos casos el contrato se "+
				"quedó sin vigilante.",
			rutaDelRefrescoEnVivo,
		)
	}
	return tipos
}

// Los nombres que aparecen dentro de `CambioEnVivo.todos`.
func laListaTodosDeDart(t *testing.T) map[string]bool {
	t.Helper()

	m := listaTodosDeDart.FindStringSubmatch(cuerpoDeCambioEnVivo(t))
	if m == nil {
		t.Fatalf(
			"no está la lista `todos` en CambioEnVivo (%s), y es contra ella contra la que "+
				"valida `refrescarConElAviso`",
			rutaDelRefrescoEnVivo,
		)
	}
	nombres := map[string]bool{}
	for _, trozo := range strings.Split(m[1], ",") {
		if n := strings.TrimSpace(trozo); n != "" {
			nombres[n] = true
		}
	}
	return nombres
}

var (
	// `static const pedidos = 'pedidos';` — con comilla simple o doble. La lista
	// `todos` no cae aquí porque su valor no es un texto.
	constanteDeDart = regexp.MustCompile(
		`static\s+const\s+(\w+)\s*=\s*(?:'([^']*)'|"([^"]*)")\s*;`,
	)
	listaTodosDeDart = regexp.MustCompile(
		`static\s+const\s+todos\s*=\s*<\s*String\s*>\s*\[([^\]]*)\]`,
	)
)

// Quita los comentarios de Dart SIN cortar dentro de un texto.
//
// Un `//` dentro de una cadena no abre un comentario, y un `'` dentro de un
// comentario no abre una cadena. Cortar a lo bruto por `//` deja esta prueba a
// merced de cómo alguien redacte un comentario, que es exactamente el fallo que
// ya se cazó en `internal/store/contador_y_lista_test.go`.
func sinComentariosDeDart(dart string) string {
	var limpio strings.Builder
	limpio.Grow(len(dart))

	var comilla byte
	for i := 0; i < len(dart); i++ {
		c := dart[i]
		if comilla != 0 {
			limpio.WriteByte(c)
			switch {
			case c == '\\' && i+1 < len(dart):
				i++
				limpio.WriteByte(dart[i])
			case c == comilla:
				comilla = 0
			}
			continue
		}
		if c == '\'' || c == '"' {
			comilla = c
			limpio.WriteByte(c)
			continue
		}
		if c == '/' && i+1 < len(dart) && dart[i+1] == '/' {
			for i < len(dart) && dart[i] != '\n' {
				i++
			}
			limpio.WriteByte('\n')
			continue
		}
		if c == '/' && i+1 < len(dart) && dart[i+1] == '*' {
			fin := strings.Index(dart[i+2:], "*/")
			if fin < 0 {
				break
			}
			i += 2 + fin + 1
			limpio.WriteByte(' ')
			continue
		}
		limpio.WriteByte(c)
	}
	return limpio.String()
}

func aQuienLeDuele(tipo string) string {
	if quien, hay := quienSeQuedaSinEnterarse[tipo]; hay {
		return quien
	}
	return "la pantalla que enseñe eso (añádela a `quienSeQuedaSinEnterarse` en esta prueba)"
}

// Las claves, ordenadas, para que el mensaje salga siempre igual.
func clavesOrdenadas(m map[string]string) []string {
	claves := make([]string, 0, len(m))
	for k := range m {
		claves = append(claves, k)
	}
	sort.Strings(claves)
	return claves
}

// Le da la vuelta al mapa: lo que viaja por el cable es el VALOR, así que es por
// ahí por donde hay que comparar; el nombre sólo sirve para el mensaje.
func porValor(m map[string]string) map[string]string {
	vuelta := make(map[string]string, len(m))
	for nombre, valor := range m {
		vuelta[valor] = nombre
	}
	return vuelta
}
