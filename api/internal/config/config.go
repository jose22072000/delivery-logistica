// Configuración del servicio, leída del entorno UNA vez al arrancar.
//
// POR QUÉ SE VALIDA AQUÍ Y NO DONDE SE USA: una variable que falta y se descubre al
// atender la primera petición que la necesita es un 500 a media tarde, en la pantalla de
// alguien que está cargando un camión, y con el proceso levantado y "sano" para el
// supervisor. Mejor no arrancar: eso lo ve quien despliega, en el momento de desplegar.
//
// Y se juntan TODAS las que faltan en un solo mensaje. Ir de una en una obliga a diez
// despliegues para descubrir diez variables.
package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

// Config es lo que el servicio necesita saber para levantarse.
type Config struct {
	// Entorno
	Entorno string // "desarrollo" | "produccion" — sólo cambia el detalle del registro
	Puerto  string
	Version string // se pone al compilar con -ldflags; el entorno puede pisarlo

	// Base de datos
	DatabaseURL     string
	PoolMaxConns    int32
	PoolMinConns    int32
	PoolMaxIdleTime time.Duration

	// Identidad
	JWTSecret []byte // el mismo con el que firma auth

	// Llave de servicio: el espejo de PEDIDO y las tareas de fondo no traen persona.
	ServiceAPIKey string

	// Tiempos del servidor HTTP
	TiempoLectura   time.Duration
	TiempoEscritura time.Duration
	TiempoApagado   time.Duration

	// Origen permitido para el navegador (la web de Flutter va en otro dominio).
	OrigenesPermitidos []string

	// --- Las otras aplicaciones de la casa -----------------------------------
	//
	// Todas estas se leían con `os.Getenv` en el sitio donde se usaban, porque este
	// fichero estaba ocupado mientras se escribían los módulos en paralelo. Leerlas ahí
	// tenía dos problemas de los que se pagan tarde: una errata en el nombre de la
	// variable no se nota hasta que alguien pulsa el botón que la usa, y no hay un solo
	// sitio donde mirar qué necesita este servicio para funcionar.

	// PedidoAPIURL es la base de PEDIDO. Hace falta para DOS cosas: el canal de salida
	// que le cuenta en qué punto va cada pedido, y `POST /api/admin/recompute`.
	//
	// NO es obligatoria para arrancar, a propósito: sin ella el servicio hace todo lo
	// demás y las dos cosas que la necesitan lo DICEN —el canal devuelve `ok:false` con
	// el motivo, el recosteo un 500 con el nombre de la variable—. Un aviso que nadie
	// recibe y que además se declara enviado es peor que no avisar.
	PedidoAPIURL string

	// DeliveryURL es a dónde manda el recosteo su lote a cotizar. Vacía significa «a mí
	// mismo» (`http://127.0.0.1:PUERTO`), que es lo correcto en el monolito de hoy.
	DeliveryURL string

	// CatalogoCada es cada cuánto se vuelve a bajar el catálogo de Ventra.
	CatalogoCada time.Duration

	// AlmacenesCache es cuánto se recuerda la lista de almacenes de Accesos. Cinco
	// minutos porque hace falta para medir CADA domicilio y no cambia de un minuto a
	// otro: sin recuerdo, cotizar un lote de 200 pedidos son 200 llamadas a Accesos.
	AlmacenesCache time.Duration

	// --- Ventra (el ERP de la casa), que vive detrás de la VPN --------------
	//
	// De ahí sale el CATÁLOGO: nombre, peso, precio y existencias, sucursal por sucursal.
	// No es un MySQL: es una API HTTP de sólo lectura (`docs/API-VENTRA.md`), alcanzable
	// sólo por la red 10.188.2.0/24. En producción la URL es
	// `http://10.188.2.2:3001/api/external-api` y el token, uno permanente de Ventra.
	//
	// NO SON OBLIGATORIAS, igual que PEDIDO_API_URL: sin ellas el servicio arranca y hace
	// todo lo demás, y `POST /api/products/sync` contesta 502 DICIENDO que no hay lector.
	// Eso es lo correcto: un 200 con «0 productos escritos» cuando en realidad no se le ha
	// preguntado a nadie deja al logístico mirando precios de hace tres semanas sin un
	// solo aviso. Aquí NO se les pone valor por defecto —ni siquiera la IP conocida— para
	// que enchufar el lector sea siempre un acto explícito de quien despliega.
	VentraURL   string
	VentraToken string

	// VentraPlazo es lo que se espera a cada petición. Treinta segundos: es un ERP al otro
	// lado de una VPN, no una API de al lado.
	VentraPlazo time.Duration

	// VentraBases empareja NUESTRO código de sucursal con el slug de la base de Ventra
	// (`STG=santiago,HOL=holguinmoa`). Normalmente va vacía: el cliente ya trae la tabla
	// de las diez bases de hoy. Está para el día que Ventra añada o renombre una, que se
	// arregla con una variable en vez de con un despliegue de código — y lo que hay en
	// juego es que una sucursal entera se quede sin catálogo sin que salte nada.
	VentraBases map[string]string

	// Accesos (el login único), que además es de donde salen los almacenes y las tasas.
	// La llave NO tiene valor por defecto: sin ella no hay firma posible y el cliente lo
	// dice antes de salir a la red, porque un «401 de auth» es mucho más difícil de
	// relacionar con una variable que falta.
	AuthURL        string
	AuthClientID   string
	AuthSigningKey string

	// --- La versión de la APLICACIÓN que hay colgada ------------------------
	//
	// Ojo con no confundirla con `Version`, que es la de ESTE servicio y la incrusta el
	// compilador. `Publicada` es la del APK y de los escritorios: la que el logístico
	// tendría que tener instalada. Son dos cosas distintas y por eso son dos campos.
	//
	// Nil significa «no hay ninguna publicada», y entonces `/api/version` devuelve
	// `"ultima": null` y ningún aparato avisa de nada. Eso es lo correcto mientras no
	// haya una descarga de verdad colgada: inventarse una versión haría que diez
	// aparatos mandaran a diez personas a un enlace que no existe.
	Publicada *Publicada
}

