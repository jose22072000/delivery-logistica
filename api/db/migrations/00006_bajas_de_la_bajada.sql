-- LAS LÁPIDAS DE LAS DEMÁS COLECCIONES. Postgres 16.
--
-- 00003 le dio lápidas a los pedidos y dejó el resto a medias: `Conjunto.Quitados`
-- (`internal/api/espejo.go`) se llenaba de verdad sólo para `orders`, y las otras siete
-- colecciones pasaban por el ayudante `conjunto()`, que devolvía `[]` SIEMPRE.
--
-- El agujero se vio con un teléfono delante el 17/09/2026: se borró una ruta desde la web
-- y el aparato la siguió enseñando —«Completada», 0 paradas, 2,6 km— porque nadie le dijo
-- nunca que ya no existía. Palabras de Jose: «¿por qué no actualiza a partir de lo que
-- tiene el servidor? Eso no puede pasar». Lo mismo con un camión dado de baja, una
-- sucursal quitada o una zona del tablero borrada desde la web.
--
-- POR QUÉ HACE FALTA UNA LÁPIDA Y NO BASTA CON MIRAR LA TABLA, otra vez y para todas:
--
--   * Lo BORRADO de verdad ya no tiene fila. No hay `updated_at` que comparar, no hay nada
--     que consultar, y el aparato se queda con ello para siempre: la lista local sólo
--     crece y nunca encoge.
--   * Lo que se MUEVE de sucursal sigue teniendo su fila, pero con OTRA sucursal, así que
--     deja de salir en cualquier consulta acotada a la vieja. El aparato de la sucursal
--     vieja tampoco se entera nunca.
--
-- QUÉ NO ESTÁ AQUÍ, Y POR QUÉ (la decisión escrita para no tener que volver a tomarla):
--
--   * `orders` tiene la suya desde 00003 (`orders_fuera_de_alcance`). No se mezcla con
--     ésta: la de pedidos ya está en producción, indexada y probada, y mover una tabla
--     viva para que dos consultas compartan nombre no arregla ningún fallo.
--   * `settings` NO LLEVA LÁPIDA y no es un olvido: es UNA fila global para toda la casa,
--     no hay ni una sentencia `DELETE FROM settings` en `db/queries/`, y la bajada ya sabe
--     contestar el caso de que no exista (`pgx.ErrNoRows` -> conjunto vacío). Una lápida
--     aquí sólo podría equivocarse.
--   * `warehouses` sigue declarado en `faltan` y no en `cambios`: vive en Accesos, que no
--     da marca de cambio ni dice qué borró. El motivo largo está en `espejo.go`, donde se
--     declara, y en `docs/integracion-pendiente.md`.
--   * `order_items` no es una colección suya: los renglones viajan DENTRO de su pedido, y
--     el aparato reemplaza la lista entera al aplicarlo.

-- +goose Up

-- Por qué se fue. Los dos NO son lo mismo para quien pregunta, exactamente como en 00003:
-- a quien ve las ocho sucursales, algo que se mudó de Santiago a Holguín no se le ha ido
-- de la vista —lo sigue viendo, en otra sucursal— y mandárselo en `quitados` le borraría
-- del aparato algo que existe. Borrado sí es borrado para todos.
CREATE TYPE motivo_de_baja AS ENUM ('borrado', 'movido');

-- Las colecciones que saben decir qué se fue, con el MISMO nombre con el que viajan en
-- `cambios` del protocolo (`docs/sincronizacion.md`). Que sea un enum y no texto libre es
-- lo que impide que una lápida nazca con «route» o «Routes» y no la lea nadie nunca: eso
-- no fallaría, que es lo peor. Los nombres van en inglés y en camelCase porque son las
-- claves del JSON, no nombres de tablas.
CREATE TYPE coleccion_de_la_bajada AS ENUM (
    'routes',
    'vehicles',
    'branches',
    'products',
    'customers',
    'boardColumns',
    'boardPlacements'
);

