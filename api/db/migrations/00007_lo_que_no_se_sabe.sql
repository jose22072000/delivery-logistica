-- Dos números que se leen bien y están mal. Los dos sólo se pueden arreglar aquí.
--
-- # 1. El kilo que nadie puso
--
-- `orders.weight` nació `NOT NULL DEFAULT 1` (00001_init.sql:276), heredado del
-- `weight Float @default(1)` del Prisma de delivery. Un pedido cuyo peso nadie sabe no
-- llega al aparato como 0 —que al menos chirría— sino como **1 kg**, que es perfectamente
-- creíble para un paquete. De ahí se suma en la tarjeta «Peso Total» de Informes, en el
-- pie de sus dos tablas, en el Excel que alguien abre para cobrar y, lo más caro, en la
-- barra de capacidad del camión, que es la que decide qué cabe.
--
-- El propio lado Go ya tiene escrita la regla contraria, en `internal/ventra`: «`weightKg`
-- viene null en muchos productos y eso NO es cero: cero kilos es una mentira». Ventra sí
-- distingue el nulo; el esquema se lo comía al guardarlo.
--
-- LO QUE SE HACE AQUÍ, Y POR QUÉ NO SE HACE MÁS:
--
--   a) **Se quita el DEFAULT.** Hoy la única sentencia que inserta en `orders` es
--      `GuardarPedidoDelEspejo`, y nombra `weight` siempre. O sea que el `DEFAULT 1` no
--      rellena ningún hueco: lo único que hace es esperar a que alguien escriba un INSERT
--      que se olvide de la columna, y entonces inventarle un kilo en silencio. Sin él,
--      ese olvido revienta contra el `NOT NULL` con un error que nombra la columna. **Un
--      peso que falta pasa de ser un número creíble a ser un fallo.**
--
--   b) **NO se hace `DROP NOT NULL`.** Sería lo correcto de verdad —«no lo sé» tiene que
--      caber en la columna—, pero un `weight` anulable cambia en silencio lo que hacen
--      las ~10 consultas que suman pesos: `sum()` se salta los NULL, así que la tarjeta
--      de Informes y la barra de capacidad pasarían de mentir por arriba a mentir por
--      abajo, sin un solo error y sin que ninguna prueba lo note. Eso no se hace a medias:
--      hay que arreglar a la vez el que suma, el que lo pinta y el que lo exporta, y eso
--      toca `internal/api/informes.go`, `internal/api/tablero.go` y varias pantallas de
--      `app/`. Queda escrito como lo que falta, no como lo que se olvidó. Quitar el
--      DEFAULT ahora es justamente lo que deja esa puerta abierta: cuando se anule la
--      columna no habrá que pelearse con un valor por defecto que la rellene.
--
--   c) **Se da de alta la confesión que ya existía**, `peso_de_los_pedidos`. Desde el
--      14/09/2026 cada renglón lleva `origen_peso` y `caso` (00004_peso_por_renglon.sql),
--      que dicen de dónde salió su peso y si casó con el catálogo. Con eso se puede saber
--      que un peso es inventado SIN tocar el tipo de la columna ni el contrato de las APK
--      instaladas. La vista lo deja a mano de quien consulta por SQL o exporta a mano, que
--      es quien hoy no tiene forma ninguna de enterarse.
--
-- LO QUE LA VISTA **NO** PUEDE DECIR, y hay que saberlo antes de creérsela: distingue tres
-- estados, no dos, y el tercero es el que más filas tiene hoy.
--
--   * `false` — hay constancia y dice que NADA respalda ese peso. El número es inventado.
--   * `true`  — algún renglón trae peso propio: el número sale de algo.
--   * `NULL`  — **no consta**. Y no consta en dos casos muy distintos: un pedido sin
--     renglones, y —el importante— todo lo que ha escrito el espejo desde el traspaso.
--     `CrearRenglonDePedido` (db/queries/orders.sql) inserta sólo
--     `(order_id, linea, description, quantity, packs, product_id)`: las siete columnas
--     que añadió 00004 **no las rellena nadie**, y por eso ahí sólo hay constancia de lo
--     que trajo el traspaso (db/migracion/02_pedidos.sql). Revivir esa escritura —el
--     espejo YA tiene los valores en `cotizar.RenglonPesado`— es lo que hace que esta
--     vista sirva para los pedidos de mañana y no sólo para los viejos.
--
-- Un NULL aquí NO significa «el peso está bien». Significa que no se guardó de dónde salía.
--
-- # 2. `routes.total_price`, fuera del aparato
--
-- Dentro de la aplicación ya está resuelto: el importe se suma de las paradas —que sí
-- saben decir que no lo saben— y `total_price` pasó a ser un espejo declarado del total
-- del servidor (`app/lib/pantallas/rutas/datos/importe_de_la_ruta.dart`). Pero la columna
-- sigue siendo `NOT NULL DEFAULT 0` (00001_init.sql:426), y **quien la consulte por SQL o
-- la exporte sigue viendo un cero indistinguible de un cero de verdad**. La ruta
-- RT-20260921-007 decía `$0.00` con sus dos paradas sin cotizar y el camión a 1,50 USD/km.
--
-- De las dos salidas apuntadas se toma la segunda: **una columna con cuántas paradas
-- entraron sin cotizar**, y no anular `total_price`. Motivos:
--
--   * No rompe a nadie que ya lea la columna —ni las APK instaladas, ni los informes, ni
--     un `SELECT` de hoy—: es un campo nuevo al lado, no un tipo cambiado.
--   * Dice MÁS que un NULL. «El total es 340 y 2 de 5 paradas no están cotizadas» se
--     puede arreglar; un NULL sólo dice que no te fíes, y en el 96% de los domicilios
--     reales (657 de 686 sin costo) habría dejado la columna vacía siempre, que es otra
--     forma de no decir nada.
--   * Es la misma forma que ya tiene `ImporteDeRuta.sinCotizar` en el aparato: el total y
--     el número de los que faltan, juntos. Dos sitios contestando lo mismo con la misma
--     forma.
--
-- Es ANULABLE a propósito, y NULL significa «no consta cuántas faltaban»: las rutas de
-- antes de esta migración. No se rellenan hacia atrás adivinando desde `orders.price`,
-- porque un pedido puede haberse bajado, corregido o traspasado desde entonces, y un
-- número inventado con cara de exacto es justo lo que se está arreglando. Un cero ahí
-- diría «estaban todas cotizadas», y eso es lo único que no se puede decir.

