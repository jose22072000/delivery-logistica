-- LA BAJADA DE PEDIDOS POR DIFERENCIAS. Postgres 16.
--
-- Cierra lo más grave de ../../docs/integracion-pendiente.md: `GET /api/sync/cambios` no
-- podía servir los pedidos, que son justo lo que el logístico se baja cada mañana. La
-- columna `updated_at` y su trigger ya estaban desde 00001; lo que faltaba era poder
-- preguntar «qué cambió desde» sin leerse la tabla entera, y poder decir qué DESAPARECIÓ.
--
-- Aquí van las dos piezas que el esquema no tenía:
--
--   1. Los índices por marca. Sin ellos, cada bajada de cada aparato es un recorrido
--      completo de `orders` y de `order_items`; con diez logísticos preguntando cada pocos
--      minutos por la conexión de allá, eso es la base de rodillas a media mañana.
--   2. `orders_fuera_de_alcance`, las lápidas. Es lo único que permite contestar
--      `quitados` de verdad.
--
-- POR QUÉ HACEN FALTA LÁPIDAS, y no basta con mirar la tabla de pedidos:
--
--   * Un pedido BORRADO ya no está. No hay fila que mirar, no hay `updated_at` que
--     comparar, y el aparato se queda con él para siempre. La lista local sólo crece.
--   * Un pedido que se MUDA de sucursal —PEDIDO corrige la sucursal de origen— deja de
--     salir en `WHERE branch_id = <la mía>`, así que el aparato de la sucursal vieja
--     tampoco se entera nunca. Y ese pedido sigue apareciendo en su tablero, y alguien lo
--     mete en un camión que no es el suyo.
--
--   El pedido ARCHIVADO no necesita lápida: la fila sigue ahí, con su `archivado` en true
--   y su `updated_at` movido por el trigger, así que sale en las diferencias y quien
--   contesta la bajada lo manda a `quitados`. Se dice aquí para que no se le añada una
--   lápida «por simetría» y acabe saliendo dos veces.

-- +goose Up

-- ---------------------------------------------------------------------------
-- Índices por marca
-- ---------------------------------------------------------------------------

-- `(branch_id, updated_at)` y no `updated_at` a secas: la bajada SIEMPRE pregunta por una
-- sucursal —el alcance es la regla de seguridad de la casa— así que la sucursal va
-- delante. Un índice sólo por la marca obligaría a leer y descartar lo de las otras siete.
CREATE INDEX orders_sucursal_marca_idx ON orders (branch_id, updated_at);

-- Los renglones se buscan por marca SIN sucursal: `order_items` no la tiene, y el cruce
-- con `orders` es lo que la pone. Cambiar un renglón tiene que sacar a su pedido en las
-- diferencias, o el aparato se queda con la lista de mercancía vieja y el camión carga lo
-- que ya no es.
CREATE INDEX order_items_marca_idx ON order_items (updated_at);

-- ---------------------------------------------------------------------------
-- Las lápidas
-- ---------------------------------------------------------------------------

-- Por qué se fue de la sucursal. Conjunto cerrado, enum de verdad, como manda 00001.
--
-- Los dos NO son lo mismo para quien pregunta: al Super Admin, que ve las ocho, un pedido
-- que se mudó de Santiago a Holguín no se le ha ido de la vista —lo sigue viendo, en otra
-- sucursal—, y mandárselo en `quitados` le borraría del aparato un pedido que existe.
-- Borrado sí es borrado para todos.
CREATE TYPE salida_de_pedido AS ENUM ('borrado', 'movido');

-- SIN CLAVE AJENA A `orders` A PROPÓSITO: la mitad de las filas de esta tabla son de
-- pedidos que ya no existen. Una clave ajena las borraría en cascada, que es exactamente
-- la constancia que hace falta guardar.
CREATE TABLE orders_fuera_de_alcance (
    id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id  uuid NOT NULL,
    -- De qué sucursal se fue. Es la VIEJA, la que tenía el pedido antes de irse: es a ese
    -- aparato al que hay que avisarle. NULL = no tenía ninguna (alta manual sin sucursal).
    branch_id uuid,
    motivo    salida_de_pedido NOT NULL,
    -- Marca de DOMINIO, con su nombre, como el resto de la casa: «cuándo se fue», que no
    -- es «cuándo se tocó la fila». La bajada compara contra ésta.
    salio_at  timestamptz NOT NULL DEFAULT now()
);

-- El índice de la consulta de la bajada: por sucursal y por marca, en ese orden.
CREATE INDEX orders_fuera_sucursal_idx ON orders_fuera_de_alcance (branch_id, salio_at);
-- Y uno por pedido, que es por donde el trigger busca la lápida vieja para reemplazarla.
CREATE INDEX orders_fuera_pedido_idx   ON orders_fuera_de_alcance (order_id);

-- +goose StatementBegin
CREATE OR REPLACE FUNCTION apuntar_salida_de_pedido() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        -- Se reemplaza la lápida en vez de añadir otra: lo que el aparato necesita saber
        -- es «este pedido ya no es tuyo», y decírselo dos veces no aporta nada. Además
        -- deja la tabla en una fila por (pedido, sucursal) y no creciendo sin techo.
        DELETE FROM orders_fuera_de_alcance
         WHERE order_id = OLD.id AND branch_id IS NOT DISTINCT FROM OLD.branch_id;
        INSERT INTO orders_fuera_de_alcance (order_id, branch_id, motivo)
        VALUES (OLD.id, OLD.branch_id, 'borrado');
        RETURN OLD;
    END IF;

    -- UPDATE. Sólo interesa el cambio de sucursal; lo demás ya lo cuenta `updated_at`.
    IF OLD.branch_id IS DISTINCT FROM NEW.branch_id THEN
        IF OLD.branch_id IS NOT NULL THEN
            DELETE FROM orders_fuera_de_alcance
             WHERE order_id = OLD.id AND branch_id = OLD.branch_id;
            INSERT INTO orders_fuera_de_alcance (order_id, branch_id, motivo)
            VALUES (OLD.id, OLD.branch_id, 'movido');
        END IF;
        -- Y al ENTRAR en una sucursal se le quita la lápida que tuviera de antes allí. Un
        -- pedido que vuelve a Santiago se baja otra vez en `puestos`; si la lápida vieja
        -- siguiera puesta, la misma bajada diría «tenlo» y «bórralo», y cuál de las dos
        -- gana depende del orden en que el aparato las aplique.
        IF NEW.branch_id IS NOT NULL THEN
            DELETE FROM orders_fuera_de_alcance
             WHERE order_id = NEW.id AND branch_id = NEW.branch_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd

-- AFTER y no BEFORE: lo que se apunta es un hecho consumado. Si el DELETE se cae por una
-- clave ajena, no puede quedar una lápida de un pedido que sigue vivo.
--
-- `UPDATE OF branch_id` acota el disparo a los UPDATE que tocan esa columna; el resto de
-- los cambios del pedido —que son casi todos— no pagan nada por esto.
CREATE TRIGGER trg_orders_salida
    AFTER DELETE OR UPDATE OF branch_id ON orders
    FOR EACH ROW EXECUTE FUNCTION apuntar_salida_de_pedido();

-- +goose Down
DROP TRIGGER IF EXISTS trg_orders_salida ON orders;
DROP FUNCTION IF EXISTS apuntar_salida_de_pedido();
DROP TABLE IF EXISTS orders_fuera_de_alcance;
DROP TYPE IF EXISTS salida_de_pedido;
DROP INDEX IF EXISTS order_items_marca_idx;
DROP INDEX IF EXISTS orders_sucursal_marca_idx;
