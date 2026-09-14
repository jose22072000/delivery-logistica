-- Sucursales y puntos de partida guardados.
--
-- OJO, AQUÍ EL ALCANCE ES DISTINTO Y NO ES UN DESCUIDO.
--
-- En la LISTA de sucursales no se pregunta «qué estoy mirando ahora» sino «a cuáles puedo
-- llegar», que sólo depende de la persona y no de la que tenga elegida arriba. Si se
-- acotara por la elegida, elegir una devolvería una sola, el selector se volvería una
-- etiqueta fija y no habría forma de cambiar a otra: la elección se comería la lista con
-- la que se elige. Por eso el parámetro se llama `sucursal_de_la_persona` y no `sucursal`.
--
-- Y OTRA COSA QUE TAMPOCO ES UN DESCUIDO: si el id que llega no existe, el llamante pasa
-- NULL y se ven todas. Filtrar por un id inexistente NO da error: da CERO. Cero pedidos,
-- cero clientes, cero rutas y hasta cero sucursales —con lo que desaparece el selector con
-- el que se podría arreglar—, todo con 200 y sin una traza. El token del login único dura
-- siete días y lleva dentro la sucursal que la persona tenía al entrar, y las sucursales
-- se recrearon en algún momento: pasa de verdad, y se vio en producción.

-- ---------------------------------------------------------------------------
-- Sucursales
-- ---------------------------------------------------------------------------

-- name: ListarSucursales :many
SELECT
    b.id, b.name, b.address, b.lat, b.lng, b.area_km2, b.external_id,
    b.origin_configured, b.creado_por, b.created_at, b.updated_at,
    (SELECT count(*) FROM saved_origins so WHERE so.branch_id = b.id) AS origenes
FROM branches b
WHERE (sqlc.narg('sucursal_de_la_persona')::uuid IS NULL
       OR b.id = sqlc.narg('sucursal_de_la_persona')::uuid)
ORDER BY b.created_at DESC;

-- name: ObtenerSucursal :one
SELECT
    b.id, b.name, b.address, b.lat, b.lng, b.area_km2, b.external_id,
    b.origin_configured, b.creado_por, b.created_at, b.updated_at
FROM branches b
WHERE b.id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR b.id = sqlc.narg('sucursal')::uuid);

-- ¿Existe esta sucursal? Es la comprobación de `resolveScope`, y el único sitio donde se
-- resuelve el alcance. Devuelve también el `external_id` porque clientes y catálogo se
-- acotan por CÓDIGO, no por uuid, y sin esa traducción el filtro no se puede armar.
-- name: ResolverSucursal :one
SELECT b.id, b.name, b.external_id, b.lat, b.lng, b.origin_configured
FROM branches b
WHERE b.id = sqlc.arg('id');

-- La sucursal por su código de PEDIDO/Ventra (CAM, HAB, STG...). Es por lo que PEDIDO
-- cotiza: manda su código y aquí se busca la nuestra.
-- name: BuscarSucursalPorCodigo :one
SELECT b.id, b.name, b.external_id, b.lat, b.lng, b.area_km2, b.origin_configured
FROM branches b
WHERE b.external_id = sqlc.arg('external_id');

-- Los códigos a los que esta persona puede llegar. Es lo que filtra la respuesta de
-- Accesos en `/api/almacenes`: Accesos devuelve las ocho sucursales y aquí se descartan
-- las que no le tocan. Sólo las que TIENEN código: sin él no hay nada que cotejar.
-- name: CodigosDeSucursalesVisibles :many
SELECT b.id, b.name, b.external_id
FROM branches b
WHERE b.external_id IS NOT NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR b.id = sqlc.narg('sucursal')::uuid)
ORDER BY b.name ASC;

-- `origin_configured` nace en true al darla de alta con coordenadas: el alta ya fija el
-- punto de partida. Mientras sea false, el cálculo de domicilios NO corre para esa
-- sucursal, y eso es deliberado — medir desde un punto que no es el almacén da un precio
-- que parece bueno y no lo es.
-- name: CrearSucursal :one
INSERT INTO branches (name, address, lat, lng, area_km2, external_id, origin_configured, creado_por)
VALUES (
    sqlc.arg('name'), sqlc.narg('address'), sqlc.arg('lat'), sqlc.arg('lng'),
    sqlc.arg('area_km2'), sqlc.narg('external_id'), true, sqlc.narg('creado_por')
)
RETURNING id, name, address, lat, lng, area_km2, external_id,
          origin_configured, creado_por, created_at, updated_at;

-- Tocar lat o lng da el punto de partida por configurado: si alguien se molestó en
-- ponerle coordenadas, ya está fijado.
-- name: ActualizarSucursal :one
UPDATE branches SET
    name        = coalesce(sqlc.narg('name')::text, name),
    address     = CASE WHEN sqlc.arg('tocar_address')::boolean
                       THEN sqlc.narg('address')::text ELSE address END,
    lat         = coalesce(sqlc.narg('lat')::double precision, lat),
    lng         = coalesce(sqlc.narg('lng')::double precision, lng),
    area_km2    = coalesce(sqlc.narg('area_km2')::double precision, area_km2),
    external_id = CASE WHEN sqlc.arg('tocar_external_id')::boolean
                       THEN sqlc.narg('external_id')::text ELSE external_id END,
    origin_configured = CASE
        WHEN sqlc.narg('lat')::double precision IS NOT NULL
          OR sqlc.narg('lng')::double precision IS NOT NULL THEN true
        ELSE origin_configured
    END
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR id = sqlc.narg('sucursal')::uuid)
RETURNING id, name, address, lat, lng, area_km2, external_id,
          origin_configured, creado_por, created_at, updated_at;

-- name: BorrarSucursal :execrows
DELETE FROM branches
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR id = sqlc.narg('sucursal')::uuid);

-- ---------------------------------------------------------------------------
-- Puntos de partida guardados  (/api/origins)
-- ---------------------------------------------------------------------------

-- Los orígenes desde los que se puede armar una ruta.
--
-- Con alcance se ven los de la sucursal; sin alcance, o todos o los de la que se pida.
-- Los orígenes SIN sucursal no se cuelan en el alcance de nadie: un punto de partida
-- suelto en la lista de Holguín es una ruta que empieza a 800 km de donde debía.
-- name: ListarOrigenes :many
SELECT
    so.id, so.name, so.address, so.lat, so.lng, so.creado_por, so.branch_id,
    so.created_at, so.updated_at,
    b.name AS sucursal_nombre
FROM saved_origins so
LEFT JOIN branches b ON b.id = so.branch_id
WHERE (sqlc.narg('sucursal')::uuid IS NULL OR so.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY so.created_at DESC;

-- name: CrearOrigen :one
INSERT INTO saved_origins (name, address, lat, lng, creado_por, branch_id)
VALUES (
    sqlc.arg('name'), sqlc.arg('address'), sqlc.arg('lat'), sqlc.arg('lng'),
    sqlc.narg('creado_por'), sqlc.narg('branch_id')
)
RETURNING id, name, address, lat, lng, creado_por, branch_id, created_at, updated_at;

-- name: BorrarOrigen :execrows
DELETE FROM saved_origins
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid);

-- ¿Tiene ya algún punto de partida? Se pregunta al crear o al corregir una sucursal con
-- coordenadas: si no tiene ninguno se le crea el de por defecto. Una sucursal con
-- coordenadas y sin origen no puede armar una ruta y no lo dice en ninguna parte.
-- name: ContarOrigenesDeSucursal :one
SELECT count(*) FROM saved_origins so
WHERE so.branch_id = sqlc.arg('sucursal_id');
