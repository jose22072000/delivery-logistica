-- Esquema del sincronizador. Postgres 16.
--
-- Sale entero de ../../docs/sincronizacion.md, que es el contrato. Aquí NO viven datos del
-- reparto: los pedidos, las rutas y los clientes son de `reparto-api` y esto no es una
-- segunda verdad. Lo que se guarda aquí es la contabilidad de la sincronización — quién
-- bajó, quién subió, qué se le aplicó y qué se le rechazó— y es justo lo que hoy no existe:
-- sin ella nadie se entera de que Palma lleva desde el martes sin subir hasta que no cuadra
-- el inventario.
--
-- Convenciones, las mismas que el reparto (../../api/db/migrations/00001_init.sql):
--   * identificadores uuid; lo que viene de sistemas ajenos (el id de la persona en auth,
--     la `clave` que se inventa el aparato) es `text` y se queda como viene.
--   * `created_at` / `updated_at` en todas, mantenidas por trigger. Las marcas de DOMINIO
--     van aparte y con su nombre: `visto_at`, `bajada_at`, `subida_at`, `hecho_at`.
--     «Cuándo se tocó la fila» y «cuándo pasó la cosa» no son lo mismo, y confundirlas es
--     exactamente lo que rompe un panel de control.
--   * los conjuntos cerrados son enums de verdad.
--
-- SOBRE LAS CLAVES AJENAS HACIA EL REPARTO. No hay ninguna, y es a propósito: son dos
-- series de migraciones distintas y nada garantiza en qué orden corren. `branch_id` y los
-- ids que devuelve el servidor se guardan como uuid sueltos. Es constancia, no integridad
-- referencial prestada de otro esquema.

-- +goose Up

-- La misma función que el reparto. Va con OR REPLACE para que este esquema se pueda
-- levantar solo, sin depender de que la otra serie haya corrido antes; si ya está, esto no
-- la cambia. El `Down` NO la borra por lo mismo: puede no ser nuestra.
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
-- ---------------------------------------------------------------------------

-- Cómo acabó un apunte del lote. Son DOS valores, no tres.
--
-- El protocolo contesta `aplicado`, `repetido` o `rechazado`, pero `repetido` NO es un
-- estado que se guarde: es lo que se responde cuando la clave YA ESTABA en la tabla.
-- Guardarlo sería anotar que algo se aplicó dos veces, que es precisamente lo que la
-- idempotencia impide. Un apunte se queda para siempre como se resolvió la primera vez.
CREATE TYPE apunte_estado AS ENUM ('aplicado', 'rechazado');

-- ---------------------------------------------------------------------------
-- 1 · El registro de aparatos
-- ---------------------------------------------------------------------------