-- SIN CLAVE AJENA A NADA, A PROPÓSITO, por lo mismo que `orders_fuera_de_alcance`: todas
-- las filas de esta tabla son de cosas que ya no existen. Una clave ajena las borraría en
-- cascada, que es justo la constancia que hace falta guardar.
CREATE TABLE bajas_de_la_bajada (
    id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    coleccion coleccion_de_la_bajada NOT NULL,
    -- LA CLAVE CON LA QUE EL APARATO BORRA, tal y como viaja en `puestos`. Es texto y no
    -- uuid porque no todas las colecciones se identifican igual: una colocación del
    -- tablero se identifica por su PEDIDO (`pedidoId`), que es su clave primaria allí.
    clave     text NOT NULL,
    -- De qué sucursal se fue. Es la VIEJA —la que tenía antes de irse—, porque es a ese
    -- aparato al que hay que avisarle. NULL significa «de ninguna»: lo global (catálogo,
    -- padrón de clientes) y también un camión sin sucursal, que lo ven todos.
    branch_id uuid,
    motivo    motivo_de_baja NOT NULL,
    -- Marca de DOMINIO con su nombre, como el resto de la casa: «cuándo se fue», que no es
    -- «cuándo se tocó la fila». La bajada compara contra ésta.
    salio_at  timestamptz NOT NULL DEFAULT now()
);

-- El índice de la consulta de la bajada: la colección primero, que es lo que siempre se
-- fija, y la marca después, que es por donde se recorre y por donde se ordena.
CREATE INDEX bajas_coleccion_marca_idx ON bajas_de_la_bajada (coleccion, salio_at);
-- Y el que usan los disparadores para encontrar la lápida vieja y reemplazarla.
CREATE INDEX bajas_clave_idx ON bajas_de_la_bajada (coleccion, clave);

-- ---------------------------------------------------------------------------
-- El disparador, UNO PARA TODAS
-- ---------------------------------------------------------------------------
--
-- Es genérico a propósito: cinco funciones calcadas es cinco sitios donde arreglar el
-- mismo fallo, y el 17/09/2026 ya costó tres días que una condición estuviera en una
-- consulta y no en su gemela. La columna de la clave y la de la sucursal llegan como
-- argumentos del disparador y se leen con `to_jsonb(OLD)`, que es lo que permite que la
-- misma función sirva a `routes`, a `vehicles` y a `branches`.
--
-- LAS TRES COSAS QUE HACE, y las tres hacen falta:
--
--   DELETE  pone la lápida. Reemplaza la que hubiera en vez de añadir otra: lo que el
--           aparato necesita saber es «esto ya no es tuyo», y decírselo dos veces no
--           aporta nada y deja la tabla creciendo sin techo.
--   UPDATE  de la columna de sucursal: lápida `movido` para la sucursal VIEJA, y se quita
--           la que hubiera en la NUEVA.
--   INSERT  QUITA la lápida. Esto es lo que impide el único fallo de verdad grave de todo
--           este cambio: que la misma bajada diga «tenlo» en `puestos` y «bórralo» en
--           `quitados`, y que cuál de las dos gana dependa del orden en que el aparato las
--           aplique. Pasa de verdad —una tarjeta que sale de una zona del tablero y vuelve
--           esa misma tarde reusa su clave, que es el id del pedido— y por eso el INSERT
--           no es simetría de adorno.
--
-- EL INSERT SÓLO SE ENGANCHA DONDE UNA CLAVE PUEDE VOLVER, y eso son dos tablas:
-- `board_placements`, cuya clave es el pedido, y `board_columns`, porque `CrearColumna`
-- acepta el id que trae el aparato (`coalesce(narg('id'), gen_random_uuid())`). En
-- `routes`, `vehicles`, `branches`, `products` y `customers` el id sale siempre de
-- `gen_random_uuid()` en el servidor, así que un id borrado no vuelve nunca y el
-- disparador sería un `DELETE` por fila insertada a cambio de nada. En el padrón, que se
-- llena de ocho mil en ocho mil desde PEDIDO, «nada» se paga caro.
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION apuntar_baja_de_la_bajada() RETURNS trigger AS $$
DECLARE
    la_coleccion coleccion_de_la_bajada;
    campo_clave  text;
    -- Vacío = esta colección no tiene columna de sucursal (el catálogo, el padrón).
    -- Entonces la lápida nace con `branch_id` nulo.
    campo_branch text;
    clave_vieja  text;
    clave_nueva  text;
    branch_viejo uuid;
    branch_nuevo uuid;
