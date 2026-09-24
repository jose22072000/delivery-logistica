# Despliegue

Cuatro piezas, dos bases y un contenedor que migra y se muere. Este documento dice qué
es cada una, qué necesita para arrancar, en qué orden se levantan y cómo se comprueba
que están vivas de verdad — no que el desplegador las haya pintado de verde.

> **Si vienes a desplegar y tienes prisa, lo que buscas es §2.1: el procedimiento de las
> migraciones.** Va **antes** de pulsar Deploy, se corre a mano, y no está automatizado a
> propósito (§2.9). Saltárselo no rompe nada desde el 21/09/2026 —los servicios se niegan a
> arrancar con la base atrasada— pero deja el despliegue sin hacer.

Los ficheros viven en `deploy/` y el de pruebas en la raíz:

```
deploy/Dockerfile.api           la API
deploy/Dockerfile.espejo        el espejo de PEDIDO
deploy/Dockerfile.sync          el sincronizador
deploy/Dockerfile.app           la web (Flutter -> nginx)
deploy/Dockerfile.migraciones   goose + los .sql de las dos series
deploy/migrar.sh                lo que corre dentro del anterior
deploy/nginx.conf               cómo se sirve la web
deploy/postgres-init/           las dos bases, SOLO para el compose de pruebas
docker-compose.yml              todo junto en la máquina de uno
.dockerignore                   lo que no viaja al contexto
```

Los cinco Dockerfile se construyen **desde la raíz del repositorio**, como los de notify:

```bash
docker build -f deploy/Dockerfile.api    -t reparto-api    .
docker build -f deploy/Dockerfile.espejo -t reparto-espejo .
docker build -f deploy/Dockerfile.sync   -t reparto-sync   .
docker build -f deploy/Dockerfile.app    -t reparto-app    .
docker build -f deploy/Dockerfile.migraciones -t reparto-migraciones .
```

---

## 1. Qué es cada servicio

| Servicio | Qué hace | Puerto | Base | ¿Se le pone dominio? |
|---|---|---|---|---|
| **api** | Las 35 rutas, el alcance por sucursal y los eventos en vivo. Es el dueño de los datos del reparto. | 8080 | reparto | sí |
| **espejo** | Trae los pedidos y los clientes de PEDIDO. **Proceso de fondo**, no servidor. | ninguno | reparto | **no** |
| **sync** | Bajada por diferencias, subida por lotes y registro de aparatos. Los datos se los pide a la api. | 8081 | reparto_sync | sí |
| **app** | La interfaz, compilada a web y servida como estáticos por nginx. | 8080 (nginx) | ninguna | sí |
| **migraciones** | `goose up` sobre las dos bases y se va. No es un servicio: es un trabajo. | ninguno | las dos | no |

**Son dos bases distintas.** El sincronizador no guarda datos del reparto sino la
contabilidad de la sincronización, con su propia serie de migraciones y sin una sola
clave ajena hacia la otra (está razonado en `sync/db/migrations/00001_sync.sql`). La
misma variable, `DATABASE_URL`, apunta a una base distinta en `api`/`espejo` que en
`sync`. Confundirlas da un arranque limpio y un «no existe la tabla» a la primera
petición.

### El espejo es un proceso de fondo, no un servidor

No expone puerto, no tiene `/health`, no lleva dominio y no hay que ponerle uno. Da
vueltas: cada minuto le pregunta a PEDIDO qué se movió y lo copia. Un sondeo HTTP no le
sirve a nadie porque no hay a qué llamar, y «el proceso está vivo» tampoco dice nada: un
espejo que lleva dos horas girando contra un 401 está vivo y no ha traído ni un pedido.
**Su salud se mide por si los datos siguen entrando** — §5.

Pero de fondo **no es lo mismo que efímero**: da vueltas hasta que lo paren, así que en
Dokploy sí es una Application, al revés que las migraciones. Cada cuánto pasa, qué
necesita y —lo importante— **qué se rompe si deja de pasar**, en §2-bis.

### Una sola réplica de la api

`GET /api/eventos` reparte los avisos en vivo (pedidos, catálogo, rutas, clientes) desde
un bus que vive **en la memoria de ese proceso**. Está escrito en la cabecera de
`api/internal/api/eventos.go`: quien avisa y quien reparte son el mismo servicio, así que
no hay Redis en medio.

La consecuencia al desplegar:

> **La api va en UNA réplica. Con dos, cada pantalla recibe sólo los avisos de los
> cambios que casualmente atendió su réplica, y la otra mitad no llega nunca. No falla
> nada, no aparece ningún error, y en el registro no hay una sola línea. Lo que se ve es
> «a veces hay que recargar para que salgan los pedidos nuevos», que es exactamente el
> tipo de fallo que cuesta dos semanas encontrar.**

En Dokploy: la Application de la api se queda en **1 réplica** y no se toca el escalado.
En `docker-compose.yml` va escrito como `deploy: replicas: 1`, y por eso `docker compose
up --scale api=2` no es una prueba válida de nada.

El día que haga falta escalarla, lo que cambia es el `Difusor` de `eventos.go` (un bus de
verdad, Redis o Postgres `LISTEN/NOTIFY`), no los manejadores. Hasta entonces: una.

---

## 2. Las migraciones: un contenedor aparte, y se corren A MANO

**Decisión: contenedor de migración aparte** (`deploy/Dockerfile.migraciones`), con
`goose`, que se ejecuta **antes** de que arranquen los servicios y termina. No se migra
al arrancar cada servicio. Cuatro motivos:

1. **Son dos bases y dos series independientes.** `api/db/migrations` va a la base del
   reparto y `sync/db/migrations` a la del sincronizador. No hay un servicio que sea
   dueño de las dos, así que «que migre el que arranque» exige elegir a dedo cuál migra
   qué y confiar en que el otro espere.
2. **La base del reparto la comparten dos contenedores**, la api y el espejo. Si migrara
   al arrancar, en cada despliegue habría dos procesos corriendo `goose up` a la vez
   sobre la misma base. Puede salir bien muchas veces; cuando sale mal, sale mal en
   producción y a la hora de desplegar.
3. **Una migración que falla tiene que parar el despliegue**, no convertirse en un bucle
   de reinicios. Con `migrate-on-start`, un `ALTER TABLE` roto se ve como «el contenedor
   se reinicia cada 10 segundos» y hay que leer el registro entero para descubrir que el
   problema no era el servicio.
4. **Las imágenes de los servicios se quedan mínimas.** `goose` no viaja en ninguna de
   las tres: la imagen final de cada servicio es un binario estático sobre `distroless`,
   sin compilador, sin shell y sin root.

`goose up` es **idempotente**: sobre una base ya migrada no hace nada. Se puede repetir
sin miedo, y por eso el paso es seguro de repetir aunque no se sepa si ya se corrió.

**En local** lo encadena `docker-compose.yml`: los tres servicios dependen de
`migraciones` con `condition: service_completed_successfully`, así que ninguno arranca si
la migración no terminó bien. En producción **no hay quien lo encadene**, y por eso el
resto de esta sección es un procedimiento y no una nota.

---

### 2.1 El procedimiento, de una pieza

Esto es lo que hay que hacer, en este orden, **antes** de pulsar Deploy en Dokploy. Lo
escribe alguien que ya lo hizo para que lo haga alguien que no estuvo.

```
1. mirar        qué migraciones hay en el árbol y que la conexión al VPS está abierta
2. subir        los .sql al servidor
3. status       ACCION=status — no escribe nada, sólo dice qué falta
4. leer         lo que dijo status; si dice algo que no esperabas, PARAR (§2.7)
5. up           ACCION=up
6. comprobar    que las dos series quedaron sin Pending (§2.6)
7. y AHORA sí   Deploy de reparto-api y reparto-sync en Dokploy
```

Los pasos 3 y 5 son **el mismo `docker run`** cambiando una variable. El 3 no se salta
nunca: es la única oportunidad de ver lo que va a pasar antes de que pase.

---

### 2.2 Antes de tocar nada

**Una sola conexión SSH.** Cada `ssh` nuevo le manda un correo a Jose
(`procovar/CLAUDE.md` §2). Se comprueba que la compartida está viva y todo lo demás viaja
por ella:

```bash
ssh -O check vps        # tiene que decir: Master running
```

**Qué hay en el árbol.** Lo que se va a aplicar es lo que hay aquí, no lo que uno recuerde:

```bash
ls api/db/migrations/ sync/db/migrations/
```

Apunta el número más alto de cada carpeta. Al terminar, `status` tiene que decir
exactamente ése. Hoy (23/09/2026) son `00006_bajas_de_la_bajada.sql` en la serie del
reparto y `00001_sync.sql` en la del sincronizador.

**Que la imagen está en el servidor.** Se construyó allí y se queda:

```bash
ssh vps 'docker images reparto-migraciones'
```

Si no está, se construye —tarda unos minutos porque baja goose— y para eso hace falta el
repositorio en el servidor:

```bash
ssh vps 'cd /tmp && rm -rf m && git clone --depth 1 -b main \
  https://github.com/jose22072000/delivery-logistica.git m && cd m && \
  docker build -f deploy/Dockerfile.migraciones -t reparto-migraciones .'
```

**Cómo se llaman las dos bases.** Son `procovar_reparto` y `procovar_reparto_sync`
(`docs/montar-en-dokploy.md`, comprobado el 22/09/2026). Cuesta una línea confirmarlo y
evita migrar la base de otro:

```bash
ssh vps 'C=$(docker ps -qf name=procovar-postgres-nlfols | head -1); \
         docker exec "$C" psql -U procovar -lqt | cut -d"|" -f1 | grep reparto'
```

**Y nadie desplegando a la vez.** No se despliega con agentes vivos escribiendo el árbol
(`CLAUDE.md` §4-bis). Aquí importa más que en ningún sitio: los `.sql` que se suben son
los del árbol de ese instante.

---

### 2.3 Subir los `.sql`

