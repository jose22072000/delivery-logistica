#!/usr/bin/env bash
# Vuelve a sacar TODOS los iconos de la aplicacion a partir de los tres SVG de esta
# carpeta. Se ejecuta desde `app/`:   marca/generar.sh
#
# Los SVG son la fuente; los PNG son resultado y se pueden borrar y rehacer. Si hay que
# tocar el dibujo, se toca aqui y se vuelve a correr esto — no se retoca un PNG.
set -euo pipefail
cd "$(dirname "$0")/.."
M=marca

# La web. El favicon usa la silueta simple: a 16 px es lo unico que se lee.
rsvg-convert -w 32  -h 32  "$M/favicon.svg" -o web/favicon.png
rsvg-convert -w 192 -h 192 "$M/icono.svg"   -o web/icons/Icon-192.png
rsvg-convert -w 512 -h 512 "$M/icono.svg"   -o web/icons/Icon-512.png
rsvg-convert -w 192 -h 192 "$M/icono-maskable.svg" -o web/icons/Icon-maskable-192.png
rsvg-convert -w 512 -h 512 "$M/icono-maskable.svg" -o web/icons/Icon-maskable-512.png

# Android. Cada densidad su tamano; el lanzador recorta, asi que va el maskable.
for par in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  d="${par%%:*}"; n="${par##*:}"
  rsvg-convert -w "$n" -h "$n" "$M/icono-maskable.svg" \
    -o "android/app/src/main/res/mipmap-$d/ic_launcher.png"
done

# Windows: un .ico con los cuatro tamanos que pide el explorador.
tmp=$(mktemp -d)
for n in 16 32 48 256; do
  fuente="$M/icono.svg"; [ "$n" -le 32 ] && fuente="$M/favicon.svg"
  rsvg-convert -w "$n" -h "$n" "$fuente" -o "$tmp/$n.png"
done
magick "$tmp/16.png" "$tmp/32.png" "$tmp/48.png" "$tmp/256.png" windows/runner/resources/app_icon.ico
rm -rf "$tmp"

echo "iconos rehechos"
