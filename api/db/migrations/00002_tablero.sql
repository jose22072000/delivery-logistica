-- El TABLERO DE PREPARACIÓN. Postgres 16.
--
-- La pantalla que delivery no tiene y que se pidió el 14/09/2026. Está especificada en
-- ../../docs/tablero.md; aquí sólo van las dos tablas y el porqué de cada decisión.
--
-- QUÉ ES, EN UNA LÍNEA: el logístico reparte por distrito, así que va poniendo los pedidos
-- del día en columnas —una por zona— y de cada columna sale una ruta.
--
-- Y LAS COLUMNAS SON SUYAS, no del sistema. Cada sucursal divide su territorio a su
-- manera: Santiago por distritos, otra por carreteras, otra por barrios. Un catálogo fijo
-- de zonas sería inventarse una geografía que sólo sirve en un sitio, y la primera vez que
-- no encajara el logístico volvería al papel. Por eso `board_columns` es una tabla y no un
-- enum, y por eso lleva `branch_id`: el tablero de Holguín no se parece al de Santiago.
--
-- Convenciones: las de 00001_init.sql. Identificadores uuid, `created_at`/`updated_at` en
-- todas con su trigger, y las marcas de dominio aparte y con su nombre.

-- +goose Up

-- ---------------------------------------------------------------------------
-- La distancia, una sola vez y en la base
-- ---------------------------------------------------------------------------

-- LA CERCANÍA AL ALMACÉN SE MIDE AQUÍ PORQUE ES UN ORDEN, NO UN CÁLCULO.
--
-- Los pedidos sin colocar tienen que salir con el más cercano al almacén primero. Eso es
-- un ORDER BY sobre miles de filas: traerlas todas a Go para ordenarlas y quedarse con las
-- primeras doscientas es bajar el municipio entero por la conexión de allá para tirar el
-- 95%. Ordenar es trabajo de la base.
--
-- La fórmula es la MISMA de `pricing.haversineDistance` y `domicilioEntrega`: haversine
-- con R = 6371 km, línea recta. No es la distancia que recorre el camión y no pretende
-- serlo — es con la que se cobra el domicilio y con la que se arma la ruta desde el primer
-- día, y tener dos medidas distintas de «cuán lejos está este cliente» es peor que tener
-- una aproximada. Una sola copia de la fórmula, y está aquí.
--
-- IMMUTABLE y PARALLEL SAFE a propósito: sin eso Postgres no puede usarla dentro de un
-- índice ni repartir el orden entre varios procesos, que es justo lo que hace falta.
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION km_haversine(
    lat1 double precision, lng1 double precision,
    lat2 double precision, lng2 double precision
) RETURNS double precision AS $$
    SELECT 2 * 6371 * asin(sqrt(
        power(sin(radians($3 - $1) / 2), 2)
        + cos(radians($1)) * cos(radians($3)) * power(sin(radians($4 - $2) / 2), 2)
    ));
$$ LANGUAGE sql IMMUTABLE PARALLEL SAFE;
-- +goose StatementEnd

-- ---------------------------------------------------------------------------
-- Las columnas del tablero
-- ---------------------------------------------------------------------------

