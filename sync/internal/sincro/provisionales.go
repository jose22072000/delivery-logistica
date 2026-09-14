package sincro

import (
	"context"
	"regexp"

	"github.com/google/uuid"

	"procovar/reparto-sync/internal/store"
	"procovar/reparto-sync/internal/store/sqlc"
)

// Los identificadores provisionales.
//
// Una ruta armada sin conexión no tiene identificador —lo pone la base— pero la pantalla
// necesita uno YA para enseñarla, imprimir el despacho y cerrarla por la tarde. El aparato
// se inventa un `local-…` y lo usa en todo lo que venga detrás en su cola.
//
// Quien tiene que sustituirlo cuando el servidor le devuelve el bueno es el APARATO. Esto
// es la red debajo: si se corta antes de aplicar la sustitución, o si el cierre de la tarde
// venía ya escrito con el `local-…`, aquí se traduce. Sin esto, el cierre de una ruta
// armada sin red sale contra `/api/routes/local-9f3a/results`, que no existe en ningún
// sitio, y se pierde el trabajo del día JUSTO DESPUÉS de haberlo subido bien.

// Un `local-…` tal como lo escribe el aparato. Sólo letras y números detrás del guion: si
// se admitieran guiones, `local-9f3a-2` se comería de una vez dos identificadores
// distintos.
var reProvisional = regexp.MustCompile(`local-[A-Za-z0-9]+`)

type traductor struct {
	datos   store.Datos
	aparato uuid.UUID
	// Lo resuelto en ESTE lote, que es el caso normal: el apunte que crea la ruta y el que
	// la cierra suben juntos, en la misma cola y en el mismo envío.
	enElLote map[string]uuid.UUID
}

func nuevoTraductor(datos store.Datos, aparato uuid.UUID) *traductor {
	return &traductor{datos: datos, aparato: aparato, enElLote: map[string]uuid.UUID{}}
}

func (t *traductor) apuntar(provisional string, real uuid.UUID) {
	if provisional == "" {
		return
	}
	t.enElLote[provisional] = real
}

// resolver busca primero en el lote y luego en la base, que es donde quedó lo de envíos
// anteriores. El resultado de la base se guarda en el lote para no preguntar dos veces por
// el mismo `local-…` cuando aparece en varios apuntes seguidos.
func (t *traductor) resolver(ctx context.Context, provisional string) (uuid.UUID, bool, error) {
	if id, ok := t.enElLote[provisional]; ok {
		return id, true, nil
	}
	id, err := t.datos.ResolverProvisional(ctx, sqlc.ResolverProvisionalParams{
		AparatoID:   t.aparato,
		Provisional: provisional,
	})
	if err != nil {
		if store.SinFilas(err) {
			return uuid.Nil, false, nil
		}
		return uuid.Nil, false, err
	}
	t.enElLote[provisional] = id
	return id, true, nil
}

// texto cambia todos los `local-…` de una cadena por el id bueno.
//
// `propio` es el provisional que ESTE apunte está creando: no se traduce, porque todavía no
// existe nada a lo que traducirlo — es el apunte que lo va a crear.
//
// Devuelve el primer `local-…` que no supo traducir. Ese caso NO es un 404 ni un apunte
// tirado: es un rechazo con su motivo, que queda en la bandeja para que una persona lo vea.
func (t *traductor) texto(ctx context.Context, s, propio string) (string, string, error) {
	posiciones := reProvisional.FindAllStringIndex(s, -1)
	if len(posiciones) == 0 {
		return s, "", nil
	}

	var salida []byte
	ultimo := 0
	for _, p := range posiciones {
		token := s[p[0]:p[1]]
		if token == propio {
			continue
		}
		id, hay, err := t.resolver(ctx, token)
		if err != nil {
			return "", "", err
		}
		if !hay {
			return "", token, nil
		}
		salida = append(salida, s[ultimo:p[0]]...)
		// El id va sin comillas ni escapes, así que meterlo dentro de una cadena JSON la
		// deja igual de válida que estaba. Por eso el cuerpo se traduce como texto y no
		// hay que desmenuzarlo: el sincronizador no sabe —ni tiene por qué saber— qué
		// forma tiene el cuerpo de cada una de las 35 rutas del reparto.
		salida = append(salida, id.String()...)
		ultimo = p[1]
	}
	if salida == nil {
		return s, "", nil
	}
	salida = append(salida, s[ultimo:]...)
	return string(salida), "", nil
}
