# Montar el reparto en Dokploy

Todo lo que se puede preparar desde fuera ya está hecho. Esto es lo que queda, y es
pegar en la interfaz de Dokploy.

**Estado al 15/09/2026:**

- [x] Repositorio: `github.com/jose22072000/delivery-logistica`, rama `main`
- [x] Bases creadas en el Postgres del VPS: `procovar_reparto` y `procovar_reparto_sync`
- [x] Migraciones aplicadas: 16 tablas y 5 tablas
- [x] Las cinco imágenes construyen
- [ ] **Los servicios en Dokploy** ← esto
- [ ] Redesplegar `auth` con los endpoints de token

## El dominio

**`reparto.procovar.cloud`**, y es definitivo. `delivery.procovar.cloud` redirigirá aquí
cuando se apague el viejo.

No es capricho de nombre: **la URL va horneada dentro de la web y del APK** (es un
`--build-arg`, no una variable de entorno). Cambiarla después obliga a recompilar y a
**reinstalar los diez aparatos**. Por eso se elige una vez y no se toca.

## Los cuatro servicios

Todos del mismo repositorio, rama `main`, con su Dockerfile y **el contexto en la raíz**.

| Servicio | Dockerfile | Puerto | Dominio |
|---|---|---|---|
| `reparto-api` | `deploy/Dockerfile.api` | 8080 | `reparto.procovar.cloud/api` |
| `reparto-sync` | `deploy/Dockerfile.sync` | 8080 | `reparto.procovar.cloud/sync` |
| `reparto-espejo` | `deploy/Dockerfile.espejo` | — | **ninguno** |
| `reparto-web` | `deploy/Dockerfile.app` | 8080 | `reparto.procovar.cloud` |

**El espejo no lleva dominio ni puerto**: es un proceso de fondo, no un servidor. Su salud
no se mide con `/health` sino por si sigue trayendo pedidos.

## Las variables

### `reparto-api`

```
DATABASE_URL=postgres://<usuario>:<clave>@<host-postgres>:5432/procovar_reparto
JWT_SECRET=<el de .secretos/reparto-jwt.txt>
PUERTO=8080
ENTORNO=produccion
ORIGENES_PERMITIDOS=https://reparto.procovar.cloud
PEDIDO_API_URL=<la interna de pedido-api>
SERVICE_API_KEY=<la misma que usa delivery hoy>
PROCOVAR_AUTH_URL=https://auth.procovar.cloud
PROCOVAR_AUTH_CLIENT_ID=reparto
PROCOVAR_AUTH_SIGNING_KEY=<la que dé auth para este cliente>
```

**`JWT_SECRET` tiene que ser el MISMO que se le ponga a `auth`.** Si no, el logístico
entra en auth y la API le contesta 401 sin decir por qué.

`PUERTO` se llama así, en español — no `PORT`.

### `reparto-sync`

```
DATABASE_URL=postgres://<usuario>:<clave>@procovar-postgres-nlfols:5432/procovar_reparto_sync
REPARTO_URL=http://reparto-api-xzlmhw:8080
REPARTO_API_KEY=<la de PEDIDO, ver abajo>
SYNC_IDENTIDAD=cabeceras
JWT_SECRET=<el mismo>
PUERTO=8080
```

Se llama **`REPARTO_URL`**, no `REPARTO_API_URL`. Y las tres de abajo son obligatorias: sin
ellas el servicio **se niega a arrancar** y dice cuáles faltan, que es lo correcto.

### `reparto-espejo`

```
DATABASE_URL=<la misma que reparto-api>
PEDIDO_API_URL=<la interna de pedido-api>
DELIVERY_URL=http://reparto-api:8080
SERVICE_API_KEY=<la misma>
```

### `reparto-web`

No lleva variables de entorno: sus URL van **horneadas al construir**, como argumentos:

```
API_URL=https://reparto.procovar.cloud/api
SYNC_URL=https://reparto.procovar.cloud/sync
AUTH_URL=https://auth.procovar.cloud
```

## De dónde se sacan los valores — esto es lo que más tiempo cuesta

**No los copies de `.secretos/delivery_env_local.txt`.** Ese fichero es la configuración de
DESARROLLO y engaña: su `PEDIDO_API_URL` es `http://localhost:8400`, que dentro de un
contenedor es el contenedor mismo, y su `SERVICE_API_KEY` **no es la de producción**. Los
dos fallos costaron seis intentos el 15/09/2026.

Se leen del contenedor que ya funciona, y así el valor nunca sale del servidor:

```
docker exec $(docker ps -qf name=pedido-api    | head -1) printenv SERVICE_API_KEY
docker exec $(docker ps -qf name=procovar-postgres | head -1) printenv POSTGRES_USER POSTGRES_PASSWORD
```

**Los servicios se llaman entre sí por su nombre COMPLETO de Dokploy**, con su sufijo:
`reparto-api-xzlmhw`, `pedido-api-zcuspu`, `procovar-postgres-nlfols`. `reparto-api` a
secas no resuelve. Se ven con `docker service ls`.

La clave de firma de Accesos se **deriva**, no se inventa:

```
S=$(docker exec $(docker ps -qf name=procovar-auth | head -1) printenv SERVICE_AUTH_SECRET)
printf 'svc:reparto' | openssl dgst -sha256 -hmac "$S" -hex
```

Y antes hay que dar de alta el cliente en `client_app` de `procovar_auth`, con los mismos
permisos que `delivery`: `callback:create` y `session:verify`.

## El contexto de construcción

**`dockerContextPath` tiene que ser `.`**, no vacío. Los Dockerfile viven en `deploy/` pero
hacen `COPY api/`, así que el contexto es **la raíz del repositorio**. Con el campo vacío
Dokploy usa la carpeta del Dockerfile y el build falla con `"/api": not found`.

En local no se nota porque `docker build -f deploy/Dockerfile.api .` lleva el contexto en
ese punto del final.

## Avisos

- **La primera construcción de la web tarda.** Clona el SDK de Flutter entero. Lánzala y
  déjala; no la mires esperando.
- **`reparto-api` va en UNA sola réplica.** Su bus de avisos en vivo es en memoria del
  proceso, así que con dos réplicas los avisos dejan de llegar a la mitad de la gente
  **sin dar ningún error**. Está dicho en la cabecera de `internal/api/eventos.go`.
- **El orden importa**: primero la api, después el sync y el espejo (los dos la
  necesitan), y la web al final.

## Lo último, y con cuidado

`auth` hay que redesplegarlo para que entren los tres endpoints de token y su
`JWT_SECRET`. **Es el servicio del que dependen todas las aplicaciones**: si ese
despliegue sale mal, se cae todo. Se hace en un momento tranquilo y mirando.
