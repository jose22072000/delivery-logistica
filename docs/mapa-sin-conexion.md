# El mapa de Cuba dentro del aparato

> «que se descargue el mapa en la aplicación de Cuba para que tenga el mapa ya siempre
> funcional; cuando cargue sólo una vez, para que pueda trabajar. Que sea una vez
> descargar la base del mapa de Cuba.»
> «hacer como hace MAPS.ME: no te descarga 6.5 [GB], te descarga 88 megas.»
> — Jose, 17/09/2026

**Va sólo en la APK de Android y en el escritorio.** En la web, nada: el navegador siempre
tiene servidor detrás (`CLAUDE.md` §1). Ésa es la primera línea de todo lo que hay debajo.

Lo que hay montado:

```
herramientas/mapa-cuba/            el generador: del .osm.pbf al .pmtiles
api/internal/config/mapa.go        de dónde sale el anuncio (MAPA_*)
api/internal/api/mapa.go           GET /api/mapa: qué hay colgado y de dónde se baja
app/lib/mapa/                      el lector, la descarga y el dibujo
app/lib/pantallas/mapa/            la pantalla que lo ofrece con su tamaño
app/test/mapa/muestra/             una muestra de verdad, para probar el lector
docs/mapa-sin-conexion.md          esto
```

---

## 1. Por qué vectorial y no imágenes — la cuenta, hecha

Un mapa se puede guardar de dos formas y la diferencia no es de matiz:

**En teselas de imagen (PNG)**, cada nivel de zoom es un dibujo nuevo y cada nivel tiene
cuatro veces más teselas que el anterior. Para Cuba:

| Hasta | Teselas (caja) | Tamaño |
|---|---|---|
| z12 | 8.094 | **111 MB** |
| z15 | ~492.000 | **6,5 GB** |

Esos son los números que traía el encargo, y cuadran: la caja de Cuba mide 10,82° de
longitud por 3,45° de latitud, que a z15 son 1.001 × 342 = 342.342 teselas, y la suma de
todos los niveles por debajo añade un tercio más (~456.000). Contando sólo la tierra —los
110.000 km² de Cuba, a 1,29 km² por tesela a z15— salen ~113.000 teselas, que siguen siendo
**más de 1,5 GB**. Por cualquiera de los dos caminos, GB.

**En teselas vectoriales (MVT)** lo que viaja es la **geometría**, y el aparato la dibuja al
tamaño que haga falta. Los niveles de zoom siguen existiendo —hay que partir la geometría en
trozos manejables y simplificarla— pero lo que se guarda en cada uno son unos miles de
puntos, no un millón de píxeles de colores. **Ésa es la razón por la que MAPS.ME baja 88 MB
y no 6,5 GB**, y es la misma razón por la que lo nuestro baja todavía menos: MAPS.ME mete
además el grafo de navegación, el índice de búsqueda de direcciones, los puntos de interés y
los números de portal. Un mapa de reparto no necesita nada de eso.

## 2. Qué formato: PMTiles

Se miraron los dos que existen de verdad.

**MBTiles** es un SQLite con una tabla de teselas. Tiene un argumento de peso: la aplicación
**ya lleva SQLite dentro** para la base local, así que leer una tesela sería una consulta y
no un lector escrito a mano.

**PMTiles** es un solo fichero plano con una cabecera de 127 bytes y unos directorios. Se
eligió éste, por tres cosas concretas:

1. **Un fichero y nada más.** SQLite se trae sus compañeros (`-wal`, `-shm`) y quiere
   permiso de escritura en la carpeta hasta para leer. Lo que hay aquí es un fichero que se
   baja una vez, se comprueba por `sha256` y no se vuelve a tocar: cuanto menos se parezca a
   una base de datos viva, mejor.
2. **Se lee por rangos**, que es exactamente la forma de «una sola descarga» — y deja
   abierta la puerta de, algún día, servir una provincia sin bajarse Cuba entera, sin tocar
   el código del aparato.
