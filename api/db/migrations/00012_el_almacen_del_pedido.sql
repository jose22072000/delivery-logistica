-- DE QUÉ ALMACÉN SALE EL PEDIDO. Hasta hoy había UNO por sucursal y no había nada que
-- guardar; ahora hay varios y el que se usaba era el que no era.
--
-- # Qué pasó, con los números delante (26/09/2026)
--
-- La distancia del domicilio se mide DESDE EL ALMACÉN, y de esos kilómetros sale el costo
-- que alguien cobra. Mientras cada sucursal tuvo un solo almacén, medir «desde el almacén
-- de la sucursal» y «desde el almacén del pedido» era la misma frase. Dejó de serlo. La
-- sesión de PEDIDO contó sus renglones por almacén:
--
--     SANTIAGO      2.185 líneas desde AURORA · 804 desde PV-STGO · 11 desde PTO MONEDERO
--     CAMAGÜEY      2.778 desde PV CAMAGÜEY   · 183 desde FLORIDA · 39 desde ALM CAMAGÜEY
--     GUANTÁNAMO    2.060 desde PV GTMO       · 940 desde ALM CENTRAL
--
-- En Santiago **dos de cada tres pedidos salen de AURORA** y el reparto los medía todos
-- desde PV-STGO, que es el principal. No es una pantalla torcida: es un kilometraje
-- creíble, con sus decimales, que nadie puede desmentir mirándolo.
--
-- # Lo que se guarda y por qué en columnas nuevas
--
-- `order_items.almacen_nombre` YA EXISTE (00004) y **NO ES ESTO**. A pesar del nombre, lo
-- que se escribe ahí es `RenglonPesado.WhName`: el nombre del PRODUCTO con el que casó el
-- catálogo local de pesos (`internal/cotizar/pesos.go`, rama 4 de la cascada — sale de
-- `Acierto.WhName`). Meter un código de almacén ahí dejaría a quien lee esa columna
-- —buscando un producto— leyendo «2» y «AURORA». El nombre engaña porque el comentario de
-- la 00004 decía «con qué almacén casó» y era ya entonces el nombre del producto: por eso
-- las columnas de este cambio llevan el prefijo `almacen_salida_`, que no se confunde con
-- nada.
--
-- Y OJO CON LA TENTACIÓN, que es fácil de tener: medido en producción el 26/09/2026,
-- `order_items.almacen_nombre` está NULA en **los 7.527 renglones**. Está vacía porque el
-- catálogo local de pesos ya no se usa —PEDIDO manda los pesos cruzados contra Ventra— así que
-- un `count(*)` invita a pensar que la columna está libre. **NO lo está**: el día que un pedido
-- entre sin peso, esa columna vuelve a llenarse con el nombre del producto, y quien tenga un
-- almacén escrito ahí se encontrará «MALTA BUCANERO 355 ML» donde esperaba «AURORA».
--
-- # POR QUÉ LA IDENTIDAD ES (SUCURSAL, CÓDIGO) Y NUNCA EL NOMBRE
--
-- Comprobado en Ventra el 26/09/2026, y las dos mitades hacen falta:
--
--   * el NOMBRE solo no identifica: `Tiendas Parranda` existe en cinco sucursales con
--     cinco ids, `Parranda Oferta` en cuatro, y **`PV-STGO` está en Santiago Y en Palma
--     Soriano**;
--   * el CÓDIGO solo tampoco: `objectCode: 2` es AURORA en Santiago, PV CAMAGÜEY en
--     Camagüey y PV GTMO en Guantánamo.
--
-- Por eso se guardan los tres: el código, el nombre (para poder leerlo sin preguntarle a
-- nadie) y la sucursal del almacén, que puede no ser la del pedido.
--
-- # NADA SE DESCARTA EN SILENCIO (`CLAUDE.md` §4)
--
-- Va a llegar un almacén que no está dado de alta en Accesos — hoy mismo hay un
-- `28 · PTO MONEDERO` en Santiago con 11 líneas. Ese pedido **no se tira y no se cambia
-- por el principal a escondidas**: se guarda su código y su nombre tal cual, se mide desde
-- el principal porque es lo único que se puede hacer, y `almacen_salida_motivo` dice
-- exactamente eso. La vista de abajo lo deja a la vista sin que nadie tenga que sospechar.
--
-- # TODO ANULABLE Y SIN DEFAULT, igual que la 00009
--
-- Hay ~5.500 pedidos y ~7.500 renglones ya bajados. Un `DEFAULT` afirmaría sobre todos
-- ellos algo que nadie ha comprobado; NULL es «no se sabe todavía» y es la verdad. Se
-- rellena solo, en la pasada siguiente del espejo, en cuanto PEDIDO mande el campo. No hay
-- UPDATE de relleno a propósito: reescribir 5.500 filas para poner un dato inventado es
-- pagar el WAL por empeorar los datos.
--
-- Y OJO CON EL ORDEN AL DESPLEGAR: esta migración va ANTES que la API o la API no arranca
-- (tiene su propia guarda, `db/migraciones.go`).