**La imagen lleva los `.sql` horneados dentro** (`COPY api/db/migrations/ /migraciones/api/`).
O sea que la imagen que ya está en el servidor trae los del día en que se construyó, y
una migración nueva **no está ahí**. Hay dos salidas y aquí se usa la segunda:

- reconstruir la imagen entera en cada migración nueva — correcto, y tarda minutos;
- **subir los `.sql` y montarlos encima** — instantáneo, y es lo que se hizo. La imagen no
  es más que goose y `migrar.sh`; lo que cambia de una vez a otra son los `.sql`.

Con la conexión ya abierta, `scp` no dispara ningún correo nuevo:

```bash
ssh vps 'mkdir -p /root/reparto-migraciones/api /root/reparto-migraciones/sync'
scp api/db/migrations/*.sql  vps:/root/reparto-migraciones/api/
scp sync/db/migrations/*.sql vps:/root/reparto-migraciones/sync/
ssh vps 'ls -1 /root/reparto-migraciones/api /root/reparto-migraciones/sync'
```

Ese último `ls` no es celo: si el montaje del paso siguiente apunta a una carpeta vacía,
goose dice **«no migrations found»** y no «te falta la 00006». Un directorio vacío se lee
como «no hay nada que hacer».

---

### 2.4 `ACCION=status` PRIMERO — no escribe nada

Todo en **una sola orden remota**, que es como manda `procovar/CLAUDE.md`: las claves se
leen dentro del servidor y no salen de allí ni pasan por este PC.

```bash
ssh vps '
set -eu
C=$(docker ps -qf name=procovar-postgres-nlfols | head -1)
U=$(docker exec "$C" printenv POSTGRES_USER)
P=$(docker exec "$C" printenv POSTGRES_PASSWORD)
H=procovar-postgres-nlfols:5432
Q="sslmode=disable&lock_timeout=5s"
docker run --rm --network dokploy-network \
  -v /root/reparto-migraciones/api:/migraciones/api:ro \
  -v /root/reparto-migraciones/sync:/migraciones/sync:ro \
  -e ACCION=status \
  -e DATABASE_URL_API="postgres://$U:$P@$H/procovar_reparto?$Q" \
  -e DATABASE_URL_SYNC="postgres://$U:$P@$H/procovar_reparto_sync?$Q" \
  reparto-migraciones:latest
'
```

Lo que se lee:

```
--- migraciones de reparto (/migraciones/api) ---
    Applied At                  Migration
    =======================================
    Mon Sep 15 09:12:03 2026 -- 00001_init.sql
    ...
    Pending                  -- 00006_bajas_de_la_bajada.sql
```

Lo normal es esto: una fecha en todas las viejas y `Pending` **sólo en las nuevas del
final**, que son justo las que se subieron en §2.3. Eso es la señal de que hace falta el
paso siguiente, y de que hace falta **exactamente eso** y nada más. **Cualquier otra cosa
se mira antes de escribir** — §2.7.

`migrar.sh` imprime el `status` **dos veces** por serie (una es la acción pedida y otra el
`status` final que hace siempre). Con `ACCION=status` sale repetido y no pasa nada.

#### `lock_timeout=5s`, y va en la URL

No es adorno, y no se quita. La 00006 crea **siete triggers, uno por tabla** —`routes`,
`vehicles`, `branches`, `products`, `customers`, `board_columns`, `board_placements`— y
un `CREATE TRIGGER` pide un candado **ACCESS EXCLUSIVE** sobre su tabla: mientras lo tiene,
nadie lee ni escribe ahí.

Y las migraciones de goose van **en una sola transacción** (ninguna de las dos series usa
`-- +goose NO TRANSACTION`). O sea que los candados que ya cogió **no los suelta** hasta el
final. Si una sola transacción abierta de la api tiene tomada la sexta tabla, sin
`lock_timeout` la migración **se queda esperando indefinidamente con cinco tablas
bloqueadas**, y detrás de ella se encola todo el que quiera leerlas: el reparto se para
entero y desde fuera parece que la base se cayó.

Con `lock_timeout=5s` eso se convierte en un error a los cinco segundos, la transacción se
deshace, se sueltan los candados y **no se aplicó nada**. Se vuelve a intentar y ya está.
Fallar rápido es barato; esperar es lo caro.

Lo que **no** se pone es `statement_timeout`: una migración puede tardar legítimamente, y
cortarla por larga sí rompería cosas. `lock_timeout` sólo limita **la espera por un
candado**, no el trabajo.

Va en la URL y no en el `.sql` a propósito: así vale para las dos series y para las
migraciones que todavía no están escritas, sin que nadie tenga que acordarse de ponerlo.
Llega al servidor como parámetro de arranque de la conexión, igual que `sslmode`. Si
alguna vez `status` contestara que no reconoce ese parámetro, se saca de la URL y se pone
como `options=-c%20lock_timeout%3D5000`, que es la forma larga de lo mismo — pero **no se
quita**.

---

### 2.5 `ACCION=up`

La misma orden con `ACCION=up`. No hay ningún otro cambio:

```bash
ssh vps '
set -eu
C=$(docker ps -qf name=procovar-postgres-nlfols | head -1)
U=$(docker exec "$C" printenv POSTGRES_USER)
P=$(docker exec "$C" printenv POSTGRES_PASSWORD)
H=procovar-postgres-nlfols:5432
Q="sslmode=disable&lock_timeout=5s"
docker run --rm --network dokploy-network \
  -v /root/reparto-migraciones/api:/migraciones/api:ro \
  -v /root/reparto-migraciones/sync:/migraciones/sync:ro \
  -e ACCION=up \
  -e DATABASE_URL_API="postgres://$U:$P@$H/procovar_reparto?$Q" \
  -e DATABASE_URL_SYNC="postgres://$U:$P@$H/procovar_reparto_sync?$Q" \
  reparto-migraciones:latest
'
```

Termina imprimiendo `migraciones aplicadas` y el `status` de las dos series. Si sale
distinto de cero, **no se pulsa Deploy**.

Las dos series van en **una sola pasada y en orden** (primero reparto, después
sincronizador). Si la primera falla, `set -eu` corta y la segunda ni se intenta: es a
propósito, porque lo que hay que arreglar es lo primero que se rompió.

---

### 2.6 Qué se mira DESPUÉS para saber que fue bien

Tres cosas, y las tres:

1. **Las dos series sin un solo `Pending`**, y el número más alto de cada una igual al que
   se apuntó en §2.2. Lo imprime el propio `up` al terminar; si se quiere volver a ver, se
   repite §2.4 con `ACCION=status`.
2. **La tabla de goose lo confirma en la base**, que es donde lo va a leer la api al
   arrancar:

   ```bash
   ssh vps 'C=$(docker ps -qf name=procovar-postgres-nlfols | head -1); \
     docker exec "$C" psql -U procovar -d procovar_reparto -c \
     "SELECT max(version_id) FROM goose_db_version WHERE is_applied;"'
   ```

   Tiene que dar **6**. El `WHERE is_applied` importa: goose apunta también las vueltas
   atrás, con `is_applied = false`, y contarlas daría por aplicada una migración que se
   deshizo (`api/internal/store/migraciones.go`).
3. **Y la prueba de verdad: que la api arranca.** Desde el 21/09/2026 la api y el
   sincronizador se niegan a arrancar con la base atrasada (§2-ter), así que un
   `reparto-api` que levanta **es** la comprobación de que la migración entró. Al revés no
   vale: mirar el registro del despliegue y confirmar que arrancó el contenedor nuevo, que
   un build fallido deja el anterior sirviendo (§5).

---

### 2.7 Si `status` dice algo raro

Esta es la parte que no se puede improvisar a las siete de la mañana. Por orden de
frecuencia:

| Lo que sale | Lo que es de verdad | Qué se hace |
|---|---|---|
| `la base de reparto no contestó en 60 s: no se migra nada` | **Casi nunca es que Postgres esté caído.** `migrar.sh` sondea con un `goose status` y ese sondeo falla igual por usuario malo, clave mala, nombre de base que no existe o red equivocada — y los cuatro se ven idénticos. | Comprobar los cuatro: el contenedor de Postgres corriendo, el nombre de las dos bases (§2.2), que el `docker run` lleva `--network dokploy-network`, y que la clave no trae caracteres que rompan la URL (abajo). |
| Una clave con `@`, `/`, `:`, `?` o `#` | La URL se parte por donde no es, y el error que llega es «no contestó» — el mismo de arriba con otra cara. | Hay que **codificarla** antes de meterla en la URL, con lo que haya en el servidor: `P=$(printf %s "$P" \| jq -sRr @uri)` o `P=$(python3 -c 'import sys,urllib.parse as u; print(u.quote(sys.argv[1], safe=""))' "$P")`. Comprobar que la clave real no lleva ninguno de esos caracteres es más rápido que depurarlo. |
| `goose: no migrations found` | La carpeta montada está vacía o el montaje apunta a otro sitio. **No** quiere decir «no falta nada». | Volver a §2.3 y mirar el `ls`. |
| Una `Pending` **más vieja** que otras ya aplicadas | Alguien aplicó fuera de orden, o un fichero llegó al árbol después de haberse migrado por encima. | **No correr `up`.** Mirar qué fichero es y de cuándo, y decidirlo con quien lo escribió. `up` la aplicaría ahora, sobre un esquema que ya no es el que ella daba por supuesto. |
| La base va por un número **más alto** que el fichero más nuevo del árbol | El servidor está por delante del árbol: se desplegó desde otra rama o desde otro portátil. | **No correr `up`** y no volver atrás. Averiguar qué se aplicó antes de tocar nada. Para arrancar servicios no estorba: una base adelantada deja levantar a propósito (§2-ter). |
| `ERROR: canceling statement due to lock timeout` | Saltó el `lock_timeout` de §2.4. **No se aplicó nada**: la transacción se deshizo entera. | Buscar quién tiene el candado y volver a lanzarlo. **No se sube el `lock_timeout`**: eso no arregla el candado, sólo alarga el rato en que el reparto está parado. |
| `relation "goose_db_version" does not exist` al mirar a mano | La base no se migró **nunca**. Es un 0, no un error. | Correr `up`: lo aplica todo desde la 00001. |

