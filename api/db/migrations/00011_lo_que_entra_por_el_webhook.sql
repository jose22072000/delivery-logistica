-- LO QUE ENTRA Y LO QUE SALE POR EL WEBHOOK, apuntado para poder mirarlo.
--
-- La 00010 montó el buzón de SALIDA —lo que el reparto le cuenta a PEDIDO—. Esta es la
-- otra mitad: lo que PEDIDO empuja hacia aquí. Jose, 26/09/2026: «aparte de recibir y
-- enviar, tener también para ver cómo está funcionando el webhook, tanto lo que envía como
-- lo que recibe».
--
-- POR QUÉ SE APUNTA LO QUE ENTRA, si los pedidos ya quedan guardados. Porque cuando un
-- pedido NO aparece en el reparto, hoy no hay forma de saber de quién es el problema: si
-- PEDIDO no lo mandó, si lo mandó y se rechazó, o si llegó y se escribió mal. Sin esta
-- tabla la respuesta es «mira los logs del contenedor», que es no tener respuesta. Con
-- ella, la pantalla de administración dice a qué hora entró la última tanda, cuántos traía
-- y cuántos se escribieron.
--
-- NO SE GUARDA EL CUERPO ENTERO. Son tandas de cientos de pedidos con nombres, teléfonos y
-- direcciones de clientes: copiarlas aquí es tener el mismo dato personal en dos sitios y
-- una tabla que crece sin techo. Se guardan los NÚMEROS y los motivos de lo rechazado, que
-- es lo que se mira.

-- +goose Up
CREATE TABLE recepciones_del_webhook (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Quién empujó. Hoy sólo PEDIDO; va nombrado para que el día que haya otro no haya
    -- que adivinar de dónde venía cada tanda.
    origen       text NOT NULL DEFAULT 'pedido',

    -- Cuántos traía la tanda y cómo acabó cada uno. Los tres números son lo que se mira:
    -- `traidos` distinto de `escritos + rechazados` es un fallo del que escribe esto.
    traidos      integer NOT NULL,
    escritos     integer NOT NULL,
    rechazados   integer NOT NULL,

    -- Los motivos de lo rechazado, uno por línea y sin el cuerpo. «no tiene folio»,
    -- «sucursal desconocida: XXX». Vacío cuando no se rechazó nada.
    motivos      text,

    -- Cuánto tardó en atenderse, para ver si el webhook está ahogando a la api.
    duracion_ms  integer NOT NULL DEFAULT 0,

    created_at   timestamptz NOT NULL DEFAULT now()
);

-- La pantalla lee las últimas, y el vigía mira si hace mucho que no entra ninguna.
CREATE INDEX recepciones_del_webhook_recientes_idx
    ON recepciones_del_webhook (created_at DESC);

-- Y LO QUE SALE, con la misma forma. Jose: «y de salida también, para saber si llegó
-- correcto o no».
--
-- `avisos_a_pedido` ya dice qué pasó con CADA aviso —pendiente, enviado, rechazado y con
-- qué motivo—. Esto es la otra pregunta, la de la tanda: si la llamada llegó, qué contestó
-- PEDIDO y cuánto tardó. Son distintas y las dos hacen falta: un aviso puede quedarse
-- pendiente porque PEDIDO está caído (la tanda no llegó) o porque lo rechazó (llegó
-- perfectamente y dijo que no). Sin la tanda apuntada, las dos se ven igual desde fuera:
-- «hay avisos sin enviar».
CREATE TABLE envios_del_webhook (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    destino      text NOT NULL DEFAULT 'pedido',

    -- Cuántos avisos iban, y qué dijo el otro lado de cada uno.
    mandados     integer NOT NULL,
    aceptados    integer NOT NULL,
    rechazados   integer NOT NULL,

    -- El código HTTP tal cual. Un 200 con cero aceptados y un 502 no son lo mismo, y
    -- guardar sólo «falló» los confunde.
    http         integer,
    -- El motivo LITERAL del otro lado, o el de la red si no se llegó a hablar. «no se
    -- pudo» no le dice nada a nadie.
    motivo       text,

    duracion_ms  integer NOT NULL DEFAULT 0,

    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX envios_del_webhook_recientes_idx ON envios_del_webhook (created_at DESC);

-- +goose Down
DROP TABLE IF EXISTS envios_del_webhook;
DROP TABLE IF EXISTS recepciones_del_webhook;