-- +goose Up

-- --------------------------------------------------------------------------- el pedido
ALTER TABLE orders
    -- El código del almacén tal como lo manda PEDIDO (`objectCode` de Ventra). Es la MITAD
    -- de la identidad: sin la sucursal no dice cuál es.
    ADD COLUMN IF NOT EXISTS almacen_salida_codigo   text,
    -- Su nombre, tal cual. Se guarda AUNQUE el almacén no esté dado de alta en Accesos: es
    -- lo único legible que queda para saber a quién hay que dar de alta.
    ADD COLUMN IF NOT EXISTS almacen_salida_nombre   text,
    -- La sucursal DEL ALMACÉN, que no siempre es la del pedido: `PV-STGO` está en Santiago
    -- y en Palma Soriano, y sin esto las dos se leen igual.
    ADD COLUMN IF NOT EXISTS almacen_salida_sucursal text,
    -- `true` = sus renglones salen de MÁS DE UN almacén, y entonces el código de arriba es
    -- el del que pone más renglones. Lo decide PEDIDO, que es quien tiene los renglones
    -- delante; aquí se copia. Un pedido mezclado son DOS recogidas, y eso hay que poder
    -- verlo sin sumar renglones a mano.
    ADD COLUMN IF NOT EXISTS almacen_salida_mezclado boolean,
    -- DESDE DÓNDE SE MIDIÓ Y POR QUÉ. Es la confesión, y sin ella un kilometraje medido
    -- desde el principal es indistinguible de uno medido desde el almacén bueno.
    --
    -- Los valores los escribe `cotizar.ElegirOrigenDelPedido` y son SEIS:
    --
    --   almacen-del-pedido           se midió desde el almacén que trae el pedido. Lo normal.
    --   el-pedido-no-trae-almacen    PEDIDO no mandó el campo: desde el principal.
    --   almacen-no-dado-de-alta      lo mandó y no está en Accesos: desde el principal.
    --   almacen-sin-coordenadas      está dado de alta y sin punto: desde el principal.
    --   accesos-sin-codigos          NINGÚN almacén de esa sucursal tiene código en Accesos,
    --                                así que no había con qué emparejar: desde el principal.
    --   sucursal-sin-almacen-con-punto  no había NI UN almacén con punto: se midió desde las
    --                                coordenadas de la SUCURSAL.
    --
    -- LOS DOS ÚLTIMOS SON DISTINTOS DE LOS OTROS Y ÉSA ES LA RAZÓN DE QUE EXISTAN.
    --
    -- `accesos-sin-codigos` no se arregla dando de alta un almacén: se arregla poniéndole el
    -- código a los que ya están. Son dos tareas distintas para dos personas distintas, y con
    -- un solo motivo las dos se leen igual.
    --
    -- `sucursal-sin-almacen-con-punto` es el peor de todos: NO se midió desde ningún almacén,
    -- se midió desde el punto de la sucursal, que **no es el sitio del que sale la carga** —
    -- está escrito en `internal/cotizar/almacen.go` y es la razón de que
    -- `/api/quote/home-delivery` conteste 409 en vez de aproximar. Aquí no se puede contestar
    -- 409: `/api/quote/batch` es LA PUERTA de los pedidos y rechazar uno es perderlo. Así que
    -- se mide con lo único que hay y **se dice con otras palabras**, porque si comparte
    -- confesión con «desde el principal» el caso peor es el único que no se ve.
    ADD COLUMN IF NOT EXISTS almacen_salida_motivo   text;