Para el candado:

```bash
ssh vps bash -s <<'SQL'
C=$(docker ps -qf name=procovar-postgres-nlfols | head -1)
docker exec "$C" psql -U procovar -d procovar_reparto -c "
  SELECT pid, state, wait_event_type, xact_start, left(query, 80) AS consulta
    FROM pg_stat_activity
   WHERE datname = current_database()
     AND state <> 'idle'
   ORDER BY xact_start;"
SQL
```

(El heredoc con `'SQL'` entre comillas es a propósito: así nada se expande en este PC y las
comillas simples del SQL llegan enteras al servidor.)

Lo que bloquea casi siempre es una transacción **`idle in transaction`**: alguien abrió una
transacción y se fue. La más vieja por `xact_start` es la culpable. Se mira de dónde sale
antes de matarla.

**`ACCION=down` existe porque goose lo tiene. En producción no se usa**: deshacer una
migración sobre datos reales se decide mirando, no con una variable de entorno. La 00006,
por ejemplo, tira siete triggers, dos funciones, una tabla y dos tipos.

---

### 2.8 Qué pasa si se salta este paso

Desde el 21/09/2026, lo que pasa es **que no se despliega**: el contenedor nuevo de la api
no levanta, Dokploy deja el anterior sirviendo y no se rompe nada. Eso es lo que se
quería, y por eso este procedimiento hoy es incómodo y no peligroso.

Lo que pasaba **antes de esa guarda** es por lo que existe todo esto, y hay que tenerlo
delante para no tener la tentación de quitarla: el 17/09/2026 la 00006 pasó **un día
entero** sin aplicarse con el código que la necesitaba ya escrito y desplegándose. La forma
del fallo es la peor posible:

- **la bajada por diferencias contesta 500, pero la carga inicial contesta 200**;
- así que **una instalación nueva funciona** —quien pruebe con un teléfono recién instalado
  lo ve todo bien—;
- **y la web también**, porque su base nace vacía en cada carga y siempre pide carga
  inicial;
- mientras **todo aparato que ya estaba en la calle se queda congelado para siempre**.

Todo verde justo donde se mira, y la flota parada. El detalle entero, en la cabecera de
`api/db/migraciones.go`.

#### La guarda que lo convirtió en algo que no se despliega

Desde el 21/09/2026 esto dejó de depender de que alguien se acuerde. La api y el
sincronizador comparan al arrancar las migraciones que llevan **incrustadas en el binario**
con la tabla `goose_db_version` de su base, y **si la base va por detrás se mueren ahí
mismo** diciendo qué ficheros faltan (`api/db/migraciones.go`, `sync/db/migraciones.go`,
la cuenta en `api/internal/store/migraciones.go`).

Lo que se compara no es «qué `.sql` hay en el disco del servidor» —ahí puede no haber
nada, porque la imagen de la api no lleva la carpeta de migraciones— sino **qué esquema da
por supuesto el código que se acaba de desplegar**.

El mensaje que sale lo lee quien está desplegando, con prisa, y dice las tres cosas:

```
la base está ATRASADA: le faltan 1 migración(es) que este código da por aplicadas:
  00006_bajas_de_la_bajada.sql
la base va por la 5.
...
Aplica las migraciones ANTES de desplegar la API — el paso está en docs/despliegue.md.
```

Un contenedor que no levanta se ve en el minuto uno y lo ve quien está desplegando. Un 500
en la bajada de un teléfono que está a 400 km no lo ve nadie.

**Al revés no**: una base **más adelantada** que el binario deja arrancar. Es lo que pasa
al volver a una imagen anterior, y ahí lo que hace falta es que el servicio levante, no
que se muera dos veces.

O sea que el orden ya no es una recomendación: es lo único que funciona. Si se pulsa Deploy
antes de migrar, el contenedor nuevo no levanta y Dokploy deja el anterior sirviendo. No se
rompe nada: no se despliega, que es lo que se quería.

---


### 2.9 Qué hace Dokploy con esto — la decisión, y por qué

Esta pregunta llevaba abierta desde el 17/09/2026 y por eso el paso seguía siendo manual
sin que nadie hubiera escrito por qué. **La respuesta es que Dokploy no tiene dónde meter
esto, y el paso se queda a mano con el procedimiento de §2.1.** Lo que sigue es el porqué,
para no tener que volver a investigarlo.

Lo primero, el hecho que decide todo: **una Application de Dokploy es un servicio de
Docker Swarm**, no un `docker run`. El panel expone la spec entera del servicio —Restart
Policy, Update Config, Placement— en «Swarm Settings», dentro de Advanced. Un servicio de
Swarm se espera vivo: el contenedor de migraciones arranca, migra y **sale con código 0**,
que para un servicio es «se cayó». Swarm lo relevanta, goose no encuentra nada que hacer,
vuelve a salir con 0, y queda un contenedor reiniciándose en bucle que desde el panel se
lee como «las migraciones se estrellan». Es exactamente el mismo bucle que `--once`
produciría en el espejo (§2-bis), por el mismo motivo.

Se miraron las cuatro cosas que Dokploy ofrece de verdad. Ninguna sirve:

| Lo que ofrece Dokploy | Qué es en realidad | Por qué no sirve aquí |
|---|---|---|
| **Schedule Jobs** (desde v0.22.0) a nivel Application o Compose | Un cron que hace **`docker exec` sobre un contenedor YA CORRIENDO**. No levanta ningún contenedor nuevo. | No puede correr la imagen `reparto-migraciones`: no existe esa forma. Y dentro de los contenedores que sí corren no hay nada que ejecutar — las tres imágenes de Go son `distroless:nonroot`: **sin shell, sin goose y sin los `.sql`**. Un `docker exec` ahí no tiene ni con qué empezar. |
| **Run Command**, en Advanced | Otro `docker exec`, esta vez a mano y **después** de que la aplicación esté construida y corriendo. | Lo mismo: contenedor distroless, nada que ejecutar. Y aunque lo hubiera, corre **después** del arranque, y el arranque es justo lo que hay que proteger. |
| **Hooks de pre-deploy / post-deploy** | No existen. No están en la documentación de Dokploy, y el propio mantenedor, preguntado por este caso exacto («correr la migración antes de que arranque el servicio»), contesta que se use otro contenedor con `depends_on`. | No hay dónde colgarlo. |
| **Swarm Settings → Restart Policy → Condition** puesto a que no reinicie | Es la salida que el mantenedor da a quien tiene justo este problema, y funciona: el contenedor termina y no se relevanta. | **Es la que más cerca está, y aun así rompe lo que importa.** Un servicio que terminó bien y uno que terminó con un `ALTER TABLE` roto quedan los dos igual de «parados» en el panel. Se pierde entero el punto 3 de arriba: *una migración que falla tiene que parar el despliegue, a la vista*. Y encima correría **en cada Deploy**, incluida una vuelta atrás a una imagen anterior, que es exactamente cuando NO se quiere migrar. |

Y la que no es de Dokploy sino de Compose, que conviene nombrar porque es la que el
mantenedor recomienda: **un despliegue de tipo Compose** con `migraciones` como servicio
con `restart: "no"` y los demás con `depends_on: condition: service_completed_successfully`.
Eso es literalmente lo que ya hace `docker-compose.yml` en local, y es la forma correcta
del problema. Pero llevarlo a producción significa **convertir las cuatro Applications en
una sola pila de Compose**, con sus dominios, sus variables y sus despliegues por
separado perdidos en el camino. Es un cambio grande, y no se hace de paso para ahorrar un
`docker run`. Queda apuntado como lo que se haría si algún día se rehace el montaje, no
como lo de ahora.

**Conclusión, y es la que se sigue:** el paso se corre a mano, con §2.1. No se crea ninguna
Application para las migraciones. Que sea manual no es el problema que había: el problema
era que **no estaba escrito**, y por eso vivía en la cabeza de quien lo hizo y se saltó un
día entero. Ya está escrito.

#### Lo único que queda por mirar, y sólo se puede mirar entrando al panel

Hay una variante que **podría** valer y que no se puede confirmar desde aquí sin romper la
regla de no tocar el VPS. Queda como pregunta abierta, y hasta que alguien la conteste y lo
escriba aquí, **el paso es el de §2.1**:

> Los Schedule Jobs tienen, además de los tipos «application» y «compose», un tipo
> **«server»**, que no hace `docker exec` sino que **corre un script de bash en el host**. Un
> job de ese tipo sí podría llevar dentro el `docker run` de §2.5, y la API de Dokploy tiene
> `schedule.runManually`, o sea que se podría **lanzar a mano desde el panel** en vez de por
> SSH — el orden lo seguiría poniendo una persona, que es lo correcto.
>
> Las tres cosas que habría que comprobar en el panel antes de montarlo, y las tres son
> eliminatorias:
>
> 1. **Que el tipo «server» exista y sea usable en este montaje**, donde el VPS es el propio
>    anfitrión de Dokploy y no un servidor remoto añadido al panel.
> 2. **Que se vea la salida del job y su código de salida.** Si un `up` que falló se ve
>    igual que uno que fue bien, esto es peor que el SSH: convierte un fallo ruidoso en uno
>    callado, que es la avería que este repositorio lleva entera en su `CLAUDE.md`.
> 3. **Que se pueda lanzar a mano sin dejar un cron vivo.** Una migración no se aplica «a
>    las 3:00 porque toca»: se aplica pegada al despliegue del código que la necesita. Un
>    cron que migrara por su cuenta aplicaría la 00007 la madrugada anterior a desplegar el
>    código que la usa — el mismo desajuste del 17/09 con el signo cambiado.
>
> Si las tres salen bien, se monta y se escribe aquí. Si alguna falla, esta sección se queda
> como está y se anota qué falló.

Lo que **no cambia pase lo que pase**, y no se negocia aunque aparezca esa función:

