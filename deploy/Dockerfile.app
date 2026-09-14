# reparto-app — LA INTERFAZ, compilada a web y servida como ficheros estáticos.
#
# Dos etapas: el SDK de Flutter (unos 2 GB) compila, y de ahí sale una carpeta de
# ficheros que sirve nginx. En la imagen final no queda ni Flutter, ni Dart, ni el
# código fuente.
#
# EL CONTEXTO ES LA RAÍZ DEL REPO (este fichero vive en deploy/ y el código en app/):
#
#   docker build -f deploy/Dockerfile.app -t reparto-app \
#     --build-arg API_URL=https://reparto.procovar.cloud/api \
#     --build-arg SYNC_URL=https://reparto.procovar.cloud/sync \
#     --build-arg AUTH_URL=https://auth.procovar.cloud .
#
# En Dokploy:  Dockerfile Path = deploy/Dockerfile.app  ·  Docker Context Path = .
#              y las tres URL van en BUILD ARGS, no en Environment.
#
# LAS TRES URL SE HORNEAN AL COMPILAR. `String.fromEnvironment` (app/lib/nucleo/red/
# entorno.dart) se resuelve en tiempo de compilación: cambiar la variable en Dokploy
# después no cambia nada, hay que volver a construir. Es lo mismo que les pasa a las
# `VITE_*` del front de notify, y está avisado en docs/DOKPLOY-NUEVO-PROYECTO.md.

# La versión del SDK va PINCHADA. app/pubspec.lock pide flutter >=3.44.0 y dart >=3.13.3:
# una imagen más vieja no resuelve las dependencias, y «la última» compila distinto cada
# mes, que es lo que app/pubspec.yaml evita a propósito fijando las versiones sin `^`.
ARG FLUTTER_VERSION=3.44.0

FROM ghcr.io/cirruslabs/flutter:${FLUTTER_VERSION} AS build
WORKDIR /app

# Dependencias primero: la capa se cachea y no se rehace en cada cambio de pantalla.
COPY app/pubspec.yaml app/pubspec.lock ./
RUN flutter pub get

# El resto del código. `lib/textos/generado` lo escribe gen_l10n solo durante el build
# (app/pubspec.yaml: `generate: true` + l10n.yaml), así que no hace falta traerlo hecho.
COPY app/ .

# Las tres URL. Los valores por defecto son los de producción, los mismos que están
# escritos en entorno.dart: si alguien construye sin argumentos, sale la de verdad y no
# un localhost que en el servidor no existe.
ARG API_URL=https://reparto.procovar.cloud/api
ARG SYNC_URL=https://reparto.procovar.cloud/sync
ARG AUTH_URL=https://auth.procovar.cloud

# Si la web cuelga de un subdirectorio (p. ej. /reparto/), esto tiene que decirlo.
ARG BASE_HREF=/

# `--no-web-resources-cdn` deja CanvasKit DENTRO de la imagen en vez de bajarlo de
# gstatic.com al abrir la página. En la conexión de allá eso son unos megas menos por
# cada aparato y una dependencia menos de una red que unos días no está.
RUN flutter build web --release \
      --no-web-resources-cdn \
      --base-href "${BASE_HREF}" \
      --dart-define=API_URL="${API_URL}" \
      --dart-define=SYNC_URL="${SYNC_URL}" \
      --dart-define=AUTH_URL="${AUTH_URL}"

# `sqlite3.wasm` y `drift_worker.js` son FICHEROS DEL DESPLIEGUE (app/lib/nucleo/base/
# conexion/conexion_web.dart lo dice con esas palabras): si falta uno, la aplicación
# arranca y la base NO. Que el build falle aquí es mucho mejor que descubrirlo en la
# pantalla de alguien que ya no tiene conexión para recargar.
RUN test -f build/web/sqlite3.wasm     || (echo "FALTA sqlite3.wasm en build/web"     && exit 1)
RUN test -f build/web/drift_worker.js  || (echo "FALTA drift_worker.js en build/web"  && exit 1)

FROM nginx:1.27-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html

# 8080 y no 80: es el Container Port que se pone en el dominio de Dokploy.
EXPOSE 8080
