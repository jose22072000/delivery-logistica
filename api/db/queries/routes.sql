-- Rutas: el tablero, el detalle con sus paradas y sus renglones, el armado y el cierre.
--
-- El alcance por sucursal va en el SQL de TODAS, incluidas las escrituras: si el filtro se
-- hiciera en Go después de leer, una ruta de otra sucursal ya habría salido de la base, y
-- un `UPDATE ... WHERE id = $1` a secas cierra la ruta de quien sea.
-- `sqlc.narg('sucursal')` es el parámetro «todas las sucursales»: NULL = no acota.

-- ---------------------------------------------------------------------------
-- El tablero de rutas  (GET /api/routes)
-- ---------------------------------------------------------------------------

-- name: ListarRutas :many
SELECT
    r.id, r.name, r.route_code, r.status, r.origin_address, r.origin_lat,
    r.origin_lng, r.total_distance, r.total_weight, r.total_price,
    r.delivery_date, r.vehicle_id, r.branch_id, r.creado_por,
    r.started_at, r.finished_at, r.optimized, r.created_at, r.updated_at,
    b.name        AS sucursal_nombre,
    b.external_id AS sucursal_codigo,
    v.name        AS vehiculo_nombre,
    v.plate       AS vehiculo_matricula,
    v.capacity    AS vehiculo_capacidad,
    vt.nombre     AS vehiculo_tipo,
    -- Cuántas paradas lleva, para no tener que traerlas todas sólo para enseñar el número.
    (SELECT count(*) FROM orders o WHERE o.route_id = r.id) AS paradas
FROM routes r
LEFT JOIN branches      b  ON b.id  = r.branch_id
LEFT JOIN vehicles      v  ON v.id  = r.vehicle_id
LEFT JOIN vehicle_types vt ON vt.id = v.vehicle_type_id
WHERE (sqlc.narg('sucursal')::uuid IS NULL OR r.branch_id = sqlc.narg('sucursal')::uuid)
  AND (sqlc.narg('estado')::route_status IS NULL OR r.status = sqlc.narg('estado')::route_status)
ORDER BY r.created_at DESC;

-- ---------------------------------------------------------------------------
-- El detalle de una ruta  (GET /api/routes/[id])
-- ---------------------------------------------------------------------------

-- La cabecera. Cero filas es «no existe O no es de tu sucursal»: desde fuera son lo mismo,
-- y tienen que serlo, porque decir «existe pero no es tuya» ya es contar algo.
-- name: ObtenerRuta :one
SELECT
    r.id, r.name, r.route_code, r.status, r.origin_address, r.origin_lat,
    r.origin_lng, r.total_distance, r.total_weight, r.total_price,
    r.delivery_date, r.vehicle_id, r.branch_id, r.creado_por,
    r.started_at, r.finished_at, r.optimized, r.created_at, r.updated_at,
    b.name        AS sucursal_nombre,
    b.external_id AS sucursal_codigo,
    v.name        AS vehiculo_nombre,
    v.plate       AS vehiculo_matricula,
    v.capacity    AS vehiculo_capacidad,
    v.status      AS vehiculo_estado,
    vt.nombre     AS vehiculo_tipo
FROM routes r
LEFT JOIN branches      b  ON b.id  = r.branch_id
LEFT JOIN vehicles      v  ON v.id  = r.vehicle_id
LEFT JOIN vehicle_types vt ON vt.id = v.vehicle_type_id
WHERE r.id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR r.branch_id = sqlc.narg('sucursal')::uuid);

-- Las paradas, en el orden en que el camión las visita.
--
-- Va por `route_id`: es la hoja del camión de HOY, lo que lleva cargado ahora mismo.
-- name: ListarParadasDeRuta :many
SELECT
    o.id, o.operation_number, o.customer_name, o.customer_phone, o.address,
    o.end_address, o.end_lat, o.end_lng, o.lat, o.lng, o.status, o.weight,
    o.price, o.segment_km, o.stop_order, o.trip_leg, o.resultado,
    o.resultado_at, o.resultado_nota, o.delivered_at, o.municipio,
    o.pedido_costo, o.external_id, o.source, o.branch_id