-- Una fila por INSTALACIÓN, no por persona ni por teléfono. La misma persona que reinstala
-- la aplicación es un aparato nuevo, con su cola nueva y su marca de bajada nueva: mezclar
-- las dos haría que la segunda creyera que ya bajó lo que bajó la primera.
--
-- El identificador lo pone la base, no el aparato — igual que el `hasta` de la bajada y que
-- el id de una ruta. `POST /sync/aparato` existe para eso: el aparato se da de alta con
-- conexión (para entrar hace falta conexión) y se guarda el uuid que le devuelven. Un
-- identificador que se inventara el teléfono podría repetirse entre dos instalaciones y
-- entonces dos aparatos compartirían cola.
CREATE TABLE aparatos (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Quién lo usa: su id EN AUTH, como texto y sin clave ajena. Aquí no hay tabla de
    -- personas y no la va a haber — quien manda en personas, roles y sucursales es auth, y
    -- una copia local sería una segunda lista que mantener al día. Es constancia.
    persona    text NOT NULL,
    -- La sucursal del aparato. El alcance ya está cerrado por sucursal, así que esto es lo
    -- que decide qué le toca en la bajada, y es la columna por la que pregunta el panel:
    -- la pregunta de verdad no es «¿qué aparato falta?» sino «¿qué SUCURSAL lleva sin
    -- reportar?».
    branch_id  uuid NOT NULL,
    -- Cómo lo llama la gente («el Samsung de Palma»). Para poder decir por teléfono cuál
    -- de los dos aparatos es el que no ha subido.
    nombre     text,
    -- La última señal de vida: se toca en CADA petición del aparato, baje o suba. No es lo
    -- mismo que `subida_at` — un aparato que abre la aplicación y baja todos los días pero
    -- no sube nada está vivo y con trabajo atascado, que es el caso que hay que ver.
    visto_at   timestamptz,
    -- Aquí el alta y la creación de la fila son la misma cosa, así que no hay `alta_at`
    -- aparte: `created_at` ES cuándo se dio de alta.
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX aparatos_sucursal_idx ON aparatos (branch_id);
CREATE INDEX aparatos_persona_idx  ON aparatos (persona);
CREATE TRIGGER trg_aparatos_updated BEFORE UPDATE ON aparatos
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- 2 · El estado de sincronización — lo que ve el panel
-- ---------------------------------------------------------------------------

-- Una fila por aparato, y va aparte del registro a propósito: el registro se escribe una
-- vez y no se vuelve a tocar, esto se reescribe en cada bajada y en cada subida. Juntarlos
-- haría que el `updated_at` del aparato se moviera cada diez minutos y ya no significara
-- nada.
--
-- Es la tabla que responde `GET /sync/estado`.
CREATE TABLE aparato_estado (
    aparato_id     uuid PRIMARY KEY REFERENCES aparatos(id) ON DELETE CASCADE,

    -- Cuándo pidió diferencias por última vez.
    bajada_at      timestamptz,
    -- El `hasta` que se le devolvió en esa bajada: la marca desde la que pedirá la próxima
    -- vez. Se guarda aquí además de en el aparato porque el aparato puede perderla —se
    -- reinstala, se limpian los datos, se cierra sesión y se borra lo local— y sin ella la
    -- única salida sería bajar el mundo entero otra vez. Con esto se sabe por dónde iba.
    bajada_hasta   timestamptz,

    -- Cuándo subió por última vez. Es LA columna del panel: «Palma, martes» se lee de aquí.
    subida_at      timestamptz,

    -- Cuántos apuntes le quedan en la cola. Lo dice el APARATO al subir; el servidor no lo
    -- puede saber por su cuenta, porque la cola vive en el teléfono y lo que no ha subido
    -- no existe aquí. Un aparato que sube con `pendientes > 0` es uno que va por tandas o
    -- que se le cortó la red a medias.
    pendientes     integer NOT NULL DEFAULT 0 CHECK (pendientes >= 0),

    -- Cuántos se le rechazaron. Es un contador para que el panel no tenga que contar
    -- `apuntes_rechazados` aparato por aparato en cada refresco; se escribe en la MISMA
    -- transacción que el rechazo. Si algún día discrepan, manda la tabla: ahí está cada
    -- rechazo con su motivo, y esto es sólo un número.
    rechazados     integer NOT NULL DEFAULT 0 CHECK (rechazados >= 0),

    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_aparato_estado_updated BEFORE UPDATE ON aparato_estado
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- «¿Qué aparatos llevan más de N horas sin subir?» — la pregunta del panel.
--
-- NULLS FIRST no es un adorno: `subida_at` vacío es un aparato que NUNCA ha subido, que es
-- el peor caso de todos y el que tiene que salir arriba. Con el orden por defecto
-- (NULLS LAST en ascendente) esos se irían al final de la lista, que es donde nadie mira.
CREATE INDEX aparato_estado_subida_idx ON aparato_estado (subida_at NULLS FIRST);

-- «¿Qué aparatos tienen trabajo sin subir?» Parcial porque lo normal es que la cola esté
-- vacía: el índice sólo guarda los que importan y se queda diminuto.
CREATE INDEX aparato_estado_pendientes_idx ON aparato_estado (pendientes DESC)
    WHERE pendientes > 0;

-- ---------------------------------------------------------------------------
-- 3 · Idempotencia — «¿he visto ya esta clave?»
-- ---------------------------------------------------------------------------

-- El libro de lo que ya se aplicó. Una subida a medias —el servidor guardó y se cortó
-- antes de contestar— se reintenta entera, y sin esta tabla una ruta armada sin conexión
-- acabaría duplicada.
--
-- La clave la pone el APARATO (un ULID por apunte) y por eso es `text`. La primaria es
-- COMPUESTA, (aparato_id, clave), y no la clave sola: la pregunta real es «¿he visto ya
-- esta clave DE ESTE APARATO?». Dos instalaciones distintas no tienen por qué ponerse de
-- acuerdo en no repetirse, y con la clave sola el choque de dos aparatos se resolvería
-- devolviéndole a uno el resultado del apunte del otro. Además la primaria compuesta ES el
-- índice de esa consulta, que se hace una vez por apunte de cada lote: no hace falta otro.
CREATE TABLE apuntes (
    aparato_id uuid NOT NULL REFERENCES aparatos(id) ON DELETE CASCADE,
    clave      text NOT NULL,

    -- Qué se hizo. Se guarda para poder enseñar el apunte a una persona cuando se
    -- rechazó, y para saber qué se repitió cuando algo no cuadra.
    metodo     text NOT NULL,
    ruta       text NOT NULL,

    estado     apunte_estado NOT NULL,
    -- El id que se creó (o el de la fila que se tocó). Es lo que se devuelve tal cual
    -- cuando la respuesta es `repetido`: la MISMA de la primera vez, no una nueva.
    -- Vacío es normal: hay apuntes que no crean nada.
    id_creado  uuid,

    -- La hora del APARATO, la que venía en el apunte. Lo que se marcó a las cuatro se
    -- guarda como las cuatro aunque subiera a las siete. No se corrige ni se compara con
    -- la del servidor: el reloj del teléfono se mueve, pero es el único que estaba
    -- delante cuando se entregó el pedido.
    hecho_at   timestamptz NOT NULL,

    -- Cuándo caduca la fila. Esto NO puede crecer para siempre: son diez aparatos por
    -- decenas de apuntes al día, y a los dos años sería una tabla de millones de filas
    -- cuya única pregunta —«¿he visto ya esta clave?»— sólo mira las últimas.
    --
    -- El plazo tiene que ser más largo que el mayor tiempo que un aparato puede estar sin
    -- conectarse, porque ese es el único que puede reintentar un apunte viejo; y ese
    -- tiempo lo marca cuánto dura el refresh (`identidad.md`, «por decidir»). 30 días es
    -- de sobra para el peor caso real: quien esté más de un mes sin señal tiene que volver
    -- a entrar, y al entrar su cola se sube con claves nuevas.
    --
    -- Sólo caducan los APLICADOS. Ver `apuntes_rechazados`.
    expira_at  timestamptz NOT NULL DEFAULT now() + interval '30 days',

    -- `created_at` es cuándo LLEGÓ al servidor, que no es `hecho_at`. La diferencia entre
    -- las dos es cuánto estuvo el aparato sin señal, y se lee de un vistazo.
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),

    PRIMARY KEY (aparato_id, clave)
);
CREATE TRIGGER trg_apuntes_updated BEFORE UPDATE ON apuntes
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- La barrida de caducados. Parcial y sólo sobre los aplicados: los rechazados no se borran
-- nunca por su cuenta —una persona tiene que decidir— y dejarlos fuera del índice evita
-- además que la barrida se lleve la fila a la que apunta un rechazo sin atender.
CREATE INDEX apuntes_caducidad_idx ON apuntes (expira_at)
    WHERE estado = 'aplicado';

-- ---------------------------------------------------------------------------
-- 4 · Los rechazados — nada se descarta en silencio
-- ---------------------------------------------------------------------------

-- El servidor dijo que no por algo, y eso tiene que quedar a la vista con su motivo y su
-- hora hasta que una persona decida. Un apunte que desaparece solo es trabajo perdido que
-- nadie sabe que perdió.
--
-- Va en su propia tabla y no como un `motivo` en `apuntes` porque son dos cosas con vidas
-- distintas: `apuntes` es un libro técnico que caduca, y esto es una bandeja de trabajo que
-- alguien tiene que vaciar. El motivo vive AQUÍ y sólo aquí; cuando hay que responder
-- `repetido` a una clave que se rechazó, se lee de esta tabla. Un texto copiado en dos
-- sitios acaba discrepando.
CREATE TABLE apuntes_rechazados (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    -- RESTRICT y no CASCADE: no se puede borrar un aparato con rechazos sin atender y
    -- llevarse por delante la constancia de lo que se le tiró. Es la misma regla de
    -- arriba, escrita donde la base la puede hacer cumplir.
    aparato_id   uuid NOT NULL REFERENCES aparatos(id) ON DELETE RESTRICT,
    clave        text NOT NULL,

    -- El motivo TAL CUAL se le contestó al aparato, en español y entero: «3 de los 8
    -- pedidos ya están en otra ruta. Vuelve a elegirlos.» No es un código de error: es la
    -- frase que va a leer la persona que tenga que arreglarlo.
    motivo       text NOT NULL,
    -- Cuándo se rechazó, que es cuándo lo decidió el SERVIDOR. La hora del aparato —cuándo
    -- se hizo el apunte— está en `apuntes.hecho_at`, y entre las dos puede haber días.
    rechazado_at timestamptz NOT NULL DEFAULT now(),

    -- El cuerpo del apunte, como vino. Es lo único de todo el esquema que se guarda sin
    -- desmenuzar, y tiene motivo: esto no es un dato del reparto por el que se vaya a
    -- preguntar nunca, es el sobre — y es lo que permite que una persona vea qué se
    -- intentó y lo repita a mano. Por eso es `text` y no jsonb ni columnas: no se consulta
    -- por dentro. Sólo se guarda de los rechazados; de los aplicados sobra, porque el
    -- resultado ya está en el reparto.
    cuerpo       text,

    -- Cuándo y quién lo dio por visto. Mientras esté vacío, sale en el panel. Rechazar no
    -- es el final: «hasta que una persona decida» necesita un sitio donde conste que
    -- decidió, o la bandeja no se vacía nunca y se deja de mirar.
    atendido_at  timestamptz,
    atendido_por text,

    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),

    -- Un apunte se rechaza una sola vez: si vuelve, la respuesta es la misma de antes.
    UNIQUE (aparato_id, clave),
    -- Y su apunte tiene que existir. Se puede porque los rechazados no caducan.
    FOREIGN KEY (aparato_id, clave) REFERENCES apuntes (aparato_id, clave)
);
CREATE TRIGGER trg_apuntes_rechazados_updated BEFORE UPDATE ON apuntes_rechazados
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- La bandeja: lo que queda por mirar, lo más reciente arriba. Parcial, porque lo atendido
-- ya no se consulta salvo para buscar un caso concreto.
CREATE INDEX apuntes_rechazados_bandeja_idx ON apuntes_rechazados (rechazado_at DESC)
    WHERE atendido_at IS NULL;
