#!/bin/sh
# Aplica las DOS series de migraciones, cada una a SU base, y se va.
#
# Las dos series son independientes y no hay claves ajenas entre ellas (está dicho en
# sync/db/migrations/00001_sync.sql): el orden de aquí es sólo para que el registro se
# lea siempre igual.
#
# Variables:
#   DATABASE_URL_API    la base del reparto        (api/db/migrations)
#   DATABASE_URL_SYNC   la base del sincronizador  (sync/db/migrations)
#   INTENTOS            cuántas veces se espera a que Postgres conteste (2 s cada una)
#   ACCION              up (por defecto) | status | up-by-one | down  ← down NO en producción
set -eu

: "${DATABASE_URL_API:?falta DATABASE_URL_API (la base del reparto)}"
: "${DATABASE_URL_SYNC:?falta DATABASE_URL_SYNC (la base del sincronizador)}"
INTENTOS="${INTENTOS:-30}"
ACCION="${ACCION:-up}"

# Esperar a Postgres AQUÍ y no en cada servicio. En local, Postgres tarda unos segundos
# en aceptar conexiones la primera vez; sin esta espera la primera migración falla y hay
# que volver a lanzarlo a mano, que es justo el paso que a nadie le apetece repetir.
esperar() {
  nombre="$1"; url="$2"; dir="$3"; i=1
  while [ "$i" -le "$INTENTOS" ]; do
    if goose -dir "$dir" postgres "$url" status >/dev/null 2>&1; then
      return 0
    fi
    echo "esperando a la base de $nombre ($i/$INTENTOS)"
    sleep 2
    i=$((i + 1))
  done
  echo "la base de $nombre no contestó en $((INTENTOS * 2)) s: no se migra nada" >&2
  return 1
}

migrar() {
  nombre="$1"; url="$2"; dir="$3"
  esperar "$nombre" "$url" "$dir"
  echo "--- migraciones de $nombre ($dir) ---"
  goose -dir "$dir" postgres "$url" "$ACCION"
  goose -dir "$dir" postgres "$url" status
}

migrar reparto        "$DATABASE_URL_API"  /migraciones/api
migrar sincronizador  "$DATABASE_URL_SYNC" /migraciones/sync

echo "migraciones aplicadas"
