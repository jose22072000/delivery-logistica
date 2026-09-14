-- Pedidos: el catálogo, los disponibles para repartir, las facetas y el espejo de PEDIDO.
--
-- CONVENCIÓN DE PARÁMETROS (vale para todos los ficheros de esta carpeta)
--
--   El alcance por sucursal es SEGURIDAD y va SIEMPRE en el SQL, nunca en Go. Se expresa
--   con un solo parámetro que admite «todas las sucursales» como NULL:
--
--       (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
--
--   `sqlc.narg('sucursal')` ES el `$1` posicional: sqlc lo numera igual, pero además le
--   pone nombre en el struct de Go. Con doce filtros opcionales, un struct de `Column1..
--   Column12` es exactamente la forma de colar el municipio en la casilla de la sucursal
--   sin que el compilador diga nada. El `::uuid` explícito es lo que obliga a sqlc a
--   generarlo como anulable.
--
--   Los demás filtros opcionales siguen el mismo patrón: NULL = no filtra.
--
-- EL TEXTO DE LOS RENGLONES YA NO SE COPIA. Donde delivery buscaba en `productosTexto`
-- —una copia a mano de los nombres, porque dentro de un JSON no se busca— aquí va un
-- EXISTS contra `order_items`. Un dato copiado en dos sitios acaba discrepando.

-- ---------------------------------------------------------------------------
-- La lista de pedidos por repartir  (GET /api/orders/available)
-- ---------------------------------------------------------------------------

-- ¿Qué pedidos puedo meter HOY en una ruta, de los que yo puedo ver?
--
-- Las cinco condiciones de arriba del WHERE no son filtros de pantalla y no se negocian:
--   * `source = 'pedido'`      — lo que no vino de PEDIDO no se reparte.
--   * `route_id IS NULL`       — si ya va en una ruta, está ocupado.
--   * `end_lat/end_lng`        — sin coordenadas no hay parada que visitar.
--   * `factura_estado IN ('igual','cambiado')` — LO REPARTIBLE. `cambiado` no es un pedido
--     roto: se facturó distinto de como se pidió y lo que sube al camión son las líneas de
--     la factura. Fuera quedan `sin_factura` (no hay nada que llevar) y el NULL, que
--     significa NO SE SABE: con un NULL colado se armó una ruta sin facturar el 2/09.
--
-- `km_max` y `costo_min` NO están aquí a propósito: el contrato los aplica después de la
-- consulta, y `total`/`truncated` se calculan ANTES que ellos. Bajarlos al SQL cambiaría
-- esos dos números y la pantalla diría «358» sobre una tabla de 120.
-- name: ListarPedidosDisponibles :many
SELECT
    o.id, o.order_date, o.created_at, o.operation_number, o.customer_name,
    o.address, o.end_address, o.end_lat, o.end_lng, o.weight,
    o.delivery_price, o.delivery_distance_km, o.estado, o.archivado,
    o.requiere_domicilio, o.pedido_costo, o.municipio, o.vendedor,
    o.branch_id, o.factura_estado, o.sucursal_codigo
FROM orders o
WHERE
    o.source = 'pedido'
    AND o.route_id IS NULL
    AND o.end_lat IS NOT NULL
    AND o.end_lng IS NOT NULL
    AND o.factura_estado IN ('igual', 'cambiado')
    -- alcance por sucursal
    AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
    -- `branch_id` de la query: estrecha, nunca amplía. Va en AND con el alcance, así que
    -- quien sólo ve una sucursal no puede pedir la de otro poniéndolo a mano.
    AND (sqlc.narg('branch_id')::uuid IS NULL OR o.branch_id = sqlc.narg('branch_id')::uuid)
    -- Una sola caja de búsqueda: quien la usa no se para a pensar en qué campo está lo
    -- que recuerda. El EXISTS es la pregunta del despacho: «¿qué pedidos llevan malta?».
    AND (
        sqlc.narg('q')::text IS NULL
        OR o.customer_name    ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.operation_number ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.end_address      ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.address          ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.municipio        ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.vendedor         ILIKE '%' || sqlc.narg('q')::text || '%'
        OR EXISTS (
            SELECT 1 FROM order_items oi
            WHERE oi.order_id = o.id
              AND oi.description ILIKE '%' || sqlc.narg('q')::text || '%'
        )
    )
    -- `expirada` se CALCULA con `now()` en cada llamada y no se guarda: un booleano
    -- guardado se queda viejo al día siguiente y empieza a mentir solo.
    -- El `estado IS NULL` explícito es obligatorio: `estado <> 'completada'` sobre un NULL
    -- da NULL, que no es TRUE, y la fila se cae de los tres filtros a la vez.
    AND (
        sqlc.narg('estado')::text IS NULL
        OR (sqlc.narg('estado')::text = 'completada' AND o.estado = 'completada')
        OR (sqlc.narg('estado')::text = 'en_proceso'
            AND (o.estado IS NULL OR o.estado <> 'completada')
            AND (o.fecha_comprometida IS NULL OR o.fecha_comprometida >= now()))
        OR (sqlc.narg('estado')::text = 'expirada'
            AND (o.estado IS NULL OR o.estado <> 'completada')
            AND o.fecha_comprometida < now())
    )
    AND (sqlc.narg('archivado')::boolean IS NULL OR o.archivado = sqlc.narg('archivado')::boolean)
    -- «Sin domicilio» incluye los que no traen el dato: no saberlo no es llevarlo.
    AND (
        sqlc.narg('domicilio')::boolean IS NULL
        OR (sqlc.narg('domicilio')::boolean AND o.requiere_domicilio)
        OR (NOT sqlc.narg('domicilio')::boolean
            AND (o.requiere_domicilio IS NULL OR NOT o.requiere_domicilio))
    )
    AND (
        sqlc.narg('cotizado')::boolean IS NULL
        OR (sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NOT NULL)
        OR (NOT sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NULL)
    )
    AND (sqlc.narg('municipio')::text IS NULL OR o.municipio = sqlc.narg('municipio')::text)
    AND (sqlc.narg('vendedor')::text  IS NULL OR o.vendedor  = sqlc.narg('vendedor')::text)
    -- El estado de REPARTO es propio del reparto: no tiene nada que ver con el estado del
    -- pedido en PEDIDO ni con el de la factura. Manda el RESULTADO de la parada y NO el
    -- estado de la ruta: una ruta completada no dice nada de cada parada, y darlo por
    -- bueno convertía en «entregado» lo que el propio cierre había grabado como devuelto.
    AND (
        sqlc.narg('reparto')::text IS NULL
        OR (sqlc.narg('reparto')::text = 'sin_entregar'
            AND o.route_id IS NULL AND o.delivered_at IS NULL
            AND (o.resultado IS NULL OR o.resultado <> 'entregado'))
        OR (sqlc.narg('reparto')::text = 'en_despacho'
            AND EXISTS (SELECT 1 FROM routes r WHERE r.id = o.route_id AND r.status = 'planned'))
        OR (sqlc.narg('reparto')::text = 'en_ruta'
            AND EXISTS (SELECT 1 FROM routes r WHERE r.id = o.route_id AND r.status = 'in_progress'))
        OR (sqlc.narg('reparto')::text = 'entregado'
            AND (o.resultado = 'entregado' OR o.delivered_at IS NOT NULL))
        OR (sqlc.narg('reparto')::text = 'devuelto'
            AND o.resultado IN ('devuelto', 'cancelado'))
    )
    -- `sin_cotejar` tiene opción propia porque NULL NO es «cuadra»: quiere decir que no se
    -- sabe —VPN a Ventra caída, pedido fuera de los días que se repasan, sucursal sin base—.
    AND (
        sqlc.narg('factura')::text IS NULL
        OR (sqlc.narg('factura')::text = 'con_factura' AND o.factura_estado IN ('igual', 'cambiado'))
        OR (sqlc.narg('factura')::text = 'cuadra'      AND o.factura_estado = 'igual')
        OR (sqlc.narg('factura')::text = 'sin_cotejar' AND o.factura_estado IS NULL)
        OR (sqlc.narg('factura')::text NOT IN ('con_factura', 'cuadra', 'sin_cotejar')
            AND o.factura_estado::text = sqlc.narg('factura')::text)
    )
    -- La segunda rama es para los pedidos anteriores a que se guardara `order_date`:
    -- con sólo la primera desaparecerían de toda búsqueda por fechas, y desaparecer sin
    -- decir nada es peor que salir con la fecha aproximada, que la pantalla ya marca.
    -- `hasta` lo manda el llamante ya como fin de día: quien escribe el 24 quiere los del 24.
    AND (
        (sqlc.narg('desde')::timestamptz IS NULL AND sqlc.narg('hasta')::timestamptz IS NULL)
        OR (o.order_date IS NOT NULL
            AND (sqlc.narg('desde')::timestamptz IS NULL OR o.order_date >= sqlc.narg('desde')::timestamptz)
            AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.order_date <= sqlc.narg('hasta')::timestamptz))
        OR (o.order_date IS NULL
            AND (sqlc.narg('desde')::timestamptz IS NULL OR o.created_at >= sqlc.narg('desde')::timestamptz)
            AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.created_at <= sqlc.narg('hasta')::timestamptz))
    )
    -- `fecha` acota UN día natural, medio abierto por arriba. Es otro filtro que el rango:
    -- la pantalla del armador ofrece los dos y se combinan en AND.
    AND (
        sqlc.narg('dia_desde')::timestamptz IS NULL
        OR (o.order_date IS NOT NULL
            AND o.order_date >= sqlc.narg('dia_desde')::timestamptz
            AND o.order_date <  sqlc.narg('dia_hasta')::timestamptz)
        OR (o.order_date IS NULL
            AND o.created_at >= sqlc.narg('dia_desde')::timestamptz
            AND o.created_at <  sqlc.narg('dia_hasta')::timestamptz)
    )