COMMENT ON COLUMN orders.almacen_salida_codigo IS
    'código del almacén de Ventra del que sale el pedido, tal como lo manda PEDIDO; NULL = no se sabe';
COMMENT ON COLUMN orders.almacen_salida_nombre IS
    'nombre del almacén tal como llegó, se guarde o no en Accesos: es lo único legible para saber a quién dar de alta';
COMMENT ON COLUMN orders.almacen_salida_sucursal IS
    'sucursal DEL ALMACÉN: (sucursal, código) es la identidad, el nombre no identifica';
COMMENT ON COLUMN orders.almacen_salida_mezclado IS
    'true = los renglones salen de MÁS de un almacén, o sea que este pedido son DOS recogidas; el código de arriba es entonces el del que pone más renglones';
COMMENT ON COLUMN orders.almacen_salida_motivo IS
    'desde dónde se midió y por qué: almacen-del-pedido | el-pedido-no-trae-almacen | almacen-no-dado-de-alta | almacen-sin-coordenadas | accesos-sin-codigos. Y el peor caso sale COMPUESTO con un + porque son dos hechos: sucursal-sin-almacen-con-punto+<uno de los cuatro>, p.ej. sucursal-sin-almacen-con-punto+almacen-no-dado-de-alta. sucursal-sin-almacen-con-punto NUNCA sale solo, así que un WHERE motivo = ... no casa con esas filas: usa LIKE o split_part(motivo, ''+'', 1)';

-- --------------------------------------------------------------------------- el renglón
--
-- POR RENGLÓN TAMBIÉN, y no sólo por pedido: un pedido mezclado sale de dos almacenes y el
-- que despacha necesita saber qué línea se recoge en cada uno. Con sólo el del pedido, las
-- 804 líneas de PV-STGO de Santiago quedarían apuntadas como de AURORA.
ALTER TABLE order_items
    ADD COLUMN IF NOT EXISTS almacen_salida_codigo text,
    ADD COLUMN IF NOT EXISTS almacen_salida_nombre text;

COMMENT ON COLUMN order_items.almacen_salida_codigo IS
    'código del almacén de Ventra del que sale ESTE renglón. NO es almacen_nombre, que es el nombre del PRODUCTO con el que casó el catálogo';
COMMENT ON COLUMN order_items.almacen_salida_nombre IS
    'nombre del almacén del que sale ESTE renglón, tal como llegó de PEDIDO';
COMMENT ON COLUMN order_items.almacen_nombre IS
    'el nombre del PRODUCTO con el que casó el catálogo local de pesos (RenglonPesado.WhName). NO es un almacén, a pesar del nombre: el del almacén es almacen_salida_nombre';

-- Para preguntar «qué hay que recoger en AURORA», que es la pregunta del despacho.
CREATE INDEX IF NOT EXISTS order_items_almacen_salida_idx
    ON order_items (almacen_salida_codigo) WHERE almacen_salida_codigo IS NOT NULL;

