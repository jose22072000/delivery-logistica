-- Esquema inicial del reparto. Postgres 16.
--
-- Sale de `delivery` (Prisma), documentado en ../../docs/modelo-datos.md, con dos cambios
-- deliberados que allí faltaban. Van explicados donde tocan:
--
--   0. NADA de JSON. Lo que venía en `meta`, `items`, `currencies` y `tiposVehiculo` son
--      datos, y los datos van en columnas y en tablas. Lo que haga falta de PEDIDO se
--      extrae en el espejo, que para eso está: guardar el documento entero «por si acaso»
--      es tener el mismo dato en dos sitios y no saber cuál manda.
--   1. `updated_at` en TODAS las tablas, no en cinco, y mantenido por un trigger.
--   2. `vehicle_types` como TABLA. En delivery el catálogo se guardaba en un campo de
--      `Settings` que nunca llegó a existir en el esquema: la pantalla escribía tipos
--      nuevos y se perdían en silencio.
--
-- Convenciones:
--   * identificadores uuid; los ids de sistemas ajenos (PEDIDO, Ventra) son `text` y se
--     quedan como vienen — no son nuestros y no tienen por qué ser uuid.
--   * `created_at` / `updated_at` en todas. Las marcas de DOMINIO van aparte y con su
--     nombre: `traido_at`, `synced_at`, `pedido_updated_at`. Significan «cuándo lo trajo
--     el origen», que no es «cuándo se tocó la fila», y confundirlas rompe el espejo.
--   * los conjuntos cerrados son enums de verdad; lo abierto se queda en text y se valida
--     contra su catálogo.

-- +goose Up

-- +goose StatementBegin
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- +goose StatementEnd

-- ---------------------------------------------------------------------------
-- Conjuntos cerrados
--
-- Los valores salen de buscar los literales que el código de delivery escribe de verdad,
-- no de lo que el esquema declaraba: Prisma los tenía todos como String.
-- ---------------------------------------------------------------------------

-- Estado de reparto del pedido. Lo que la pantalla enseña NO sale de aquí: se deriva de
-- `resultado`, `delivered_at` y el estado de la ruta.
CREATE TYPE order_status AS ENUM ('pending', 'delivered');

-- Cómo acabó la parada cuando el camión vuelve. Ni `devuelto` ni `cancelado` tocan
-- inventario: el reintegro lo hace Ventra, aquí queda la constancia.
CREATE TYPE stop_result AS ENUM ('entregado', 'devuelto', 'cancelado');

-- `cancelled` se reserva: el tablero ya lo excluye en sus consultas aunque hoy nadie lo
-- escriba. Dejarlo fuera obligaría a un ALTER TYPE el día que se use.
CREATE TYPE route_status AS ENUM ('planned', 'in_progress', 'completed', 'cancelled');

-- No existe `maintenance` en el código. Se ocupa al despachar la ruta y se libera al
-- cerrarla o al borrarla.
CREATE TYPE vehicle_status AS ENUM ('available', 'in_use');

-- El tramo. Hoy sólo se escribe `outbound`; `return` se lee para pintar el mapa.
CREATE TYPE trip_leg AS ENUM ('outbound', 'return');

-- El estado EN PEDIDO, copiado. Quien manda sobre él es PEDIDO; aquí sólo se filtra.
-- `expirada` NO está: es derivado —la fecha comprometida ya pasó y no se completó— y
-- guardarlo lo dejaría viejo al día siguiente.
CREATE TYPE pedido_estado AS ENUM ('completada', 'en_proceso');

-- Cómo quedó el pedido frente a la factura de Ventra. Copiado de PEDIDO.
-- NULL = no cotejado (no hay facturación traída de ese día), que no es lo mismo que
-- `sin_factura`.
CREATE TYPE factura_estado AS ENUM ('igual', 'cambiado', 'sin_factura');

-- De dónde vino. NULL = alta manual en el reparto.
CREATE TYPE procedencia AS ENUM ('pedido');

-- ---------------------------------------------------------------------------
-- Personas y sucursales
-- ---------------------------------------------------------------------------