- **la migración va ANTES del Deploy**, nunca dentro ni después;
- **una migración que falla tiene que dejar el despliegue sin hacer, y a la vista**;
- **`ACCION=status` antes de `ACCION=up`**, siempre.

---

### 2.10 La primera vez, y sólo la primera: crear las dos bases

Las bases no las crea goose. Antes del primer `up` hay que crearlas dentro del Postgres que
ya existe —**uno solo para toda la casa**, regla 1 de `procovar/CLAUDE.md`; no se levanta
otro— siguiendo `procovar/docs/DOKPLOY-NUEVO-PROYECTO.md`, Parte 4:

```bash
ssh vps '
C=$(docker ps -qf name=procovar-postgres-nlfols | head -1)
docker exec "$C" psql -U procovar -d postgres -c "CREATE DATABASE \"procovar_reparto\"      OWNER procovar;"
docker exec "$C" psql -U procovar -d postgres -c "CREATE DATABASE \"procovar_reparto_sync\" OWNER procovar;"
'
```

Y hay un paso que se olvida y no avisa: **añadir las dos a la lista `BASES` de
`/usr/local/bin/procovar-backup-db`**. Una base que no está en esa lista no se respalda, y
eso no se descubre hasta el día en que hace falta el respaldo.

Las dos ya estaban creadas y migradas el 22/09/2026 (`docs/montar-en-dokploy.md`): 16
tablas en la del reparto y 5 en la del sincronizador.

---

## 2-bis. El espejo: un proceso que VIVE, y por eso SÍ es una Application

Lo primero, porque es la pregunta que decide todo lo demás: **el espejo no es un trabajo
que arranca y se muere.** Sin argumentos, `api/cmd/espejo` entra en `Correr` y da vueltas
hasta que alguien lo pare (`internal/espejo/ciclo.go`). El temporizador lo lleva él
dentro. Por eso va como **Application de Dokploy**, con su `restart` normal, y **no** como
el contenedor de migraciones de §2.

La diferencia con las migraciones es exactamente la que dice §2, punto 3, leída al revés:

| | migraciones | espejo |
|---|---|---|
| ¿Termina? | sí, y tiene que terminar | no, y si termina es que falló |
| ¿Application de Dokploy? | **no** — un contenedor que termina lo relevanta el desplegador, y eso es un bucle de reinicios que desde el panel se lee como «se estrella» | **sí** |
| ¿Cómo se corre? | `docker run --rm … reparto-migraciones` a mano, antes del Deploy | Deploy normal, y se queda |
| Si se cae | para el despliegue, a la vista | **nadie se entera** — abajo |

**A la Application del espejo NO se le pone `--once`.** Con esa bandera hace una pasada y
sale con 0, Dokploy lo vuelve a levantar, y en un minuto hay un contenedor reiniciándose
sin parar que además machaca a PEDIDO con la pasada entera cada vez. `--once` es para dos
cosas y sólo dos: probar a mano (§5) y, el día que se quisiera por cron, un `docker run`
desde el servidor como el de las migraciones — **no una Application con un horario**.

### Cada cuánto corre

Todo esto sale de `api/internal/espejo/opciones.go` y se cambia por entorno (§3.2). Los
números por defecto son los medidos:

| Cada | Qué hace |
|---|---|
| **1 minuto** (`SYNC_POLL_MS`) | Una vuelta entera: el catálogo de Ventra si toca, los clientes, **lo que se movió desde la marca de agua**, los recién cotizados de los últimos 30 minutos y un repaso a los últimos 3 días. |
| **10 minutos** (`SYNC_BARRIDO_CADA_MS`) | Además, estira el histórico 30 días más hacia atrás (`SYNC_HISTORICO_POR_CICLO`), en tramos de 3 días, hasta los 420. |

Un ciclo normal es barato: lo incremental casi siempre trae cero filas. Lo caro es el
barrido, y por eso tiene su propio freno. Un espejo recién desplegado **no tiene el año
entero desde el primer minuto**: tiene lo reciente enseguida —que es con lo que se
trabaja hoy— y se va llenando solo durante las horas siguientes. Eso es a propósito: un
proceso de una hora que si se corta hay que empezar de nuevo es peor.

El minuto no es un número redondo elegido a ojo: **el costo del domicilio lo pone el
repartidor desde la APK de Entrega, en PEDIDO**, y hasta que el espejo no pasa, aquí ese
pedido sigue diciendo «sin cotizar». Cinco minutos mirando una pantalla que no cambia se
leen como que está roto.

### Qué necesita

Las cuatro de siempre, y las cuatro hay que escribirlas (la lista completa, con sus topes
y sus interruptores, está en §3.2):

```
DATABASE_URL=postgres://…/reparto      la MISMA base que la api
SERVICE_API_KEY=…                      la MISMA clave que la api
PEDIDO_API_URL=http://pedido-api-XXXXXX:8400
DELIVERY_URL=http://reparto-api-XXXXXX:8080
ENTORNO=produccion                     sólo para que el registro salga en JSON
```

Y **son cinco, no cuatro**. El 22/09/2026 la Application llevaba desplegada cuatro días con
las cuatro primeras y sin `ENTORNO`, así que el registro salía en texto plano: no rompe
nada, pero es el único sitio donde se mira si el espejo va, y en texto plano no se filtra
por `level`. Lo que hay que llevarse de ahí no es la variable, es que **una Application que
lleva días «done» puede estar incompleta**: al tomar una que ya existe se cotejan sus
variables con esta lista antes de dar nada por bueno.

Las dos URL van por el **appName completo de Dokploy**, con su sufijo. Y `DELIVERY_URL`
hay que ponerla sí o sí: «vacía = a mí mismo» es una regla de la api, y **este proceso no
es la api**.

Sin `SERVICE_API_KEY` no arranca y lo dice. Con una que no sea la de la api, arranca,
trae los pedidos de PEDIDO y **se come un 401 al meterlos**: los trae y no los guarda.

### QUÉ SE ROMPE SI NO CORRE — y por qué no lo va a ver nadie

Esto es lo que hay que tener delante al desplegar, porque es la avería más silenciosa de
todo el reparto:

**Aquí no se da de alta un pedido a mano. En ninguna pantalla.** Los pedidos, sus
vendedores y los clientes son de PEDIDO, y el espejo es el único camino por el que entran.
Si se para:

- **El tablero se queda con los pedidos de la última pasada.** No sale un error, no hay
  una franja roja, no se queda nada en blanco: la api sigue sana y sirve lo que tiene en
  la base, que es la foto del minuto en que el espejo dejó de pasar. Un lunes por la
  mañana eso son los pedidos del viernes, y se ven exactamente igual de reales que los de
  hoy.
- **Y nadie lo nota**, porque no hay quien lo diga. La api no sabe si el espejo corre —no
  se hablan—, y de la web se quitaron a propósito el sello de «Datos de las 10:36» y el
  resto de avisos de frescura (el `CLAUDE.md` del repo, §3-quinquies): en un navegador
  hablaban de una copia que no existe. O sea que **la única señal de que el espejo está
  parado es que los pedidos que se esperaban no están**, y eso quien lo descubre es un
  logístico que no encuentra un pedido y supone que PEDIDO va tarde.
- **Los costos de domicilio se congelan.** Lo que el repartidor cotiza desde Entrega entra
  por aquí. Sin espejo, los pedidos se quedan en «sin cotizar» para siempre, que es justo
  lo que la gente está mirando.
- **Un cliente nuevo no existe.** Su pedido puede llegar (o no) pero el cliente no está, y
  eso se ve al intentar colocarlo en un camión.
- **El catálogo de Ventra deja de refrescarse**, con lo cual los productos y sus pesos se
  quedan con los de la última vuelta — y el peso es lo que decide si cabe en el camión.

Lo que **no** pasa, y conviene saberlo para no asustarse al arreglarlo: **no se pierde
nada**. La marca de agua se deriva de los propios datos (§5), no de un contador aparte, así
que el espejo que vuelve retoma por donde iba y recupera todo lo de las horas caídas en
las vueltas siguientes. Lo que se pierde es **el rato en que nadie supo que la pantalla
mentía**, y ése no se recupera.

Por eso la comprobación del espejo no es «el contenedor está corriendo» sino la consulta
de §5, y por eso se mira **dos veces con unos minutos de diferencia**. Un espejo girando
contra un 401 lleva dos horas «sano».

### La imagen corre sus pruebas, y se lleva dos ficheros de fuera de `api/`

`deploy/Dockerfile.espejo` hace `go vet ./... && go test ./...` antes de compilar, como los
otros tres. **Son los cuatro, y éste era el que faltaba**: se escribió el 14/09/2026, dos
días antes de que una mutación de prueba se desplegara sola por esta misma puerta abierta
en `Dockerfile.sync`, y se quedó sin la línea. Aquí importa más que en ningún otro, porque
el espejo **no tiene pantalla**: una guarda rota en `internal/espejo` sigue trayendo datos
y dejando el tablero verde con la mitad de los pedidos — que es literalmente lo que pasó
con los 2.284 de una sola ventana (`CLAUDE.md` §3), con 200 OK.

Y como el espejo y la api son **el mismo módulo de Go**, ese `go test ./...` corre también
todas las pruebas de la api. Dos de ellas leen ficheros que **no están dentro de `api/`**, y
las dos mueren con `t.Fatalf` si faltan, así que los dos Dockerfile de Go los copian:

| Fichero | Quién lo lee | Dónde cae en la imagen |
|---|---|---|
| `app/lib/nucleo/refresco_en_vivo.dart` | `internal/api/protocolo_avisos_test.go` — ata los tipos de aviso del servidor con los de la aplicación | `/app/lib/nucleo/…` |
| `docs/orden-de-paradas.casos.json` | `internal/api/orden_de_paradas_test.go` — ata el orden de visita de Go con el de Dart; es el **mismo** fichero, no una copia | `/docs/…` |