// Publicada es la última versión de la aplicación que está colgada para descargar.
//
// Sale del entorno y no de la base a propósito. Publicar es un acto del despliegue —se
// sube el APK a algún sitio y se anuncia—, no un dato del reparto: no tiene alcance por
// sucursal, no lo edita nadie desde una pantalla y no hace falta una migración para
// cambiarlo. Además así `/api/version` sigue siendo un manejador síncrono que no toca
// Postgres, que es lo que permite que lo llamen los diez aparatos a la vez al arrancar.
type Publicada struct {
	// Version es la de `pubspec.yaml` sin el `+`: "1.5.0".
	Version string
	// Compilacion es el número de después del `+` (el `versionCode` de Android). Cero
	// significa «no se dijo»; entonces el aparato compara por el número de versión.
	Compilacion int
	// Notas, una línea de qué trae. Opcional: si está vacía el aviso no la enseña.
	Notas string
	// PublicadaAt en RFC3339. Opcional.
	PublicadaAt string

	// De dónde se baja, una por plataforma. La web NO tiene: se actualiza sola al
	// recargar y no descarga nada.
	Android string
	Windows string
	Linux   string
}

// HayAlguna dice si se anunció algo. Un `Publicada` sin versión no se construye nunca,
// pero el manejador no tiene por qué saberlo.
func (p *Publicada) HayAlguna() bool { return p != nil && p.Version != "" }

// Obligatorias: sin una de éstas el servicio no puede hacer su trabajo, así que no
// arranca. Ojo con relajar esta lista — una variable "opcional" con valor por defecto
// silencioso es la forma de tener producción apuntando a la base de desarrollo.
var obligatorias = []string{"DATABASE_URL", "JWT_SECRET"}

