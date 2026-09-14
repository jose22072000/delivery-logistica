-- El peso de cada renglón, que se estaba perdiendo.
--
-- # Qué pasó
--
-- El esquema nuevo dio por buena la descripción del pliego, que decía que `Order.items`
-- era `[{ description, quantity }]`. Al traspasar los datos REALES de producción
-- (14/09/2026, 85.902 renglones) resultó que cada uno trae DOCE campos:
--
--   name, descripcion, code, whName      — cómo se llama y con qué casó
--   quantity, packs                      — cuánto
--   pesoKg, unitWeightKg                 — cuánto pesa la unidad
--   pesoLineaKg, weightKg                — cuánto pesa la LÍNEA entera
--   matched, weightSource                — si casó con el catálogo y de dónde salió el peso
--
-- # Por qué importa y no es un capricho
--
-- El peso de la línea estaba GUARDADO, no calculado. Sin estas columnas habría que
-- recalcularlo como `products.weight × quantity`, y eso da otro número en cuanto el peso
-- del catálogo cambie después —que cambia, porque el catálogo se refresca desde Ventra— o
-- cuando el renglón no casó con ningún producto.
--
-- `weightSource` es justamente la confesión de que no siempre sale del catálogo. Tirarlo
-- sería recalcular el peso del pre-despacho con el catálogo de hoy sobre un pedido de
-- hace tres meses: el papel diría un peso y el almacén otro.
--
-- Es exactamente la clase de error que no revienta: da un número distinto y nadie se
-- entera.

-- +goose Up

ALTER TABLE order_items
    -- El nombre del producto tal como vino, y la descripción aparte: en los datos reales
    -- son dos campos distintos y la descripción suele ser «SIN DESCRIPCION».
    ADD COLUMN nombre            text,
    -- El código del producto en el origen, y con qué almacén casó.
    ADD COLUMN codigo            text,
    ADD COLUMN almacen_nombre    text,
    -- Si el renglón encontró su producto en el catálogo. Un renglón sin casar tiene peso
    -- igualmente —lo trajo PEDIDO— y hay que respetarlo.
    ADD COLUMN caso              boolean,
    -- El peso, tal como se guardó. `peso_unitario_kg` es por unidad y `peso_linea_kg` es
    -- el de la línea entera; NO se deduce uno del otro, porque en los datos reales no
    -- siempre es un múltiplo exacto.
    ADD COLUMN peso_unitario_kg  double precision,
    ADD COLUMN peso_linea_kg     double precision,
    -- De dónde salió ese peso: del catálogo, de PEDIDO, o de ningún sitio. Es lo que
    -- permite saber si el número es fiable sin tener que adivinarlo.
    ADD COLUMN origen_peso       text;

-- Para el pre-despacho, que suma pesos por pedido.
CREATE INDEX order_items_peso_idx ON order_items (order_id) WHERE peso_linea_kg IS NOT NULL;

-- +goose Down
DROP INDEX IF EXISTS order_items_peso_idx;
ALTER TABLE order_items
    DROP COLUMN IF EXISTS nombre,
    DROP COLUMN IF EXISTS codigo,
    DROP COLUMN IF EXISTS almacen_nombre,
    DROP COLUMN IF EXISTS caso,
    DROP COLUMN IF EXISTS peso_unitario_kg,
    DROP COLUMN IF EXISTS peso_linea_kg,
    DROP COLUMN IF EXISTS origen_peso;
