#!/usr/bin/env bash
# Vuelve a sacar TODOS los iconos a partir de los SVG de esta carpeta. Desde `app/`:
#
#     marca/generar.sh
#
# Los SVG son la fuente; los PNG son resultado y se rehacen. Si hay que tocar el dibujo,
# se toca el SVG y se vuelve a correr esto — no se retoca un PNG a mano.
#
# LA REGLA DEL TAMANO, que es de lo que trata este script:
#
#   96 px o mas  ->  `icono.svg`          el camion CON el monograma de PROCOVAR
#   menos de 96  ->  `icono-pequeno.svg`  la silueta sola
#
# El monograma ocupa poco mas de un tercio del ancho, asi que a 48 px mide dieciseis y se
# convierte en una mancha dentro de la caja — peor que no ponerlo, porque ensucia la unica
# forma que a ese tamano se lee. La decision la toma este fichero y no quien llame: asi no
# hay forma de pedir por error el grande en pequeno.
set -euo pipefail
cd "$(dirname "$0")/.."
M=marca

# Elige la fuente por tamano.
fuente()  { [ "$1" -ge 96 ] && echo "$M/icono.svg"          || echo "$M/icono-pequeno.svg"; }
# La maskable ademas encoge al 60 %, asi que su umbral es mas alto: a 96 px el dibujo
# util son 58 y el monograma vuelve a no leerse.
mascara() { [ "$1" -ge 192 ] && echo "$M/icono-maskable.svg" || echo "$M/icono-maskable-pequeno.svg"; }

# La web.
rsvg-convert -w 32  -h 32  "$(fuente 32)"  -o web/favicon.png
rsvg-convert -w 192 -h 192 "$(fuente 192)" -o web/icons/Icon-192.png
rsvg-convert -w 512 -h 512 "$(fuente 512)" -o web/icons/Icon-512.png
rsvg-convert -w 192 -h 192 "$(mascara 192)" -o web/icons/Icon-maskable-192.png
rsvg-convert -w 512 -h 512 "$(mascara 512)" -o web/icons/Icon-maskable-512.png

# Android: el lanzador recorta, asi que va la maskable.
for par in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  d="${par%%:*}"; n="${par##*:}"
  rsvg-convert -w "$n" -h "$n" "$(mascara "$n")" \
    -o "android/app/src/main/res/mipmap-$d/ic_launcher.png"
done

# Android, el ICONO ADAPTATIVO (26/09/2026): primer plano transparente sobre el fondo oro
# que pone `res/values/colors.xml`. Es lo que usa el lanzador desde Android 8 y, sobre todo,
# el SPLASH de Android 12+, que dibuja el icono de la app dentro de un circulo: con el PNG
# cuadrado de arriba salia un cuadrado encogido con hueco alrededor. El lienzo del
# adaptativo son 108 dp, de ahi estos tamanos; el umbral del monograma es el mismo que el
# de la maskable, porque el dibujo va igual de encogido.
primer_plano() { [ "$1" -ge 192 ] && echo "$M/icono-primer-plano.svg" || echo "$M/icono-primer-plano-pequeno.svg"; }
for par in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
  d="${par%%:*}"; n="${par##*:}"
  rsvg-convert -w "$n" -h "$n" "$(primer_plano "$n")" \
    -o "android/app/src/main/res/mipmap-$d/ic_launcher_foreground.png"
done

# Windows: un .ico con los cuatro tamanos que pide el explorador.
tmp=$(mktemp -d)
for n in 16 32 48 256; do rsvg-convert -w "$n" -h "$n" "$(fuente "$n")" -o "$tmp/$n.png"; done
magick "$tmp/16.png" "$tmp/32.png" "$tmp/48.png" "$tmp/256.png" windows/runner/resources/app_icon.ico
rm -rf "$tmp"

echo "iconos rehechos"
