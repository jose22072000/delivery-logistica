// Package reparto es la frontera con `reparto-api`, que es el dueño de los datos.
//
// El sincronizador no escribe pedidos ni rutas: pide diferencias y reenvía apuntes. Toda la
// lógica de negocio —quién puede armar una ruta, si el peso cabe en el vehículo, si esos
// pedidos ya están en otra— vive allí y se queda allí. Aquí sólo se traduce entre HTTP y
// las dos interfaces de `internal/sincro`.
package reparto

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"time"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/sincro"
)

type Cliente struct {
	base  string
	clave string
	http  *http.Client
}

var (
	_ sincro.Origen    = (*Cliente)(nil)
	_ sincro.Aplicador = (*Cliente)(nil)
)

func Nuevo(base, clave string, espera time.Duration) *Cliente {
	return &Cliente{
		base:  base,
		clave: clave,
		http:  &http.Client{Timeout: espera},
	}
}

type sobreCambios struct {
	Cambios  sincro.Cambios `json:"cambios"`
	Truncado bool           `json:"truncado"`
}

// Diferencias le pide al reparto lo que cambió en la ventana. La ventana entera —el `desde`
// y el `hasta`— la decide el sincronizador; el reparto sólo la obedece.
func (c *Cliente) Diferencias(ctx context.Context, v sincro.Ventana) (sincro.Cambios, bool, error) {
	q := url.Values{}
	q.Set("sucursal", v.Sucursal.String())
	q.Set("hasta", v.Hasta.Format(time.RFC3339Nano))
	q.Set("tope", strconv.Itoa(int(v.Tope)))
	if v.Desde != nil {
		q.Set("desde", v.Desde.Format(time.RFC3339Nano))
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.base+"/api/sync/cambios?"+q.Encode(), nil)
	if err != nil {
		return nil, false, err
	}
	c.cabeceras(req, "", uuid.Nil, time.Time{})

	res, err := c.http.Do(req)
	if err != nil {
		return nil, false, err
	}
	defer res.Body.Close()

	cuerpo, err := io.ReadAll(io.LimitReader(res.Body, 64<<20))
	if err != nil {
		return nil, false, err
	}
	if res.StatusCode != http.StatusOK {
		return nil, false, fmt.Errorf("el reparto contestó %d: %s", res.StatusCode, motivoDe(cuerpo))
	}

	var sobre sobreCambios
	if err := json.Unmarshal(cuerpo, &sobre); err != nil {
		return nil, false, fmt.Errorf("no se entendió la respuesta del reparto: %w", err)
	}
	return sobre.Cambios, sobre.Truncado, nil
}

type sobreCreado struct {
	ID *uuid.UUID `json:"id"`
}

// Aplicar reenvía un apunte al reparto tal cual, con la hora del aparato y su sucursal.
//
// La traducción de los códigos es lo importante de esta función:
//
//   - 2xx          → aplicado. Si trae `id`, es el de lo que se acaba de crear.
//   - 4xx          → RECHAZO de negocio, con el motivo literal que escribió el reparto. No
//     se reintenta: queda en la bandeja para que una persona lo lea.
//   - 5xx o red    → caída. Es un error normal y el apunte se queda en la cola del aparato.
//
// Confundir los dos últimos es lo que llenaría la bandeja de rechazos falsos el día que el
// reparto se reinicie, y lo que haría reintentar para siempre un apunte que nunca va a
// entrar.
func (c *Cliente) Aplicar(ctx context.Context, p sincro.Peticion) (*uuid.UUID, error) {
	var cuerpo io.Reader
	if len(p.Cuerpo) > 0 {
		cuerpo = bytes.NewReader(p.Cuerpo)
	}
	req, err := http.NewRequestWithContext(ctx, p.Metodo, c.base+p.Ruta, cuerpo)
	if err != nil {
		return nil, err
	}
	if len(p.Cuerpo) > 0 {
		req.Header.Set("Content-Type", "application/json")
	}
	c.cabeceras(req, p.Persona, p.Sucursal, p.Hecho)
	req.Header.Set("X-Apunte", p.Clave)

	res, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()

	datos, err := io.ReadAll(io.LimitReader(res.Body, 8<<20))
	if err != nil {
		return nil, err
	}

	switch {
	case res.StatusCode >= 200 && res.StatusCode < 300:
		var creado sobreCreado
		// Que no venga `id` es normal: hay apuntes que no crean nada (marcar una parada,
		// corregirla). Por eso un cuerpo que no se entiende no tira el apunte.
		_ = json.Unmarshal(datos, &creado)
		return creado.ID, nil
	case res.StatusCode >= 400 && res.StatusCode < 500:
		return nil, &sincro.Rechazo{Motivo: motivoDe(datos)}
	default:
		return nil, fmt.Errorf("el reparto contestó %d: %s", res.StatusCode, motivoDe(datos))
	}
}

func (c *Cliente) cabeceras(req *http.Request, persona string, sucursal uuid.UUID, hecho time.Time) {
	// Las rutas de servicio del reparto van con `x-api-key`; la persona y la sucursal van
	// aparte porque el alcance lo sigue aplicando el reparto, no este servicio.
	req.Header.Set("x-api-key", c.clave)
	req.Header.Set("Accept", "application/json")
	if persona != "" {
		req.Header.Set("X-Persona", persona)
	}
	if sucursal != uuid.Nil {
		req.Header.Set("X-Sucursal", sucursal.String())
	}
	if !hecho.IsZero() {
		// La hora del APARATO, para que el reparto guarde cuándo se hizo y no cuándo
		// llegó. Lo que se marcó a las cuatro tiene que constar como las cuatro.
		req.Header.Set("X-Hecho-At", hecho.UTC().Format(time.RFC3339Nano))
	}
}

// motivoDe saca la frase de `{"error": "..."}`. Es el mensaje literal en español que va a
// leer la persona que tenga que arreglarlo, así que se conserva entero; si la respuesta no
// tiene esa forma, se devuelve lo que vino, recortado.
func motivoDe(datos []byte) string {
	var sobre struct {
		Error string `json:"error"`
	}
	if err := json.Unmarshal(datos, &sobre); err == nil && sobre.Error != "" {
		return sobre.Error
	}
	texto := string(bytes.TrimSpace(datos))
	if texto == "" {
		return "El reparto no dijo por qué"
	}
	if len(texto) > 500 {
		texto = texto[:500]
	}
	return texto
}
