-- Índices que faltaban, MEDIDOS antes y después. Ninguno está aquí por intuición.
--
-- Medido el 26/09/2026 en un Postgres 16 con el volumen de producción sembrado (55.600
-- pedidos, 50.800 archivados, 222.400 renglones, 6.000 rutas, 8 sucursales), cada
-- consulta cinco veces y la mejor, con plan a medida (ver `PlanesAMedida` en
-- `internal/store/store.go`, que es el otro medio de este arreglo y el que más pesa):
--
--   ListarPedidosDisponibles            5,3 ms  ->  0,5 ms   orders_repartibles_idx
--   ListarPedidos con búsqueda         22,7 ms  ->  0,05 ms  orders_sucursal_fecha_idx
--   DiferenciasDePedidos (la bajada)    1,1 ms  ->  0,3 ms   orders_marca_idx
--   ListarVehiculos                     6,0 ms  ->  1,4 ms   los de vehicle_id
--   ListarPedidosParaInforme            5,7 ms  ->  1,9 ms   orders_sucursal_alta_idx
--
-- LO QUE SE PROBÓ Y NO ENTRÓ: un `routes (branch_id, created_at)` para `ListarRutas` no
-- movió la aguja (2,5 ms con y sin él), así que no se paga su coste en cada escritura.
-- Y se quedan `orders_archivado_idx` y `orders_domicilio_idx`, que parecían inútiles
-- por ser booleanos: `NOT archivado` son 4.800 de 55.600, y el planificador los usa.
--
-- # Por qué NO TRANSACTION y CONCURRENTLY
--
-- Un `CREATE INDEX` normal bloquea las escrituras de la tabla mientras se construye, y
-- `orders` la escribe el espejo cada pocos minutos. `CONCURRENTLY` no bloquea, pero no
-- puede ir dentro de una transacción, y goose mete cada migración en una salvo que se
-- le diga lo contrario. Por eso esta migración va SOLA y sin nada que no sea índices.
--
-- Cada índice va precedido de su `DROP ... IF EXISTS`, y no por adorno: si un
-- `CONCURRENTLY` se corta a medias deja el índice creado pero INVÁLIDO, y un `IF NOT
-- EXISTS` lo daría por bueno para siempre. Así, volver a lanzar la migración lo rehace.
--
-- # Lo que se probó y se QUITÓ: el buscador con trigramas (pg_trgm)
--
-- Se escribió entero —extensión, una función `texto_de_busqueda` con las seis columnas y
-- dos índices GIN— y las búsquedas SELECTIVAS pasaban de ~60 ms a ~2 ms con los mismos
-- resultados. La auditoría lo tumbó, y con razón: para aprovechar el índice la consulta
-- tenía que ser `q IS NULL OR o.id IN (SELECT … UNION ALL SELECT …)`, y un `IN` metido
-- dentro de un `OR` no se puede convertir en un cruce. Con un término FRECUENTE («a», una
-- palabra corta) Postgres no cabe en memoria el subconjunto y lo recorre fila por fila:
-- **más de 25 s** donde la consulta de siempre tardaba 100 ms. Un buscador que se cuelga
-- con lo que más se teclea es peor que uno algo lento. Las búsquedas siguen con su
-- `ILIKE` de antes; la lista de Pedidos buscando ya va rápida por
-- `orders_sucursal_fecha_idx`, que la saca en su orden y para en la página.
--
-- # Si se corta a medias
--
-- La URL de las migraciones lleva `lock_timeout=5s` (docs/despliegue.md §2.4), y la
-- espera de un `CONCURRENTLY` a que acaben las transacciones abiertas cuenta como espera
-- de candado: con una transacción del espejo abierta más de 5 s, se cancela y deja el
-- índice INVÁLIDO. goose no apunta la migración y basta con relanzarla, porque cada
-- `CREATE` va precedido de su `DROP ... IF EXISTS`. Lo vigila
-- `internal/store/migracion_de_indices_test.go`.