3. **Lo escriben las herramientas de siempre.** `tippecanoe --output=x.pmtiles` y
   `planetiler` sacan esto mismo, y `pmtiles show` lo abre. Si un día nuestro generador se
   queda corto, se cambia el generador y no la aplicación.

Lo que costó elegirlo: hay que escribir el lector (`app/lib/mapa/pmtiles.dart`, ~350 líneas
de Dart puro, sin plugins ni bibliotecas de mapas). Se paga una vez.

## 3. Qué capas lleva, y qué NO lleva

Lo que necesita un mapa de reparto:

| Capa | Qué es | Por qué |
|---|---|---|
| `carretera` | vías con su **clase** y su **nombre** | por donde pasa el camión |
| `costa` | la línea del mar | **Cuba es una isla: sin costa el mapa no se reconoce** |
| `agua` | embalses, lagunas, ríos anchos | explica por qué una carretera da un rodeo |
| `poblacion` | núcleos con su nombre | sin ellos el mapa es una telaraña sin un sitio reconocible |

Y nada más. **Fuera se quedan**, medido sobre el `.pbf` de Cuba del 16/09/2026:

- **35.243 vías por las que no pasa un camión**: senderos, escaleras, carriles bici, aceras,
  vías en construcción.
- **13.463 relaciones (multipolígonos)**: lagunas y embalses mapeados como relación. Coserlos
  bien es un problema de por sí y lo que se gana es una mancha azul más. La costa, que es lo
  que de verdad hace falta, viene en vías sueltas y **sí** entra.
- **517 núcleos sin nombre**: un punto sin nombre ocupa y no dice nada.

Nada de senderos ni curvas de nivel. Cada capa que sobra son megas en el teléfono del
repartidor.

## 4. Los niveles de detalle, con su peso MEDIDO

Generados el 17/09/2026 desde
`https://download.geofabrik.de/central-america/cuba-latest.osm.pbf` —**61.976.781 bytes**,
`Last-Modified` 16/09/2026, `sha256`
`f3a98b5b73bc1215c27fde7b90b7a91c010e4f7ce24efa417c29b405c72bbb2a`—. No son estimaciones: se
generaron y se pesaron.

| Nivel | Qué trae | Zoom | Teselas | **Bytes** | Se enseña como |
|---|---|---|---|---|---|
| `basico` | carreteras entre pueblos, costa, núcleos | z0–z11 | 823 | **2.375.346** | «Sólo carreteras — 2,4 MB» |
| `completo` | + calles de ciudad con su nombre | z0–z14 | 30.095 | **25.763.142** | «Completo, con calles — 25,8 MB» |
| `detallado` | + caminos de tierra y un acercamiento más | z0–z15 | 112.693 | **61.089.619** | «Detallado, con caminos — 61,1 MB» |

Crecimiento por nivel de zoom, acumulado, para el `completo`:

```
z0–z11    2,4 MB       z13     12,1 MB
z12       4,9 MB       z14     25,6 MB
```

**El que hay que ofrecer por defecto es `completo`.** Es el que llega a un domicilio, y 25,8
MB es menos de lo que ocupa el propio APK. El `basico` está para quien tiene la conexión
justa y sólo necesita ver por dónde va la ruta; el `detallado` sólo si se reparte fuera de la
ciudad — **ocupa el doble y no añade una sola calle nueva**.

### Dónde está el tamaño, medido

Dos cosas más, medidas por si un día hay que apretar:

- **Los nombres de las calles cuestan 2.496.647 bytes**, el 9,7 % del `completo` (23,3 MB
  sin ellos contra 25,8 MB con ellos). Se quedan: son lo que permitirá rotular, y volver a
  generar cuesta 11 segundos.
- **Los nombres no viajan por debajo del z9** (`NombresDesde`). Un «Calle 23» metido en la
  tesela del z6 ocupa lo mismo que en la del z14 y ahí la calle entera mide dos píxeles.
