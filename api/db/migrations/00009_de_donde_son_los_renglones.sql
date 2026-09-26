-- DE DÓNDE SON LOS RENGLONES: del pedido o de la factura.
--
-- Cuando un pedido se factura distinto de como se tomó, PEDIDO manda **las líneas de la
-- factura** en `items` —descartando las que se pidieron y no se facturaron, para que nadie
-- cargue un hueco—. O sea que los kg y las unidades que este reparto ya tiene son los que
-- van a subir al camión. Comprobado contra producción el 26/09/2026:
--
--     PAT26-260923-1246 · el vendedor tomó MALTA 1.5L ×15 y MALTA 0.33L ×10;
--                         la factura dice SÓLO 10 blísters de 330 ml;
--                         aquí hay 1 renglón, 60 uds y 24,194 kg — los de la factura.
--
-- Lo que faltaba era DECIRLO. En pantalla salía «Cambió en la factura» y nada más, así que
-- quien mira un número no sabe si tiene delante lo que se pidió o lo que se facturó.
--
-- Jose, 26/09/2026: «cuando la factura cambió el pedido, el pedido en delivery debe mostrar
-- la factura, no el pedido: se facturó otra cosa, ese pedido ya no representa la cantidad
-- total». Y cómo se resuelve, con sus palabras: «mantenemos el pedido y sólo le añadimos
-- una factura a ese pedido para saber si cambió o no».
--
-- POR QUÉ UNA COLUMNA Y NO DEDUCIRLO DE `factura_estado`. No es lo mismo. `cambiado` dice
-- que la factura difiere; esta columna dice **qué estoy mirando yo**. Un pedido `igual`
-- también trae las líneas de la factura, y uno `cambiado` cuyo cotejo no pudo atar la
-- factura a ESTE pedido se queda con las del pedido. Deducirlo sería adivinar, y el
-- adivinado se lee igual de bien que el bueno.
--
-- Se deja NULL en lo ya bajado: NULL es «no se sabe», y la pantalla no dice nada hasta que
-- el espejo lo rellene en la próxima pasada. Poner `'pedido'` por defecto sería afirmar
-- sobre 5.385 pedidos algo que nadie ha comprobado.

-- +goose Up
ALTER TABLE orders ADD COLUMN IF NOT EXISTS items_origen text;

COMMENT ON COLUMN orders.items_origen IS
    'factura | pedido | NULL(no se sabe): de dónde salieron los renglones de este pedido';

-- +goose Down
ALTER TABLE orders DROP COLUMN IF EXISTS items_origen;