-- +goose NO TRANSACTION
-- +goose Up
-- Los repartibles: lo que ofrecen el armador y el tablero. ~2.800 de 55.600, y ya en el
-- orden de la lista. La condición es la parte común a las CUATRO consultas que lo usan
-- (Listar/ContarPedidosDisponibles y Listar/ContarPedidosSinColocar); el resto de sus
-- filtros se aplica sobre esas pocas filas. Si una de ellas deja de pedir alguna de estas
-- cuatro condiciones, Postgres deja de poder usar el índice SIN AVISAR: lo ata
-- `internal/store/migracion_de_indices_test.go`.
DROP INDEX CONCURRENTLY IF EXISTS orders_repartibles_idx;
CREATE INDEX CONCURRENTLY orders_repartibles_idx
    ON orders (branch_id, order_date DESC NULLS LAST, created_at DESC)
    WHERE source = 'pedido' AND route_id IS NULL AND delivered_at IS NULL AND NOT archivado;

-- El orden de la lista de Pedidos. `orders_fecha_idx` es sólo `order_date`, y recorrido
-- hacia atrás saca los NULL PRIMERO, al revés de lo que pide el `NULLS LAST`.
DROP INDEX CONCURRENTLY IF EXISTS orders_sucursal_fecha_idx;
CREATE INDEX CONCURRENTLY orders_sucursal_fecha_idx
    ON orders (branch_id, order_date DESC NULLS LAST, created_at DESC);

-- Los informes y el uso de productos van por la fecha de alta.
DROP INDEX CONCURRENTLY IF EXISTS orders_sucursal_alta_idx;
CREATE INDEX CONCURRENTLY orders_sucursal_alta_idx ON orders (branch_id, created_at DESC);

-- La bajada pregunta «qué cambió desde la marca» SIN sucursal en esa rama.
-- `orders_sucursal_marca_idx (branch_id, updated_at)` empieza por la sucursal y ahí no
-- sirve: cada ciclo de cada aparato leía `orders` entera.
DROP INDEX CONCURRENTLY IF EXISTS orders_marca_idx;
CREATE INDEX CONCURRENTLY orders_marca_idx ON orders (updated_at);

-- Claves ajenas a `vehicles` sin índice. Postgres NO indexa solo el lado que referencia:
-- borrar un vehículo, o listarlos con sus rutas y pedidos, recorría las tres tablas.
DROP INDEX CONCURRENTLY IF EXISTS orders_vehiculo_idx;
CREATE INDEX CONCURRENTLY orders_vehiculo_idx ON orders (vehicle_id);
DROP INDEX CONCURRENTLY IF EXISTS routes_vehiculo_idx;
CREATE INDEX CONCURRENTLY routes_vehiculo_idx ON routes (vehicle_id);
DROP INDEX CONCURRENTLY IF EXISTS order_vehicles_vehiculo_idx;
CREATE INDEX CONCURRENTLY order_vehicles_vehiculo_idx ON order_vehicles (vehicle_id);

-- Y fuera los dos que sólo cuestan. `order_items_order_idx` lo cubre entero el
-- `UNIQUE (order_id, linea)`, que empieza por la misma columna. `order_items_desc_idx` es
-- de texto completo (`to_tsvector`) y ninguna consulta usa `@@`: busca con `ILIKE`, que
-- ese índice no sabe contestar. Los dos se pagaban en cada renglón que escribe el espejo.
DROP INDEX CONCURRENTLY IF EXISTS order_items_order_idx;
DROP INDEX CONCURRENTLY IF EXISTS order_items_desc_idx;

-- +goose Down
-- También aquí el DROP delante y no un `IF NOT EXISTS`: un índice inválido de un intento
-- cortado se daría por bueno.
DROP INDEX CONCURRENTLY IF EXISTS order_items_desc_idx;
CREATE INDEX CONCURRENTLY order_items_desc_idx
    ON order_items USING gin (to_tsvector('spanish', description));
DROP INDEX CONCURRENTLY IF EXISTS order_items_order_idx;
CREATE INDEX CONCURRENTLY order_items_order_idx ON order_items (order_id);
DROP INDEX CONCURRENTLY IF EXISTS order_vehicles_vehiculo_idx;
DROP INDEX CONCURRENTLY IF EXISTS routes_vehiculo_idx;
DROP INDEX CONCURRENTLY IF EXISTS orders_vehiculo_idx;
DROP INDEX CONCURRENTLY IF EXISTS orders_marca_idx;
DROP INDEX CONCURRENTLY IF EXISTS orders_sucursal_alta_idx;
DROP INDEX CONCURRENTLY IF EXISTS orders_sucursal_fecha_idx;
DROP INDEX CONCURRENTLY IF EXISTS orders_repartibles_idx;