El segundo entró el 21/09/2026 y **tumbó la construcción de las dos imágenes de Go, la de
la api incluida**, hasta que se añadió su `COPY`. Es la regla del `.dockerignore` otra vez,
vista desde el otro lado: se excluye lo que se **regenera**, nunca lo que se **necesita** —
y un fichero de `docs/` puede ser código para una prueba. Quien añada una prueba que lea
algo de fuera de su módulo tiene que pasar por aquí; si no, lo descubre el build del
despliegue.

---

## 3. Las variables, una por una

Salen de `api/internal/config/config.go`, `api/internal/espejo/opciones.go` y
`sync/internal/config/config.go`. **Aquí no hay ninguna inventada**: lo que no esté en
esas tres listas no lo lee nadie.

### 3.1 api (`api/cmd/api`)

**Sin estas dos no arranca**, y lo dice nombrando las que falten:

| Variable | Qué es |
|---|---|
| `DATABASE_URL` | Postgres del reparto. `postgres://usuario:clave@host:5432/reparto` |
| `JWT_SECRET` | El **mismo** con el que firma `auth.procovar.cloud`. **Mínimo 32 caracteres** o no arranca: uno corto se rompe fuera de línea y el token que sale abre la sucursal entera. |

Con valor por defecto:

| Variable | Por defecto | Qué es |
|---|---|---|
| `ENTORNO` | `desarrollo` | `desarrollo` \| `produccion`. Cualquier otra cosa y no arranca. En producción el registro sale en JSON. |
| `PUERTO` | `8080` | Tiene que cuadrar con el Container Port del dominio. |
| `VERSION_APP` | la del compilador | La de **este servicio**. Normalmente se incrusta con `-ldflags`; el entorno la pisa. Sale en `/version` como latido del despliegue. **No es la de la aplicación**: eso es `APP_ULTIMA_VERSION`, aquí abajo. |
| `SERVICE_API_KEY` | vacía | La puerta de las rutas de servicio (`x-api-key`). **Vacía las deja CERRADAS**, nunca abiertas. Sin ella el espejo no puede entrar y desde fuera parece que PEDIDO no manda nada. |
| `ORIGENES_PERMITIDOS` | vacía | Lista cerrada separada por comas. Vacía = el navegador no puede llamar desde otro dominio. No se pone `*`: con `*` no viajan las cookies y la sesión de la web es una cookie. |
| `POOL_MAX_CONNS` | `10` | |
| `POOL_MIN_CONNS` | `2` | Mayor que el máximo y no arranca. |
| `POOL_MAX_IDLE` | `5m` | Duración de Go (`30s`, `5m`, `1h`). |
| `TIEMPO_LECTURA` | `15s` | |
| `TIEMPO_ESCRITURA` | `30s` | También es el plazo de las conexiones de eventos, que se renueva en cada escritura. |
| `TIEMPO_APAGADO` | `8s` | **No subirlo de 10 s**: es lo que espera Docker antes de mandar SIGKILL, y pasado ese punto se corta igual. |
| `PEDIDO_API_URL` | vacía | Para el canal que le cuenta a PEDIDO en qué punto va cada pedido y para `POST /api/admin/recompute`. Vacía: el servicio hace todo lo demás y **esas dos cosas lo dicen** (el canal devuelve `ok:false` con el motivo; el recosteo, un 500 con el nombre de la variable). Tiene que empezar por `http://` o `https://` o no arranca. |
| `DELIVERY_URL` | vacía | A dónde manda el recosteo su lote a cotizar. **Vacía significa «a mí mismo»** (`http://127.0.0.1:PUERTO`), que es lo correcto hoy. |
| `CATALOGO_CADA_MS` | `43200000` (12 h) | **En milisegundos**, no duración de Go. |
| `ALMACENES_CACHE_MS` | `300000` (5 min) | **En milisegundos**. Sin recuerdo, cotizar 200 pedidos son 200 llamadas a Accesos. |
| `PROCOVAR_AUTH_URL` | `https://auth.procovar.cloud` | |
| `PROCOVAR_AUTH_CLIENT_ID` | `delivery` | |

Y las del **anuncio de versión de la aplicación**, que es lo que leen los aparatos para
saber si tienen que actualizarse. Todas opcionales, pero **a medias no arranca**: con una
URL puesta y sin `APP_ULTIMA_VERSION` no se anunciaría nada nunca, y con la versión puesta
y sin ninguna URL se avisaría sin decir de dónde bajarla. El documento entero es
`docs/actualizaciones.md`.

| Variable | Por defecto | Qué es |
|---|---|---|
| `APP_ULTIMA_VERSION` | vacía | La versión de la **aplicación** que hay colgada (`1.5.0`). Vacía = no se anuncia nada y ningún aparato avisa. Es el estado seguro mientras no haya un fichero de verdad colgado. |
| `APP_ULTIMA_COMPILACION` | vacía | El `versionCode` (el número de después del `+` en `pubspec.yaml`). Es lo único que Android compara de verdad. Si no es un número, no arranca. |
| `APP_DESCARGA_ANDROID` | vacía | URL del `.apk`. |
| `APP_DESCARGA_WINDOWS` | vacía | URL del escritorio de Windows. |
| `APP_DESCARGA_LINUX` | vacía | URL del escritorio de Linux. |
| `APP_ULTIMA_NOTAS` | vacía | Una línea de qué trae. |
| `APP_ULTIMA_PUBLICADA` | vacía | `2026-09-15` o RFC3339. Se guarda normalizada. |

**No hay `APP_DESCARGA_WEB` y no la va a haber**: la web se actualiza sola al recargar.
| `PROCOVAR_AUTH_SIGNING_KEY` | vacía | La llave con la que se firma hacia Accesos (HMAC). Sin ella no se pueden pedir los almacenes ni las tasas, así que **no se puede cotizar ningún domicilio**. Arranca, pero lo avisa. |

Las tres URL se comprueban al arrancar aunque sean opcionales: una `PEDIDO_API_URL` sin
esquema no falla al concatenar, falla dentro de una gorutina de fondo, y lo único que se
ve es un aviso que no llegó.

### 3.2 espejo (`api/cmd/espejo`)

**No usa `config.Cargar`**: no pide `JWT_SECRET` porque no valida a ninguna persona. Su
pool es fijo (4 conexiones máximo, 1 mínima) y no se configura: el espejo no puede
quedarse con las conexiones que necesita la api para atender a quien está cargando un
camión.

Obligatorias:

| Variable | Qué es |
|---|---|
| `DATABASE_URL` | La **misma base que la api** (la del reparto). Ahí guarda los clientes y lee su marca de agua. |
| `SERVICE_API_KEY` | La **misma que la api**. Con ella firma hacia PEDIDO y con ella entra a `/api/quote/batch`. Si no coinciden, trae los pedidos y no consigue meterlos. |

Con valor por defecto:

| Variable | Por defecto | Qué es |
|---|---|---|
| `PEDIDO_API_URL` | `http://localhost:8400` | **Hay que ponerla**: el valor por defecto es el de una máquina de desarrollo y dentro de un contenedor no existe. |
| `DELIVERY_URL` | `http://localhost:3002` | A dónde manda los lotes a cotizar, o sea la api. **Aquí sí hay que escribirla**: «vacía = a mí mismo» es cosa de la api, y este proceso no es la api. |
| `SUCURSAL_CODIGO` | vacía | Vacía = las ocho sucursales. Se pone sólo para traer una. |
| `SYNC_POLL_MS` | `60000` (1 min) | Cada cuánto se repasa. **Un minuto, no cinco**: el costo del domicilio lo pone el repartidor desde Entrega y hasta que el espejo no pasa aquí sigue diciendo «sin cotizar». |
| `SYNC_TRAMO_DIAS` | `3` | Días por petición al recorrer el histórico. |
| `SYNC_HISTORICO_DIAS` | `420` | Hasta dónde atrás llega el histórico. |
| `SYNC_HISTORICO_POR_CICLO` | `30` | Cuánto histórico se estira por vuelta. Así lo reciente está desde el primer ciclo y el año se llena solo. |
| `SYNC_REPASO_DIAS` | `3` | La repasada de los últimos días, siempre. **Tiene que ser menor que `SYNC_HISTORICO_DIAS`** o no arranca: el barrido se quedaría sin recorrido. |
| `SYNC_BARRIDO_CADA_MS` | `600000` (10 min) | Cada cuánto toca estirar el histórico. Lo caro. |
| `SYNC_COTIZADOS_MIN` | `30` | La ventana de «los recién cotizados», en minutos. |
| `SYNC_LOTE` | `200` | Pedidos por POST a `/api/quote/batch`. Miles en un solo POST es lo que reventó la memoria la vez anterior. |
| `SYNC_PAGINA_CLIENTES` | `1000` | Clientes por página. Todos de golpe eran 2,17 MB en una respuesta. |
| `SYNC_SOLO_DOMICILIO` | apagado | Se enciende **sólo con el valor `1`**. |
| `SYNC_SOLO_COTIZADOS` | apagado | Con `1`. Encendido, el reparto se queda con seis pedidos y parece roto. |
| `SYNC_TODOS` | apagado | Con `1` trae el catálogo entero de PEDIDO. Apagado (lo normal) trae **sólo lo repartible**. |
| `ENTORNO` | — | Sólo cambia el formato del registro: `produccion` lo saca en JSON. |

Los tres interruptores comparan con `"1"` exactamente: un `SYNC_TODOS=false` heredado de
otro sitio **no** enciende nada, a propósito.

> **Cuidado con el prefijo `SYNC_`.** Estas variables son del **espejo**, y el
> sincronizador tiene otras que empiezan igual (`SYNC_ADDR`, `SYNC_TOPE_BAJADA`,
> `SYNC_IDENTIDAD`…). Son dos servicios distintos. En Dokploy, cada Application tiene su
> propio Environment: no hay un grupo compartido de variables `SYNC_*` y no debe haberlo.

### 3.3 sync (`sync/cmd/sync`)

Obligatorias — junta todos los fallos en un solo mensaje:

| Variable | Qué es |
|---|---|
| `DATABASE_URL` | La base **del sincronizador** (`reparto_sync`), no la del reparto. |
| `REPARTO_URL` | Dónde vive la api. El sincronizador no es dueño de los datos: se los pide. |
| `REPARTO_API_KEY` | La clave de servicio (`x-api-key`), la **misma** `SERVICE_API_KEY` de la api. Sin ella todo respondería 401 apunte por apunte, y el aparato lo leería como diez rechazos seguidos. |
| `SYNC_IDENTIDAD` | **`token`**, y con él hace falta `JWT_SECRET` (el mismo de la api, mínimo 32 caracteres). **No tiene valor por defecto a propósito**, para que nadie lo elija sin mirar. Corregido el 21/09/2026: aquí decía `cabeceras` y **eso es el camino roto** — ver el aviso de abajo. |

Con valor por defecto:

| Variable | Por defecto | Qué es |
|---|---|---|
| `SYNC_ADDR` | `:8081` | Dónde escucha. |
| `SYNC_DB_MAX_CONNS` | `10` | |
| `SYNC_TOPE_BAJADA` | `500` | Filas por tanda antes de contestar `truncado: true`. Existe porque la primera bajada de una sucursal grande no cabe de una vez en la conexión de allá. |
| `SYNC_REPARTO_TIMEOUT` | `30s` | |
| `SYNC_READ_TIMEOUT` | `15s` | |
| `SYNC_WRITE_TIMEOUT` | `60s` | Largo a propósito: un lote de un día entero se aplica apunte por apunte contra la api. |

> **`SYNC_IDENTIDAD=cabeceras` no se pone en el servidor, y estuvo escrito aquí.** Ese
> modo saca la identidad de `X-Persona`, `X-Sucursal` y `X-Super-Admin`, que **debía**
> poner un proxy que verificara el token delante del servicio. **Ese proxy nunca
> existió**: Traefik enruta `reparto.procovar.cloud/sync` directo al contenedor, así que
> la cabecera llega vacía y el sincronizador contesta **401 a todo** — y un 401 que
> sobrevive a renovar el cliente lo lee como «la sesión murió», o sea que echa al
> logístico a la pantalla de acceso justo cuando le vuelve la señal, con el día del
> almacén dentro del teléfono. Además, en `cabeceras` la identidad no trae token, así que
> `reparto-sync` no tiene qué reenviarle a la api y la cola del tablero vuelve a recibir
> 401. Visto el 16/09/2026, escrito en `sync/internal/config/config.go` y en el comentario
> de `docker-compose.yml`, y sigue valiendo: **`token`**.
>
> **Una diferencia con la api que conviene saber:** aquí un número o una duración mal
> escritos **no impiden arrancar** — se usa el valor por defecto en silencio
> (`sync/internal/config/config.go`, funciones `entero` y `espera`). Un
> `SYNC_TOPE_BAJADA=quinientos` arranca con 500 y nadie se entera. Al desplegar, cotejar
> lo que se puso con lo que el servicio dice que tiene: lo registra al arrancar, en la
> línea `sincronizador escuchando`.

### 3.4 app (`app/`)

> Esto es la **web**, que construye Dokploy con `deploy/Dockerfile.app`. El APK y los dos
> escritorios **no se construyen aquí**: se compilan a mano, y las órdenes exactas —con las
> variables sin las que el APK no compila desde Cuba— están en `docs/compilar.md`.

**No tiene variables de entorno. Tiene argumentos de construcción**, y esto no es un
detalle: `String.fromEnvironment` (`app/lib/nucleo/red/entorno.dart`) se resuelve **al
compilar**. Cambiar una URL en el Environment de Dokploy después de construir no cambia
absolutamente nada; hay que volver a construir. Es lo mismo que les pasa a las `VITE_*`
del front de notify.

| Build Arg | Por defecto | Qué es |
|---|---|---|
| `API_URL` | `https://reparto.procovar.cloud/api` | La base de la api **con `/api` incluido**. |
| `SYNC_URL` | `https://reparto.procovar.cloud/sync` | La base del sincronizador **con `/sync` incluido**. |
| `AUTH_URL` | `https://auth.procovar.cloud` | Accesos, que es de toda Procovar y puede mudarse sin las otras dos. |
| `BASE_HREF` | `/` | Sólo si la web cuelga de un subdirectorio. |
| `FLUTTER_VERSION` | `3.44.0` | `app/pubspec.lock` pide flutter `>=3.44.0` y dart `>=3.13.3`. |
| `GO_VERSION` (los tres de Go) | `1.27` | `go.mod` dice `go 1.27.0`. |
| `GOPROXY` (los cuatro de Go) | `https://proxy.golang.org,direct` | Por si la red del servidor lo bloquea. |
| `VERSION` (sólo api) | `dev` | Lo que devuelve `/version`. Pásale `git describe --tags --always`. |

Las tres URL las ve **el navegador**, no el contenedor: son las públicas, nunca
`http://api:8080`, que desde el navegador no existe.

### 3.5 migraciones

| Variable | Por defecto | Qué es |
|---|---|---|
| `DATABASE_URL_API` | — obligatoria | La base del reparto. |
| `DATABASE_URL_SYNC` | — obligatoria | La base del sincronizador. |
| `INTENTOS` | `30` | Cuántas veces espera a que Postgres conteste, 2 s cada una. |
| `ACCION` | `up` | `up` \| `status` \| `up-by-one` \| `down`. **`status` primero, siempre** (§2.4). `down` no se usa en producción. |

Y lo que no es una variable pero decide lo que se aplica: **los `.sql` van horneados en la
imagen** (`COPY api/db/migrations/ /migraciones/api/`), así que una imagen construida hace
días trae las migraciones de hace días. Por eso el procedimiento monta encima las del árbol
de hoy con `-v … :/migraciones/api:ro` — §2.3.

---

## 4. En qué orden se levantan

```
1. postgres          hasta que pg_isready conteste
2. migraciones       las DOS bases; tiene que TERMINAR BIEN
3. api               es el dueño de los datos; todo lo demás le habla a ella
4. espejo  y  sync   en cualquier orden, los dos necesitan la api
5. app               sólo estáticos; puede subir cuando quiera
```

Por qué ese orden y no otro:

- **La api antes que el espejo**, porque el espejo manda sus lotes a `/api/quote/batch`.
  Si la api no está, el ciclo falla y lo dice, y vuelve a intentarlo al minuto: no se
  pierde nada, pero el primer minuto de registro se llena de errores que no lo son.
- **La api antes que el sync**, porque el sincronizador no tiene datos propios: todo lo
  que reparte se lo pide a la api.
- **La app la última o la primera, da igual**: son ficheros estáticos. Lo que no puede es
  estar construida contra unas URL y desplegada contra otras.

En `docker-compose.yml` esto está encadenado con `depends_on` y el `healthcheck` de
Postgres; no hace falta hacer nada a mano:

```bash
docker compose up --build        # levanta todo en ese orden
```

En Dokploy no hay `depends_on` y **no hay nada que encadene esto**: el orden lo pone quien
despliega, a mano. Migraciones con el procedimiento de **§2.1**, luego Deploy de la api,
luego los otros tres. Por qué no se puede automatizar con lo que Dokploy ofrece, en §2.9.

---

## 5. Cómo se comprueba que están vivos

Lo primero, siempre, lo que dice `docs/DOKPLOY-NUEVO-PROYECTO.md` Parte 7: **un build que
falla deja el contenedor anterior en pie**, así que un 200 no demuestra que desplegaste.
Confirmar en el registro que el contenedor nuevo arrancó.

### api

`/health` y `/version` van **sin sesión** a propósito: el desplegador sondea la salud sin
token y la APK lee la versión antes de entrar. `/health` no es «el proceso responde»:
hace ping a Postgres, así que un 200 significa que también llega a la base. Un 503 con el
proceso vivo es la base, no la api.

> **Ojo con dónde cuelga `/health`.** Es una ruta de la RAÍZ del servicio, no de `/api`.
> Con el reparto de dominios de §6 —la api en `/api` y la web en `/`— una petición a
> `https://reparto.procovar.cloud/health` **no llega a la api**: la atiende el nginx de la
> web, que contesta 200 y el `index.html`. Es decir, **el sondeo obvio da verde aunque la
> api esté caída**. Hay dos salidas y hay que elegir una:
>
> 1. Sondear por dentro de la red, que es lo que se hace aquí:
>
> ```bash
> ssh vps 'docker run --rm --network dokploy-network curlimages/curl:latest \
>            -s -o /dev/null -w "%{http_code}\n" http://reparto-api-XXXXXX:8080/health'
> ```
>
> 2. O añadirle a la Application de la api un dominio más con Path `/health` (Traefik da
>    prioridad a la ruta más específica). Si se hace, queda escrito aquí.
>
> Desde fuera, lo que **sí** llega a la api y sirve de latido es `/api/version`, que es la
> misma ruta de versión montada bajo el prefijo:
>
> ```bash
> curl -s https://reparto.procovar.cloud/api/version
> ```

Y en el registro del arranque, los cinco avisos que **no** impiden arrancar pero que hay
que leer al desplegar, porque cada uno es una cosa que no va a funcionar:

```
SERVICE_API_KEY vacía: las rutas de servicio quedan cerradas …
ORIGENES_PERMITIDOS vacío: el navegador no podrá llamar …
PEDIDO_API_URL vacía: no se le podrá contar a PEDIDO …
PROCOVAR_AUTH_SIGNING_KEY vacía: … no se podrán cotizar domicilios
APP_ULTIMA_VERSION vacía: /api/version no anuncia ninguna versión de la aplicación …
```

Si sale alguno y no era intencionado, falta una variable.

### sync

`/salud` es la única ruta sin sesión, y también hace ping a la base: 503 = la base no
contesta. Las cuatro rutas del protocolo (`/sync/aparato`, `/sync/bajada`,
`/sync/subida`, `/sync/estado`) exigen las cabeceras de identidad.