ORDER BY o.order_date DESC NULLS LAST, o.created_at DESC
LIMIT sqlc.arg('limite');

-- El `total` de la pantalla de disponibles: el mismo WHERE, sin tope ni orden.
-- Tiene que ser EL MISMO o el contador dice una cosa y la tabla otra.
-- name: ContarPedidosDisponibles :one
SELECT count(*)
FROM orders o
WHERE
    o.source = 'pedido'
    AND o.route_id IS NULL
    AND o.end_lat IS NOT NULL
    AND o.end_lng IS NOT NULL
    AND o.factura_estado IN ('igual', 'cambiado')
    AND (sqlc.narg('sucursal')::uuid  IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
    AND (sqlc.narg('branch_id')::uuid IS NULL OR o.branch_id = sqlc.narg('branch_id')::uuid)
    AND (
        sqlc.narg('q')::text IS NULL
        OR o.customer_name    ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.operation_number ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.end_address      ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.address          ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.municipio        ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.vendedor         ILIKE '%' || sqlc.narg('q')::text || '%'
        OR EXISTS (
            SELECT 1 FROM order_items oi
            WHERE oi.order_id = o.id
              AND oi.description ILIKE '%' || sqlc.narg('q')::text || '%'
        )
    )
    AND (
        sqlc.narg('estado')::text IS NULL
        OR (sqlc.narg('estado')::text = 'completada' AND o.estado = 'completada')
        OR (sqlc.narg('estado')::text = 'en_proceso'
            AND (o.estado IS NULL OR o.estado <> 'completada')
            AND (o.fecha_comprometida IS NULL OR o.fecha_comprometida >= now()))
        OR (sqlc.narg('estado')::text = 'expirada'
            AND (o.estado IS NULL OR o.estado <> 'completada')
            AND o.fecha_comprometida < now())
    )
    AND (sqlc.narg('archivado')::boolean IS NULL OR o.archivado = sqlc.narg('archivado')::boolean)
    AND (
        sqlc.narg('domicilio')::boolean IS NULL
        OR (sqlc.narg('domicilio')::boolean AND o.requiere_domicilio)
        OR (NOT sqlc.narg('domicilio')::boolean
            AND (o.requiere_domicilio IS NULL OR NOT o.requiere_domicilio))
    )
    AND (
        sqlc.narg('cotizado')::boolean IS NULL
        OR (sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NOT NULL)
        OR (NOT sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NULL)
    )
    AND (sqlc.narg('municipio')::text IS NULL OR o.municipio = sqlc.narg('municipio')::text)
    AND (sqlc.narg('vendedor')::text  IS NULL OR o.vendedor  = sqlc.narg('vendedor')::text)
    AND (
        sqlc.narg('reparto')::text IS NULL
        OR (sqlc.narg('reparto')::text = 'sin_entregar'
            AND o.route_id IS NULL AND o.delivered_at IS NULL
            AND (o.resultado IS NULL OR o.resultado <> 'entregado'))
        OR (sqlc.narg('reparto')::text = 'en_despacho'
            AND EXISTS (SELECT 1 FROM routes r WHERE r.id = o.route_id AND r.status = 'planned'))
        OR (sqlc.narg('reparto')::text = 'en_ruta'
            AND EXISTS (SELECT 1 FROM routes r WHERE r.id = o.route_id AND r.status = 'in_progress'))
        OR (sqlc.narg('reparto')::text = 'entregado'
            AND (o.resultado = 'entregado' OR o.delivered_at IS NOT NULL))
        OR (sqlc.narg('reparto')::text = 'devuelto'
            AND o.resultado IN ('devuelto', 'cancelado'))
    )
    AND (
        sqlc.narg('factura')::text IS NULL
        OR (sqlc.narg('factura')::text = 'con_factura' AND o.factura_estado IN ('igual', 'cambiado'))
        OR (sqlc.narg('factura')::text = 'cuadra'      AND o.factura_estado = 'igual')
        OR (sqlc.narg('factura')::text = 'sin_cotejar' AND o.factura_estado IS NULL)
        OR (sqlc.narg('factura')::text NOT IN ('con_factura', 'cuadra', 'sin_cotejar')
            AND o.factura_estado::text = sqlc.narg('factura')::text)
    )
    AND (
        (sqlc.narg('desde')::timestamptz IS NULL AND sqlc.narg('hasta')::timestamptz IS NULL)
        OR (o.order_date IS NOT NULL
            AND (sqlc.narg('desde')::timestamptz IS NULL OR o.order_date >= sqlc.narg('desde')::timestamptz)
            AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.order_date <= sqlc.narg('hasta')::timestamptz))
        OR (o.order_date IS NULL
            AND (sqlc.narg('desde')::timestamptz IS NULL OR o.created_at >= sqlc.narg('desde')::timestamptz)
            AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.created_at <= sqlc.narg('hasta')::timestamptz))
    )
    AND (
        sqlc.narg('dia_desde')::timestamptz IS NULL
        OR (o.order_date IS NOT NULL
            AND o.order_date >= sqlc.narg('dia_desde')::timestamptz
            AND o.order_date <  sqlc.narg('dia_hasta')::timestamptz)
        OR (o.order_date IS NULL
            AND o.created_at >= sqlc.narg('dia_desde')::timestamptz
            AND o.created_at <  sqlc.narg('dia_hasta')::timestamptz)
    );