// Cargar lee el entorno y devuelve la configuración ya validada, o un error que dice
// exactamente qué falta.
func Cargar(version string) (*Config, error) {
	var faltan []string
	for _, nombre := range obligatorias {
		if strings.TrimSpace(os.Getenv(nombre)) == "" {
			faltan = append(faltan, nombre)
		}
	}
	if len(faltan) > 0 {
		return nil, fmt.Errorf(
			"faltan variables de entorno obligatorias: %s\n"+
				"  DATABASE_URL  cadena de conexión a Postgres (postgres://usuario:clave@host:5432/base)\n"+
				"  JWT_SECRET    el MISMO secreto con el que firma auth.procovar.cloud; sin él no se puede\n"+
				"                validar a nadie y todas las peticiones serían 401",
			strings.Join(faltan, ", "))
	}

	secreto := os.Getenv("JWT_SECRET")
	// Un secreto corto se rompe por fuerza bruta fuera de línea, y el token que sale de
	// ahí abre la sucursal entera. 32 bytes es el mínimo razonable para HS256.
	if len(secreto) < 32 {
		return nil, fmt.Errorf("JWT_SECRET tiene %d caracteres: hacen falta al menos 32", len(secreto))
	}

	c := &Config{
		Entorno:            valor("ENTORNO", "desarrollo"),
		Puerto:             valor("PUERTO", "8080"),
		Version:            valor("VERSION_APP", version),
		DatabaseURL:        os.Getenv("DATABASE_URL"),
		JWTSecret:          []byte(secreto),
		ServiceAPIKey:      os.Getenv("SERVICE_API_KEY"),
		OrigenesPermitidos: lista("ORIGENES_PERMITIDOS"),

		// Se les quita la barra final AQUÍ y no en cada sitio que las concatena: una
		// barra de más en la variable produce `//integration/orders/status`, que unos
		// servidores toleran y otros contestan con un 404 que nadie sabe explicar.
		PedidoAPIURL:   strings.TrimRight(valor("PEDIDO_API_URL", ""), "/"),
		DeliveryURL:    strings.TrimRight(valor("DELIVERY_URL", ""), "/"),
		AuthURL:        strings.TrimRight(valor("PROCOVAR_AUTH_URL", "https://auth.procovar.cloud"), "/"),
		AuthClientID:   valor("PROCOVAR_AUTH_CLIENT_ID", "delivery"),
		AuthSigningKey: strings.TrimSpace(os.Getenv("PROCOVAR_AUTH_SIGNING_KEY")),

		VentraURL:   strings.TrimRight(valor("WAREHOUSE_API_URL", ""), "/"),
		VentraToken: strings.TrimSpace(os.Getenv("WAREHOUSE_API_TOKEN")),
	}

	var errs []error
	var err error

	if c.Entorno != "desarrollo" && c.Entorno != "produccion" {
		errs = append(errs, fmt.Errorf("ENTORNO vale %q: sólo se admite \"desarrollo\" o \"produccion\"", c.Entorno))
	}
	if _, err := strconv.Atoi(c.Puerto); err != nil {
		errs = append(errs, fmt.Errorf("PUERTO vale %q y no es un número", c.Puerto))
	}
	// pgx acepta tanto la URL como el formato clave=valor; si no es ninguno, que se vea
	// ahora y no en el primer intento de conexión.
	if !strings.HasPrefix(c.DatabaseURL, "postgres://") &&
		!strings.HasPrefix(c.DatabaseURL, "postgresql://") &&
		!strings.Contains(c.DatabaseURL, "=") {
		errs = append(errs, errors.New("DATABASE_URL no parece una cadena de conexión de Postgres"))
	}

	if c.PoolMaxConns, err = entero32("POOL_MAX_CONNS", 10); err != nil {
		errs = append(errs, err)
	}
	if c.PoolMinConns, err = entero32("POOL_MIN_CONNS", 2); err != nil {
		errs = append(errs, err)
	}
	if c.PoolMaxConns > 0 && c.PoolMinConns > c.PoolMaxConns {
		errs = append(errs, fmt.Errorf("POOL_MIN_CONNS (%d) es mayor que POOL_MAX_CONNS (%d)", c.PoolMinConns, c.PoolMaxConns))
	}
	if c.PoolMaxIdleTime, err = duracion("POOL_MAX_IDLE", 5*time.Minute); err != nil {
		errs = append(errs, err)
	}
	if c.TiempoLectura, err = duracion("TIEMPO_LECTURA", 15*time.Second); err != nil {
		errs = append(errs, err)
	}
	if c.TiempoEscritura, err = duracion("TIEMPO_ESCRITURA", 30*time.Second); err != nil {
		errs = append(errs, err)
	}
	// El apagado ordenado no puede durar más que el plazo que le da quien nos para
	// (Docker manda SIGKILL a los 10 s por defecto): pasado ese punto se corta igual, y
	// entonces sí se pierden las peticiones en vuelo.
	if c.TiempoApagado, err = duracion("TIEMPO_APAGADO", 8*time.Second); err != nil {
		errs = append(errs, err)
	}

	// Las URLs de las otras aplicaciones se comprueban AQUÍ aunque sean opcionales. Una
	// `PEDIDO_API_URL=pedido.procovar.cloud` sin esquema no falla al arrancar ni al
	// concatenar: falla al hacer la petición, dentro de una goroutine de fondo, y lo
	// único que se ve es un aviso que no llegó.
	for _, u := range []struct{ nombre, valor string }{
		{"PEDIDO_API_URL", c.PedidoAPIURL},
		{"DELIVERY_URL", c.DeliveryURL},
		{"PROCOVAR_AUTH_URL", c.AuthURL},
		{"WAREHOUSE_API_URL", c.VentraURL},
	} {
		if u.valor == "" {
			continue // vacía es «no configurada», y cada quien sabe qué hacer con eso
		}
		if !strings.HasPrefix(u.valor, "http://") && !strings.HasPrefix(u.valor, "https://") {
			errs = append(errs, fmt.Errorf(
				"%s vale %q: tiene que empezar por http:// o https://", u.nombre, u.valor))
		}
	}

	if c.CatalogoCada, err = milisegundos("CATALOGO_CADA_MS", 12*time.Hour); err != nil {
		errs = append(errs, err)
	}
	if c.AlmacenesCache, err = milisegundos("ALMACENES_CACHE_MS", 5*time.Minute); err != nil {
		errs = append(errs, err)
	}
	if c.VentraPlazo, err = milisegundos("WAREHOUSE_TIMEOUT_MS", 30*time.Second); err != nil {
		errs = append(errs, err)
	}
	if c.VentraBases, err = pares("VENTRA_BASES"); err != nil {
		errs = append(errs, err)
	}

	pub, errsPub := leerPublicada()
	c.Publicada = pub
	errs = append(errs, errsPub...)

	if len(errs) > 0 {
		return nil, fmt.Errorf("configuración no válida:\n  - %s", unirErrores(errs))
	}
	return c, nil
}