-- «¿Qué se le rechazó a ESTE aparato?», atendido o no.
CREATE INDEX apuntes_rechazados_aparato_idx ON apuntes_rechazados (aparato_id, rechazado_at DESC);

-- ---------------------------------------------------------------------------
-- 5 · Los identificadores provisionales
-- ---------------------------------------------------------------------------

-- Una ruta armada sin conexión no tiene identificador —lo pone la base— pero la pantalla
-- necesita uno YA para enseñarla, imprimir el despacho y cerrarla por la tarde. El aparato
-- se inventa un `local-…` y aquí queda con cuál se correspondió.
--
-- Quien tiene que sustituirlo es el APARATO, en todo lo que le quedara en la cola detrás:
-- si no, el cierre de la tarde saldría contra `/api/routes/local-9f3a/results`, que no
-- existe en ningún sitio, y se perdería el trabajo justo después de haberlo subido. Esta
-- tabla es la red debajo de eso: si el aparato se corta antes de aplicar la sustitución y
-- reintenta con el `local-…`, el servidor sabe a qué ruta se refería en vez de dar 404.
--
-- Primaria compuesta por lo mismo que en `apuntes`: `local-9f3a` sólo quiere decir algo
-- dentro del aparato que se lo inventó. Dos aparatos pueden elegir el mismo y no se enteran.
CREATE TABLE ids_provisionales (
    aparato_id  uuid NOT NULL REFERENCES aparatos(id) ON DELETE CASCADE,
    -- El `local-…` tal como lo mandó el aparato.
    provisional text NOT NULL,
    -- El de verdad, el que devolvió el servidor.
    id_real     uuid NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),

    PRIMARY KEY (aparato_id, provisional)
);
CREATE TRIGGER trg_ids_provisionales_updated BEFORE UPDATE ON ids_provisionales
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Esto NO caduca con los apuntes, aunque nazca de uno. El apunte que creó la ruta se puede
-- barrer al mes; el `local-…` de esa ruta puede seguir en el aparato mucho más tiempo —en
-- una pantalla abierta, en un despacho impreso, en una cola que nunca terminó de subir—, y
-- el día que aparezca hay que saber traducirlo.

-- +goose Down
DROP TABLE IF EXISTS ids_provisionales, apuntes_rechazados, apuntes,
                     aparato_estado, aparatos CASCADE;
DROP TYPE  IF EXISTS apunte_estado;
-- `set_updated_at()` no se borra: si el sincronizador comparte base con el reparto, es la
-- suya y dejarla caer se llevaría por delante los triggers de todas sus tablas.