-- ---------------------------------------------------------------------------
-- El catálogo de pedidos  (GET /api/orders)
-- ---------------------------------------------------------------------------

-- La lista paginada, con su ruta y su sucursal. Mismos filtros que los disponibles —tienen
-- que significar lo MISMO en las dos pantallas o los números no cuadran y nadie sabe cuál
-- creerse—, pero SIN las cinco condiciones fijas: aquí se ve todo el histórico.
-- name: ListarPedidos :many
SELECT
    o.id, o.operation_number, o.customer_name, o.customer_phone, o.address,
    o.end_address, o.end_lat, o.end_lng, o.weight, o.status, o.notes,
    o.route_id, o.delivery_price, o.delivery_distance_km, o.order_date,
    o.created_at, o.delivered_at, o.resultado, o.resultado_nota, o.stop_order,
    o.estado, o.archivado, o.fecha_comprometida, o.requiere_domicilio,
    o.pedido_costo, o.factura_estado, o.factura_numero, o.factura_domicilio,
    o.municipio, o.vendedor, o.sucursal_codigo, o.branch_id,
    r.name          AS ruta_nombre,
    r.route_code    AS ruta_codigo,
    r.status        AS ruta_estado,
    r.delivery_date AS ruta_fecha,
    v.name          AS vehiculo_nombre,
    v.plate         AS vehiculo_matricula,
    b.name          AS sucursal_nombre,
    b.lat           AS sucursal_lat,
    b.lng           AS sucursal_lng
