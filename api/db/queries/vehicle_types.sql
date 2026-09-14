-- El catálogo de tipos de vehículo — LA TABLA QUE FALTABA.
--
-- En delivery esto se guardaba en `Settings.tiposVehiculo`, un campo que NUNCA EXISTIÓ en
-- el esquema: la pantalla de vehículos dejaba crear tipos nuevos, los mandaba a guardar y
-- se perdían sin un solo error. Por eso `Vehicle.type` era un conjunto abierto que nadie
-- podía cerrar — su catálogo no estaba en ninguna parte.
--
-- GLOBAL, sin alcance por sucursal: un «camión» es un camión en las ocho, y la tabla no
-- tiene columna de sucursal que filtrar. Lo que sí es por sucursal es qué VEHÍCULO
-- concreto es el de referencia, y eso vive en `vehicles`.

-- Los tipos que se pueden elegir. Por defecto sólo los activos: `activo` existe para poder
-- RETIRAR un tipo sin romper los vehículos que ya lo usan — borrarlo dejaría la clave
-- ajena colgando y no hay a dónde mover un camión que ya es de ese tipo.
-- name: ListarTiposDeVehiculo :many
SELECT
    vt.id, vt.nombre, vt.costo_km_usd, vt.activo, vt.created_at, vt.updated_at,
    (SELECT count(*) FROM vehicles v WHERE v.vehicle_type_id = vt.id) AS vehiculos
FROM vehicle_types vt
WHERE (sqlc.narg('solo_activos')::boolean IS NULL
       OR NOT sqlc.narg('solo_activos')::boolean
       OR vt.activo)
ORDER BY vt.nombre ASC;

-- name: ObtenerTipoDeVehiculo :one
SELECT vt.id, vt.nombre, vt.costo_km_usd, vt.activo, vt.created_at, vt.updated_at
FROM vehicle_types vt
WHERE vt.id = sqlc.arg('id');

-- Por nombre, para el espejo y para el alta de vehículos: el cuerpo del POST manda
-- `type: "truck"`, un texto, y hay que traducirlo al id del catálogo. `nombre` es UNIQUE.
-- name: BuscarTipoDeVehiculoPorNombre :one
SELECT vt.id, vt.nombre, vt.costo_km_usd, vt.activo
FROM vehicle_types vt
WHERE vt.nombre = sqlc.arg('nombre');

-- El costo por km del tipo es un VALOR POR DEFECTO, no el bueno: cada vehículo puede tener
-- el suyo porque quien lo da es el camionero y dos camiones del mismo tipo no cuestan
-- igual. Se deja vacío a propósito en los cuatro que vienen de fábrica — ponerle un número
-- inventado es peor que no tenerlo, porque se cobra igual y nadie lo revisa.
-- name: CrearTipoDeVehiculo :one
INSERT INTO vehicle_types (nombre, costo_km_usd, activo)
VALUES (sqlc.arg('nombre'), sqlc.narg('costo_km_usd'), sqlc.arg('activo'))
RETURNING id, nombre, costo_km_usd, activo, created_at, updated_at;

-- name: ActualizarTipoDeVehiculo :one
UPDATE vehicle_types SET
    nombre       = coalesce(sqlc.narg('nombre')::text, nombre),
    costo_km_usd = CASE WHEN sqlc.arg('tocar_costo')::boolean
                        THEN sqlc.narg('costo_km_usd')::double precision
                        ELSE costo_km_usd END,
    activo       = coalesce(sqlc.narg('activo')::boolean, activo)
WHERE id = sqlc.arg('id')
RETURNING id, nombre, costo_km_usd, activo, created_at, updated_at;

-- Retirar un tipo NO es borrarlo. Se desactiva: deja de ofrecerse en el desplegable y los
-- camiones que ya lo tienen siguen funcionando. Un DELETE choca contra la clave ajena de
-- `vehicles.vehicle_type_id`, y hacerlo a la fuerza dejaría camiones sin tipo, que es un
-- camión sin costo por km y por tanto sin fórmula del domicilio.
-- name: RetirarTipoDeVehiculo :execrows
UPDATE vehicle_types SET activo = false WHERE id = sqlc.arg('id');

-- Sólo se puede borrar de verdad un tipo que no use nadie. Se comprueba aquí, en la misma
-- sentencia, y no con un conteo antes: entre el conteo y el borrado cabe un alta.
-- name: BorrarTipoDeVehiculoSinUso :execrows
DELETE FROM vehicle_types vt
WHERE vt.id = sqlc.arg('id')
  AND NOT EXISTS (SELECT 1 FROM vehicles v WHERE v.vehicle_type_id = vt.id);