// EnProduccion dice si hay que ser parco en el registro y no soltar detalles de error
// hacia fuera.
func (c *Config) EnProduccion() bool { return c.Entorno == "produccion" }

// Direccion es lo que se le pasa a net/http.
func (c *Config) Direccion() string { return ":" + c.Puerto }

func valor(nombre, porDefecto string) string {
	if v := strings.TrimSpace(os.Getenv(nombre)); v != "" {
		return v
	}
	return porDefecto
}

func lista(nombre string) []string {
	crudo := strings.TrimSpace(os.Getenv(nombre))
	if crudo == "" {
		return nil
	}
	var salida []string
	for _, p := range strings.Split(crudo, ",") {
		if p = strings.TrimSpace(p); p != "" {
			salida = append(salida, p)
		}
	}
	return salida
}

// pares lee una variable con la forma `CLAVE=valor,CLAVE=valor` y la devuelve como mapa,
// con las claves en mayúsculas. Vacía es un mapa vacío, no un error.
//
// Se valida AQUÍ y no donde se usa por lo de siempre: un `VENTRA_BASES=STG santiago` que
// se ignora en silencio deja a Santiago sin catálogo, y eso no se ve hasta que alguien
// busca un producto y no está.
func pares(nombre string) (map[string]string, error) {
	crudo := strings.TrimSpace(os.Getenv(nombre))
	if crudo == "" {
		return map[string]string{}, nil
	}
	salida := map[string]string{}
	for _, p := range strings.Split(crudo, ",") {
		if p = strings.TrimSpace(p); p == "" {
			continue
		}
		clave, valor, hay := strings.Cut(p, "=")
		clave, valor = strings.TrimSpace(clave), strings.TrimSpace(valor)
		if !hay || clave == "" || valor == "" {
			return nil, fmt.Errorf(
				"%s tiene %q, que no es un par CLAVE=valor: se escribe como STG=santiago,HOL=holguinmoa",
				nombre, p)
		}
		salida[strings.ToUpper(clave)] = valor
	}
	return salida, nil
}