FROM orders o
LEFT JOIN routes   r ON r.id = o.route_id
LEFT JOIN vehicles v ON v.id = r.vehicle_id
LEFT JOIN branches b ON b.id = o.branch_id
WHERE
    (sqlc.narg('sucursal')::uuid  IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
    AND (sqlc.narg('branch_id')::uuid IS NULL OR o.branch_id = sqlc.narg('branch_id')::uuid)
    AND (
        sqlc.narg('q')::text IS NULL
        OR o.customer_name    ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.operation_number ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.end_address      ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.address          ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.municipio        ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.vendedor         ILIKE '%' || sqlc.narg('q')::text || '%'
        OR EXISTS (
            SELECT 1 FROM order_items oi
            WHERE oi.order_id = o.id
              AND oi.description ILIKE '%' || sqlc.narg('q')::text || '%'
        )
    )
    AND (
        sqlc.narg('estado')::text IS NULL
        OR (sqlc.narg('estado')::text = 'completada' AND o.estado = 'completada')
        OR (sqlc.narg('estado')::text = 'en_proceso'
            AND (o.estado IS NULL OR o.estado <> 'completada')
            AND (o.fecha_comprometida IS NULL OR o.fecha_comprometida >= now()))
        OR (sqlc.narg('estado')::text = 'expirada'
            AND (o.estado IS NULL OR o.estado <> 'completada')
            AND o.fecha_comprometida < now())
    )
    AND (sqlc.narg('archivado')::boolean IS NULL OR o.archivado = sqlc.narg('archivado')::boolean)
    AND (
        sqlc.narg('domicilio')::boolean IS NULL
        OR (sqlc.narg('domicilio')::boolean AND o.requiere_domicilio)
        OR (NOT sqlc.narg('domicilio')::boolean
            AND (o.requiere_domicilio IS NULL OR NOT o.requiere_domicilio))
    )
    AND (
        sqlc.narg('cotizado')::boolean IS NULL
        OR (sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NOT NULL)
        OR (NOT sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NULL)
    )
    AND (sqlc.narg('municipio')::text IS NULL OR o.municipio = sqlc.narg('municipio')::text)
    AND (sqlc.narg('vendedor')::text  IS NULL OR o.vendedor  = sqlc.narg('vendedor')::text)
    AND (
        sqlc.narg('reparto')::text IS NULL
        OR (sqlc.narg('reparto')::text = 'sin_entregar'
            AND o.route_id IS NULL AND o.delivered_at IS NULL
            AND (o.resultado IS NULL OR o.resultado <> 'entregado'))
        OR (sqlc.narg('reparto')::text = 'en_despacho' AND r.status = 'planned')
        OR (sqlc.narg('reparto')::text = 'en_ruta'     AND r.status = 'in_progress')
        OR (sqlc.narg('reparto')::text = 'entregado'
            AND (o.resultado = 'entregado' OR o.delivered_at IS NOT NULL))
        OR (sqlc.narg('reparto')::text = 'devuelto'
            AND o.resultado IN ('devuelto', 'cancelado'))
    )
    AND (
        sqlc.narg('factura')::text IS NULL
        OR (sqlc.narg('factura')::text = 'con_factura' AND o.factura_estado IN ('igual', 'cambiado'))
        OR (sqlc.narg('factura')::text = 'cuadra'      AND o.factura_estado = 'igual')
        OR (sqlc.narg('factura')::text = 'sin_cotejar' AND o.factura_estado IS NULL)
        OR (sqlc.narg('factura')::text NOT IN ('con_factura', 'cuadra', 'sin_cotejar')
            AND o.factura_estado::text = sqlc.narg('factura')::text)
    )
    AND (
        (sqlc.narg('desde')::timestamptz IS NULL AND sqlc.narg('hasta')::timestamptz IS NULL)
        OR (o.order_date IS NOT NULL
            AND (sqlc.narg('desde')::timestamptz IS NULL OR o.order_date >= sqlc.narg('desde')::timestamptz)
            AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.order_date <= sqlc.narg('hasta')::timestamptz))
        OR (o.order_date IS NULL
            AND (sqlc.narg('desde')::timestamptz IS NULL OR o.created_at >= sqlc.narg('desde')::timestamptz)
            AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.created_at <= sqlc.narg('hasta')::timestamptz))
    )
ORDER BY o.order_date DESC NULLS LAST, o.created_at DESC
LIMIT sqlc.arg('limite') OFFSET sqlc.arg('desplazamiento');

-- El total del catálogo, para la paginación. Mismo WHERE que `ListarPedidos`.
-- name: ContarPedidos :one
SELECT count(*)
FROM orders o
LEFT JOIN routes r ON r.id = o.route_id
WHERE
    (sqlc.narg('sucursal')::uuid  IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
    AND (sqlc.narg('branch_id')::uuid IS NULL OR o.branch_id = sqlc.narg('branch_id')::uuid)
    AND (
        sqlc.narg('q')::text IS NULL
        OR o.customer_name    ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.operation_number ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.end_address      ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.address          ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.municipio        ILIKE '%' || sqlc.narg('q')::text || '%'
        OR o.vendedor         ILIKE '%' || sqlc.narg('q')::text || '%'
        OR EXISTS (
            SELECT 1 FROM order_items oi
            WHERE oi.order_id = o.id
              AND oi.description ILIKE '%' || sqlc.narg('q')::text || '%'
        )
    )
    AND (
        sqlc.narg('estado')::text IS NULL
        OR (sqlc.narg('estado')::text = 'completada' AND o.estado = 'completada')
        OR (sqlc.narg('estado')::text = 'en_proceso'
            AND (o.estado IS NULL OR o.estado <> 'completada')
            AND (o.fecha_comprometida IS NULL OR o.fecha_comprometida >= now()))
        OR (sqlc.narg('estado')::text = 'expirada'
            AND (o.estado IS NULL OR o.estado <> 'completada')
            AND o.fecha_comprometida < now())
    )
    AND (sqlc.narg('archivado')::boolean IS NULL OR o.archivado = sqlc.narg('archivado')::boolean)
    AND (
        sqlc.narg('domicilio')::boolean IS NULL
        OR (sqlc.narg('domicilio')::boolean AND o.requiere_domicilio)
        OR (NOT sqlc.narg('domicilio')::boolean
            AND (o.requiere_domicilio IS NULL OR NOT o.requiere_domicilio))
    )
    AND (
        sqlc.narg('cotizado')::boolean IS NULL
        OR (sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NOT NULL)
        OR (NOT sqlc.narg('cotizado')::boolean AND o.pedido_costo IS NULL)
    )
    AND (sqlc.narg('municipio')::text IS NULL OR o.municipio = sqlc.narg('municipio')::text)
    AND (sqlc.narg('vendedor')::text  IS NULL OR o.vendedor  = sqlc.narg('vendedor')::text)
    AND (
        sqlc.narg('reparto')::text IS NULL
        OR (sqlc.narg('reparto')::text = 'sin_entregar'
            AND o.route_id IS NULL AND o.delivered_at IS NULL
            AND (o.resultado IS NULL OR o.resultado <> 'entregado'))
        OR (sqlc.narg('reparto')::text = 'en_despacho' AND r.status = 'planned')
        OR (sqlc.narg('reparto')::text = 'en_ruta'     AND r.status = 'in_progress')
        OR (sqlc.narg('reparto')::text = 'entregado'
            AND (o.resultado = 'entregado' OR o.delivered_at IS NOT NULL))
        OR (sqlc.narg('reparto')::text = 'devuelto'
            AND o.resultado IN ('devuelto', 'cancelado'))
    )
    AND (
        sqlc.narg('factura')::text IS NULL
        OR (sqlc.narg('factura')::text = 'con_factura' AND o.factura_estado IN ('igual', 'cambiado'))
        OR (sqlc.narg('factura')::text = 'cuadra'      AND o.factura_estado = 'igual')
        OR (sqlc.narg('factura')::text = 'sin_cotejar' AND o.factura_estado IS NULL)
        OR (sqlc.narg('factura')::text NOT IN ('con_factura', 'cuadra', 'sin_cotejar')
            AND o.factura_estado::text = sqlc.narg('factura')::text)
    )
    AND (
        (sqlc.narg('desde')::timestamptz IS NULL AND sqlc.narg('hasta')::timestamptz IS NULL)
        OR (o.order_date IS NOT NULL
            AND (sqlc.narg('desde')::timestamptz IS NULL OR o.order_date >= sqlc.narg('desde')::timestamptz)
            AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.order_date <= sqlc.narg('hasta')::timestamptz))
        OR (o.order_date IS NULL
            AND (sqlc.narg('desde')::timestamptz IS NULL OR o.created_at >= sqlc.narg('desde')::timestamptz)
            AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.created_at <= sqlc.narg('hasta')::timestamptz))
    );

