-- La tasa de cambio, GUARDADA EN LA SUCURSAL, para que el aparato la tenga sin conexión.
--
-- # El fallo que cierra
--
-- En la barra superior del aparato el selector de moneda estaba PERMANENTEMENTE en la
-- pastilla ámbar «esta sucursal no tiene tasa de cambio todavía», en las ocho sucursales,
-- tuvieran tasa o no. El motivo: la barra leía la tabla local `currencies`, y a esa tabla
-- no la llenaba nadie — la bajada del día no la trae. Salía vacía siempre.
--
-- # Por qué en `branches` y no en `settings`, ni en una tabla aparte
--
-- `settings` es GLOBAL. Lo dice nuestra propia API en `internal/api/ajustes.go`: «son de
-- toda la empresa… La tasa POR SUCURSAL es otra cosa y vive en Accesos, no aquí».
-- `settings.cup_rate` es el campo viejo de delivery, con 320 por defecto, y leerlo
-- repetiría el error que ya pasó en PEDIDO y que está contado con estas palabras:
--
--   «Antes caía a la general y Granma enseñaba los 685 de La Habana como si fueran
--    suyos: un importe así se lee bien y está mal, que es lo peor que puede pasarle a un
--    número que alguien va a cobrar.»
--
-- Una tabla aparte (`branch_rates`, con su clave ajena) también valdría, y se descartó por
-- tres cosas concretas:
--
--  1. **La relación es 1:1 y no tiene historia.** Aquí no se guarda la serie de tasas: se
--     guarda LA tasa de hoy de cada sucursal, que es lo único que se usa para pintar. Una
--     tabla con una fila por sucursal y sin más filas nunca es una tabla: es cuatro
--     columnas puestas lejos de su dueño.
--  2. **`branches` YA BAJA en la sincronización.** Poniéndolo aquí, la tasa viaja al
--     aparato por el mismo `GET /api/sync/cambios` que ya existe, con las mismas
--     diferencias y el mismo `quitados`. Una tabla nueva sería una colección nueva en el
--     protocolo, en `Colecciones`, en la frescura y en la pantalla que la cuenta.
--  3. **La regla «con todas las sucursales no hay CUP» sale sola.** Si la tasa es una
--     columna de la sucursal, no elegir sucursal es literalmente no tener de dónde
--     leerla. Con una tabla aparte habría que acordarse de no hacer un `max()` ni un
--     «coge la primera», que es exactamente el error de Granma otra vez.
--
-- # Por qué `cup_rate_traido_at` y no `cup_rate_updated_at`
--
-- Porque NO es cuándo escribimos nosotros la fila: es el `traidoAt` de Accesos, o sea
-- cuándo puso Entrega esa tasa. La fila ya tiene un `updated_at` que mueve el disparador
-- `trg_branches_updated` en cada UPDATE, y dos columnas llamadas casi igual al lado la una
-- de la otra acaban confundiéndose. Además `settings.cup_rate_updated_at` existe y es otra
-- cosa —la global y vieja—: con nombres distintos no hay forma de leer una creyendo que es
-- la otra.
--
-- # Sin DEFAULT, y eso es la mitad del arreglo
--
-- `settings.cup_rate` trae 320 por defecto, así que ver un 320 NO demuestra que nadie haya
-- puesto la tasa. Aquí las cuatro columnas nacen NULL: **la marca de cuándo es lo único
-- que demuestra que la tasa existe**, y quien la lee tiene que exigirla.

-- +goose Up

ALTER TABLE branches
    -- Cuántos CUP son 1 USD en ESTA sucursal. NULL = esta sucursal no tiene tasa, que es
    -- un estado normal y no un error: hoy, en producción, seis de las ocho están así.
    ADD COLUMN cup_rate           double precision,
    -- De dónde salió (`entrega`, `manual`…). Es el `fuente` de Accesos, tal cual.
    ADD COLUMN cup_rate_fuente    text,
    -- El `traidoAt` de Accesos: cuándo se puso esa tasa en Entrega. LO QUE DEMUESTRA que
    -- la tasa es de verdad, y lo que se enseña al lado del número.
    ADD COLUMN cup_rate_traido_at timestamptz,
    -- Si Accesos la da por fresca (allí son 24 h). NO SE DECIDE AQUÍ: quien sabe cuándo
    -- una tasa está pasada es quien la mantiene. Se copia el booleano y se enseña el
    -- aviso; calcularlo por nuestra cuenta sería una segunda regla que se separa de la
    -- primera en cuanto una de las dos cambie.
    ADD COLUMN cup_rate_fresca    boolean;

-- La tasa se busca por CÓDIGO de sucursal, que es la clave que cruza las tres
-- aplicaciones. El índice de `external_id` ya existe (es UNIQUE), así que no hace falta
-- ninguno nuevo: el refresco recorre las ocho filas enteras una vez por hora.

-- +goose Down
ALTER TABLE branches
    DROP COLUMN IF EXISTS cup_rate,
    DROP COLUMN IF EXISTS cup_rate_fuente,
    DROP COLUMN IF EXISTS cup_rate_traido_at,
    DROP COLUMN IF EXISTS cup_rate_fresca;
