package api

import (
	"errors"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"

	"procovar/reparto-api/internal/alcance"
	"procovar/reparto-api/internal/httpx"
)

// acotado saca el alcance de la petición. Si no está, es que la ruta se montó sin el
// middleware: se responde 401 y se deja constancia, porque una ruta sin alcance es una
// ruta que enseña las ocho sucursales a quien sea, y eso no puede pasar en silencio.
func acotado(w http.ResponseWriter, r *http.Request) (*alcance.Acotado, bool) {
	a := alcance.De(r)
	if a == nil {
		httpx.Registro(r).Error("ruta montada sin alcance", "ruta", r.URL.Path)
		httpx.NoAutorizado(w, r)
		return nil, false
	}
	return a, true
}

// idDeRuta lee el `{id}` del patrón. Un id que no es un uuid no existe, así que es un
// 404 —el mismo que si no estuviera—, no un 400: por fuera no hay diferencia entre «ese
// id está mal escrito» y «ese id no está», y contar cuál de las dos es sólo sirve para
// que alguien pruebe formatos.
func idDeRuta(w http.ResponseWriter, r *http.Request, mensajeNoEncontrado string) (uuid.UUID, bool) {
	id, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		httpx.Error(w, r, http.StatusNotFound, mensajeNoEncontrado)
		return uuid.Nil, false
	}
	return id, true
}

// ---------------------------------------------------------------------------
// Conversiones a y desde los tipos de pgx
// ---------------------------------------------------------------------------

// hora pasa un timestamptz a algo que el cliente entiende, o a null. Se devuelve en
// RFC3339 con zona: la APK trabaja sin conexión y con la hora del aparato, así que una
// marca sin zona se interpreta mal en cuanto el teléfono cruza de huso.
func hora(t pgtype.Timestamptz) *time.Time {
	if !t.Valid {
		return nil
	}
	v := t.Time
	return &v
}

func idOpcional(u pgtype.UUID) *uuid.UUID {
	if !u.Valid {
		return nil
	}
	v := uuid.UUID(u.Bytes)
	return &v
}

// aTexto devuelve nil si la cadena está vacía. Es el `address || null` del contrato:
// una cadena vacía guardada es un dato que parece puesto y no lo está.
func aTexto(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

// pgDe es lo contrario de idOpcional: un uuid nuestro en el tipo que espera sqlc.
func pgDe(id uuid.UUID) pgtype.UUID {
	return pgtype.UUID{Bytes: [16]byte(id), Valid: true}
}

// esClaveRepetida reconoce el 23505 de Postgres (unique_violation).
//
// Se mira el CÓDIGO y no el texto del error: el texto lo traduce el servidor según su
// idioma, y una comprobación por texto deja de funcionar el día que la base se levante
// con otro locale, sin que nada falle al compilar.
func esClaveRepetida(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}