-- ---------------------------------------------------------------------------
-- Un pedido suelto
-- ---------------------------------------------------------------------------

-- name: ObtenerPedido :one
SELECT
    o.id, o.operation_number, o.customer_name, o.customer_phone, o.address,
    o.end_address, o.end_lat, o.end_lng, o.lat, o.lng, o.weight, o.status,
    o.trip_leg, o.notes, o.route_id, o.ultima_ruta_id, o.vehicle_id, o.price,
    o.segment_km, o.delivery_price, o.delivery_distance_km, o.branch_id,
    o.source, o.external_id, o.order_date, o.pedido_updated_at, o.estado,
    o.archivado, o.fecha_comprometida, o.requiere_domicilio, o.pedido_costo,
    o.municipio, o.vendedor, o.sucursal_codigo, o.factura_estado,
    o.factura_numero, o.factura_at, o.factura_domicilio, o.factura_corregido_at,
    o.stop_order, o.delivered_at, o.resultado, o.resultado_at, o.resultado_nota,
    o.created_at, o.updated_at,
    r.name  AS ruta_nombre,
    v.name  AS vehiculo_nombre,
    v.plate AS vehiculo_matricula,
    vt.nombre AS vehiculo_tipo
FROM orders o
LEFT JOIN routes        r  ON r.id  = o.route_id
LEFT JOIN vehicles      v  ON v.id  = o.vehicle_id
LEFT JOIN vehicle_types vt ON vt.id = v.vehicle_type_id
WHERE o.id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid);

