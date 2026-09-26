-- EL BUZÓN DE SALIDA HACIA PEDIDO: en qué punto del reparto va cada pedido.
--
-- Hasta hoy el reparto sólo TIRABA de PEDIDO —`GET /integration/orders` y `/clients`— y no
-- le contaba nada de vuelta. O sea que el vendedor que tomó el pedido no se enteraba nunca
-- de si se entregó, se devolvió o sigue en el camión, y el único que lo sabía era quien
-- tenía el reparto abierto. Jose, 26/09/2026: «el webhook para delivery, el de recibir y el
-- de enviar el estado de los pedidos de delivery para que PEDIDO se entere de eso».
--
-- PEDIDO ya sabe recibirlo: `POST /integration/orders/status`, con los cinco estados de su
-- `ESTADOS_ENTREGA`. Lo que faltaba era quién se lo diga.
--
-- POR QUÉ UNA TABLA Y NO UNA LLAMADA AL VUELO. Porque la llamada se pierde. Marcar una
-- parada entregada es un gesto de alguien que está en la calle, y si en ese instante
-- PEDIDO está caído, la red va mal o el proceso se reinicia, ese aviso no vuelve a existir:
-- el pedido queda entregado aquí y eterno «en proceso» allá, y nadie se entera nunca. El
-- aviso se escribe EN LA MISMA TRANSACCIÓN que el resultado —o los dos o ninguno— y un
-- trabajador lo drena después. Es la misma forma que la cola del aparato, y por lo mismo.
--
-- Y POR QUÉ SE GUARDA EL RECHAZO. `CLAUDE.md` §4: nada se descarta en silencio. Si PEDIDO
-- dice que no —un pedido que allá no existe, un estado que no conoce—, el aviso se queda
-- con su motivo literal hasta que una persona lo mire. Un `DELETE` al fallar deja el número
-- cuadrado y la verdad perdida.

-- +goose Up
CREATE TYPE aviso_a_pedido_estado AS ENUM ('pendiente', 'enviado', 'rechazado');

CREATE TABLE avisos_a_pedido (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- El id de PEDIDO, que es el `external_id` de aquí. NO el nuestro: el que recibe es
    -- PEDIDO y allá nuestro uuid no significa nada.
    pedido_id     text NOT NULL,
    -- El folio, sólo para poder leer esta tabla sin ir a buscar a qué pedido se refiere.
    -- No se usa para casar nada: el que casa es `pedido_id`.
    folio         text,

    -- Uno de los cinco de PEDIDO: despachado | en_transito | entregado | devuelto |
    -- cancelado. No se declara como ENUM a propósito: el vocabulario es SUYO, y un ENUM
    -- aquí obligaría a un ALTER TYPE cada vez que ellos añadan uno — y mientras tanto el
    -- aviso no se podría ni escribir, que es peor que mandarlo y que lo rechacen.
    estado        text NOT NULL,
    nota          text,
    -- Cuándo pasó de verdad, no cuándo se pudo avisar. Con la red mala pueden ser horas
    -- distintas, y la que vale para el vendedor es la primera.
    ocurrio_at    timestamptz NOT NULL,

    situacion     aviso_a_pedido_estado NOT NULL DEFAULT 'pendiente',
    intentos      integer NOT NULL DEFAULT 0,
    -- El motivo LITERAL de PEDIDO. «no se pudo» no le dice nada a nadie; «no existe aquí
    -- (¿otra sucursal?)» dice dónde mirar.
    motivo        text,
    resuelto_at   timestamptz,

    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Por aquí drena el trabajador: los pendientes, los más viejos primero, para que un aviso
-- no se quede al fondo mientras entran otros.
CREATE INDEX avisos_a_pedido_pendientes_idx
    ON avisos_a_pedido (situacion, created_at)
    WHERE situacion = 'pendiente';

-- Y por aquí se lee la pantalla de administración: qué pasó con los de un pedido.
CREATE INDEX avisos_a_pedido_pedido_idx ON avisos_a_pedido (pedido_id, created_at DESC);

-- +goose Down
DROP TABLE IF EXISTS avisos_a_pedido;
DROP TYPE IF EXISTS aviso_a_pedido_estado;
