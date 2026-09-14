package sincro

import (
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
)

// Los tipos de pgx para columnas que pueden venir vacías, traducidos a los de Go, en un
// solo sitio. Repartidos por los handlers acaban dando una respuesta con `{"Valid":false}`
// dentro, que el aparato no sabe leer.

func marca(t time.Time) pgtype.Timestamptz {
	return pgtype.Timestamptz{Time: t, Valid: true}
}

// hora devuelve nil cuando la columna está vacía, y eso importa: en el panel, «nunca subió»
// no es «subió hace 0 horas».
func hora(ts pgtype.Timestamptz) *time.Time {
	if !ts.Valid {
		return nil
	}
	t := ts.Time
	return &t
}

func identificador(id uuid.UUID) pgtype.UUID {
	return pgtype.UUID{Bytes: id, Valid: true}
}

func deIdentificador(v pgtype.UUID) *uuid.UUID {
	if !v.Valid {
		return nil
	}
	id := uuid.UUID(v.Bytes)
	return &id
}

// alcance traduce «la sucursal por la que filtrar, o todas» al parámetro anulable que
// esperan las consultas. El filtro vive en el SQL: aquí sólo se decide qué se le pasa.
func alcance(sucursal *uuid.UUID) pgtype.UUID {
	if sucursal == nil {
		return pgtype.UUID{} // NULL: todas las sucursales, o sea el Super Admin
	}
	return identificador(*sucursal)
}