-- Los renglones de UN pedido, en el orden del papel del vendedor. `linea` no es decorativa:
-- la hoja del despacho tiene que salir igual que lo que el vendedor escribió.
--
-- El JOIN contra `orders` está SÓLO para poder acotar por sucursal: `order_items` no tiene
-- `branch_id` y sin él bastaría con acertar un uuid de pedido para leer qué mercancía
-- lleva un cliente de otra sucursal. El id del pedido llega de fuera; no se da por bueno.
-- name: ListarRenglonesDePedido :many
SELECT oi.id, oi.order_id, oi.linea, oi.description, oi.quantity, oi.packs, oi.product_id
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
WHERE oi.order_id = sqlc.arg('pedido_id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY oi.linea ASC;

-- Los renglones de VARIOS pedidos de una vez. Una sola consulta para toda la página, no
-- una por fila: con 200 pedidos en pantalla, lo segundo son 200 idas y vueltas.
-- El alcance va aquí también aunque los ids ya vengan de una consulta acotada: si un id se
-- cuela desde el cliente, sin este filtro se leerían los renglones de otra sucursal.
-- name: ListarRenglonesDePedidos :many
SELECT oi.id, oi.order_id, oi.linea, oi.description, oi.quantity, oi.packs, oi.product_id
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
WHERE oi.order_id = ANY(sqlc.arg('pedido_ids')::uuid[])
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
ORDER BY oi.order_id, oi.linea ASC;

-- ---------------------------------------------------------------------------
-- Facetas del catálogo  (GET /api/orders/facetas)
-- ---------------------------------------------------------------------------

-- Los municipios que EXISTEN de verdad en lo que esta persona puede ver, para llenar el
-- desplegable. Si se sacaran de una lista fija, ofrecería municipios sin un solo pedido.
-- name: FacetasMunicipios :many
SELECT o.municipio AS valor, count(*) AS pedidos
FROM orders o
WHERE o.municipio IS NOT NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
GROUP BY o.municipio
ORDER BY o.municipio ASC;

-- name: FacetasVendedores :many
SELECT o.vendedor AS valor, count(*) AS pedidos
FROM orders o
WHERE o.vendedor IS NOT NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
GROUP BY o.vendedor
ORDER BY o.vendedor ASC;

-- Las sucursales con pedidos. El nombre se compone aquí —«Nombre (COD)»— porque es lo que
-- la gente reconoce: el código a secas no dice nada y el nombre solo se repite.
-- name: FacetasSucursales :many
SELECT
    o.branch_id AS valor,
    b.name        AS sucursal_nombre,
    b.external_id AS sucursal_codigo,
    count(*)      AS pedidos
FROM orders o
LEFT JOIN branches b ON b.id = o.branch_id
WHERE o.branch_id IS NOT NULL
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
GROUP BY o.branch_id, b.name, b.external_id
ORDER BY b.name ASC NULLS LAST;

-- ---------------------------------------------------------------------------
-- Pre-despacho: qué mercancía hay que sacar del almacén
-- ---------------------------------------------------------------------------

-- La cuenta de lo que hay que preparar, agrupada por nombre de renglón.
--
-- `formatos` son los bultos y son la unidad con la que se carga y se cuenta un camión;
-- cuando el renglón no los trae se cae a las unidades, porque es lo que hay y cero sería
-- mentira. El peso sale ahora del catálogo (`products.weight`), que es el mismo dato con
-- el que PEDIDO cotiza: el `pesoLineaKg` que venía dentro del JSON de `items` ya no existe.
-- name: ResumenPreDespacho :many
SELECT
    btrim(oi.description) AS producto,
    sum(CASE WHEN oi.packs > 0 THEN oi.packs ELSE oi.quantity END) AS formatos,
    sum(oi.quantity)                                               AS unidades,
    round(sum(coalesce(p.weight, 0) * oi.quantity)::numeric, 2)     AS peso_kg
FROM order_items oi
JOIN orders o        ON o.id = oi.order_id
LEFT JOIN products p ON p.id = oi.product_id
WHERE btrim(oi.description) <> ''
  AND o.id = ANY(sqlc.arg('pedido_ids')::uuid[])
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
GROUP BY btrim(oi.description)
ORDER BY formatos DESC, producto ASC;

-- ---------------------------------------------------------------------------
-- Escrituras del catálogo
-- ---------------------------------------------------------------------------

-- PATCH de un pedido a mano. `coalesce` deja pasar sólo lo que viene: lo que no se manda
-- no se pisa con NULL. `delivered_at` se pone solo al marcar `delivered` — no se le pide
-- al cliente que lo mande, que es como acaban dos pedidos con la misma hora de entrega.
-- name: ActualizarPedido :one
UPDATE orders SET
    operation_number = coalesce(sqlc.narg('operation_number')::text, operation_number),
    customer_name    = coalesce(sqlc.narg('customer_name')::text, customer_name),
    address          = coalesce(sqlc.narg('address')::text, address),
    end_address      = coalesce(sqlc.narg('end_address')::text, end_address),
    end_lat          = coalesce(sqlc.narg('end_lat')::double precision, end_lat),
    end_lng          = coalesce(sqlc.narg('end_lng')::double precision, end_lng),
    lat              = coalesce(sqlc.narg('lat')::double precision, lat),
    lng              = coalesce(sqlc.narg('lng')::double precision, lng),
    weight           = coalesce(sqlc.narg('weight')::double precision, weight),
    notes            = coalesce(sqlc.narg('notes')::text, notes),
    status           = coalesce(sqlc.narg('status')::order_status, status),
    trip_leg         = coalesce(sqlc.narg('trip_leg')::trip_leg, trip_leg),
    price            = coalesce(sqlc.narg('price')::double precision, price),
    stop_order       = coalesce(sqlc.narg('stop_order')::integer, stop_order),
    -- `route_id` va con interruptor y no con coalesce porque ponerlo a NULL es la mitad
    -- de su utilidad: es como se baja un pedido de un camión a mano. Y NO toca
    -- `ultima_ruta_id`, igual que en delivery: en qué ruta viajó no se reescribe desde
    -- una corrección suelta. Meter o sacar pedidos de una ruta de verdad es cosa de
    -- /api/routes; esto es el parche de una equivocación.
    route_id         = CASE WHEN sqlc.arg('tocar_route_id')::boolean
                            THEN sqlc.narg('route_id')::uuid ELSE route_id END,
    delivered_at     = CASE
        WHEN sqlc.narg('status')::order_status = 'delivered' THEN now()
        ELSE delivered_at
    END
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid)
RETURNING id, operation_number, customer_name, address, end_address, end_lat,
          end_lng, lat, lng, weight, status, trip_leg, notes, route_id,
          ultima_ruta_id, price, segment_km, stop_order, delivered_at,
          branch_id, updated_at;

-- :execrows y no :exec: cero filas es «no existe O no es de tu sucursal», que es el 404.
-- Con :exec no hay forma de distinguirlo de un borrado hecho.
-- name: BorrarPedido :execrows
DELETE FROM orders
WHERE id = sqlc.arg('id')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR branch_id = sqlc.narg('sucursal')::uuid);

-- Recalcular el peso desde el catálogo (POST /api/orders/recompute-weights). Va sin
-- alcance a propósito: es una faena de servicio sobre todo el espejo, con clave de API.
-- name: ActualizarPesoDePedido :exec
UPDATE orders SET weight = sqlc.arg('weight')::double precision
WHERE id = sqlc.arg('id');

-- Los pedidos de una procedencia, para el repaso de pesos. Sin alcance: es de servicio.
-- name: ListarPedidosPorFuente :many
SELECT o.id, o.weight, o.external_id
FROM orders o
WHERE o.source = sqlc.arg('source')::procedencia
ORDER BY o.created_at ASC;

-- El peso que le TOCA a cada pedido según el catálogo, junto al que tiene guardado.
--
-- POR QUÉ SE SUMA EN LA BASE Y NO EN GO: el repaso es sobre el espejo ENTERO —decenas de
-- miles de pedidos y sus renglones—, y traérselo todo para multiplicar y sumar es cargar
-- el espejo en la memoria del proceso para devolver dos números por fila.
--
-- El peso sale de `products.weight`, que es el mismo dato con el que PEDIDO cotiza. El
-- `pesoLineaKg` que venía dentro del JSON de `items` YA NO EXISTE: era una copia, y una
-- copia acaba discrepando del catálogo que la originó.
--
-- El LEFT JOIN a `order_items` es a propósito: un pedido SIN renglones tiene que salir
-- igual, con peso calculado 0. Si se cayera de la lista, `totalOrders` diría menos
-- pedidos de los que hay y nadie sabría cuáles faltan.
-- name: PesosDelCatalogoPorFuente :many
SELECT
    o.id,
    o.weight AS peso_guardado,
    coalesce(sum(coalesce(p.weight, 0) * oi.quantity), 0)::double precision AS peso_catalogo