FROM orders o
WHERE o.route_id = sqlc.arg('ruta_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY o.stop_order ASC NULLS LAST, o.created_at ASC;

-- Las paradas que VIAJARON en esta ruta, se hayan bajado del camión o no.
--
-- Va por `ultima_ruta_id`, que no se libera nunca, y por eso son dos campos y no uno: un
-- devuelto suelta su `route_id` al cerrar la ruta para poder repartirse mañana, y con un
-- solo campo eso lo borraría de la hoja de lo que bajó del camión. Es el universo del
-- post-despacho y el de corregir el resultado de una parada ya cerrada.
-- name: ListarParadasQueViajaronEnRuta :many
SELECT
    o.id, o.operation_number, o.customer_name, o.address, o.end_address,
    o.weight, o.stop_order, o.resultado, o.resultado_at, o.resultado_nota,
    o.delivered_at, o.external_id, o.source, o.branch_id
FROM orders o
WHERE o.ultima_ruta_id = sqlc.arg('ruta_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY o.stop_order ASC NULLS LAST, o.created_at ASC;

-- Los renglones de TODAS las paradas de la ruta, de una vez.
--
-- Es la hoja de carga y la del post-despacho: lo que sube al camión y, al volver, lo que
-- debería seguir arriba. Una sola consulta y no una por parada — con 40 paradas, lo
-- segundo son 40 idas y vueltas por una pantalla que se abre veinte veces al día.
--
-- Por `ultima_ruta_id` para que el post-despacho siga viendo los renglones de lo que se
-- devolvió: al cerrar, esos pedidos ya soltaron su `route_id`.
-- name: ListarRenglonesDeRuta :many
SELECT
    oi.order_id, oi.linea, oi.description, oi.quantity, oi.packs, oi.product_id,
    o.customer_name, o.stop_order, o.resultado
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
WHERE o.ultima_ruta_id = sqlc.arg('ruta_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY o.stop_order ASC NULLS LAST, oi.linea ASC;

-- Las paradas de VARIAS rutas de una vez, para el tablero.
--
-- Existe para no repetir `ListarParadasDeRuta` una vez por ruta: el tablero sale sin
-- filtro de fecha y con un año de trabajo son cientos de rutas, o sea cientos de idas y
-- vueltas a la base para pintar UNA pantalla. Con un array de ids son tres consultas
-- fijas: las rutas, sus paradas y sus renglones.
--
-- Va por `route_id` —lo que el camión lleva cargado— igual que la de una sola.
-- name: ListarParadasDeRutas :many
SELECT
    o.route_id, o.id, o.operation_number, o.customer_name, o.customer_phone, o.address,
    o.end_address, o.end_lat, o.end_lng, o.lat, o.lng, o.status, o.weight,
    o.price, o.segment_km, o.stop_order, o.trip_leg, o.resultado,
    o.resultado_at, o.resultado_nota, o.delivered_at, o.municipio,
    o.pedido_costo, o.external_id, o.source, o.branch_id
FROM orders o
WHERE o.route_id = ANY(sqlc.arg('ruta_ids')::uuid[])
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY o.stop_order ASC NULLS LAST, o.created_at ASC;

-- Los renglones de las paradas de VARIAS rutas, de una vez.
--
-- Por `route_id` y no por `ultima_ruta_id` a propósito: éstos son los renglones de lo que
-- va EN el camión, que es lo que acompaña a cada parada de la lista. Los de lo que ya se
-- bajó (un devuelto que soltó su `route_id`) son otra pregunta y los trae
-- `ListarRenglonesDeRuta`, que es la del post-despacho.
-- name: ListarRenglonesDeRutas :many
SELECT
    o.route_id, oi.order_id, oi.linea, oi.description, oi.quantity, oi.packs, oi.product_id
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
WHERE o.route_id = ANY(sqlc.arg('ruta_ids')::uuid[])
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY o.stop_order ASC NULLS LAST, oi.linea ASC;

-- ---------------------------------------------------------------------------
-- Armado de ruta  (POST /api/routes)
-- ---------------------------------------------------------------------------

-- Los pedidos elegidos que TODAVÍA se pueden meter en una ruta.
--
-- Esta consulta es la validación, no una lectura previa a ella: se pide por ids y devuelve
-- sólo los que siguen cumpliendo. Si vuelven menos de los que se pidieron, alguien se los
-- llevó entre que se pintó la lista y se pulsó el botón — con diez logísticos armando
-- rutas a la vez eso pasa de verdad — y de ahí sale el 409 con «N de los M ya están en
-- otra ruta». Comprobarlo en Go sobre una lectura anterior es mirar una foto vieja.
--
-- `factura_estado` se deja pasar `igual` y `cambiado` porque es el mismo listón de la
-- lista de disponibles; el corte a sólo `igual` lo hace el handler DESPUÉS, para poder
-- nombrar en el error cuál falla y por qué («cambió en la factura» / «sin cotejar»).
-- Un WHERE que los descarte aquí deja el mismo 409 sin nada que decir.
-- name: PedidosParaArmarRuta :many
SELECT
    o.id, o.operation_number, o.customer_name, o.end_lat, o.end_lng,
    o.weight, o.pedido_costo, o.factura_estado, o.branch_id, o.external_id, o.source
FROM orders o
WHERE o.id = ANY(sqlc.arg('pedido_ids')::uuid[])
  AND o.source = 'pedido'
  AND o.route_id IS NULL
  AND o.end_lat IS NOT NULL
  AND o.end_lng IS NOT NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY o.created_at ASC;

-- Cuántas rutas se llevan hoy, para el `NNN` de `RT-YYYYMMDD-NNN`.
--
-- OJO: no es atómico. Dos armados a la vez leen el mismo número y salen con el mismo
-- código. Delivery tenía la misma carrera; se hereda tal cual para no cambiar el formato
-- del código, que es lo que la gente se dice por teléfono. Si empieza a chocar, la salida
-- es una secuencia por día, no un reintento.
-- name: ContarRutasDelDia :one
SELECT count(*) FROM routes r
WHERE r.route_code LIKE sqlc.arg('prefijo')::text || '%';

-- La ruta nace `planned` y `optimized` en false: los totales y el orden de visita se
-- calculan después, con las paradas ya enganchadas, y se fijan con `FijarTotalesDeRuta`.
--
-- `creado_por` es el id de la persona EN AUTH y es CONSTANCIA, no un filtro: aquí nada
-- pertenece a nadie. Filtrar por el creador fue lo que dejó los 3.528 pedidos importados a
-- nombre del Super Admin y escondió los de Holguín a sus propios compañeros de Holguín.
-- name: CrearRuta :one
INSERT INTO routes (
    name, route_code, origin_address, origin_lat, origin_lng,
    delivery_date, vehicle_id, branch_id, creado_por
) VALUES (
    sqlc.narg('name'), sqlc.arg('route_code'), sqlc.narg('origin_address'),
    sqlc.arg('origin_lat'), sqlc.arg('origin_lng'), sqlc.narg('delivery_date'),
    sqlc.narg('vehicle_id'), sqlc.narg('branch_id'), sqlc.narg('creado_por')
)
RETURNING id, name, route_code, status, origin_address, origin_lat, origin_lng,
          total_distance, total_weight, total_price, delivery_date, vehicle_id,
          branch_id, creado_por, started_at, finished_at, optimized,
          created_at, updated_at;

-- Engancha un pedido a la ruta como parada número `stop_order`.
--
-- `route_id` y `ultima_ruta_id` se ponen los DOS y valen lo mismo hoy: el primero dice
-- «está ocupado» y el segundo «en qué camión fue». Son dos preguntas distintas y con un
-- solo campo no se pueden responder las dos.
--
-- `segment_km` es la distancia RADIAL desde el origen, no la del tramo del recorrido: se
-- hereda así de delivery porque es el número con el que se repartió la carga hasta hoy.
-- `price` es ese reparto de carga y NO el costo del domicilio, que es `pedido_costo`.
--
-- El alcance va aquí también: sin él, mandar el id de un pedido de otra sucursal en
-- `orderIds` lo subiría a tu camión.
-- name: EngancharPedidoARuta :execrows
UPDATE orders SET
    route_id       = sqlc.arg('ruta_id'),
    ultima_ruta_id = sqlc.arg('ruta_id'),
    stop_order     = sqlc.arg('stop_order'),
    trip_leg       = 'outbound',
    segment_km     = sqlc.narg('segment_km'),
    price          = coalesce(sqlc.narg('price')::double precision, 0)
WHERE id = sqlc.arg('pedido_id')
  AND route_id IS NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid);

-- Los totales, ya con las paradas puestas y el recorrido calculado.
-- `total_distance` es el CIRCUITO CERRADO: los tramos más el regreso al origen. El camión
-- vuelve, y no contar la vuelta subestima el viaje justo a la mitad de las rutas largas.
-- name: FijarTotalesDeRuta :one
UPDATE routes SET
    total_distance = sqlc.arg('total_distance'),
    total_weight   = sqlc.arg('total_weight'),
    total_price    = sqlc.arg('total_price'),
    optimized      = true
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
RETURNING id, name, route_code, status, origin_address, origin_lat, origin_lng,
          total_distance, total_weight, total_price, delivery_date, vehicle_id,
          branch_id, started_at, finished_at, optimized, created_at, updated_at;

-- ---------------------------------------------------------------------------
-- Cambios de estado de la ruta  (PATCH /api/routes/[id])
-- ---------------------------------------------------------------------------

-- Nombre y estado, con las horas de salida y regreso.
--
-- `started_at` sólo se pone la PRIMERA vez que arranca: volver a marcar `in_progress`
-- después de una corrección no debe reescribir la hora de salida, que es con la que se
-- mide cuánto se demoró. `finished_at` se limpia al arrancar de nuevo por lo mismo.
-- Ninguna de las dos se deduce de `created_at` —la ruta se arma la noche anterior— ni de
-- `updated_at`, que se mueve al tocar cualquier cosa.
-- name: ActualizarEstadoDeRuta :one
UPDATE routes SET
    name   = coalesce(sqlc.narg('name')::text, name),
    status = coalesce(sqlc.narg('status')::route_status, status),
    started_at = CASE
        WHEN sqlc.narg('status')::route_status = 'in_progress' AND started_at IS NULL THEN now()
        ELSE started_at
    END,
    finished_at = CASE
        WHEN sqlc.narg('status')::route_status = 'in_progress' THEN NULL
        WHEN sqlc.narg('status')::route_status = 'completed'   THEN now()
        ELSE finished_at
    END
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
RETURNING id, name, route_code, status, vehicle_id, branch_id,
          started_at, finished_at, total_distance, total_weight, total_price,
          delivery_date, created_at, updated_at;

-- Cambiar el camión. Va aparte del cambio de estado porque en el contrato tiene prioridad
-- y retorna antes: liberar el camión viejo y ocupar el nuevo es lo único que hace.
-- name: CambiarVehiculoDeRuta :one
UPDATE routes SET
    vehicle_id = sqlc.narg('vehicle_id'),
    name       = coalesce(sqlc.narg('name')::text, name),
    status     = coalesce(sqlc.narg('status')::route_status, status)
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
RETURNING id, name, route_code, status, vehicle_id, branch_id,
          started_at, finished_at, created_at, updated_at;

-- ---------------------------------------------------------------------------
-- Cierre de ruta  (POST /api/routes/[id]/results)
-- ---------------------------------------------------------------------------

-- Cómo acabó UNA parada. Es la consulta más delicada del reparto: de aquí sale lo que se
-- le cuenta a PEDIDO y la cuenta del post-despacho.
--
-- Cuatro cosas van juntas a propósito y en una sola sentencia:
--
--  1. `WHERE ultima_ruta_id = ...` y NO `route_id`: así se puede corregir el resultado de
--     un devuelto que ya soltó su `route_id` al cerrar. Y sirve de validación — cero filas
--     significa «ese pedido no va en esta ruta», que es el rechazo del contrato, sin tener
--     que comprobarlo antes en Go sobre una lectura que ya puede estar vieja.
--  2. `route_id = NULL` SÓLO si no se entregó: el pedido baja del camión y vuelve a la
--     lista de disponibles para la ruta de mañana. `ultima_ruta_id` y `stop_order` no se
--     tocan NUNCA: son la hoja de lo que bajó del camión.
--  3. `delivered_at` se limpia cuando no se entregó. Un devuelto que conserve la hora de
--     entrega de un intento anterior se pinta «entregado» en la lista, que es exactamente
--     la contradicción que se vio con un pedido de La Habana el 2 de septiembre.
--  4. `resultado_nota` se guarda siempre: un devuelto sin motivo es un número que nadie
--     sabe explicar tres semanas después.
--
-- Ni `devuelto` ni `cancelado` tocan inventario: el reintegro lo hace Ventra.
-- name: MarcarResultadoDeParada :execrows
UPDATE orders SET
    resultado      = sqlc.arg('resultado')::stop_result,
    resultado_at   = now(),
    resultado_nota = sqlc.narg('nota'),
    delivered_at = CASE
        WHEN sqlc.arg('resultado')::stop_result = 'entregado' THEN now()
        ELSE NULL
    END,
    status = CASE
        WHEN sqlc.arg('resultado')::stop_result = 'entregado' THEN 'delivered'::order_status
        ELSE 'pending'::order_status
    END,
    route_id = CASE
        WHEN sqlc.arg('resultado')::stop_result = 'entregado' THEN route_id
        ELSE NULL
    END
WHERE id = sqlc.arg('pedido_id')
  AND ultima_ruta_id = sqlc.arg('ruta_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid);

-- ---------------------------------------------------------------------------
-- Borrar una ruta  (DELETE /api/routes/[id])
-- ---------------------------------------------------------------------------

-- Los pedidos NO se borran: se sueltan y vuelven a la lista de disponibles.
-- `ultima_ruta_id` se conserva — el pasado de un pedido no se reescribe porque alguien
-- deshaga la ruta de hoy.
-- name: SoltarPedidosDeRuta :execrows
UPDATE orders SET
    route_id   = NULL,
    stop_order = NULL,
    segment_km = NULL,
    trip_leg   = 'outbound'
WHERE route_id = sqlc.arg('ruta_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid);

-- name: BorrarRuta :execrows
DELETE FROM routes
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid);

-- ---------------------------------------------------------------------------
-- Para el panel y para la flota
-- ---------------------------------------------------------------------------

-- Rutas vivas. `cancelled` se excluye igual que `completed` aunque hoy nadie lo escriba:
-- el enum lo tiene declarado para no obligar a un ALTER TYPE el día que se use, y el
-- tablero ya lo descarta.
-- name: ContarRutasActivas :one
SELECT count(*) FROM routes r
WHERE r.status NOT IN ('completed', 'cancelled')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR r.branch_id = sqlc.narg('sucursal')::uuid);

-- La ruta viva más reciente de un camión, para la tarjeta de la flota.
-- name: RutaActivaDeVehiculo :one
SELECT r.id, r.name, r.route_code, r.status, r.created_at
FROM routes r
WHERE r.vehicle_id = sqlc.arg('vehiculo_id')
  AND r.status <> 'completed'
  AND (sqlc.narg('sucursal')::uuid IS NULL OR r.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY r.created_at DESC
LIMIT 1;

-- Al liberar un camión a mano se cierra la ruta que llevaba: un camión disponible con una
-- ruta abierta detrás es una ruta que nadie va a cerrar nunca y que sigue contando como
-- activa en el panel.
-- name: CompletarRutasDeVehiculo :execrows
UPDATE routes SET status = 'completed', finished_at = coalesce(finished_at, now())
WHERE vehicle_id = sqlc.arg('vehiculo_id')
  AND status <> 'completed'
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid);

-- Al borrar un camión, sus rutas se quedan sin él pero no se borran: el histórico de lo
-- que se repartió no depende de que el camión siga en la flota.
-- name: DesvincularVehiculoDeRutas :execrows
UPDATE routes SET vehicle_id = NULL
WHERE vehicle_id = sqlc.arg('vehiculo_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid);