- **La simplificación se afloja en los zooms bajos** (tolerancia 8 hasta z8, 4 hasta z11,
  1,5 por encima): ahí no se nota, y es donde está la mitad del ahorro.

## 5. Cómo se genera y cómo se cuelga — **el procedimiento, para ejecutarlo tú**

> **Nada de esto lo hace ningún agente.** El generador escribe ficheros y dice cuánto pesan;
> **no sube nada a ningún sitio y no habla con el VPS**.

### 5.1 Bajar el extracto (una vez por actualización)

```bash
cd ~/Work/procovar/delivery-logistica
mkdir -p /tmp/mapa && cd /tmp/mapa
curl -L -C - -o cuba-latest.osm.pbf \
  https://download.geofabrik.de/central-america/cuba-latest.osm.pbf
ls -l cuba-latest.osm.pbf          # ~62 MB
```

Geofabrik lo regenera **a diario**. Una vez al mes es más que suficiente: el mapa de Cuba de
hace un mes sigue siendo un mapa de Cuba.

### 5.2 Generar los tres niveles

```bash
cd ~/Work/procovar/delivery-logistica/herramientas/mapa-cuba
go run . -pbf /tmp/mapa/cuba-latest.osm.pbf -salida /tmp/mapa
```

Tarda **unos 40 segundos los tres** en este portátil y necesita ~2 GB de RAM (guarda las
coordenadas de los ~7 millones de nodos). Al terminar imprime, por nivel, **los bytes y el
`sha256`** — que es exactamente lo que hay que ponerle a la api.

Para uno solo: `-nivel completo`.

### 5.3 Comprobar el fichero ANTES de colgarlo

```bash
go run . -comprobar /tmp/mapa/cuba-completo.pmtiles
```

Lo abre de verdad, recorre los directorios, **decodifica una tesela de cada nivel** y
comprueba que la atribución de OpenStreetMap está dentro. Si algo no cuadra dice qué y sale
con código 1. Un fichero que no pase esto no se cuelga.

### 5.4 Colgarlo en el VPS

**El servidor es el nuestro, no el de OSM.** Bajar teselas en bloque de
`tile.openstreetmap.org` va contra su política de uso y el castigo es un bloqueo por IP — ya
nos pasó con Hostinger el 04/08/2026.

Sitio propuesto: la misma carpeta de estáticos del nginx de la web, servida por el dominio de
siempre, bajo `/mapa/`. Queda pendiente de que la decidas tú, igual que la de los APK
(`docs/actualizaciones.md` §6) — **son el mismo problema y conviene que sea la misma carpeta**.

```bash
# desde tu equipo, con la conexión SSH que ya está montada
scp /tmp/mapa/cuba-*.pmtiles vps:/ruta/de/estaticos/mapa/

# y DENTRO del servidor, comprobar que llegó entero:
ssh vps 'cd /ruta/de/estaticos/mapa && sha256sum cuba-*.pmtiles && ls -l'
```

Los `sha256` que salgan ahí tienen que ser **los mismos** que imprimió el generador. Si no lo
son, el fichero se estropeó por el camino y no se anuncia.

> **Ojo con el camino, que es la trampa del §3-quater de `CLAUDE.md`.** Traefik reparte por
> prefijo de **cadena**, no de segmento: `Host(reparto.procovar.cloud)` sin más va a la
> aplicación. Los ficheros bajo `/mapa/` los sirve ese mismo nginx desde el disco y funcionan
> —el fichero existe, así que el `try_files` de la SPA no se lo come—, pero **el camino
> `/mapa/` no puede ser también una ruta del enrutador de Flutter**, o recargar ahí serviría
> el `.pmtiles` en vez de la pantalla. Por eso la pantalla se registró en
> `/mapa-sin-conexion` y no en `/mapa`. Si se cambia el sitio de los ficheros, hay que volver
> a mirar esto.

El servidor de estáticos tiene que **admitir peticiones por rango** (`Accept-Ranges: bytes`).
nginx lo hace de serie con ficheros estáticos. Sin eso la descarga sigue funcionando, pero
**deja de poder reanudarse**, que en la conexión de allá es la diferencia entre terminar y no
terminar. Se comprueba dentro del servidor:

```bash
ssh vps 'curl -sI -r 0-99 http://127.0.0.1/mapa/cuba-completo.pmtiles | head -5'
# tiene que decir: HTTP/1.1 206 Partial Content
```

### 5.5 Anunciarlo

Se le ponen estas variables a la api y se vuelve a desplegar. Es **exactamente** el mismo
mecanismo que el anuncio de versión de la aplicación, incluida la regla de que **a medias no
arranca**.

| Variable | ¿Obligatoria? | Qué es |
|---|---|---|
| `MAPA_VERSION` | la que manda | El sello del `.osm.pbf` del que salió: `260916`. Vacía = no se anuncia nada. |
| `MAPA_FECHA` | no | `2026-09-16`. Se guarda normalizada. |
| `MAPA_<NIVEL>_URL` | las tres o ninguna | URL del `.pmtiles`. |
| `MAPA_<NIVEL>_BYTES` | las tres o ninguna | Lo que dice `ls -l`. |
| `MAPA_<NIVEL>_SHA256` | las tres o ninguna | Lo que imprime el generador. |

`<NIVEL>` es `BASICO`, `COMPLETO` o `DETALLADO`. **Los niveles se descubren del entorno**: no
hay una lista cerrada en el código, así que colgar un cuarto nivel no obliga a tocar la api.
El precio de eso, y está asumido: una errata (`MAPA_COMPLTO_URL`) crea un nivel llamado
«complto» que **sale en la pantalla del logístico**. Es feo y **se ve**, que es mejor que un
nivel que falta y no se ve.

Ejemplo con los números medidos hoy:

```
MAPA_VERSION=260916
MAPA_FECHA=2026-09-16
MAPA_BASICO_URL=https://reparto.procovar.cloud/mapa/cuba-basico.pmtiles
MAPA_BASICO_BYTES=2375346
MAPA_BASICO_SHA256=21e725bac45518ad5b889e0afa2927fb78d25946b19c485b1ce66dbc13100a0b
MAPA_COMPLETO_URL=https://reparto.procovar.cloud/mapa/cuba-completo.pmtiles
MAPA_COMPLETO_BYTES=25763142
MAPA_COMPLETO_SHA256=ed9c3bf5dd964bc0fa319b1807bb5d7c620db057dbf76e6a270463e407f1e9c9
MAPA_DETALLADO_URL=https://reparto.procovar.cloud/mapa/cuba-detallado.pmtiles
MAPA_DETALLADO_BYTES=61089619
MAPA_DETALLADO_SHA256=93f3e939aaa5a3fd5947333e8a963998477a8a8a343937169195db8b5b96116f
```

**Qué para el arranque, y por qué cada una** (`api/internal/config/mapa.go`):

- Una `MAPA_*_URL` puesta y `MAPA_VERSION` vacía → no se anunciaría nada nunca, sin un solo
  error a la vista. Desde fuera se ve como «los aparatos no descargan el mapa».
- `MAPA_VERSION` puesta y ningún nivel → se avisaría de que hay mapa sin decir de dónde
  bajarlo.
- Un nivel con dos de las tres → o se baja a ciegas (sin `BYTES`) o no hay forma de saber si
  llegó entero (sin `SHA256`).
- Un `SHA256` que no son 64 caracteres hexadecimales → **rechazaría TODAS las descargas, para
  siempre**, y eso no se parece en nada a un error de configuración cuando se descubre.
- Una URL sin `http://` o `https://`, o unos `BYTES` que no son un número.

## 6. El anuncio: `GET /api/mapa`

Sin sesión, como `/api/version`: el aparato lo consulta al arrancar.

```jsonc
{
  "niveles": [                      // null mientras no haya nada colgado
    {
      "nivel": "basico",
      "version": "260916",          // la del ORIGEN de los datos
      "fecha": "2026-09-16T00:00:00Z",
      "bytes": 2375346,
      "sha256": "21e725…",
      "url": "https://reparto.procovar.cloud/mapa/cuba-basico.pmtiles"
    }
  ]
}
```