func entero32(nombre string, porDefecto int32) (int32, error) {
	crudo := strings.TrimSpace(os.Getenv(nombre))
	if crudo == "" {
		return porDefecto, nil
	}
	n, err := strconv.ParseInt(crudo, 10, 32)
	if err != nil {
		return 0, fmt.Errorf("%s vale %q y no es un número entero", nombre, crudo)
	}
	if n <= 0 {
		return 0, fmt.Errorf("%s vale %d: tiene que ser mayor que cero", nombre, n)
	}
	return int32(n), nil
}

func duracion(nombre string, porDefecto time.Duration) (time.Duration, error) {
	crudo := strings.TrimSpace(os.Getenv(nombre))
	if crudo == "" {
		return porDefecto, nil
	}
	d, err := time.ParseDuration(crudo)
	if err != nil {
		return 0, fmt.Errorf("%s vale %q y no es una duración (ejemplos: 30s, 5m, 1h)", nombre, crudo)
	}
	if d <= 0 {
		return 0, fmt.Errorf("%s vale %q: tiene que ser mayor que cero", nombre, crudo)
	}
	return d, nil
}

// milisegundos lee una variable que viene EN MILISEGUNDOS y no como duración de Go.
//
// Son las que ya venían así de delivery (`CATALOGO_CADA_MS`, `ALMACENES_CACHE_MS`) y se
// conserva el formato a propósito: cambiarlo a `12h` obligaría a tocar el entorno de los
// despliegues que ya existen, y una variable que se relee mal en silencio —`12h` leído
// como número da 0— es un temporizador que se dispara sin parar.
func milisegundos(nombre string, porDefecto time.Duration) (time.Duration, error) {
	crudo := strings.TrimSpace(os.Getenv(nombre))
	if crudo == "" {
		return porDefecto, nil
	}
	ms, err := strconv.Atoi(crudo)
	if err != nil {
		return 0, fmt.Errorf("%s vale %q y no es un número de milisegundos", nombre, crudo)
	}
	if ms <= 0 {
		return 0, fmt.Errorf("%s vale %d: tiene que ser mayor que cero", nombre, ms)
	}
	return time.Duration(ms) * time.Millisecond, nil
}

func unirErrores(errs []error) string {
	textos := make([]string, 0, len(errs))
	for _, e := range errs {
		textos = append(textos, e.Error())
	}
	return strings.Join(textos, "\n  - ")
}

