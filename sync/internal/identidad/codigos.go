package identidad

import (
	"context"
	"sync"
	"time"

	"github.com/google/uuid"
)

// EL CACHÉ DE CÓDIGOS DE SUCURSAL.
//
// La traducción `CAM` -> uuid la hace `reparto-api`, que es quien tiene la tabla. Sin
// caché eso sería **una ida y vuelta más en cada petición del protocolo**, incluida la
// subida de una cola de ocho horas que llega apunte a apunte cuando el aparato coge señal.
//
// Qué se guarda y qué no:
//
//   - Lo que SÍ se guarda es el acierto, y se guarda mucho tiempo: una sucursal no cambia
//     de id. Ocho códigos, ocho filas.
//   - Lo que NO se guarda es el fallo. Ni el «no existe» ni el «no contesté»: guardar un
//     fallo es convertir un tropiezo de un segundo en media hora de aparatos rechazados,
//     y eso aquí significa colas que no suben.
type Cache struct {
	de    func(ctx context.Context, codigo string) (uuid.UUID, error)
	dura  time.Duration
	ahora func() time.Time

	mu    sync.RWMutex
	filas map[string]fila
}

type fila struct {
	id    uuid.UUID
	hasta time.Time
}

// NuevoCache envuelve al que pregunta de verdad. `dura` es cuánto vale un acierto.
func NuevoCache(de func(ctx context.Context, codigo string) (uuid.UUID, error), dura time.Duration) *Cache {
	if dura <= 0 {
		dura = time.Hour
	}
	return &Cache{de: de, dura: dura, ahora: time.Now, filas: map[string]fila{}}
}

// Resolver es el [Resolutor] que se le pasa a [DeToken].
func (c *Cache) Resolver(ctx context.Context, codigo string) (uuid.UUID, error) {
	c.mu.RLock()
	f, hay := c.filas[codigo]
	c.mu.RUnlock()
	if hay && c.ahora().Before(f.hasta) {
		return f.id, nil
	}

	id, err := c.de(ctx, codigo)
	if err != nil {
		return uuid.Nil, err
	}

	c.mu.Lock()
	c.filas[codigo] = fila{id: id, hasta: c.ahora().Add(c.dura)}
	c.mu.Unlock()
	return id, nil
}