FROM orders o
LEFT JOIN order_items oi ON oi.order_id = o.id
LEFT JOIN products    p  ON p.id = oi.product_id
WHERE o.source = sqlc.arg('source')::procedencia
GROUP BY o.id, o.weight
ORDER BY o.created_at ASC;

-- Los renglones que el catálogo NO sabe pesar, contados por nombre. Es la lista que hay
-- que llevarle a quien mantiene el catálogo de Ventra: sin ella, `ordersSinPeso` dice que
-- hay un problema pero no dice de qué producto.
--
-- `(sin nombre)` literal para el renglón con la descripción en blanco: agruparlos bajo la
-- cadena vacía deja una fila sin etiqueta en la pantalla que nadie sabe leer.
-- name: RenglonesSinPesoPorFuente :many
SELECT
    (coalesce(nullif(btrim(oi.description), ''), '(sin nombre)'))::text AS nombre,
    count(*) AS veces
FROM order_items oi
JOIN orders o        ON o.id = oi.order_id
LEFT JOIN products p ON p.id = oi.product_id
WHERE o.source = sqlc.arg('source')::procedencia
  AND coalesce(p.weight, 0) <= 0
GROUP BY 1
ORDER BY veces DESC, nombre ASC;

-- ---------------------------------------------------------------------------
-- El espejo de PEDIDO  (POST /api/quote/batch)
-- ---------------------------------------------------------------------------

-- Alta o actualización idempotente por (`source`, `external_id`): volver a pasar el mismo
-- lote no duplica. Va sin alcance porque el espejo entra con clave de servicio y trae las
-- ocho sucursales de una vez; la sucursal de cada pedido la decide el propio lote.
--
-- POR QUÉ SON TRES CONSULTAS Y NO UN `ON CONFLICT`: en la migración, `orders_origen_idx`
-- sobre (`source`, `external_id`) es un índice NORMAL, no único, así que no hay nada que
-- inferir en un `ON CONFLICT` y Postgres lo rechazaría al ejecutarlo. Se busca primero y
-- se escribe después, que es además lo que hace el contrato.
--
-- PENDIENTE DE DECIDIR: hacer ese índice UNIQUE. Hoy nada impide que dos pasadas
-- simultáneas del espejo creen el mismo pedido dos veces — las dos leen «no existe» antes
-- de que ninguna escriba. Con el índice único, la segunda falla y se reintenta como
-- actualización; sin él, queda un duplicado que nadie ve hasta que el pedido sale dos
-- veces en la lista del armador.
-- name: BuscarPedidoDelEspejo :one
SELECT o.id, o.branch_id, o.route_id, o.ultima_ruta_id, o.stop_order, o.pedido_updated_at
FROM orders o
WHERE o.source = sqlc.arg('source')::procedencia
  AND o.external_id = sqlc.arg('external_id')::text;

-- name: CrearPedidoDelEspejo :one
INSERT INTO orders (
    operation_number, customer_name, customer_phone, address, end_address,
    end_lat, end_lng, weight, branch_id, source, external_id, order_date,
    pedido_updated_at, estado, archivado, fecha_comprometida, requiere_domicilio,
    pedido_costo, municipio, vendedor, sucursal_codigo, factura_estado,
    factura_numero, factura_at, factura_domicilio, factura_corregido_at,
    delivery_distance_km, delivery_price
) VALUES (
    sqlc.narg('operation_number'), sqlc.arg('customer_name'), sqlc.narg('customer_phone'),
    sqlc.arg('address'), sqlc.narg('end_address'), sqlc.narg('end_lat'), sqlc.narg('end_lng'),
    sqlc.arg('weight'), sqlc.narg('branch_id'), sqlc.arg('source'), sqlc.narg('external_id'),
    sqlc.narg('order_date'), sqlc.narg('pedido_updated_at'), sqlc.narg('estado'),
    sqlc.arg('archivado'), sqlc.narg('fecha_comprometida'), sqlc.narg('requiere_domicilio'),
    sqlc.narg('pedido_costo'), sqlc.narg('municipio'), sqlc.narg('vendedor'),
    sqlc.narg('sucursal_codigo'), sqlc.narg('factura_estado'), sqlc.narg('factura_numero'),
    sqlc.narg('factura_at'), sqlc.narg('factura_domicilio'), sqlc.narg('factura_corregido_at'),
    sqlc.narg('delivery_distance_km'), sqlc.narg('delivery_price')
)
RETURNING id, branch_id, external_id;

-- Lo que NO se pisa nunca: `route_id`, `ultima_ruta_id`, `stop_order`, `resultado`,
-- `resultado_nota` y `delivered_at`. Eso es del reparto y PEDIDO no sabe nada de ello:
-- dejarlo entrar borraría de un plumazo el resultado de una parada ya cerrada, que es
-- justo el dato que dice qué mercancía bajó del camión.
-- name: ActualizarPedidoDelEspejo :one
UPDATE orders SET
    operation_number     = sqlc.narg('operation_number'),
    customer_name        = sqlc.arg('customer_name'),
    customer_phone       = sqlc.narg('customer_phone'),
    address              = sqlc.arg('address'),
    end_address          = sqlc.narg('end_address'),
    end_lat              = sqlc.narg('end_lat'),
    end_lng              = sqlc.narg('end_lng'),
    weight               = sqlc.arg('weight'),
    branch_id            = sqlc.narg('branch_id'),
    order_date           = sqlc.narg('order_date'),
    pedido_updated_at    = sqlc.narg('pedido_updated_at'),
    estado               = sqlc.narg('estado'),
    archivado            = sqlc.arg('archivado'),
    fecha_comprometida   = sqlc.narg('fecha_comprometida'),
    requiere_domicilio   = sqlc.narg('requiere_domicilio'),
    pedido_costo         = sqlc.narg('pedido_costo'),
    municipio            = sqlc.narg('municipio'),
    vendedor             = sqlc.narg('vendedor'),
    sucursal_codigo      = sqlc.narg('sucursal_codigo'),
    factura_estado       = sqlc.narg('factura_estado'),
    factura_numero       = sqlc.narg('factura_numero'),
    factura_at           = sqlc.narg('factura_at'),
    factura_domicilio    = sqlc.narg('factura_domicilio'),
    factura_corregido_at = sqlc.narg('factura_corregido_at'),
    delivery_distance_km = sqlc.narg('delivery_distance_km'),
    delivery_price       = sqlc.narg('delivery_price')