CREATE TABLE branches (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name              text NOT NULL,
    address           text,
    lat               double precision NOT NULL,
    lng               double precision NOT NULL,
    area_km2          double precision NOT NULL DEFAULT 1,
    -- La sucursal equivalente en PEDIDO. Permite que PEDIDO cotice mandando sólo su id.
    external_id       text UNIQUE,
    -- Mientras sea false, el cálculo de domicilios NO corre para esta sucursal: el punto
    -- de partida real (el almacén) todavía no está fijado.
    origin_configured boolean NOT NULL DEFAULT false,
    -- Quién la dio de alta, por su id en auth. Constancia, no clave ajena.
    creado_por        text,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_branches_updated BEFORE UPDATE ON branches
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- No hay tabla de personas, y es a propósito.
--
-- Quien manda en personas, roles y sucursales es auth. Delivery tenía un modelo `User`
-- que era un resto de cuando tuvo login propio, y el código lo delata: `products/sync`
-- tenía que INVENTARSE un dueño (`findFirst where branchId null`) para poder escribir una
-- fila, y hay un comentario diciendo que filtrar por `userId` devolvía 404 sobre vehículos
-- que existen de verdad. Su propio `scope.ts` ya lo dice: «aquí nada pertenece a una
-- persona: los pedidos entran solos desde PEDIDO y son de la sucursal que los originó».
--
-- Donde hace falta dejar constancia de quién hizo algo va `creado_por`: el id de esa
-- persona EN AUTH, como texto y sin clave ajena. Es constancia, no una copia de la lista
-- de personas que habría que mantener al día.

CREATE TABLE saved_origins (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name       text NOT NULL,
    address    text NOT NULL,
    lat        double precision NOT NULL,
    lng        double precision NOT NULL,
    creado_por text,
    branch_id  uuid REFERENCES branches(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_saved_origins_updated BEFORE UPDATE ON saved_origins
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- La flota
-- ---------------------------------------------------------------------------

-- EL CATÁLOGO DE TIPOS DE VEHÍCULO — la tabla que faltaba.
--
-- En delivery esto se guardaba en `Settings.tiposVehiculo`, un campo que **nunca existió
-- en el esquema**: la pantalla de vehículos dejaba crear tipos nuevos, los mandaba a
-- guardar y se perdían sin un solo error. Por eso `Vehicle.type` era un conjunto abierto
-- que nadie podía cerrar: su catálogo no estaba en ninguna parte.
--
-- El costo por km es del TIPO y sirve de valor por defecto; cada vehículo puede tener el
-- suyo, porque quien lo da es el camionero y dos camiones del mismo tipo no cuestan igual.
CREATE TABLE vehicle_types (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre       text NOT NULL UNIQUE,
    costo_km_usd double precision,
    -- Para poder retirar un tipo sin romper los vehículos que ya lo usan.
    activo       boolean NOT NULL DEFAULT true,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_vehicle_types_updated BEFORE UPDATE ON vehicle_types
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Los cuatro que la pantalla de delivery ofrecía, MÁS lo que hay de verdad en producción.
--
-- Comprobado el 14/09/2026 contra el volcado real: de los 12 vehículos, uno tiene el tipo
-- `Camion` — escrito a mano, en español y con mayúscula. No está en ninguna lista de la
-- aplicación, y es la prueba de que este catálogo era abierto de hecho aunque la pantalla
-- ofreciera cuatro opciones: alguien lo escribió y la base lo aceptó.
--
-- Va aquí para que la migración de los datos no se caiga. Si al final resulta que es un
-- duplicado de `truck`, se unifica desde la pantalla y se retira con `activo = false` —
-- para eso está esa columna. Lo que no se puede es que un dato real no tenga dónde entrar.
--
-- El costo por km se deja vacío a propósito: lo pone el camionero, y ponerle un número
-- inventado es peor que no tenerlo, porque se cobra igual y nadie lo revisa.
INSERT INTO vehicle_types (nombre) VALUES ('truck'), ('van'), ('motorcycle'), ('car'), ('Camion');

CREATE TABLE vehicles (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name                text NOT NULL,
    vehicle_type_id     uuid NOT NULL REFERENCES vehicle_types(id),
    plate               text,
    capacity            double precision NOT NULL DEFAULT 1000,
    -- Costo de rodar ESTE camión, en USD por km. Con la capacidad define el CKK de la
    -- fórmula del domicilio. Si está vacío se usa el del tipo.
    costo_km_usd        double precision,
    -- El vehículo de REFERENCIA de su sucursal para calcular el domicilio.
    usar_para_domicilio boolean NOT NULL DEFAULT false,
    status              vehicle_status NOT NULL DEFAULT 'available',
    notes               text,
    -- Sucursal dueña. NULL = de todas.
    branch_id           uuid REFERENCES branches(id),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_vehicles_updated BEFORE UPDATE ON vehicles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Sólo uno por sucursal puede ser el de referencia. En delivery esto era un comentario
-- que pedía que «sólo uno debería tenerla en true»; aquí lo impide la base.
CREATE UNIQUE INDEX vehicles_una_referencia_por_sucursal
    ON vehicles (branch_id) WHERE usar_para_domicilio;

-- ---------------------------------------------------------------------------
-- Catálogo y clientes — espejos de Ventra vía PEDIDO
-- ---------------------------------------------------------------------------

-- Se llena solo: PEDIDO sondea Ventra y aquí se copia lo que él ya tiene. No hay alta
-- manual — dos catálogos escritos por separado discrepan sin que nadie lo vea.
--
-- Con sucursal, no sin ella: en Ventra el precio y las existencias varían por sucursal,
-- así que un catálogo único ofrece en Camagüey un producto que sólo hay en La Habana, y
-- al precio de La Habana.
CREATE TABLE products (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name              text NOT NULL,
    weight            double precision NOT NULL DEFAULT 0,
    packaging         text,
    units_per_package double precision,
    category          text,
    -- El código de Ventra. Es por lo que se reconoce una fila entre pasadas.
    sku               text,
    sucursal_codigo   text,
    price             double precision,
    stock             double precision,
    unit              text,
    -- Cuándo lo trajo Ventra. Dice si lo que se mira es de hace diez minutos o de hace
    -- tres días porque la VPN lleva caída desde el lunes.
    traido_at         timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    UNIQUE (sucursal_codigo, sku)
);
CREATE INDEX products_sucursal_idx ON products (sucursal_codigo);
CREATE INDEX products_name_idx     ON products (name);
CREATE TRIGGER trg_products_updated BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Sólo los GEOLOCALIZADOS: sin coordenadas no se cotiza.
CREATE TABLE customers (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    source          procedencia,
    -- El id del cliente EN PEDIDO. Con `source` da la idempotencia: re-sincronizar no
    -- duplica.
    external_id     text,
    name            text NOT NULL,
    phone           text,
    address         text,
    municipio       text,
    zona            text,
    -- El código del cliente en PEDIDO (SC06TCP1257). Es como lo nombra la gente.
    codigo          text,
    -- El vendedor que lo atiende. Sacado de `meta` a su propia columna: dentro del JSON,
    -- filtrar por él obligaba a leer y descartar los siete mil clientes.
    vendedor        text,
    lat             double precision NOT NULL,
    lng             double precision NOT NULL,
    sucursal_codigo text,
    synced_at       timestamptz NOT NULL DEFAULT now(),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);
-- ÚNICO, no un índice normal: es la idempotencia del espejo.
--
-- Siendo normal, dos pasadas del espejo a la vez leen «no existe» antes de que ninguna
-- escriba y crean el cliente dos veces. Parcial porque el alta manual no tiene origen ni
-- id externo, y de esos puede haber los que sean.
CREATE UNIQUE INDEX customers_origen_idx ON customers (source, external_id)
    WHERE source IS NOT NULL AND external_id IS NOT NULL;
CREATE INDEX customers_vendedor_idx ON customers (vendedor);
CREATE INDEX customers_codigo_idx   ON customers (codigo);
CREATE TRIGGER trg_customers_updated BEFORE UPDATE ON customers
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- Pedidos
-- ---------------------------------------------------------------------------

CREATE TABLE orders (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    operation_number     text,
    customer_name        text NOT NULL,
    address              text NOT NULL,
    end_address          text,
    end_lat              double precision,
    end_lng              double precision,
    lat                  double precision,
    lng                  double precision,
    weight               double precision NOT NULL DEFAULT 1,
    status               order_status NOT NULL DEFAULT 'pending',
    trip_leg             trip_leg NOT NULL DEFAULT 'outbound',
    notes                text,

    -- La ruta que lo lleva AHORA. Un pedido con esto puesto está ocupado y no se puede
    -- meter en otra. Un devuelto lo pierde al cerrar la ruta: volvió al almacén.
    route_id             uuid,
    -- En qué ruta VIAJÓ. Esto no se libera nunca.
    --
    -- Son dos preguntas distintas —«¿está ocupado?» y «¿en qué camión fue?»— y con un
    -- solo campo no se pueden responder las dos: soltar al devuelto para poder repartirlo
    -- otra vez lo borraba de la hoja de lo que bajó del camión.
    ultima_ruta_id       uuid,

    vehicle_id           uuid REFERENCES vehicles(id),

    price                double precision,
    segment_km           double precision,
    -- El envío a domicilio INDIVIDUAL (viaje dedicado sucursal → cliente). Es otro número
    -- que `price`, que es el reparto de carga de una ruta. Confundirlos es cobrar uno por
    -- el otro.
    delivery_price       double precision,
    delivery_distance_km double precision,
    branch_id            uuid REFERENCES branches(id),

    source               procedencia,
    -- El id/folio del pedido EN PEDIDO. Con `source` da la idempotencia.
    external_id          text,

    -- La FECHA DEL PEDIDO en PEDIDO, que NO es `created_at`: eso es cuándo lo copió el
    -- espejo, y el espejo copia muchos días de golpe. El armador filtra por día, así que
    -- sin esto cualquier día que no fuera hoy devolvía cero pedidos aunque los hubiera.
    order_date           timestamptz,
    -- Cuándo se tocó por última vez EN PEDIDO: la marca de agua del espejo, que pide
    -- `since = max(pedido_updated_at)`. Se deriva de los datos y no de un contador aparte
    -- a propósito: un contador se adelanta si una tanda falla a medias y entonces el
    -- espejo se salta pedidos para siempre sin dar ningún error.
    pedido_updated_at    timestamptz,

    estado               pedido_estado,
    -- Archivado en PEDIDO (borrado blando). Son la inmensa mayoría del histórico.
    archivado            boolean NOT NULL DEFAULT false,
    -- Cuándo se comprometió la entrega. `expirado` no se guarda: es que esta fecha ya
    -- pasó y no se completó, y un booleano guardado se queda viejo al día siguiente.
    fecha_comprometida   timestamptz,

    requiere_domicilio   boolean,
    -- El costo que le puso la APK de Entrega EN PEDIDO. No es `delivery_price`.
    pedido_costo         double precision,

    municipio            text,
    vendedor             text,
    sucursal_codigo      text,

    -- Cómo quedó frente a la FACTURA de Ventra. El cotejo lo hace PEDIDO; aquí sólo se
    -- guarda para filtrar. NULL = no cotejado, que no es `sin_factura`.
    factura_estado       factura_estado,
    factura_numero       text,
    factura_at           timestamptz,
    -- Lo que la factura cobró por el reparto. Es la señal más fiable de que va a
    -- domicilio: sale del mostrador y no de una casilla marcada al tomar el pedido.
    factura_domicilio    double precision,
    -- Cuándo PEDIDO lo reescribió con lo que decía la factura. Cuadra igual y se reparte
    -- igual, pero quien carga el camión tiene que poder verlo.
    factura_corregido_at timestamptz,

    customer_phone       text,

    stop_order           integer,
    delivered_at         timestamptz,
    -- CÓMO ACABÓ la parada cuando el camión vuelve. De aquí sale el post-despacho: lo que
    -- queda en el camión es lo que NO está entregado.
    resultado            stop_result,
    resultado_at         timestamptz,
    -- Por qué volvió. Un devuelto sin motivo es un número que nadie sabe explicar tres
    -- semanas después.
    resultado_nota       text,

    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now()
);

-- Los índices son de los filtros que la pantalla ofrece de verdad. Uno por columna y no
-- uno compuesto: se combinan de todas las formas y Postgres los cruza por su cuenta.
-- ÚNICO, no un índice normal: es la idempotencia del espejo. Sin esto, dos pasadas
-- simultáneas crean el mismo pedido dos veces y sale DOS VECES en el armador de rutas.
-- Parcial porque el alta manual no tiene origen ni id externo.
CREATE UNIQUE INDEX orders_origen_idx ON orders (source, external_id)
    WHERE source IS NOT NULL AND external_id IS NOT NULL;
CREATE INDEX orders_fecha_idx       ON orders (order_date);
CREATE INDEX orders_marca_agua_idx  ON orders (pedido_updated_at);
CREATE INDEX orders_estado_idx      ON orders (estado);
CREATE INDEX orders_archivado_idx   ON orders (archivado);
CREATE INDEX orders_municipio_idx   ON orders (municipio);
CREATE INDEX orders_vendedor_idx    ON orders (vendedor);
CREATE INDEX orders_domicilio_idx   ON orders (requiere_domicilio);
CREATE INDEX orders_resultado_idx   ON orders (resultado);
CREATE INDEX orders_ultima_ruta_idx ON orders (ultima_ruta_id);
CREATE INDEX orders_ruta_idx        ON orders (route_id);
CREATE TRIGGER trg_orders_updated BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- LOS RENGLONES DEL PEDIDO — la segunda tabla que faltaba.
--
-- En delivery esto era `Order.items`, un JSON. Y por eso existía `productosTexto`: una
-- copia de los nombres en texto plano, metida a mano, para poder responder a «¿qué
-- pedidos llevan malta?» — porque dentro de un JSON no se busca sin leerse los cincuenta
-- mil pedidos enteros.
--
-- Con los renglones en su tabla, esa copia sobra: se pregunta por el nombre y ya está.
-- Un dato copiado en dos sitios acaba discrepando, y este además se copiaba a mano.
CREATE TABLE order_items (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id    uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    -- El orden en que venían en el pedido. Hace falta para que la hoja del despacho salga
    -- igual que el papel del vendedor.
    linea       integer NOT NULL,
    description text NOT NULL,
    quantity    double precision NOT NULL,
    -- Los bultos, cuando la factura los distingue de las unidades.
    packs       double precision,
    -- El producto del catálogo con el que casó, si casó. Vacío no es un error: hay
    -- renglones escritos a mano que no están en Ventra.
    product_id  uuid REFERENCES products(id),
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (order_id, linea)
);
CREATE INDEX order_items_order_idx   ON order_items (order_id);
CREATE INDEX order_items_product_idx ON order_items (product_id);
-- Buscar «malta» sin leerse la tabla entera. Es lo que `productosTexto` hacía a mano.
CREATE INDEX order_items_desc_idx    ON order_items USING gin (to_tsvector('spanish', description));
CREATE TRIGGER trg_order_items_updated BEFORE UPDATE ON order_items
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- Rutas
-- ---------------------------------------------------------------------------

CREATE TABLE routes (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name           text,
    route_code     text,
    status         route_status NOT NULL DEFAULT 'planned',
    origin_address text,
    origin_lat     double precision,
    origin_lng     double precision,
    total_distance double precision NOT NULL DEFAULT 0,
    total_weight   double precision NOT NULL DEFAULT 0,
    total_price    double precision NOT NULL DEFAULT 0,
    delivery_date  timestamptz,
    vehicle_id     uuid REFERENCES vehicles(id),
    creado_por     text,
    branch_id      uuid REFERENCES branches(id),
    -- Cuándo salió y cuándo volvió: con las dos se sabe cuánto se demoró. No se deduce de
    -- `created_at` —la ruta se arma la noche anterior— ni de `updated_at`, que se mueve
    -- al tocar cualquier cosa.
    started_at     timestamptz,
    finished_at    timestamptz,
    optimized      boolean NOT NULL DEFAULT false,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX routes_branch_idx ON routes (branch_id);
CREATE INDEX routes_status_idx ON routes (status);
CREATE TRIGGER trg_routes_updated BEFORE UPDATE ON routes
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE orders
    ADD CONSTRAINT orders_route_fk       FOREIGN KEY (route_id)       REFERENCES routes(id) ON DELETE SET NULL,
    ADD CONSTRAINT orders_ultima_ruta_fk FOREIGN KEY (ultima_ruta_id) REFERENCES routes(id) ON DELETE SET NULL;

CREATE TABLE order_vehicles (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id   uuid NOT NULL REFERENCES orders(id)   ON DELETE CASCADE,
    vehicle_id uuid NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
    is_primary boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (order_id, vehicle_id)
);
CREATE TRIGGER trg_order_vehicles_updated BEFORE UPDATE ON order_vehicles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- Facturación traída de Ventra
-- ---------------------------------------------------------------------------

-- El cotejo contra la facturación lo hace PEDIDO —el pedido es suyo y es allí donde se
-- corrige cuando la factura dice otra cosa—. Aquí no se escribe: el resultado llega por
-- el espejo, en `orders.factura_estado`.
CREATE TABLE ventas_facturadas (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    -- El id de la línea en Ventra. Por él se reconoce entre pasadas.
    ventra_id       text NOT NULL UNIQUE,
    sucursal_codigo text NOT NULL,
    fecha           timestamptz NOT NULL,
    -- El número de operación: es LA FACTURA. Varias líneas comparten número.
    oper_number     text NOT NULL,
    cliente_codigo  text,
    cliente_nombre  text NOT NULL,
    producto_codigo text,
    producto_nombre text NOT NULL,
    cantidad        double precision NOT NULL,
    precio_usd      double precision,
    traido_at       timestamptz NOT NULL DEFAULT now(),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ventas_sucursal_fecha_idx ON ventas_facturadas (sucursal_codigo, fecha);
CREATE INDEX ventas_cliente_idx        ON ventas_facturadas (cliente_nombre);
CREATE INDEX ventas_oper_idx           ON ventas_facturadas (oper_number);
CREATE TRIGGER trg_ventas_updated BEFORE UPDATE ON ventas_facturadas
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- Ajustes
-- ---------------------------------------------------------------------------

-- Una sola fila, y la base lo impide en vez de confiarlo a un `findFirst`. Dos filas de
-- ajustes es media aplicación mirando una y media mirando la otra.
CREATE TABLE settings (
    id                 boolean PRIMARY KEY DEFAULT true CHECK (id),
    -- Por dónde va el barrido del histórico, en DÍAS HACIA ATRÁS. Hace falta guardarlo
    -- porque de los datos no se puede deducir: hay pedidos viejos sueltos, así que «el
    -- más antiguo que tengo» no significa «tengo todo hasta ahí».
    sync_barrido_dia   integer NOT NULL DEFAULT 0,
    -- Cuándo se trajo el catálogo de Ventra. Cambia poco y se llega por VPN: preguntarle
    -- en cada ciclo del espejo sería cargar un enlace delicado por gusto.
    catalogo_traido_at timestamptz,
    currency           text NOT NULL DEFAULT 'USD',
    cup_rate           double precision NOT NULL DEFAULT 320.0,
    cup_rate_updated_at timestamptz NOT NULL DEFAULT now(),
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_settings_updated BEFORE UPDATE ON settings
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

INSERT INTO settings DEFAULT VALUES;

-- LAS MONEDAS — la tercera tabla que faltaba.
--
-- Era `Settings.currencies`, un JSON con `[{code, rate}]`. Una lista de cosas con su
-- clave y su valor es una tabla: así se puede poner única la moneda, saber cuándo se
-- cambió cada tasa y corregir una sin reescribir el array entero.
CREATE TABLE currencies (
    code       text PRIMARY KEY,
    -- Unidades de esta moneda por 1 USD. CUP = 320.
    rate       double precision NOT NULL,
    activa     boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_currencies_updated BEFORE UPDATE ON currencies
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

INSERT INTO currencies (code, rate) VALUES ('USD', 1), ('CUP', 320);

-- +goose Down
DROP TABLE IF EXISTS currencies, settings, ventas_facturadas, order_vehicles,
                     order_items, routes, orders, customers, products,
                     vehicles, vehicle_types, saved_origins, branches CASCADE;
DROP TYPE  IF EXISTS procedencia, factura_estado, pedido_estado, trip_leg,
                     vehicle_status, route_status, stop_result, order_status;
DROP FUNCTION IF EXISTS set_updated_at();