// leerPublicada arma el anuncio de la última versión de la aplicación, o devuelve nil si
// no se anunció ninguna.
//
// LA MITAD DE UNA CONFIGURACIÓN ES UN ERROR, NO UN VALOR POR DEFECTO. Poner la URL del
// APK y olvidarse de `APP_ULTIMA_VERSION` deja un anuncio que no se manda nunca: nadie se
// entera de que hay versión nueva, no aparece un solo error, y desde fuera se ve como
// «los aparatos no avisan». Al revés —versión sin ninguna descarga— es peor todavía: diez
// personas enteradas de que tienen que actualizar y ningún sitio de donde bajarlo. Las
// dos cosas paran el arranque, que es cuando lo ve quien despliega.
func leerPublicada() (*Publicada, []error) {
	p := &Publicada{
		Version:     valor("APP_ULTIMA_VERSION", ""),
		Notas:       valor("APP_ULTIMA_NOTAS", ""),
		PublicadaAt: valor("APP_ULTIMA_PUBLICADA", ""),
		Android:     strings.TrimSpace(os.Getenv("APP_DESCARGA_ANDROID")),
		Windows:     strings.TrimSpace(os.Getenv("APP_DESCARGA_WINDOWS")),
		Linux:       strings.TrimSpace(os.Getenv("APP_DESCARGA_LINUX")),
	}
	descargas := []struct{ nombre, valor string }{
		{"APP_DESCARGA_ANDROID", p.Android},
		{"APP_DESCARGA_WINDOWS", p.Windows},
		{"APP_DESCARGA_LINUX", p.Linux},
	}
	compilacion := strings.TrimSpace(os.Getenv("APP_ULTIMA_COMPILACION"))

	if p.Version == "" {
		var sueltas []string
		for _, d := range descargas {
			if d.valor != "" {
				sueltas = append(sueltas, d.nombre)
			}
		}
		if compilacion != "" {
			sueltas = append(sueltas, "APP_ULTIMA_COMPILACION")
		}
		if len(sueltas) > 0 {
			return nil, []error{fmt.Errorf(
				"%s está puesta pero APP_ULTIMA_VERSION no: sin número de versión no se anuncia "+
					"nada y los aparatos no se enteran de que hay una nueva",
				strings.Join(sueltas, ", "))}
		}
		// Nada anunciado, que es lo normal hasta que haya una descarga de verdad colgada.
		return nil, nil
	}

	var errs []error

	// Al menos un sitio de donde bajarla. La web no cuenta: se actualiza sola.
	hayDonde := false
	for _, d := range descargas {
		if d.valor == "" {
			continue
		}
		hayDonde = true
		if !strings.HasPrefix(d.valor, "http://") && !strings.HasPrefix(d.valor, "https://") {
			errs = append(errs, fmt.Errorf(
				"%s vale %q: tiene que empezar por http:// o https://", d.nombre, d.valor))
		}
	}
	if !hayDonde {
		errs = append(errs, errors.New(
			"APP_ULTIMA_VERSION está puesta pero no hay ninguna APP_DESCARGA_*: se avisaría de una "+
				"versión nueva sin decir de dónde bajarla"))
	}

	if compilacion != "" {
		n, err := strconv.Atoi(compilacion)
		switch {
		case err != nil:
			errs = append(errs, fmt.Errorf(
				"APP_ULTIMA_COMPILACION vale %q y no es un número (es el de después del `+` en "+
					"pubspec.yaml, el mismo `versionCode` que compara Android)", compilacion))
		case n <= 0:
			errs = append(errs, fmt.Errorf("APP_ULTIMA_COMPILACION vale %d: tiene que ser mayor que cero", n))
		default:
			p.Compilacion = n
		}
	}

	// La fecha se admite en los dos formatos que una persona escribe a mano y se guarda
	// normalizada: un `publicadaAt` que el aparato no sepa leer sale como «sin fecha» y
	// eso no se distingue de no haberla puesto.
	if p.PublicadaAt != "" {
		normal, err := fecha(p.PublicadaAt)
		if err != nil {
			errs = append(errs, err)
		} else {
			p.PublicadaAt = normal
		}
	}

	if len(errs) > 0 {
		return nil, errs
	}
	return p, nil
}

func fecha(crudo string) (string, error) {
	for _, formato := range []string{time.RFC3339, "2006-01-02"} {
		if t, err := time.Parse(formato, crudo); err == nil {
			return t.UTC().Format(time.RFC3339), nil
		}
	}
	return "", fmt.Errorf(
		"APP_ULTIMA_PUBLICADA vale %q: se espera 2026-09-15 o 2026-09-15T10:00:00Z", crudo)
}