Le pasa lo mismo que a `/health` de la api: **`/salud` cuelga de la raíz del servicio, no
de `/sync`**, así que desde el dominio público no se llega. Se sondea por dentro:

```bash
ssh vps 'docker run --rm --network dokploy-network curlimages/curl:latest \
           -s http://reparto-sync-XXXXXX:8081/salud'
# {"estado":"bien"}
```

En local, donde el puerto sí está publicado:

```bash
curl -s localhost:8081/salud
```

Además, al arrancar registra lo que tiene, y eso es lo que hay que cotejar con lo que se
puso en el Environment (§3.3):

```
sincronizador escuchando  config=direccion=:8081 reparto=http://api:8080 identidad=cabeceras tope_bajada=500
```

### espejo — aquí no hay curl que valga

No tiene puerto. **«El contenedor está corriendo» no es una comprobación**: un espejo que
lleva dos horas girando contra un 401 está corriendo y no ha traído nada.

**1. Que el ciclo pasa.** Cada vuelta deja rastro; el registro es lo primero:

```bash
docker service logs reparto-espejo-isgzxg --tail 50 --follow
```

**2. Que los datos entran, que es lo único que importa.** En la base del reparto:

```sql
SELECT count(*)                  AS pedidos,
       max(pedido_updated_at)    AS marca_de_agua,
       max(updated_at)           AS ultimo_toque
FROM orders
WHERE source = 'pedido';
```

`marca_de_agua` es el `since` de la próxima bajada y **se deriva de los datos**, no de un
contador aparte. Se mira dos veces con unos minutos de diferencia:

- `pedidos` sube y `marca_de_agua` avanza → el espejo trae.
- `ultimo_toque` avanza y `marca_de_agua` no → está repasando lo de siempre y no le llega
  nada nuevo de PEDIDO. Puede ser normal (una noche) o puede ser que PEDIDO no esté
  tocando `updatedAt`.
- nada se mueve en veinte minutos con el proceso vivo → **está roto aunque parezca sano**.
  Mirar el registro: 401 es `SERVICE_API_KEY`, error de red es `PEDIDO_API_URL`.

**3. Una pasada a mano**, que es la forma rápida de ver qué pasa sin esperar al ciclo:

```bash
docker run --rm --network dokploy-network --env-file /ruta/al/env reparto-espejo --once
```

Hace una sola pasada, la cuenta entera en el registro, y se va.

### app

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://reparto.procovar.cloud/nginx-salud
```

Eso sólo dice que nginx sirve. Lo que hay que comprobar de verdad, en el navegador:

1. La página abre y **no se queda en blanco**.
2. En la consola no hay un 404 de `sqlite3.wasm` ni de `drift_worker.js`. Si falta uno,
   la aplicación arranca y **la base local no**; el `Dockerfile.app` lo comprueba al
   construir para que falle ahí y no en la pantalla de alguien que ya no tiene conexión.
3. La aplicación no muestra el aviso de **«la base cayó a memoria»**. Si lo muestra, al
   recargar la pestaña se pierde todo lo que no se haya subido — que en una aplicación
   que existe para trabajar sin conexión no es un detalle.
4. Las llamadas salen a la URL buena. Si salen a `reparto.procovar.cloud` estando en
   pruebas, es que se construyó sin los Build Args.

---

## 6. Dokploy

Cuatro Applications en el proyecto **Procovar-dev** (`Fpt1-2Miy6SpzwoGDBEVB`), entorno
`production` (`hgKnOJXZWZU8el7I7T4tR`), todas con Build Type **Dockerfile**, Provider Git,
rama **`main`**, y **Docker Context Path `.`** (el contexto es la raíz).

> El nombre del proyecto engaña: **`Procovar-dev` ES producción**
> (`procovar/docs/VPS-179.198.107.1.md`). Ahí viven pedidos, auth, delivery y rutas con sus
> dominios públicos.

| Application | `applicationId` | Dockerfile Path | Container Port | Dominio |
|---|---|---|---|---|
| `reparto-api` | `0iQ8gLv5ZIHD1n_DRlzOa` | `deploy/Dockerfile.api` | 8080 | `reparto.procovar.cloud` path `/api` |
| `reparto-espejo` | `X0mtoCkFtThgp15BOYqpn` | `deploy/Dockerfile.espejo` | — | **ninguno** |
| `reparto-sync` | `cL2fUM3oqIbQ0wEsMk4rz` | `deploy/Dockerfile.sync` | 8081 | `reparto.procovar.cloud` path `/sync` |
| `reparto-web` | `LNwUtx-ck325iAEB-rKyZ` | `deploy/Dockerfile.app` | 8080 | `reparto.procovar.cloud` path `/` |

**Y no hay una quinta para las migraciones**, que es la pregunta que siempre vuelve: el
porqué entero está en §2.9.

### 6-bis. La Application del espejo, paso a paso

Es la única de las cuatro que no se parece a nada de lo que ya hay montado, y por eso está
escrita entera. **Sí es una Application** —el espejo da vueltas y no termina, §2-bis— pero
es la que más fácil se configura mal, porque todo lo que en las otras se rellena, aquí se
deja vacío.

Antes de crearla, **mirar si ya está**. Crear una segunda deja **dos espejos barriendo a
PEDIDO a la vez**, y eso no da ningún error: da el doble de carga sobre PEDIDO y dos
procesos escribiendo las mismas filas.

```bash
ssh vps 'K=<la clave de .secretos/vps-nuevo>; curl -s -H "x-api-key: $K" \
  "http://127.0.0.1:3000/api/application.one?applicationId=X0mtoCkFtThgp15BOYqpn" | head -c 400'