-- +goose Up

-- ---------------------------------------------------------------------------
-- 1. El peso
-- ---------------------------------------------------------------------------

ALTER TABLE orders ALTER COLUMN weight DROP DEFAULT;

COMMENT ON COLUMN orders.weight IS
    'Kilos del pedido. NO sabe decir «no se sabe»: un peso sin resolver entra como 0 y lo '
    'anterior al traspaso entra como 1 (el DEFAULT de Prisma). Antes de sumarlo o cobrarlo, '
    'mira peso_de_los_pedidos.peso_respaldado.';

CREATE VIEW peso_de_los_pedidos AS
SELECT
    o.id,
    o.weight AS peso_guardado,
    c.renglones,
    c.renglones_con_constancia,
    c.peso_respaldado
FROM orders o
LEFT JOIN LATERAL (
    SELECT
        count(*)                                                 AS renglones,
        count(*) FILTER (WHERE oi.peso_linea_kg IS NOT NULL
                            OR oi.origen_peso   IS NOT NULL)     AS renglones_con_constancia,
        -- LOS TRES ESTADOS SALEN DEL `FILTER`, no de un CASE: el filtro deja fuera los
        -- renglones que no guardaron constancia ninguna, y `bool_or` sobre cero filas da
        -- NULL. Así, un pedido cuyos renglones se escribieron sin `origen_peso` sale NULL
        -- —«no consta»— en vez de `false` —«inventado»—, que sería acusar de mentira a un
        -- peso probablemente bueno: cambiar una mentira por la contraria.
        --
        -- 'none' es `cotizar.PesoDesconocido`: el renglón confesando que lo intentó y no
        -- pudo. Va en OR con el peso porque son dos respaldos distintos —un renglón puede
        -- traer origen 'catalogo' y línea 0 porque no venían los bultos, y eso sigue
        -- siendo un peso resuelto, no un peso inventado.
        bool_or(coalesce(oi.peso_linea_kg, 0) > 0
                OR (oi.origen_peso IS NOT NULL AND oi.origen_peso <> 'none'))
            FILTER (WHERE oi.peso_linea_kg IS NOT NULL
                       OR oi.origen_peso   IS NOT NULL)          AS peso_respaldado
    FROM order_items oi
    WHERE oi.order_id = o.id
) c ON true;

COMMENT ON VIEW peso_de_los_pedidos IS
    'Si el peso guardado de un pedido está respaldado por sus renglones. true = algún '
    'renglón trae peso propio; false = hay constancia y ninguno sabe pesar, el número es '
    'inventado; NULL = no consta (pedido sin renglones, o renglones escritos sin origen_peso). '
    'NULL no quiere decir que el peso esté bien.';

-- ---------------------------------------------------------------------------
-- 2. El importe de la ruta
-- ---------------------------------------------------------------------------

ALTER TABLE routes ADD COLUMN paradas_sin_cotizar integer;

COMMENT ON COLUMN routes.total_price IS
    'Suma de lo que SÍ está cotizado, no de la ruta entera: las paradas sin costo suman 0. '
    'Sólo es el total de la ruta cuando paradas_sin_cotizar = 0. Un 0 aquí con '
    'paradas_sin_cotizar > 0 no dice que el reparto fuera gratis.';

COMMENT ON COLUMN routes.paradas_sin_cotizar IS
    'Cuántas paradas entraron en la ruta sin costo de domicilio, contadas al armarla. '
    'NULL = no consta (rutas anteriores a esta migración); 0 = estaban todas cotizadas.';

-- +goose Down

DROP VIEW IF EXISTS peso_de_los_pedidos;
ALTER TABLE routes DROP COLUMN IF EXISTS paradas_sin_cotizar;
ALTER TABLE orders ALTER COLUMN weight SET DEFAULT 1;