**Tres números que no son el mismo y que no tienen por qué coincidir nunca:** `version` de
`/api/version` es la de la api; `ultima.version` es la de la aplicación; y este `version` es
la del mapa. Se publican por separado, porque el mapa cambia cuando cambia OpenStreetMap y no
cuando cambia la aplicación.

Los niveles salen **de menor a mayor tamaño**: lo primero que ve la persona es lo más barato
de bajar.

## 7. Qué compara el aparato

`app/lib/mapa/anuncio_de_mapa.dart`, y los estados son sellados como los del aviso de
versión, para que la pantalla tenga que tratarlos todos:

| Estado | Qué pasó | Qué se enseña |
|---|---|---|
| `MapaNoAplica` | web | nada |
| `SinPaqueteDeMapa` | no hay nada guardado | lo que se puede bajar, **con su tamaño** |
| `MapaAlDia` | lo guardado es lo colgado | «está al día» y los otros niveles |
| `HayMapaNuevo` | otra versión del **mismo** nivel | el aviso con su motivo |
| `NoSeSupoDelMapa` | no hubo red | **nada**; lo guardado sigue sirviendo |

Dos decisiones que parecen detalles:

- **Se compara el MISMO nivel, no «el último».** Quien eligió «Sólo carreteras» porque tiene
  2,4 MB y la conexión de allá **no está desactualizado** porque haya salido uno de 61 MB. Eso
  no es una versión nueva: es otra decisión, y la toma él.
- **Misma versión y otra huella también avisa.** Significa que alguien volvió a colgar el
  fichero sin cambiar el número. Callarlo deja el aparato con algo que el servidor cree que no
  tiene, para siempre.

## 8. La descarga

`app/lib/mapa/descarga_de_mapa.dart`.

- **El tamaño se dice ANTES**, en el botón: «Completo, con calles — 25,8 MB».
- **No se baja nada solo.** Se ofrece, decide la persona.
- **Se reanuda.** Lo bajado va a `cuba-<nivel>.pmtiles.parcial` y se continúa con `Range`. El
  bueno **no se toca hasta que la huella cuadra**: perder el mapa que ya había por intentar
  bajar el nuevo, en la conexión de allá, es lo que no puede pasar.
- **Se comprueba el tope dos veces**: que los bytes sean exactamente los anunciados y que el
  `sha256` cuadre. Los bytes pueden cuadrar y el contenido no.
- **Se comprueba que el reanudado se reanudó de verdad**, que es la misma regla de §3
  aplicada a `Range`. Hay dos formas de que el servidor no cumpla y tienen arreglos distintos:
  - contesta `200` con el fichero entero (ignora `Range`) → se tira lo que había y se escribe
    éste desde cero: se gasta la descarga, pero termina bien;
  - contesta `206` **desde otro sitio** → lo que viene es un trozo que dejaría un agujero en
    medio. No se escribe ni un byte: se descarta el parcial y se dice, y el siguiente intento
    empieza limpio.
- **Si falla, se dice el motivo literal** y si lo bajado se conserva.

## 9. El dibujo: sin biblioteca de mapas, y sin tocar el mapa que ya hay

`app/lib/mapa/fondo_del_paquete.dart`.

**La decisión:** el croquis ya pide sus teselas por un puerto —`FondoDeCalles.tesela(z,x,y) →
ui.Image?`— y esto es **otra implementación de ese puerto**. Nada más. No se tocó ni una línea
de `croquis_de_ruta.dart`, `mapa_de_la_ruta.dart` ni `mapa_en_vivo.dart`.

Eso trae cuatro cosas gratis:

1. **El croquis se sigue dibujando SIEMPRE.** El paquete es una mejora, nunca un requisito.
2. **La atribución de OpenStreetMap sigue saliendo**, también sin conexión: el pintor la
   escribe en cuanto se dibuja una tesela, venga de donde venga. Y además viaja **dentro del
   `.pmtiles`**, en sus metadatos, así que no se pierde aunque cambie la pantalla.
