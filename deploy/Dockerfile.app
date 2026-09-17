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

# El SDK se trae del repositorio OFICIAL de Flutter, pinchado por etiqueta.
#
# # Por qué no una imagen ya hecha
#
# Antes esto usaba `ghcr.io/cirruslabs/flutter:3.44.0`. Falló al construir, después de
# media hora bajando sus 794 MB:
#
#     Because reparto requires SDK version ^3.13.3, version solving failed.
#
# El proyecto pide Dart ^3.13.3 y esa imagen trae uno más viejo. Y comprobado el
# 15/09/2026, de esa familia **sólo existen `3.44.0` y `stable`**: no hay 3.45, ni 3.46,
# ni la 3.47.4 que usa el proyecto. Van por detrás de Flutter.
#
# `stable` resolvería hoy y es lo que NO se puede hacer: es una etiqueta móvil, así que la
# imagen cambia bajo los pies y reconstruir esto dentro de seis meses daría algo distinto
# sin que nadie tocara una línea. Es justo lo que `app/pubspec.yaml` evita fijando las
# versiones sin `^`.
#
# Clonando el repositorio oficial por etiqueta, la versión la decidimos nosotros y es
# exactamente la que se usa para desarrollar. `--depth 1` de una sola etiqueta trae lo
# justo.
ARG FLUTTER_VERSION=3.47.4

FROM debian:bookworm-slim AS build
# Lo que pide el SDK para compilar para web, y nada más.
RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl unzip xz-utils ca-certificates \
 && rm -rf /var/lib/apt/lists/*
ARG FLUTTER_VERSION
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git /sdk
ENV PATH="/sdk/bin:/sdk/bin/cache/dart-sdk/bin:${PATH}"
# `git config` porque el SDK se queja de ser un repositorio de otro dueño dentro de la
# imagen, y se para antes de hacer nada.
RUN git config --global --add safe.directory /sdk && flutter --version
WORKDIR /app

# Dependencias primero: la capa se cachea y no se rehace en cada cambio de pantalla.
COPY app/pubspec.yaml app/pubspec.lock ./
RUN flutter pub get

# El resto del código. `lib/textos/generado` lo escribe gen_l10n solo durante el build
# (app/pubspec.yaml: `generate: true` + l10n.yaml), así que no hace falta traerlo hecho.
COPY app/ .

# LAS PRUEBAS, ANTES DE CONSTRUIR. Como en `Dockerfile.api` y `Dockerfile.sync`.
#
# El 16/09/2026 una mutación de prueba llegó a producción porque el Dockerfile del
# sincronizador sólo compilaba. Se arregló ahí y en la api, y **aquí se quedó sin
# arreglar**: la web se construía sin pasar una sola prueba. O sea, el mismo
# agujero por el que ya se coló una vez, abierto en el otro lado.
#
# `analyze` además de `test` porque son cosas distintas: `analyze` caza el código
# que no compila en un destino aunque las pruebas no lo toquen.
#
# `timeout 600` porque un contenedor sin pantalla es más lento que esta máquina, y
# una prueba colgada no puede dejar el build corriendo para siempre.
# LOS TEXTOS GENERADOS, ANTES DE ANALIZAR. Sin esto la imagen NO CONSTRUYE.
#
# `.dockerignore` excluye `app/lib/textos/generado/` y `lib/textos/textos.dart`
# lo importa, así que dentro de la imagen ese directorio no existe. Antes daba
# igual porque el primer mandato tras el `COPY` era `flutter build web`, **y ése
# sí genera l10n**. `flutter analyze` no: se queda en 11 errores de
# «Target of URI doesn't exist: 'generado/textos.dart'».
#
# O sea: el `analyze` que se añadió aquí para que no se escapara nada habría
# roto todos los despliegues de la web. Lo cazó el auditor reproduciendo la
# secuencia del Dockerfile paso a paso, no leyéndola.
RUN flutter gen-l10n

RUN flutter analyze
RUN timeout 600 flutter test

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

# LA HUELLA, que es lo que hace que la caché deje de adivinar.
#
# Flutter llama a su código `main.dart.js` SIEMPRE IGUAL, en cada compilación: misma
# dirección, contenido distinto. Cualquier caché del mundo —el navegador, Cloudflare, el
# proxy de una oficina— tiene derecho a quedarse con la vieja, porque nadie le dijo que
# cambió. Eso pasó el 16/09: los cuatro servicios desplegados, el servidor sirviendo el
# fichero nuevo, y la pantalla enseñando la aplicación del día anterior.
#
# La salida NO es prohibir la caché: es que el nombre cambie cuando cambia el contenido.
# Se le pega a cada petición la huella del PROPIO fichero, así que:
#
#   * si el código no cambió, la dirección es la misma y la caché lo sirve al instante
#     —que con la conexión de allá es justo lo que se quiere—;
#   * si cambió, la dirección es otra y NO PUEDE servirse una copia vieja, porque de esa
#     dirección nadie tiene ninguna.
#
# `index.html` se queda sin cachear (`deploy/nginx.conf`) y es el único sitio donde vive
# la huella: se pide siempre, y de él sale la dirección buena de todo lo demás.
#
# EL FAVICON ENTRA TAMBIÉN, y no por simetría. El 16/09 se cambió el icono de Flutter por
# el de Procovar, el servidor servía el nuevo —mismo md5 que el del repo, comprobado— y en
# la pestaña seguía saliendo el de Flutter. El favicon es la caché más terca de un
# navegador: se lo guarda casi ignorando las cabeceras y ni una recarga forzada lo tira
# siempre. Con la huella en la dirección no hay nada que tirar: es otro fichero.
#
# Es md5 del contenido y no la fecha ni el commit a propósito: dos compilaciones del mismo
# código dan la MISMA huella, así que un redespliegue que no cambia nada no obliga a nadie
# a volver a bajarse cinco megas.
RUN set -eu; \
    H=$(md5sum build/web/main.dart.js | cut -c1-12); \
    sed -i "s#flutter_bootstrap\.js#flutter_bootstrap.js?v=$H#g" build/web/index.html; \
    sed -i "s#main\.dart\.js#main.dart.js?v=$H#g" build/web/flutter_bootstrap.js; \
    sed -i "s#href=\"favicon\.png\"#href=\"favicon.png?v=$H\"#g" build/web/index.html; \
    sed -i "s#href=\"icons/Icon-192\.png\"#href=\"icons/Icon-192.png?v=$H\"#g" build/web/index.html; \
    echo "huella de esta compilacion: $H"; \
    for marca in "flutter_bootstrap.js?v=$H" "favicon.png?v=$H"; do \
      grep -q "$marca" build/web/index.html \
        || (echo "NO se pudo poner la huella de $marca en index.html" && exit 1); \
    done; \
    grep -q "main.dart.js?v=$H" build/web/flutter_bootstrap.js \
      || (echo "NO se pudo poner la huella en flutter_bootstrap.js" && exit 1)

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
