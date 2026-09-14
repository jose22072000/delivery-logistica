// Package config lee el entorno una sola vez, al arrancar, y falla ahí mismo si falta algo.
//
// El porqué de fallar al arrancar y no al primer uso: este servicio vive en un VPS y se
// despliega con Dokploy. Una variable mal puesta que sólo se note cuando un logístico
// intenta subir la cola del día es un fallo que se descubre en el peor momento posible —en
// la calle, con el trabajo dentro del teléfono—. Al arrancar, en cambio, lo ve el que
// despliega.
package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	// Dónde escucha. Detrás va un proxy que termina TLS.
	Direccion string

	// La base del sincronizador. Aquí NO viven los datos del reparto: sólo la
	// contabilidad de la sincronización.
	BaseDeDatos   string
	MaxConexiones int32

	// El reparto (`reparto-api`), que es el dueño de los datos. La bajada le pide
	// diferencias y la subida le manda cada apunte: este servicio no escribe pedidos.
	RepartoURL    string
	RepartoClave  string
	RepartoTiempo time.Duration

	// De dónde sale quién está llamando. Ver `internal/identidad`.
	Identidad string

	// Cuántas filas como mucho en una tanda de la bajada antes de contestar
	// `truncado: true`. Existe porque la primera bajada de una sucursal grande no cabe
	// de una vez en la conexión de allá.
	TopeBajada int32

	EsperaLectura   time.Duration
	EsperaEscritura time.Duration
}

// Cargar junta TODOS los fallos antes de devolver, en vez de parar en el primero: quien
// despliega ve de una vez todo lo que le falta y no arranca cinco veces seguidas.
func Cargar() (Config, error) {
	var fallos []string

	c := Config{
		Direccion:       texto("SYNC_ADDR", ":8081"),
		BaseDeDatos:     os.Getenv("DATABASE_URL"),
		RepartoURL:      strings.TrimRight(os.Getenv("REPARTO_URL"), "/"),
		RepartoClave:    os.Getenv("REPARTO_API_KEY"),
		Identidad:       os.Getenv("SYNC_IDENTIDAD"),
		MaxConexiones:   entero("SYNC_DB_MAX_CONNS", 10),
		TopeBajada:      entero("SYNC_TOPE_BAJADA", 500),
		RepartoTiempo:   espera("SYNC_REPARTO_TIMEOUT", 30*time.Second),
		EsperaLectura:   espera("SYNC_READ_TIMEOUT", 15*time.Second),
		EsperaEscritura: espera("SYNC_WRITE_TIMEOUT", 60*time.Second),
	}

	if c.BaseDeDatos == "" {
		fallos = append(fallos, "falta DATABASE_URL")
	}
	if c.RepartoURL == "" {
		fallos = append(fallos, "falta REPARTO_URL (el sincronizador no es dueño de los datos: se los pide al reparto)")
	}
	// La clave de servicio no es opcional: las rutas de `reparto-api` que se llaman desde
	// aquí van con `x-api-key` y sin ella todo respondería 401 apunte por apunte, que el
	// aparato leería como diez rechazos seguidos.
	if c.RepartoClave == "" {
		fallos = append(fallos, "falta REPARTO_API_KEY")
	}
	// A propósito no hay valor por defecto. Mientras el verificador del token de auth no
	// esté, la identidad viene en cabeceras que pone el proxy de delante, y eso sólo es
	// seguro si NADIE más puede llegar a este puerto. Que haya que escribirlo a mano
	// obliga a mirar esa frase antes de publicar el servicio.
	if c.Identidad != "cabeceras" {
		fallos = append(fallos, `falta SYNC_IDENTIDAD=cabeceras (de dónde sale quién llama; ver internal/identidad)`)
	}
	if c.TopeBajada <= 0 {
		fallos = append(fallos, "SYNC_TOPE_BAJADA tiene que ser mayor que cero")
	}

	if len(fallos) > 0 {
		return Config{}, errors.New("configuración incompleta: " + strings.Join(fallos, "; "))
	}
	return c, nil
}

func texto(clave, porDefecto string) string {
	if v := os.Getenv(clave); v != "" {
		return v
	}
	return porDefecto
}

func entero(clave string, porDefecto int32) int32 {
	v := os.Getenv(clave)
	if v == "" {
		return porDefecto
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return porDefecto
	}
	return int32(n)
}

func espera(clave string, porDefecto time.Duration) time.Duration {
	v := os.Getenv(clave)
	if v == "" {
		return porDefecto
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return porDefecto
	}
	return d
}

func (c Config) String() string {
	// Sin la clave de servicio ni la cadena de la base: esto se registra al arrancar.
	return fmt.Sprintf("direccion=%s reparto=%s identidad=%s tope_bajada=%d",
		c.Direccion, c.RepartoURL, c.Identidad, c.TopeBajada)
}
