# Despliegue

Cuatro piezas, dos bases y un contenedor que migra y se muere. Este documento dice qué
es cada una, qué necesita para arrancar, en qué orden se levantan y cómo se comprueba
que están vivas de verdad — no que el desplegador las haya pintado de verde.

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

## 2. Las migraciones: un contenedor aparte

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
sin miedo, y por eso el paso es seguro de automatizar.

**En local** lo encadena `docker-compose.yml`: los tres servicios dependen de
`migraciones` con `condition: service_completed_successfully`, así que ninguno arranca si
la migración no terminó bien.

**En Dokploy** las Applications son procesos largos y reinician lo que termina, así que
el trabajo de migración **no se despliega como Application**. Se corre a mano en el
servidor, antes del Deploy:

```bash
ssh vps
cd /tmp && git clone --depth 1 -b dev https://github.com/PROCOVAR-DEV/delivery-logistica.git m && cd m
docker build -f deploy/Dockerfile.migraciones -t reparto-migraciones .
docker run --rm \
  --network dokploy-network \
  -e DATABASE_URL_API='postgres://procovar:LA_PASS@procovar-postgres-nlfols:5432/reparto?sslmode=disable' \
  -e DATABASE_URL_SYNC='postgres://procovar:LA_PASS@procovar-postgres-nlfols:5432/reparto_sync?sslmode=disable' \
  reparto-migraciones
```

Imprime el `status` de las dos series al terminar. Si algo falla, **no se pulsa Deploy**.

Antes de la primera vez hay que crear las dos bases dentro del Postgres que ya existe
(`docs/DOKPLOY-NUEVO-PROYECTO.md`, Parte 4) y añadirlas a la lista `BASES` de
`/usr/local/bin/procovar-backup-db`:

```bash
C=$(docker ps -qf name=procovar-postgres-nlfols)
docker exec $C psql -U procovar -d postgres -c 'CREATE DATABASE "reparto" OWNER procovar;'
docker exec $C psql -U procovar -d postgres -c 'CREATE DATABASE "reparto_sync" OWNER procovar;'
```

Otras acciones del mismo contenedor, con `ACCION`:

```bash
docker run --rm ... -e ACCION=status reparto-migraciones   # sólo mirar, no escribe
```

`ACCION=down` existe porque goose lo tiene. **En producción no se usa**: deshacer una
migración sobre datos reales se decide mirando, no con una variable de entorno.

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
| `SYNC_IDENTIDAD` | Literalmente `cabeceras`. **No tiene valor por defecto a propósito**: hoy la identidad viene en `X-Persona`, `X-Sucursal` y `X-Super-Admin`, que pone el proxy de delante, y eso sólo es seguro si nadie más puede llegar a este puerto. Escribirlo a mano obliga a mirar esa frase antes de publicar el servicio. |

Con valor por defecto:

| Variable | Por defecto | Qué es |
|---|---|---|
| `SYNC_ADDR` | `:8081` | Dónde escucha. |
| `SYNC_DB_MAX_CONNS` | `10` | |
| `SYNC_TOPE_BAJADA` | `500` | Filas por tanda antes de contestar `truncado: true`. Existe porque la primera bajada de una sucursal grande no cabe de una vez en la conexión de allá. |
| `SYNC_REPARTO_TIMEOUT` | `30s` | |
| `SYNC_READ_TIMEOUT` | `15s` | |
| `SYNC_WRITE_TIMEOUT` | `60s` | Largo a propósito: un lote de un día entero se aplica apunte por apunte contra la api. |

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
| `ACCION` | `up` | `up` \| `status` \| `up-by-one` \| `down`. |

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

En Dokploy no hay `depends_on`: **el orden lo pone quien despliega**. Migraciones a mano
(§2), luego Deploy de la api, luego los otros tres.

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
docker service logs <appName-del-espejo> --tail 50 --follow
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

Cuatro Applications en el proyecto **Procovar**, todas con Build Type **Dockerfile**,
Provider Git, rama **`dev`**, y **Docker Context Path `.`** (el contexto es la raíz).

| Application | Dockerfile Path | Container Port | Dominio |
|---|---|---|---|
| `reparto-api` | `deploy/Dockerfile.api` | 8080 | `reparto.procovar.cloud` path `/api` |
| `reparto-espejo` | `deploy/Dockerfile.espejo` | — | **ninguno** |
| `reparto-sync` | `deploy/Dockerfile.sync` | 8081 | `reparto.procovar.cloud` path `/sync` |
| `reparto-app` | `deploy/Dockerfile.app` | 8080 | `reparto.procovar.cloud` path `/` |

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
2. **El repositorio no tiene remoto** (`git remote -v` está vacío) y la rama es `master`,
   no `dev`. Dokploy tira de un remoto y de una rama.
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
4. **Que las migraciones se apliquen contra un Postgres de verdad**: aquí no hay ninguno
   levantado.

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