BEGIN
    -- Los argumentos se leen AQUÍ y no como valor por defecto del DECLARE: así no hay que
    -- fiarse de en qué momento se evalúan los defaults de un bloque de disparador, que es
    -- justo la clase de detalle que no se puede comprobar sin un Postgres delante.
    la_coleccion := TG_ARGV[0]::coleccion_de_la_bajada;
    campo_clave  := TG_ARGV[1];
    campo_branch := coalesce(TG_ARGV[2], '');

    IF TG_OP <> 'INSERT' THEN
        clave_vieja := to_jsonb(OLD) ->> campo_clave;
        IF campo_branch <> '' THEN
            branch_viejo := (to_jsonb(OLD) ->> campo_branch)::uuid;
        END IF;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        clave_nueva := to_jsonb(NEW) ->> campo_clave;
        IF campo_branch <> '' THEN
            branch_nuevo := (to_jsonb(NEW) ->> campo_branch)::uuid;
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN
        DELETE FROM bajas_de_la_bajada
         WHERE coleccion = la_coleccion
           AND clave     = clave_vieja
           AND branch_id IS NOT DISTINCT FROM branch_viejo;
        INSERT INTO bajas_de_la_bajada (coleccion, clave, branch_id, motivo)
        VALUES (la_coleccion, clave_vieja, branch_viejo, 'borrado');
        RETURN OLD;
    END IF;

    IF TG_OP = 'INSERT' THEN
        -- Vuelve a existir: fuera la lápida, pase lo que pase. Se borran TODAS las de esa
        -- clave en esa colección y no sólo la de su sucursal, porque una lápida `movido`
        -- de la sucursal vieja de la que salió hace un mes seguiría diciéndole a aquel
        -- aparato que lo borre, y aquel aparato es el que lo acaba de recibir en `puestos`
        -- si ha vuelto.
        DELETE FROM bajas_de_la_bajada
         WHERE coleccion = la_coleccion AND clave = clave_nueva;
        RETURN NEW;
    END IF;

    -- UPDATE, y sólo llega aquí si tocó la columna de la sucursal (`UPDATE OF`).
    IF branch_viejo IS DISTINCT FROM branch_nuevo THEN
        -- La lápida se pone TAMBIÉN cuando la sucursal vieja era nula, y eso no es
        -- simetría: un camión sin sucursal lo ven los ocho aparatos (`ListarVehiculos`
        -- deja pasar `v.branch_id IS NULL`), así que al asignarlo a Holguín se les va de
        -- la vista a los otros siete. La lápida nula es la única forma de decírselo. Al de
        -- Holguín no le borra nada porque quien contesta la bajada tacha de `quitados`
        -- todo lo que está vivo en su lista — ver `quitadosDe` en `espejo.go`.
        DELETE FROM bajas_de_la_bajada
         WHERE coleccion = la_coleccion
           AND clave     = clave_vieja
           AND branch_id IS NOT DISTINCT FROM branch_viejo;
        INSERT INTO bajas_de_la_bajada (coleccion, clave, branch_id, motivo)
        VALUES (la_coleccion, clave_vieja, branch_viejo, 'movido');

        IF branch_nuevo IS NOT NULL THEN
            DELETE FROM bajas_de_la_bajada
             WHERE coleccion = la_coleccion AND clave = clave_nueva AND branch_id = branch_nuevo;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd

-- Las colocaciones del tablero van aparte y no por la función genérica: su sucursal NO ES
-- UNA COLUMNA SUYA —la tiene la zona en la que están— y hay que ir a buscarla. Y su clave
-- es el PEDIDO, que es su clave primaria (`board_placements.order_id`) y lo que el aparato
-- usa para borrar.
--
-- La zona todavía existe cuando esto corre: `column_id` es `ON DELETE RESTRICT`, así que
-- no se puede borrar una zona con tarjetas dentro. Si aun así no apareciera, la lápida
-- nace con sucursal nula y se la lleva quien la tenga; es preferible a no ponerla.
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION apuntar_baja_de_colocacion() RETURNS trigger AS $$
DECLARE
    sucursal uuid;
BEGIN
    IF TG_OP = 'DELETE' THEN
        SELECT c.branch_id INTO sucursal FROM board_columns c WHERE c.id = OLD.column_id;
        DELETE FROM bajas_de_la_bajada
         WHERE coleccion = 'boardPlacements' AND clave = OLD.order_id::text;
        INSERT INTO bajas_de_la_bajada (coleccion, clave, branch_id, motivo)
        VALUES ('boardPlacements', OLD.order_id::text, sucursal, 'borrado');
        RETURN OLD;
    END IF;
    -- INSERT: la tarjeta vuelve al tablero. Fuera la lápida, o la misma bajada diría
    -- «tenla» y «bórrala». Esto pasa CADA TARDE: una tarjeta que sale de una zona y vuelve
    -- a otra reusa su clave, porque la clave es el pedido.
    DELETE FROM bajas_de_la_bajada
     WHERE coleccion = 'boardPlacements' AND clave = NEW.order_id::text;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd

