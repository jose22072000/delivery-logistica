-- EL WEBHOOK, EN LOS DOS SENTIDOS, Y CÓMO VA.
--
-- `avisos_a_pedido` (00010) dice qué pasó con CADA aviso. Estas dos tablas dicen qué pasó
-- con cada TANDA: si la llamada llegó, qué contestó el otro lado y cuánto tardó. Son
-- preguntas distintas y las dos hacen falta — un aviso sin enviar puede ser «PEDIDO está
-- caído» o «PEDIDO lo rechazó», y desde fuera se ven igual.

-- ---------------------------------------------------------------------------
-- Lo que entra
-- ---------------------------------------------------------------------------

-- name: ApuntarRecepcionDelWebhook :exec
INSERT INTO recepciones_del_webhook (origen, traidos, escritos, rechazados, motivos, duracion_ms)
VALUES (
    sqlc.arg('origen'), sqlc.arg('traidos'), sqlc.arg('escritos'),
    sqlc.arg('rechazados'), sqlc.narg('motivos'), sqlc.arg('duracion_ms')
);

-- name: ListarRecepcionesDelWebhook :many
SELECT id, origen, traidos, escritos, rechazados, motivos, duracion_ms, created_at
FROM recepciones_del_webhook
ORDER BY created_at DESC
LIMIT sqlc.arg('tope');

-- ---------------------------------------------------------------------------
-- Lo que sale
-- ---------------------------------------------------------------------------

-- name: ApuntarEnvioDelWebhook :exec
INSERT INTO envios_del_webhook (destino, mandados, aceptados, rechazados, http, motivo, duracion_ms)
VALUES (
    sqlc.arg('destino'), sqlc.arg('mandados'), sqlc.arg('aceptados'),
    sqlc.arg('rechazados'), sqlc.narg('http'), sqlc.narg('motivo'), sqlc.arg('duracion_ms')
);

-- name: ListarEnviosDelWebhook :many
SELECT id, destino, mandados, aceptados, rechazados, http, motivo, duracion_ms, created_at
FROM envios_del_webhook
ORDER BY created_at DESC
LIMIT sqlc.arg('tope');

-- ---------------------------------------------------------------------------
-- Cómo va, en una lectura
-- ---------------------------------------------------------------------------
--
-- Las horas de la última tanda de cada lado son lo primero que se mira: un webhook que
-- lleva seis horas sin recibir nada no da ningún error, sólo deja de pasar cosas. Y
-- `null` es «nunca», que no es lo mismo que «hace mucho» y se dice con otras palabras.

-- name: ResumenDelWebhook :one
SELECT
    (SELECT max(created_at) FROM recepciones_del_webhook)::timestamptz AS ultima_entrada,
    (SELECT max(created_at) FROM envios_del_webhook)::timestamptz      AS ultima_salida,
    (SELECT coalesce(sum(escritos), 0)::bigint
       FROM recepciones_del_webhook
      WHERE created_at > now() - interval '24 hours')              AS escritos_hoy,
    (SELECT coalesce(sum(rechazados), 0)::bigint
       FROM recepciones_del_webhook
      WHERE created_at > now() - interval '24 hours')              AS rechazados_al_entrar,
    (SELECT count(*)::bigint FROM avisos_a_pedido
      WHERE situacion = 'pendiente')                               AS avisos_pendientes,
    (SELECT count(*)::bigint FROM avisos_a_pedido
      WHERE situacion = 'rechazado')                               AS avisos_rechazados,
    -- El más viejo sin mandar. Es el número que dice si esto está atascado: veinte
    -- pendientes de hace un minuto es el ritmo normal; uno de hace seis horas, no.
    (SELECT min(created_at) FROM avisos_a_pedido
      WHERE situacion = 'pendiente')::timestamptz                  AS pendiente_mas_viejo;
