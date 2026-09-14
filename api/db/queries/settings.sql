-- Ajustes y monedas. GLOBALES: no llevan alcance por sucursal y no es un olvido — son de
-- toda la empresa, y no hay ninguna columna de sucursal en estas dos tablas que filtrar.
-- La tasa POR SUCURSAL es otra cosa y vive en Accesos, no aquí.

-- ---------------------------------------------------------------------------
-- Ajustes: una sola fila
-- ---------------------------------------------------------------------------

-- Los ajustes. Siempre hay fila y siempre es la misma: la clave primaria es un booleano
-- con `CHECK (id)`, así que la base impide que haya dos. En delivery esto era un
-- `findFirst` y un `create` si no había —dentro de un GET—, y dos filas de ajustes es
-- media aplicación mirando una y media mirando la otra.
-- name: ObtenerAjustes :one
SELECT
    s.id, s.sync_barrido_dia, s.catalogo_traido_at, s.currency,
    s.cup_rate, s.cup_rate_updated_at, s.created_at, s.updated_at
FROM settings s
WHERE s.id;

-- `cup_rate_updated_at` se mueve SÓLO cuando cambia la tasa, no en cada guardado: es lo
-- que dice si el número que se está usando es de hoy o de hace tres semanas, y tocarlo por
-- guardar la moneda lo convertiría en una copia de `updated_at`, que ya existe.
-- name: ActualizarAjustes :one
UPDATE settings SET
    currency = coalesce(sqlc.narg('currency')::text, currency),
    cup_rate = coalesce(sqlc.narg('cup_rate')::double precision, cup_rate),
    cup_rate_updated_at = CASE
        WHEN sqlc.narg('cup_rate')::double precision IS NOT NULL
         AND sqlc.narg('cup_rate')::double precision <> cup_rate THEN now()
        ELSE cup_rate_updated_at
    END
WHERE id
RETURNING id, sync_barrido_dia, catalogo_traido_at, currency,
          cup_rate, cup_rate_updated_at, created_at, updated_at;

-- Por dónde va el barrido del histórico, en DÍAS HACIA ATRÁS.
--
-- Hace falta guardarlo porque de los datos NO se puede deducir: hay pedidos viejos
-- sueltos, así que «el más antiguo que tengo» no significa «tengo todo hasta ahí».
-- name: FijarBarridoDelEspejo :exec
UPDATE settings SET sync_barrido_dia = sqlc.arg('sync_barrido_dia') WHERE id;

-- Cuándo se trajo el catálogo de Ventra. Sólo se marca si se escribió ALGO: si todas las
-- sucursales fallaron, la hora no se toca, para poder reintentar antes de las doce horas
-- en vez de quedarse medio día con el catálogo a medias.
-- name: MarcarCatalogoTraido :exec
UPDATE settings SET catalogo_traido_at = now() WHERE id;

-- ---------------------------------------------------------------------------
-- Monedas
-- ---------------------------------------------------------------------------

-- `rate` son unidades de esta moneda por 1 USD: CUP = 320, no al revés. Escrito al revés,
-- todos los importes salen divididos por cien mil y parecen céntimos.
-- name: ListarMonedas :many
SELECT c.code, c.rate, c.activa, c.created_at, c.updated_at
FROM currencies c
WHERE (sqlc.narg('solo_activas')::boolean IS NULL
       OR NOT sqlc.narg('solo_activas')::boolean
       OR c.activa)
ORDER BY c.code ASC;

-- name: ObtenerMoneda :one
SELECT c.code, c.rate, c.activa, c.created_at, c.updated_at
FROM currencies c
WHERE c.code = sqlc.arg('code');

-- Una moneda se corrige sola, sin reescribir la lista entera. Eso es lo que la tabla
-- compra frente al array de JSON que había antes: se puede saber cuándo cambió cada tasa
-- —`updated_at`, que lo mantiene el trigger— y corregir una sin tocar las demás.
-- name: GuardarMoneda :one
INSERT INTO currencies (code, rate, activa)
VALUES (sqlc.arg('code'), sqlc.arg('rate'), sqlc.arg('activa'))
ON CONFLICT (code) DO UPDATE SET
    rate   = excluded.rate,
    activa = excluded.activa
RETURNING code, rate, activa, created_at, updated_at;

-- Retirar una moneda es desactivarla, no borrarla: los importes ya guardados se
-- convirtieron con su tasa y sin la fila no hay forma de volver a explicarlos.
-- name: DesactivarMoneda :execrows
UPDATE currencies SET activa = false WHERE code = sqlc.arg('code');