-- AFTER y no BEFORE, como en 00003: lo que se apunta es un hecho consumado. Si el DELETE
-- se cae por una clave ajena no puede quedar una lápida de algo que sigue vivo.
--
-- `UPDATE OF branch_id` acota el disparo a los UPDATE que tocan esa columna; el resto de
-- los cambios —que son casi todos— no pagan nada por esto.

CREATE TRIGGER trg_routes_baja
    AFTER DELETE OR UPDATE OF branch_id ON routes
    FOR EACH ROW EXECUTE FUNCTION apuntar_baja_de_la_bajada('routes', 'id', 'branch_id');

CREATE TRIGGER trg_vehicles_baja
    AFTER DELETE OR UPDATE OF branch_id ON vehicles
    FOR EACH ROW EXECUTE FUNCTION apuntar_baja_de_la_bajada('vehicles', 'id', 'branch_id');

-- La sucursal es su propia sucursal: quien la ve es el aparato acotado a ella y quien ve
-- las ocho. No hay «mudarse» para una sucursal, así que sólo DELETE.
CREATE TRIGGER trg_branches_baja
    AFTER DELETE ON branches
    FOR EACH ROW EXECUTE FUNCTION apuntar_baja_de_la_bajada('branches', 'id', 'id');

-- El catálogo y el padrón se acotan por `sucursal_codigo` —el CÓDIGO (STG, HOL), no el
-- uuid— y sus lápidas NO lo llevan. Es una decisión, no un descuido, y está escrita entera
-- en `espejo.go`, donde se sirven. El resumen: una lápida sólo nace de un `DELETE` de
-- verdad, esa fila ya no existe para nadie, y mandársela a un aparato que no la tenía es
-- una orden que no encuentra nada. Cuesta unos ids y no cuesta un dato.
--
-- Lo que esto NO tapa: un producto o un cliente al que le CAMBIAN el `sucursal_codigo` sale
-- del alcance sin borrarse y se queda puesto en el aparato de la sucursal vieja. Taparlo
-- pide una columna `sucursal_codigo` aquí y un disparador de `UPDATE OF sucursal_codigo`.
--
-- El padrón es el que más lo necesita: `BorrarClientesDelEspejoQueYaNoVienen` borra de
-- golpe todos los que PEDIDO dejó de mandar, y sin lápida esos clientes se quedan en el
-- teléfono del repartidor hasta que alguien reinstale la aplicación.
CREATE TRIGGER trg_products_baja
    AFTER DELETE ON products
    FOR EACH ROW EXECUTE FUNCTION apuntar_baja_de_la_bajada('products', 'id');

CREATE TRIGGER trg_customers_baja
    AFTER DELETE ON customers
    FOR EACH ROW EXECUTE FUNCTION apuntar_baja_de_la_bajada('customers', 'id');

-- `board_columns.branch_id` es NOT NULL y no se mueve de sucursal: una zona es de su
-- tablero. Va DELETE y va INSERT, y el INSERT aquí SÍ hace falta: `CrearColumna` acepta el
-- id que trae el aparato (un UUIDv7 suyo) y devuelve la que ya estaba si se sube dos veces,
-- así que una zona borrada puede volver con su mismo id.
CREATE TRIGGER trg_board_columns_baja
    AFTER INSERT OR DELETE ON board_columns
    FOR EACH ROW EXECUTE FUNCTION apuntar_baja_de_la_bajada('boardColumns', 'id', 'branch_id');

CREATE TRIGGER trg_board_placements_baja
    AFTER INSERT OR DELETE ON board_placements
    FOR EACH ROW EXECUTE FUNCTION apuntar_baja_de_colocacion();

-- +goose Down
DROP TRIGGER IF EXISTS trg_board_placements_baja ON board_placements;
DROP TRIGGER IF EXISTS trg_board_columns_baja ON board_columns;
DROP TRIGGER IF EXISTS trg_customers_baja ON customers;
DROP TRIGGER IF EXISTS trg_products_baja ON products;
DROP TRIGGER IF EXISTS trg_branches_baja ON branches;
DROP TRIGGER IF EXISTS trg_vehicles_baja ON vehicles;
DROP TRIGGER IF EXISTS trg_routes_baja ON routes;
DROP FUNCTION IF EXISTS apuntar_baja_de_colocacion();
DROP FUNCTION IF EXISTS apuntar_baja_de_la_bajada();
DROP TABLE IF EXISTS bajas_de_la_bajada;
DROP TYPE IF EXISTS coleccion_de_la_bajada;
DROP TYPE IF EXISTS motivo_de_baja;