```

Los valores, uno por uno:

| Campo de Dokploy | Valor | Por qué |
|---|---|---|
| Proyecto / entorno | `Procovar-dev` / `production` | Donde están las otras tres. |
| Name | `reparto-espejo` | Dokploy le añade su sufijo (`reparto-espejo-isgzxg`); ése es el nombre por el que lo llaman los demás. |
| Build Type | **Dockerfile** | No Nixpacks. |
| Provider | Git · `github.com/jose22072000/delivery-logistica` · rama **`main`** | La misma que las otras tres. |
| **Dockerfile Path** | `deploy/Dockerfile.espejo` | |
| **Docker Context Path** | **`.`** | **No se deja vacío.** El Dockerfile vive en `deploy/` pero hace `COPY api/`, así que el contexto es la raíz del repositorio. Con el campo vacío Dokploy usa la carpeta del Dockerfile y el build muere con `"/api": not found`. |
| **Command** | **vacío** | Ver abajo: aquí es donde se rompe. |
| **Container Port** | **ninguno** | No escucha en nada. Si algún día aparece un puerto aquí, es que algo se torció. |
| **Dominio** | **ninguno** | No es un servidor. |
| Sondeo de salud | **ninguno** | No hay `/health` al que llamar, y «el proceso vive» no dice nada: un espejo girando contra un 401 lleva dos horas sano. |
| Réplicas | **1** | Dos espejos barren lo mismo dos veces. |

**El Command se deja VACÍO, y en particular NADA de `--once`.** Con esa bandera el espejo
hace una pasada, sale con 0, Dokploy lo relevanta, y queda un bucle de reinicios que desde
el panel se lee como «el espejo se estrella» — y que además **machaca a PEDIDO con la
pasada entera cada vez**. El ciclo ya lo lleva el proceso dentro, cada minuto
(`SYNC_POLL_MS`). `--once` sirve para dos cosas y sólo dos: probar a mano (§5) y un
`docker run` suelto desde el servidor.

**Las cinco variables, y son CINCO** (la lista completa con sus topes, en §3.2):

```
DATABASE_URL=postgres://<usuario>:<clave>@procovar-postgres-nlfols:5432/procovar_reparto
SERVICE_API_KEY=<LA MISMA que reparto-api>
PEDIDO_API_URL=http://pedido-api-zcuspu:<puerto>
DELIVERY_URL=http://reparto-api-xzlmhw:8080
ENTORNO=produccion
```

Las tres trampas de esas cinco, y las tres ya pasaron:

- **`SERVICE_API_KEY` distinta de la de la api**: el espejo arranca, le pide los pedidos a
  PEDIDO y **se come un 401 al meterlos**. Los trae y no los guarda, sin que nadie lo vea.
- **`DELIVERY_URL` vacía**: «vacía = a mí mismo» es una regla de la api, y **esto no es la
  api**. Y va con el **appName completo**, con su sufijo: `reparto-api` a secas no
  resuelve.
- **`ENTORNO` olvidada**: es la que faltó durante cuatro días (22/09/2026). No rompe nada,
  pero el registro sale en texto plano en vez de JSON, y el registro es **el único sitio
  donde se mira si el espejo va**. Lo que hay que llevarse de ahí no es la variable: es que
  **una Application que lleva días en `done` puede estar incompleta**. Al tomar una que ya
  existe se cotejan sus variables con esta lista antes de dar nada por bueno.

**Y no se da por creada hasta comprobar que TRAE DATOS**, que no es lo mismo que que el
contenedor corra. Se hace como dice §5: la consulta de la marca de agua, **dos veces con
unos minutos de diferencia**. Así se comprobó el 22/09/2026 — 13:52:40 leído a las 13:54Z y
13:59:38 a las 14:01Z, con los pedidos subiendo de 4.069 a 4.071. El contenedor corriendo
no habría demostrado nada.

> **Estado al 23/09/2026.** `docs/montar-en-dokploy.md` da esta Application por **creada y
> corriendo** desde el 22/09/2026, con estos mismos valores y ya redesplegada con
> `ENTORNO=produccion`. Si eso es así, aquí no hay nada que crear: lo que queda es **cotejar
> sus cinco variables contra la lista de arriba** y volver a hacer la comprobación de la
> marca de agua. Esta sección se escribe igual porque es la que hace falta el día que haya
> que rehacerla, y porque hasta hoy esos valores sólo estaban en la cabeza de quien la
> montó.

Los tres dominios son el mismo host con rutas distintas; los de la api y el sincronizador
van **antes** que el de la web, y **Strip Path en `no`** en los dos: las rutas de la api
ya se llaman `/api/...` y las del sincronizador `/sync/...`. Quitarles el prefijo las
dejaría sin encontrar.

> **Ninguna pantalla de la aplicación puede llamarse `/api…` ni `/sync…`.** Esos dos
> prefijos se los queda el proxy antes de que la web vea nada, así que una pantalla ahí
> funciona navegando por el menú —eso lo resuelve el enrutador dentro del navegador— y
> **falla al recargar o al abrir el enlace**, que es cuando sí hay una petición al
> servidor. Pasó con la pantalla de Sincronización, que vivía en `/sync`: recargar ahí
> devolvía un `401` del sincronizador. Se movió a `/sincronizacion`; el prefijo no se
> toca, porque es la dirección que ya usan las APK instaladas para subir y bajar.
>
> Y es prefijo de **cadena**, no de segmento: `PathPrefix(`/sync`)` atrapa `/sync-estado`
> igual que `/sync`. Lo vigila la prueba «ninguna ruta invade un camino del proxy» de
> `app/test/navegacion/contrato_registro_test.dart`.

Con ese reparto, `/health` de la api y `/salud` del sincronizador **quedan fuera del
dominio**: cuelgan de la raíz de cada servicio y la raíz pública es la web. El sondeo se
hace por dentro de la red, o se les añade su propio Path; está explicado en §5.

Los servicios se llaman entre sí por su **appName** (el nombre con el sufijo que pone
Dokploy), nunca por `localhost`:

```
# en reparto-espejo
DELIVERY_URL=http://reparto-api-XXXXXX:8080
# en reparto-sync
REPARTO_URL=http://reparto-api-XXXXXX:8080
```

Las tres URL de la web van en **Build Args**, no en Environment (§3.4).

Y lo que no se hace: no se crea un Postgres nuevo (hay uno para toda la casa, con muchas
bases dentro), no se publican puertos al host, y los secretos no van al repositorio.

### Los eventos en vivo, a través de Traefik

`GET /api/eventos` es SSE, y eso tiene tres cosas que ya costaron una vuelta y están
escritas en `api/internal/api/eventos.go`: el latido (una conexión callada la corta el
proxy al minuto), la cabecera `X-Accel-Buffering: no` (sin ella el proxy guarda los
eventos y los suelta en bloque) y **nunca** `Connection: keep-alive` (con Cloudflare
delante da `ERR_QUIC_PROTOCOL_ERROR`). Las manda el propio servicio; lo que hay que
vigilar al desplegar es que nadie ponga delante un proxy que amortigüe la respuesta ni un
tiempo de espera corto para esa ruta.

---

## 7. Antes del primer despliegue

Cosas comprobadas en el repositorio que **hoy impiden que un clone limpio construya**, y
que no se arreglan desde los ficheros de despliegue:

1. ~~**Media aplicación de Flutter no está en git.**~~ — **ya no (comprobado el
   15/09/2026).** Están todos seguidos: `app/lib/pantallas/` (73 ficheros),
   `app/lib/diseno/` (11), `app/lib/textos/` (6), `app/assets/` (2) y `app/l10n.yaml` (1),
   según `git ls-files`. Queda escrito porque era el punto de la Parte 0 de
   `DOKPLOY-NUEVO-PROYECTO.md` y lo que hay que saber es que ese ya no frena el clone.
2. ~~**El repositorio no tiene remoto** y la rama es `master`.~~ — **ya no (23/09/2026).**
   El remoto es `github.com/jose22072000/delivery-logistica` y la rama es **`main`**, que es
   de la que tiran las cuatro Applications. Queda escrito porque el resto del documento
   decía `dev` y el proyecto `PROCOVAR-DEV`, y las dos cosas eran falsas.
3. **`app/android/build/` está seguido en git** y no debería: son artefactos. `.gitignore`
   ignora `/app/build/` pero no ése.
4. **`GET /api/sync/cambios` todavía no existe en la api.** Es lo que le pide la bajada
   del sincronizador, así que **`GET /sync/bajada` contesta 502** hasta que esté. El
   servicio arranca y está sano: es una ruta que falta, no un fallo de despliegue. Está
   documentado en `sync/README.md`.
5. **La etiqueta de la imagen de Flutter hay que confirmarla.** `Dockerfile.app` pincha
   `ghcr.io/cirruslabs/flutter:3.44.0` porque `pubspec.lock` pide `>=3.44.0`. Si esa
   etiqueta no existe, se ajusta con `--build-arg FLUTTER_VERSION=…` y se deja escrita la
   que sea.

## 8. Lo que no se ha podido comprobar aquí

*Revisado el 15/09/2026. Lo de antes decía que Flutter no estaba instalado en este equipo:
ya no es verdad, y por eso media tabla es nueva.*

**Las cinco imágenes SIGUEN SIN CONSTRUIRSE.** El demonio de Docker sí está ahora en
marcha —`systemctl start docker` lo levanta **sin contraseña**, por polkit, porque el
usuario está en `wheel`—, pero eso no basta: el socket `/var/run/docker.sock` es
`root:docker` y **el grupo `docker` no tiene ni un miembro** (`getent group docker` →
`docker:x:967:`). El cliente contesta `permission denied while trying to connect to the
Docker API`. Entrar en el grupo es `usermod -aG docker`, que pide root, y `sudo` pide
contraseña. Tampoco hay Docker rootless (no están `rootlesskit` ni
`dockerd-rootless-setuptool.sh`) ni `podman`. **Así que `docker build` no se ha ejecutado
todavía y esto sigue diciendo «no comprobado».**

> Meter a un usuario en el grupo `docker` es darle root sin contraseña por la puerta de al
> lado. Es una decisión de Jose, no algo que se hace de paso para poder construir.

Lo que sí se comprobó, y con qué:

| Comprobado | Cómo |
|---|---|
| Los tres binarios de Go compilan estáticos, con las mismas órdenes del Dockerfile | `CGO_ENABLED=0 go build -trimpath -ldflags="-s -w"` sobre `./cmd/api`, `./cmd/espejo` y `./cmd/sync`; `file` dice `statically linked` en los tres |
| La versión de Go que pincha el Dockerfile es la del código | `GO_VERSION=1.27`, y `api/go.mod` y `sync/go.mod` piden `go 1.27.0` |
| La línea de goose de `Dockerfile.migraciones` | `go install github.com/pressly/goose/v3/cmd/goose@v3.28.0` → `goose version: v3.28.0` |
| Las dos series de migraciones las entiende goose | `goose -dir api/db/migrations validate` y `goose -dir sync/db/migrations validate` |
| `docker-compose.yml` es válido y las variables resuelven | `docker compose config` (no necesita el demonio) |
| `deploy/migrar.sh` no tiene errores de sintaxis | `sh -n` |
| Todas las rutas que copian los Dockerfile existen | `api/cmd/api`, `api/cmd/espejo`, `sync/cmd/sync`, `api/db/migrations`, `sync/db/migrations`, `deploy/migrar.sh` y los dos `go.sum` |
| **`flutter build web` TERMINA** | las mismas banderas del `Dockerfile.app` (`--release --no-web-resources-cdn --base-href / --dart-define=…`); 90 s y `✓ Built build/web` |
| **Las dos comprobaciones que el `Dockerfile.app` hace fallar el build pasan** | `build/web/sqlite3.wasm` y `build/web/drift_worker.js` están los dos |
| CanvasKit queda DENTRO y no se baja de gstatic | `--no-web-resources-cdn` deja `build/web/canvaskit/` |
| La capa de dependencias del `Dockerfile.app` se sostiene | `flutter pub get` en una carpeta vacía con SÓLO `pubspec.yaml` y `pubspec.lock` → `Got dependencies!`. Era la duda razonable: con `generate: true` podía pedir el `l10n.yaml` y los `.arb`, que en esa capa aún no están. No los pide |
| El puerto de nginx cuadra con el `EXPOSE` | `deploy/nginx.conf` → `listen 8080` |

**Sigue sin comprobarse, y hace falta `docker build` para ello:**

1. **Que las etiquetas de las imágenes base existan y se puedan bajar**: `golang:1.27-alpine`,
   `gcr.io/distroless/static-debian12:nonroot`, `alpine:3.20`, `nginx:1.27-alpine` y sobre
   todo **`ghcr.io/cirruslabs/flutter:3.44.0`**, que ya estaba en duda en §7.5.
2. **Que el `.dockerignore` no deje fuera nada que el build necesite.**
3. **Que el binario arranque dentro de `distroless:nonroot`** — que compile estático no
   dice que `/app/api` corra como `nonroot`.
4. ~~**Que las migraciones se apliquen contra un Postgres de verdad**: aquí no hay ninguno
   levantado.~~ — **en este PC sigue sin poder comprobarse, pero ya no hace falta: están
   aplicadas en producción.** Las dos series corrieron contra el Postgres del VPS y
   dejaron 16 tablas en la base del reparto y 5 en la del sincronizador
   (`docs/montar-en-dokploy.md`, 22/09/2026). El procedimiento con el que se hace, en §2.1.

**Y una advertencia que vale para toda esta sección §8: lo que no se ha comprobado *aquí*
no es lo mismo que lo que no se ha comprobado.** Las cinco imágenes construyen —lo hacen en
el servidor en cada Deploy— y los cuatro servicios están corriendo. Lo que sigue sin
poderse hacer es construirlas **en este portátil**, por lo del grupo `docker`.

Un matiz del de Flutter: el build de aquí salió con **Flutter 3.47.4**, que es el de este
portátil, y el `Dockerfile.app` pincha **3.44.0**. Prueba que el código compila para web;
**no** prueba que esa etiqueta concreta compile.

Lo primero que hay que hacer en una máquina con Docker es esto, y en este orden:

```bash
docker compose build          # las cinco imágenes
docker compose up             # y mirar que la migración termine antes que nada arranque
curl -s localhost:8080/health
curl -s localhost:8081/salud
docker compose logs -f espejo
```