WHERE id = sqlc.arg('id')
RETURNING id, branch_id, external_id;

-- Los renglones se reescriben enteros en cada pasada del espejo: PEDIDO puede haber
-- quitado una línea, y un UPDATE línea a línea dejaría la vieja colgada. Se borran y se
-- vuelven a poner dentro de la MISMA transacción que el upsert de arriba.
-- name: BorrarRenglonesDePedido :exec
DELETE FROM order_items WHERE order_id = sqlc.arg('pedido_id');

-- name: CrearRenglonDePedido :one
INSERT INTO order_items (order_id, linea, description, quantity, packs, product_id)
VALUES (
    sqlc.arg('pedido_id'), sqlc.arg('linea'), sqlc.arg('description'),
    sqlc.arg('quantity'), sqlc.narg('packs'), sqlc.narg('product_id')
)
RETURNING id, order_id, linea, description, quantity, packs, product_id;

-- La marca de agua del espejo: `since` de la próxima bajada.
--
-- Se DERIVA de los datos y no de un contador aparte a propósito: un contador se adelanta
-- si una tanda falla a medias, y entonces el espejo se salta esos pedidos para siempre
-- sin dar un solo error.
-- name: MarcaDeAguaDelEspejo :one
SELECT max(o.pedido_updated_at)::timestamptz AS marca
FROM orders o
WHERE o.source = 'pedido'
  AND (sqlc.narg('sucursal_codigo')::text IS NULL
       OR o.sucursal_codigo = sqlc.narg('sucursal_codigo')::text);

-- ---------------------------------------------------------------------------
-- Panel  (GET /api/dashboard)  e informes  (GET /api/reports)
-- ---------------------------------------------------------------------------

-- Los siete números del panel en UNA consulta.
--
-- REPARTIBLE es el mismo listón del armador de rutas —sin ruta, con coordenadas y con
-- factura que se puede llevar—: si el panel contara otra cosa, diría «40 por repartir» y
-- el armador ofrecería 12, y la respuesta correcta sería «ninguno de los dos».
-- name: PanelResumen :one
SELECT
    count(*)                                                        AS total_pedidos,
    count(*) FILTER (WHERE o.route_id IS NULL
                       AND o.end_lat IS NOT NULL
                       AND o.factura_estado IN ('igual','cambiado')) AS sin_ruta,
    count(*) FILTER (WHERE o.delivered_at >= sqlc.arg('hoy')::timestamptz) AS entregados_hoy,
    coalesce(sum(o.weight) FILTER (WHERE o.route_id IS NULL
                       AND o.end_lat IS NOT NULL
                       AND o.factura_estado IN ('igual','cambiado')), 0)::double precision AS peso_pendiente,
    coalesce(sum(o.pedido_costo), 0)::double precision              AS total_domicilios
FROM orders o
WHERE (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid);

-- El reparto de lo repartible por sucursal. Lo ve quien no tiene alcance —el Super Admin—;
-- a quien sí lo tiene le sale una sola fila, que es justo lo correcto.
-- name: PanelPorSucursal :many
SELECT
    o.branch_id,
    b.name    AS sucursal_nombre,
    count(*)  AS pedidos,
    coalesce(sum(o.weight), 0)::double precision AS peso_kg
FROM orders o
LEFT JOIN branches b ON b.id = o.branch_id
WHERE o.route_id IS NULL
  AND o.end_lat IS NOT NULL
  AND o.factura_estado IN ('igual','cambiado')
  AND (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
GROUP BY o.branch_id, b.name
ORDER BY pedidos DESC;

-- El informe. `ingreso` es `price` si lo hay y si no `pedido_costo`: `price` es el reparto
-- de carga de una ruta y `pedido_costo` lo que cobró Entrega; no son lo mismo y cobrar uno
-- por el otro es el error que este COALESCE hace visible en un solo sitio.
-- name: ListarPedidosParaInforme :many
SELECT
    o.id, o.customer_name, o.address, o.end_address, o.weight,
    coalesce(o.price, o.pedido_costo, 0) AS ingreso,
    o.segment_km, o.created_at,
    coalesce(r.route_code, r.name) AS ruta_nombre,
    -- El id del camión sale para poder AGRUPAR por él en `byVehicle`. Agrupar por nombre
    -- juntaría dos camiones distintos que se llamen igual —«Camión 1» lo hay en varias
    -- sucursales, y la matrícula puede estar vacía—, y el informe daría un vehículo con el
    -- doble de ingresos sin que nada falle.
    v.id    AS vehiculo_id,
    v.name  AS vehiculo_nombre,
    v.plate AS vehiculo_matricula
FROM orders o
LEFT JOIN routes   r ON r.id = o.route_id
LEFT JOIN vehicles v ON v.id = r.vehicle_id
WHERE
    (sqlc.narg('sucursal')::uuid IS NULL OR o.branch_id = sqlc.narg('sucursal')::uuid)
    AND (sqlc.narg('desde')::timestamptz IS NULL OR o.created_at >= sqlc.narg('desde')::timestamptz)
    AND (sqlc.narg('hasta')::timestamptz IS NULL OR o.created_at <= sqlc.narg('hasta')::timestamptz)
    AND (sqlc.narg('vehiculo_id')::uuid IS NULL OR r.vehicle_id = sqlc.narg('vehiculo_id')::uuid)
ORDER BY o.created_at DESC;