-- --------------------------------------------------------------------------- la confesión
--
-- LOS ALMACENES DESDE LOS QUE **NO** SE MIDIÓ, con el motivo y con cuántos pedidos. Es el
-- mismo patrón que `peso_de_los_pedidos` de la 00007: la regla de la casa es que nada se
-- descarta en silencio (`CLAUDE.md` §4), y para eso no basta con no tirarlo — hay que poder
-- mirarlo **sin sospecharlo primero**. Un motivo guardado en una columna que ninguna vista
-- ni pantalla mira es la regla a medias.
--
-- SON LOS CINCO MOTIVOS, no sólo el del almacén sin dar de alta, y la razón es lo que va a
-- pasar esta semana: los 6 almacenes nuevos están dados de alta **sin punto a propósito**
-- —los ponen los logísticos— así que durante unos días el dato llega antes que las
-- coordenadas. Eso es lo normal y no es un fallo, pero mientras dure sus pedidos se miden
-- desde el principal, y con una vista que sólo mirara `almacen-no-dado-de-alta` no saldrían
-- en ningún sitio. Cada motivo se arregla en un lugar distinto y por una persona distinta:
-- dar de alta un almacén, ponerle el punto, ponerle el código en Accesos, o que PEDIDO
-- empiece a mandar el campo. Con un solo motivo las cuatro tareas se leen igual.
--
-- Se filtra por el MOTIVO y no por «el código no está en una lista»: los almacenes viven en
-- Accesos y esta base NO los tiene, así que aquí no hay contra qué comparar. El que sí pudo
-- comprobarlo fue quien escribió la fila, y dejó dicho lo que vio.
--
-- Un pedido de éstos NO está perdido: está guardado y medido desde donde se pudo. Sale aquí
-- con su código y su nombre tal cual llegaron, para que alguien lo arregle.
--
-- `sucursal_codigo` sale para poder ACOTAR: sin él, unir esta vista a una consulta de la API
-- le enseñaría Santiago al logístico de Camagüey, que es la regla 1 de la casa.
CREATE OR REPLACE VIEW almacenes_del_pedido_sin_medir AS
SELECT
    o.sucursal_codigo,
    o.almacen_salida_motivo                                AS motivo,
    o.almacen_salida_codigo                                AS codigo,
    o.almacen_salida_nombre                                AS nombre,
    count(*)                                               AS pedidos,
    min(coalesce(o.order_date, o.created_at))::timestamptz  AS desde,
    max(coalesce(o.order_date, o.created_at))::timestamptz  AS hasta
FROM orders o
WHERE o.almacen_salida_motivo IS NOT NULL
  AND o.almacen_salida_motivo <> 'almacen-del-pedido'
  AND NOT o.archivado
GROUP BY o.sucursal_codigo, o.almacen_salida_motivo,
         o.almacen_salida_codigo, o.almacen_salida_nombre;

COMMENT ON VIEW almacenes_del_pedido_sin_medir IS
    'los pedidos que NO se midieron desde su propio almacén, agrupados por sucursal, motivo y almacén: qué llegó, cuántos pedidos y desde cuándo';

-- +goose Down
DROP VIEW IF EXISTS almacenes_del_pedido_sin_medir;
DROP INDEX IF EXISTS order_items_almacen_salida_idx;
-- El comentario de `almacen_nombre` se quita también: antes de esta migración la columna no
-- tenía ninguno (la 00004 sólo lo explicaba en el fichero, y explicándolo mal). Dejarlo
-- puesto sería que la base siguiera describiéndose con una migración que ya no está.
COMMENT ON COLUMN order_items.almacen_nombre IS NULL;
ALTER TABLE order_items
    DROP COLUMN IF EXISTS almacen_salida_codigo,
    DROP COLUMN IF EXISTS almacen_salida_nombre;
ALTER TABLE orders
    DROP COLUMN IF EXISTS almacen_salida_codigo,
    DROP COLUMN IF EXISTS almacen_salida_nombre,
    DROP COLUMN IF EXISTS almacen_salida_sucursal,
    DROP COLUMN IF EXISTS almacen_salida_mezclado,
    DROP COLUMN IF EXISTS almacen_salida_motivo;
