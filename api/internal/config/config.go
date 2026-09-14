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
}

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

func unirErrores(errs []error) string {
	textos := make([]string, 0, len(errs))
	for _, e := range errs {
		textos = append(textos, e.Error())
	}
	return strings.Join(textos, "\n  - ")
}