3. **La escala, el encuadre y los pines siguen cuadrando**: es la misma proyección, Mercator
   web, y la tesela se entrega en el mismo sitio y del mismo tamaño que la de OSM.
4. **No entra ninguna biblioteca de mapas.** Se descartó `vector_map_tiles` y `maplibre`: son
   plugins con código nativo por destino, pesan en el APK, hay que comprobar que no se llevan
   por delante la web ni el escritorio, y traen etiquetas curvadas, rotación, inclinación y
   estilos de Mapbox de los que aquí no se usa una línea. Lo que se añadió en su lugar son dos
   ficheros de Dart puro: el decodificador de MVT (~350 líneas) y el lector de PMTiles (~350).

**Qué se dibuja:** agua rellena, costa, carreteras con grosor y color por clase, y los núcleos
con su nombre. En ese orden, que es el que manda un mapa: al revés el agua tapa las carreteras
que la cruzan.

**El orden de las fuentes es paquete → red**, no al revés: el paquete es instantáneo, no gasta
datos y es lo único que hay en el patio de un almacén.

**Por encima del zoom del paquete se amplía**, no se deja hueco: el paquete llega a z11/z14/z15
y el mapa de una ruta apretada pide hasta z19. Se coge la tesela más profunda que haya y se
dibuja el trocito que toca. Se ve más gordo, y se ve.

### Lo que este dibujo todavía NO hace

**No rotula las calles.** Los nombres están en el paquete y se leen bien, pero dibujarlos
tesela a tesela repetiría el mismo nombre en cada tesela que la calle cruza. Hacerlo bien pide
una pasada de colocación de etiquetas entre teselas, que es justo lo que trae una biblioteca de
mapas. Se deja apuntado y no se finge: hoy se rotulan los **núcleos**, que son los que
convierten una telaraña de líneas en un sitio reconocible.

## 10. Lo que falta para que esto funcione de verdad

- [ ] **Enchufar el fondo.** Sobrescribir `fondoDeCallesProvider` con `fondoConPaqueteProvider`
      en el `ProviderScope` de `app/lib/main.dart:21`. **Sin esto el paquete se descarga y no
      se dibuja.** Es una línea y no se hizo aquí porque `main.dart` es de otra tarea; está en
      el informe con el texto exacto.
- [ ] **Decidir dónde se cuelgan los ficheros** y poner las `MAPA_*`. Mientras no estén,
      `/api/mapa` devuelve `"niveles": null` y ningún aparato ofrece descargar nada, que es el
      estado seguro.

Y dos de más adelante:

- [ ] **Rotular las calles** (§9).
- [ ] **Recortar por provincia.** Hoy se baja Cuba entera porque es lo que pidió Jose y porque
      25,8 MB lo aguanta cualquiera. El formato ya permite servir sólo la zona que se mira, sin
      bajarse el fichero: el día que haga falta, no hay que cambiar el aparato.

## 11. Cómo se comprueba

```bash
# el generador
cd herramientas/mapa-cuba && go vet ./... && go test ./...

# el aparato (timeout 300 SIEMPRE: es lo único que convierte un cuelgue en un fallo)
cd app && timeout 300 flutter test test/mapa

# la api
cd api && go test ./internal/config/ ./internal/api/
```

**Nada de red desde el PC de Jose**: las pruebas del aparato inyectan el fichero y el servidor
es un doble que vive en el propio fichero de pruebas. La muestra
(`app/test/mapa/muestra/cuba-muestra.pmtiles`, 91 kB, z0–z6) la escribió el generador de Go a
partir del `.pbf` de verdad, y la lee el lector de Dart: **un lector probado sólo contra
ficheros que él mismo escribe no comprueba el formato**, comprueba que es consistente consigo
mismo, y dos errores que se compensan salen verdes.