CREATE TABLE board_columns (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    -- NOT NULL, y es la única diferencia con `routes` y `orders`, donde la sucursal puede
    -- faltar. Aquí no puede: una columna sin sucursal aparecería en el tablero de las diez
    -- y diez personas colocarían pedidos en la misma «Centro» sin verse entre ellas.
    branch_id  uuid NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
    nombre     text NOT NULL,
    -- De izquierda a derecha. Se guarda porque el orden es información: el logístico pone
    -- primero las zonas que salen temprano, y ese orden es su manera de recordar el día.
    posicion   integer NOT NULL,
    -- El camión PREVISTO para esta zona. Sirve para una sola cosa: saber si lo que hay
    -- puesto en la columna cabe. La capacidad NO se copia aquí —se lee del vehículo— para
    -- que cambiarle la capacidad al camión no deje el aviso del tablero mintiendo.
    -- Vacío es lo normal: a media mañana todavía no se sabe qué camión va a cada zona.
    vehicle_id uuid REFERENCES vehicles(id) ON DELETE SET NULL,
    -- Quién la creó, por su id en auth. Constancia, no clave ajena ni filtro.
    creado_por text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_board_columns_updated BEFORE UPDATE ON board_columns
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- DEFERRABLE, y no es un adorno.
--
-- Reordenar columnas es un baile: la tercera pasa a primera y las otras se corren. En
-- medio de ese baile hay dos con la misma posición durante un instante. Con una única
-- normal, Postgres comprueba fila por fila y revienta a mitad del `UPDATE`; la salida
-- sería escribir posiciones absurdas (−1, 1000) para hacer sitio, que es exactamente el
-- truco que deja huecos raros cuando algo falla por el medio. Diferida, la comprobación
-- se hace al cerrar la transacción, cuando el baile ya terminó.
ALTER TABLE board_columns
    ADD CONSTRAINT board_columns_posicion_unica UNIQUE (branch_id, posicion)
    DEFERRABLE INITIALLY DEFERRED;

-- Dos columnas «Vista Alegre» en el mismo tablero es colocar la mitad de los pedidos en la
-- equivocada y no enterarse hasta que salen dos camiones al mismo barrio. Sin distinguir
-- mayúsculas porque «centro» y «Centro» son la misma zona para quien las escribe.
CREATE UNIQUE INDEX board_columns_nombre_idx ON board_columns (branch_id, lower(nombre));
CREATE INDEX board_columns_branch_idx ON board_columns (branch_id, posicion);

-- ---------------------------------------------------------------------------
-- Dónde está colocado cada pedido
-- ---------------------------------------------------------------------------

-- SIN ID PROPIO, Y A PROPÓSITO: la clave es el pedido.
--
-- La fila no es «una colocación», es «dónde está este pedido». Con un `id` de la casa
-- podrían existir dos filas del mismo pedido en dos columnas, y entonces el tablero
-- enseñaría la misma parada dos veces y la ruta la cargaría dos veces. La regla «un
-- pedido, un sitio» la sostiene la clave primaria y no un `findFirst` de nadie.
CREATE TABLE board_placements (
    order_id     uuid PRIMARY KEY REFERENCES orders(id) ON DELETE CASCADE,
    -- RESTRICT y NO cascade. Borrar una columna con pedidos dentro tiene que doler.
    --
    -- Con CASCADE, las tarjetas vuelven a «sin colocar» sin decir nada, y quien borró
    -- «Centro» creyendo que estaba vacía se entera al día siguiente, cuando a la ruta le
    -- faltan ocho paradas. Con RESTRICT la base se niega, y el contrato obliga a decir
    -- qué se hace con lo de dentro: se vacía a mano o se manda a otra columna. Deshacer
    -- trabajo en silencio es la única cosa que este tablero no puede hacer.
    column_id    uuid NOT NULL REFERENCES board_columns(id) ON DELETE RESTRICT,
    -- El orden DENTRO de la columna: es el orden de visita que propone el logístico, el
    -- que conoce las calles. El armador lo respeta o lo reoptimiza, pero para eso tiene
    -- que estar guardado.
    posicion     integer NOT NULL,
    -- Quién la colocó y cuándo. `colocado_at` es marca de DOMINIO y no vale `created_at`:
    -- mover una tarjeta de columna no crea la fila, la actualiza, y `created_at` se
    -- quedaría con la hora de la primera vez que se tocó ese pedido.
    colocado_por text,
    colocado_at  timestamptz NOT NULL DEFAULT now(),
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_board_placements_updated BEFORE UPDATE ON board_placements
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Diferida por lo mismo que la de las columnas: meter una tarjeta en el medio corre a
-- todas las de abajo en un solo `UPDATE`, y a mitad de ese `UPDATE` hay dos iguales.
ALTER TABLE board_placements
    ADD CONSTRAINT board_placements_posicion_unica UNIQUE (column_id, posicion)
    DEFERRABLE INITIALLY DEFERRED;

CREATE INDEX board_placements_column_idx ON board_placements (column_id, posicion);

-- NO HAY CLAVE AJENA A `branches` AQUÍ, y hace falta explicarlo: la sucursal de la
-- colocación es la de su columna, y la del pedido tiene que ser la misma. Eso no lo puede
-- decir una clave ajena —son dos tablas distintas— y por eso lo comprueba el `INSERT` de
-- `ColocarPedido`, que sólo escribe si `orders.branch_id = board_columns.branch_id`.
-- Guardar aquí una tercera copia de la sucursal sería el sitio perfecto para que las tres
-- dejaran de coincidir.

-- +goose Down
DROP TABLE IF EXISTS board_placements, board_columns CASCADE;
DROP FUNCTION IF EXISTS km_haversine(double precision, double precision, double precision, double precision);
