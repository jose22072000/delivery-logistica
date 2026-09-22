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
| `suelo` | parques, vegetación, zona urbana, industrial y portuaria | sin esto es **papel en blanco entre calles** |
| `edificio` | la silueta de las manzanas | es lo que dice si uno ha llegado al portal |
| `tren` | las vías de tren | |

Las tres últimas son del **21/09/2026**, de comparar la misma ruta en el teléfono de Jose: la
web con teselas de OSM contra nuestro paquete. Sus palabras: «nos faltan mas cosas q tiene el
mapa con conexion q aqui no tenemos podemos ponerlas». Lo que faltaba no eran calles —esas ya
estaban— sino **lo que hay entre las calles**.

### El contrato con el pintor: capa, clase y desde qué zoom

Esto es lo que el dibujo (`app/lib/mapa/fondo_del_paquete.dart`) busca por **estas cadenas
exactas**. Cambiarlas aquí y no allí deja el mapa en blanco sin un solo error.

| Capa | Forma | `clase` | Entra desde (básico / completo / detallado) |
|---|---|---|---|
| `suelo` | polígono | `bosque` | z9 / z9 / z9 |
| | | `humedal` | z9 / z9 / z9 |
| | | `urbano` | z9 / z9 / z9 |
| | | `industrial` | z10 / z10 / z10 |
| | | `portuario` | z10 / z10 / z10 |
| | | `parque` | z11 / z11 / z11 |
| | | `hierba` | — / z13 / z13 |
| `edificio` | polígono | `edificio` | — / **z14** / **z15** |
| `tren` | línea | `tren` | z9 / z9 / z9 |
| | | `via_estrecha` | — / z12 / z12 |

Un guion es «este nivel no la lleva», y entonces **ni siquiera se anuncia en los metadatos**
del `.pmtiles`: prometer edificios en el `basico` hace que quien abra el fichero crea que está
roto en vez de ver que ese nivel no los trae.

**`humedal` es de la tarde del 21/09/2026** y es la única clase nueva de todo esto. Estaba
fuera con un motivo escrito en `niveles.go` —«casi todos están mapeados como relación, y las
relaciones no entran»— y ese motivo se acabó: son 363 multipolígonos, y el más grande es la
**Ciénaga de Zapata**. Se pinta aparte y no como un verde más de `bosque` porque no es lo
mismo: por un bosque se puede meter un camino y por una ciénaga no.

**Y desde esa misma tarde los rellenos pueden traer AGUJEROS.** Una laguna dentro de un bosque
llega como un hueco de verdad en la misma mancha, no como una mancha de agua encima. En el
formato eso no se marca con ninguna etiqueta: **se marca dando la vuelta al anillo** (§3-bis).

**Ninguna de las tres viaja con `nombre`.** Los edificios son 582.433 y casi ninguno tiene uno
que sirva para orientarse; el suelo sí lo tendría («Parque Central») pero hoy nadie lo dibuja
y un nombre que nadie lee son bytes; el tren se reconoce por dónde va.

**El orden de dibujo** manda, igual que el agua tiene que ir antes que las carreteras que la
cruzan:

```
suelo  →  agua  →  costa  →  edificio  →  tren  →  carretera  →  poblacion
```

Al revés, la mancha de un barrio tapa las manzanas y las manzanas tapan las calles.

Y nada más. **Fuera se quedan**, medido sobre el `.pbf` de Cuba del 21/09/2026:

- **35.260 vías por las que no pasa un camión**: senderos, escaleras, carriles bici, aceras,
  vías en construcción.
- **624 relaciones `type=boundary`**: son límites administrativos. Se miraron una a una: 612
  son `boundary=administrative` y el resto husos horarios, códigos postales y cuatro áreas
  protegidas. **Ni una sola cae en una capa de las que hay hoy**, así que no aportan nada. Se
  cuentan con su propio motivo por si algún día se añade una capa de áreas protegidas.
- **4.651 relaciones que no son un multipolígono**: restricciones de giro, líneas de guagua,
  paradas, agrupaciones de edificios. No son contornos de nada.
- **17.923 campos de cultivo** (`landuse=farmland`, `farmyard`, `orchard`, `vineyard`,
  invernaderos). En Cuba es media isla: pintarlo todo del mismo color **no distingue nada** —si
  todo es campo, nada destaca— y multiplica el fichero. Es una decisión, no un olvido, y por eso
  sale con su propio motivo en la lista de descartes del generador.
- **1.283 vías de tren que no son una vía** (en desuso, abandonadas, andenes, en obra) y
  **3.328 agujas de patio y apartaderos**, que son una telaraña gris encima de un almacén.
- **517 núcleos sin nombre**: un punto sin nombre ocupa y no dice nada.
- **`building=no`**, que en OSM significa *que ahí NO hay un edificio*: es la forma de tapar un
  dato malo de otra fuente. Tomarlo por un edificio pinta un bloque donde alguien se molestó en
  decir que no lo hay.

Nada de senderos ni curvas de nivel. Cada capa que sobra son megas en el teléfono del
repartidor.

**Lo que ya NO se queda fuera: los multipolígonos.** Hasta esa mañana se tiraban las 13.483
relaciones del `.pbf` con un motivo escrito a mano —«relación (multipolígono) no soportada»— y
era lo que más se echaba en falta de las capas nuevas. De las 8.208 que son
`type=multipolygon`, **5.945 caen en una capa de las que hay** (medido sobre el `completo`,
que las lleva todas):

| | | | |
|---|---|---|---|
| bosque 1.924 | edificio 1.336 | urbano 910 | hierba 748 |
| agua 463 | **humedal 363** | industrial 160 | parque 41 |

De ésas se cosen **5.939**. Las seis que faltan salen en la lista de descartes con su motivo:
5 sin ningún contorno exterior y 1 con el contorno sin coser (le falta un trozo, o cae fuera
del extracto). Se cuentan además 3 multipolígonos que caerían en una capa que no se pinta
rellena y 2 agujeros que no caían dentro de ningún contorno.

Y una que tiene su propia línea en los descartes: **135 vías que ya van dentro de una
relación del mismo color**. Llevan sus propias etiquetas *y además* son miembro de una
relación con esas mismas etiquetas, o sea la misma mancha pintada dos veces del mismo verde.
Se quitan **sólo si la relación llegó a coserse**: quitarlas siempre dejaría sin mancha a la
relación rota, que es cambiar unos bytes de más por un hueco de menos.

## 3-bis. Un agujero se dibuja DANDO LA VUELTA AL ANILLO

No hay ningún campo en el formato que diga «esto es un hueco». Lo único que distingue *la
laguna que hay dentro del bosque* de *otra mancha de bosque encima de la laguna* es **el
sentido de giro**, y la especificación MVT (2.1) lo pide así, en coordenadas de tesela, donde
la Y crece hacia abajo:

```
el anillo de fuera  →  sentido HORARIO
los de dentro       →  sentido ANTIHORARIO
```

Con la Y hacia abajo, «horario en la pantalla» es área con signo positivo, que es lo que `orb`
llama `CCW`. No es una errata: `orb.Ring.Orientation` mira el signo del área tal cual, sin
saber para dónde mira la Y, y su propio decodificador usa exactamente ese criterio.

**`orb` no lo hace solo**: escribe los anillos como se los den. Estaba apuntado en el informe
de la mañana del 21/09 como algo que *daría igual hasta que hubiera agujeros*. Ya los hay, así
que se endereza al escribir cada tesela (`enderezarAnillos`, en `teselar.go`), lo último de
todo, con la geometría ya recortada y simplificada.

Lo que pasa sin eso, y por eso se arregla aunque nuestro pintor de hoy no se entere: un lector
que siga la especificación —`pmtiles show`, tippecanoe, MapLibre— lee el agujero como un
polígono aparte y **pinta el bosque encima de la laguna**. Y nuestro pintor rellena con
`nonZero`, que también necesita que los dos anillos giren al revés para dejar el hueco.

**Y de paso se tiran los agujeros que no tienen área.** Al proyectar a la tesela las
coordenadas se redondean a enteros, así que una isla más pequeña que una unidad de tesela se
queda en una raya: en el `basico` eran **1.879 de los 11.832 anillos de dentro**. Una raya no
pinta nada, ocupa, y sobre todo **no se puede enderezar** —no gira ni para un lado ni para el
otro—, así que dejarlas hacía que el fichero no se pudiera comprobar de verdad. Lo encontró
`-comprobar`, que ahora exige que **todo agujero que quede, gire**.

## 4. Los niveles de detalle, con su peso MEDIDO

Generados el **21/09/2026** desde
`https://download.geofabrik.de/central-america/cuba-latest.osm.pbf` —**62.056.884 bytes**,
`sha256` `108a6553b32a52861812b4c8e354722e19c9b687648adfba508ed0d100d9125e`—. No son
estimaciones: se generaron y se pesaron, uno a uno.

| Nivel | Qué trae | Zoom | Teselas | **Bytes** | Se enseña como |
|---|---|---|---|---|---|
| `basico` | carreteras entre pueblos, costa, núcleos, **verde y tren** | z0–z11 | 824 | **5.996.112** | «Sólo carreteras — 6,0 MB» |
| `completo` | + calles de ciudad con su nombre y **las manzanas** | z0–z14 | 34.498 | **49.198.548** | «Completo, con calles — 49,2 MB» |
| `detallado` | + caminos de tierra y un acercamiento más | z0–z15 | 129.436 | **101.652.569** | «Detallado, con caminos — 101,7 MB» |

> Esta tabla y las tres que vienen debajo son **el estudio del 21/09/2026**, y se quedan como
> están porque sólo valen entre sí: cada número sale del mismo `.pbf`, y restar el peso de una
> capa contra un extracto de otro día no mide una capa, mide un día de OpenStreetMap. **Lo que
> está colgado hoy no es ese fichero**: se regeneró el 22/09/2026 desde el extracto de ese día
> y pesa unos kilobytes más. Los bytes y los `sha256` de verdad, los que anuncia la api, están
> en el §5.5 — y son ésos los que hay que mirar, no éstos.

**El que hay que ofrecer por defecto sigue siendo `completo`.** Es el que llega a un
domicilio. Pasó de 25,8 a 44,1 MB al meterle el suelo, las manzanas y el tren, y de ahí a
49,2 al coser los multipolígonos; eso es lo que cuesta que el mapa se parezca al que Jose ve
con conexión.

El `basico` está para quien tiene la conexión justa y sólo necesita ver por dónde va la ruta;
el `detallado` sólo si se reparte fuera de la ciudad — **ocupa más del doble y no añade una
sola calle nueva**, sólo caminos de tierra y un acercamiento más.

### Lo que cuesta cada capa, GENERANDO CON ELLA Y SIN ELLA

No es una estimación ni un reparto de la suma: cada fila es **un fichero que se generó y se
pesó**, quitando una capa y dejando las demás (`go run . -sin <capa>`). Los tres se generan
otra vez en 50 segundos, así que esta tabla se puede rehacer el día que haya que apretar.

| | `basico` (z0–z11) | `completo` (z0–z14) | `detallado` (z0–z15) |
|---|---|---|---|
| **con todo** | **4.289.483** | **44.063.381** | **95.860.285** |
| sin `suelo` | 2.499.546 | 33.337.245 | 77.278.069 |
| sin `edificio` | *no lo lleva* | 37.349.053 | 81.343.457 |
| sin `tren` | 4.163.294 | 43.204.361 | 94.227.168 |
| sin las tres (lo de antes) | 2.375.429 | 25.764.235 | 61.092.512 |

*Esa tabla es la de la mañana, antes de los multipolígonos; sirve igual para decidir qué capa
se cae si hay que apretar. Los totales de hoy son los de la tabla de abajo.*

### Lo que cuestan los multipolígonos, GENERANDO CON ELLOS Y SIN ELLOS

Lo mismo y por lo mismo: se genera con ellos y sin ellos —`go run . -sin-relaciones`— y se
restan los bytes. **Ninguna de estas cifras es una estimación.**

| | `basico` | `completo` | `detallado` |
|---|---|---|---|
| lo que había esta mañana | 4.289.483 | 44.063.381 | 95.860.285 |
| con el generador de ahora, **sin** multipolígonos | 4.222.279 | 40.399.735 | 87.189.146 |
| **con multipolígonos (lo que hay)** | **5.996.112** | **49.198.548** | **101.652.569** |
| lo que cuestan los multipolígonos | **+1,77 MB** (+42 %) | **+8,80 MB** (+22 %) | **+14,46 MB** (+17 %) |
| lo que cambia frente a esta mañana | +1,71 MB (+40 %) | +5,14 MB (+12 %) | +5,79 MB (+6 %) |

**El `detallado` se queda en 101,7 MB, por debajo del techo de ~110 MB. No hizo falta recortar
por zoom**, y eso se lo debe entero a lo de abajo.

### El recorte por capa: 21 MB que no pintaba nadie

Los multipolígonos, metidos tal cual, dejaban el `detallado` en **147,6 MB** —muy por encima
del techo— y el `completo` en 74,0. Lo primero que se miró fue la simplificación, que es lo
que se mira siempre, y **no era eso**: aflojarla de 1,5 a 8 unidades para las manchas sólo
bajaba de 147,6 a 139,5.

Era el **recorte**. `orb` recorta por defecto de -4096 a 8191, es decir **una tesela de margen
por cada lado: un cuadrado de 3×3**. Para una línea hace falta —una carretera cortada justo en
el borde se dibuja con su grosor y deja una costura blanca entre dos teselas—, pero **una
mancha no tiene grosor y ese margen es pagar nueve veces** por un contorno que ninguna de esas
nueve teselas llega a pintar.

Mientras las manchas fueron manzanas y parques no se notó: caben enteras en una tesela. Un
bosque cosido de una relación cruza cientos, y la Ciénaga de Zapata sola cae en ~2.800 teselas
del z15. Medido sobre el `completo`, capa por capa:

| capa | con el margen de `orb` | con el margen de una mancha |
|---|---|---|
| `suelo` | 34.410.995 | **15.361.989** |
| `agua` | 5.940.373 | **3.292.563** |

Son **21,3 MB del `completo` y 38 del `detallado`**, y no se pierde un solo píxel: es contorno
que se escribía ocho veces de más. Está en `recorteDe` (`teselar.go`), con su prueba
(`TestElMargenDeLasManchasEsLaDecisionDeTamano`), porque cambiar ese número no rompe nada, no
avisa de nada y devuelve el fichero por encima del techo.

Con eso resuelto **la simplificación se dejó como estaba** (1,5 por encima del z11, para todo):
aflojarla sólo para las manchas ahorra 2,4 MB en el `completo` y unos 5 en el `detallado`, y no
hacen falta. Queda apuntado en `niveles.go` como lo siguiente que se tira el día que el `.pbf`
crezca.

Y la resta, que es lo que decide:

| Capa | `basico` | `completo` | `detallado` |
|---|---|---|---|
| `suelo` | **1,79 MB** (+75 %) | **10,73 MB** (+42 %) | **18,58 MB** (+30 %) |
| `edificio` | — | **6,71 MB** (+26 %) | **14,52 MB** (+24 %) |
| `tren` | **0,13 MB** (+5 %) | **0,86 MB** (+3 %) | **1,63 MB** (+3 %) |

Tres cosas que se leen de ahí y que mandan sobre lo que hay en `niveles.go`:

1. **El tren es gratis.** 3 % en los dos niveles que importan, y es una referencia que se ve
   desde lejos. Entra en los tres desde z9.
2. **El suelo es lo que más cuesta** —más que los edificios— y aun así entra pronto (z9), y
   por una razón: es lo único que funciona **a zoom bajo**. Una mancha de ciudad a z10 dice
   dónde está el pueblo; una manzana a z10 no se ve.
3. **Los edificios son la decisión de tamaño de este fichero**, y por eso entran en z14 y en
   ningún zoom más. Metidos un solo nivel más abajo el fichero se dispara —son 582.433
   polígonos, y cada uno cae en las teselas de todos los niveles por debajo— y **a ese tamaño
   no se ven**: a z13 la tesela entera son 5 km y un edificio mide 15 metros. El techo está
   escrito como constante (`edificiosNuncaPorDebajoDe`) y vigilado por
   `TestLosEdificiosSonLaDecisionDeTamano`, porque bajar ese número no rompe nada, no avisa de
   nada y deja un paquete que ya no cabe en el teléfono de nadie.

### Y el z14 del `detallado` lleva los edificios aunque el `completo` ya los lleve

Se escribió primero al revés —edificios desde z15 en el `detallado`, «para no pagar dos veces
el z14»— y esa cuenta está mal: **son tres descargas distintas y nadie tiene dos**. Quien se
baja los 101,7 MB vería a z14 menos manzana que quien se bajó los 49,2. Ni un error, ni una
pantalla en blanco: un mapa peor por pagar más. Lo caza
`TestCadaNivelLlevaTodoLoDelAnterior`, que compara cada nivel con el anterior clase por clase.

### Dónde está el resto del tamaño, medido

Tres cosas más, medidas por si un día hay que apretar:

- **Los nombres de las calles cuestan 2.496.647 bytes**, el 9,7 % del `completo` de antes
  (23,3 MB sin ellos contra 25,8 MB con ellos). Se quedan: son lo que permite rotular, y
  volver a generar cuesta 13 segundos.
- **Los nombres no viajan por debajo del z9** (`NombresDesde`). Un «Calle 23» metido en la
  tesela del z6 ocupa lo mismo que en la del z14 y ahí la calle entera mide dos píxeles. Y
  **`suelo`, `edificio` y `tren` no llevan nombre nunca** (§3).
- **La simplificación se afloja en los zooms bajos** (tolerancia 8 hasta z8, 4 hasta z11,
  1,5 por encima): ahí no se nota, y es donde está la mitad del ahorro. Con los rellenos eso
  tiene un efecto que conviene saber: **una mancha pequeña desaparece sola en los zooms
  bajos**, porque al simplificar su contorno se queda sin área y `RemoveEmpty` la tira. No es
  un fallo, es exactamente lo que se quiere.

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

Tarda **poco más de minuto y medio los tres** en este portátil (4 s el `basico`, 25 s el
`completo`, 68 s el `detallado`) y necesita ~3 GB de RAM (guarda las coordenadas de los ~7
millones de nodos y, para el `detallado`, 891.152 rasgos). Al terminar imprime, por nivel,
**los bytes y el `sha256`** —que es exactamente lo que hay que ponerle a la api— y **la lista
de lo que se quedó fuera con su motivo y su número**, que es lo que explica un fichero que
adelgaza.

Si otra cosa está usando el equipo, `nice -n 19` delante: es CPU entera todo el rato.

**El `.pbf` se lee DOS veces por nivel**, y conviene saber por qué antes de sorprenderse: en
un `.pbf` el orden es nodos, vías y relaciones, así que al llegar a una relación las vías ya
pasaron. O se guardan todas en memoria —millones, para usar 26.358— o se lee otra vez. La
primera pasada sólo mira relaciones (`SkipNodes`, `SkipWays`) y son **0,2 segundos**.

Para uno solo: `-nivel completo`.

Y para **medir** lo que cuesta una capa, que es como se hizo la tabla del §4 —se genera con
ella y sin ella y se restan los bytes, no se estima—:

```bash
go run . -pbf /tmp/mapa/cuba-latest.osm.pbf -nivel completo -sin edificio
# deja cuba-completo-sin-edificio.pmtiles, con el nombre puesto para que no
# se confunda nunca con uno que se pueda colgar

go run . -pbf /tmp/mapa/cuba-latest.osm.pbf -nivel completo -sin-relaciones
# lo mismo para los multipolígonos: deja cuba-completo-sin-relaciones.pmtiles
```

### 5.3 Comprobar el fichero ANTES de colgarlo

```bash
go run . -comprobar /tmp/mapa/cuba-completo.pmtiles
```

Lo abre de verdad, recorre los directorios, **decodifica hasta 24 teselas repartidas por cada
nivel de zoom**, comprueba que la atribución de OpenStreetMap está dentro y, desde el
21/09/2026 por la tarde, **que el sentido de giro de cada anillo es el que pide la
especificación** (§3-bis). Si algo no cuadra dice qué y sale con código 1. Un fichero que no
pase esto no se cuelga.

Y saca, por nivel, **qué capas trae, con cuántos rasgos y cuántos de ellos tienen agujero**,
que es lo que hace falta para comparar un paquete nuevo con el que está colgado:

```
z13    6809 teselas · 25 abiertas: agua=44 carretera=400 costa=32 poblacion=15 suelo=111 tren=15 · 6 con agujero
z14   24967 teselas · 25 abiertas: agua=8 carretera=78 costa=19 edificio=17 poblacion=5 suelo=55 tren=4 · 3 con agujero
```

**El contador de agujeros no es adorno: es la única forma de ver desde fuera que los
multipolígonos entraron.** Un paquete con 0 agujeros en todos los niveles es un paquete al que
se le cayeron las relaciones —es exactamente lo que sale al generar con `-sin-relaciones`— y
eso no da ningún error por ningún otro lado.

Se abren **varias y repartidas**, no la primera: con una sola no se puede contestar «qué capas
trae este nivel», porque la primera tesela de un z14 cae donde caiga y puede ser un trozo de
mar con nada más que costa. **Un nivel entero sin teselas ya lo cazó esta herramienta una
vez** (el `clonar` de `teselar.go`); un nivel entero sin una capa es el mismo fallo con otra
ropa, y ahora también se ve.

### 5.4 Colgarlo en el VPS — **está en MinIO desde el 22/09/2026**

**El servidor es el nuestro, no el de OSM.** Bajar teselas en bloque de
`tile.openstreetmap.org` va contra su política de uso y el castigo es un bloqueo por IP — ya
nos pasó con Hostinger el 04/08/2026.

**Y no es una preferencia de sitio: es un incidente cerrado.** Los ficheros vivían **dentro
de la imagen de la web**, y ahí duran hasta el siguiente despliegue. El 21/09/2026 se
desplegó `reparto-web` a las 18:41 y **se los llevó por delante**. Lo peor no fue perderlos:
fue **cómo se veía desde fuera**. La api seguía anunciando los tres niveles con sus bytes y
su `sha256`, y `GET /mapa/cuba-detallado.pmtiles` contestaba **200 con 1.608 bytes**, que era
el `index.html` de la aplicación — el `try_files` de la SPA sirviendo la página en vez del
fichero que no estaba. Un 200 con la página de la web dentro de un `.pmtiles`. Lo único que
lo delataba era el `sha256` del aparato al terminar de bajar.

El primer parche fue montar `/var/lib/procovar/mapa` dentro del contenedor de la web. **No
llegó a entrar**: medido el 22/09/2026, `docker service inspect reparto-web-dihwbq --format
'{{json .Spec.TaskTemplate.ContainerSpec.Mounts}}'` contestaba `null` — dado de alta en el
panel sí, en el servicio que corría no. O sea que los `.pmtiles` seguían dentro del
contenedor, que es exactamente la situación del día 21.

**Así quedó, y ya no depende de ningún despliegue:**

```
https://archivos.procovar.cloud/reparto/mapa/cuba-<nivel>-<fecha>.pmtiles
```

Es **MinIO**, un almacén S3 de verdad (mismo protocolo, mismos SDK) en su propia Application
de Dokploy, en el proyecto **Infraestructura**. Los bytes viven en
`/var/lib/procovar/minio` del host, **fuera de cualquier imagen**: desplegar la web, la api o
el propio MinIO no los toca. El detalle entero del servicio —imagen fijada, montaje,
credenciales, consola— está en `../../docs/VPS-179.198.107.1.md`.

El día que haya que irse a otro sitio (S3 de Amazon, R2, lo que sea) **no cambia el código**:
cambian las cuatro URL de §5.5.

#### Subirlos

Se sube **desde dentro del servidor**, con `mc-procovar` —un envoltorio que corre el cliente
de MinIO en un contenedor de usar y tirar; en el host no hay nada instalado—. La carpeta
`/var/lib/procovar` del host se ve dentro como `/host`:

```bash
# desde tu equipo, el fichero al host primero
scp /tmp/mapa/cuba-*.pmtiles vps:/var/lib/procovar/mapa/

# y DENTRO del servidor, a MinIO:
ssh vps 'for n in basico completo detallado; do
  mc-procovar cp --attr "Content-Type=application/octet-stream;Cache-Control=private, no-store" \
    "/host/mapa/cuba-$n-260922.pmtiles" "procovar/reparto/mapa/cuba-$n-260922.pmtiles" < /dev/null
done'
```

**Ese `Cache-Control: private, no-store` no es un detalle, es lo que salva las descargas por
rango.** El dominio pasa por Cloudflare; Cloudflare cachea las extensiones que reconoce y de
su copia **no sirve `206`**, contesta `200` con el fichero entero. Con `no-store` contesta
`BYPASS` y la petición llega a MinIO intacta. Se ve en la sección de MinIO del inventario del
VPS, con el `.apk` como caso que lo destapó.

**Y el `< /dev/null` tampoco sobra**: el contenedor se lanza con `-i`, así que dentro de un
guion remoto `mc` se come el resto del guion y no imprime nada, como si no hubiera pasado.

#### Comprobarlo, las cuatro cosas

```bash
ssh vps 'B=https://archivos.procovar.cloud/reparto/mapa
for n in basico completo detallado; do
  curl -s -o /tmp/z "$B/cuba-$n-260922.pmtiles"
  echo "$n  $(sha256sum /tmp/z | cut -d\  -f1)  $(stat -c%s /tmp/z)  \
rango=$(curl -s -o /dev/null -w "%{http_code}" -r 0-99 "$B/cuba-$n-260922.pmtiles")  \
magia=$(head -c7 /tmp/z)"
done; rm -f /tmp/z'
```

Las cuatro tienen que salir:

1. **El `sha256` igual** al que imprimió el generador y al que anuncia la api. Si no, el
   fichero se estropeó por el camino y **no se anuncia**.
2. **Los bytes iguales** a los de `ls -l`.
3. **`rango=206`**. Sin peticiones por rango la descarga sigue funcionando pero **deja de
   poder reanudarse**, y en la conexión de allá eso es la diferencia entre terminar y no
   terminar.
4. **`magia=PMTiles`** (`504d 5469 6c65 73`). Es lo que desmiente el fallo del 21/09: si lo
   que contesta es la página de la web, aquí sale `<!doctype`.

Medido el 22/09/2026, con los tres niveles anunciados:

| Nivel | bytes | `sha256` | rango |
|---|---|---|---|
| `basico` | 5.996.612 | `34ccf34f83db9a8f1334bb19866f6428d74199cf03d083a9131630fa437b02c5` | 206 |
| `completo` | 49.204.814 | `b78bf65ee38c69db42222dfec0acb955428b768ffc64f837e3dfa4949388eff4` | 206 |
| `detallado` | 101.663.628 | `0c1c988f5a2ae758b6d71d4c98416ea412fdad8c63117f06660ee0aa608ba5ba` | 206 |

Los tres son **byte a byte** los mismos que hay en `/var/lib/procovar/mapa`, y el `detallado`
—97 MB— bajó entero por el dominio en 2,8 segundos desde el propio servidor.

#### Lo viejo se queda de red, por ahora

`/var/lib/procovar/mapa` **sigue ahí**, y el nginx de `reparto-web` sigue teniendo su copia
dentro del contenedor sirviendo `https://reparto.procovar.cloud/mapa/…`. **Nadie la anuncia
ya**, pero no se borra hasta que Jose haya bajado el mapa en su teléfono desde la URL nueva.
Cuando lo confirme:

```bash
ssh vps 'rm -f /var/lib/procovar/mapa/cuba-*.pmtiles'
```

Y con eso el montaje `mountId SQaRd2j1rtvP9Y4vnCNAO` de `reparto-web`, y el camino `/mapa/`
de su nginx, **sobran**: la web ya no sirve ficheros, sólo la aplicación.

> **La trampa del camino ya no aplica igual, pero conviene saber por qué estaba.** Traefik
> reparte por prefijo de **cadena**, no de segmento, así que cuando los ficheros salían por
> `reparto.procovar.cloud/mapa/` el camino `/mapa/` no podía ser además una ruta del
> enrutador de Flutter —recargar ahí habría servido el `.pmtiles` en vez de la pantalla—, y
> por eso la pantalla se registró en `/mapa-sin-conexion`. Ahora los ficheros salen por otro
> dominio y el choque desaparece; **la pantalla se queda donde está igualmente**, porque
> moverla obligaría a recompilar los aparatos.

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

**Lo que está puesto hoy, 22/09/2026** — y esto ya no es un ejemplo: es lo que contesta
`/api/mapa`, copiado de las variables de la api. Son los tres paquetes **con los
multipolígonos**, generados desde el extracto del 22/09/2026 (62.077.074 bytes, `sha256`
`e1e03f6eb0cbbfb6ee172d97ec5f502d9cbb3eab99e25a42183be94e6cdfbdb7`):

```
MAPA_VERSION=260922
MAPA_FECHA=2026-09-22
MAPA_BASICO_URL=https://archivos.procovar.cloud/reparto/mapa/cuba-basico-260922.pmtiles
MAPA_BASICO_BYTES=5996612
MAPA_BASICO_SHA256=34ccf34f83db9a8f1334bb19866f6428d74199cf03d083a9131630fa437b02c5
MAPA_COMPLETO_URL=https://archivos.procovar.cloud/reparto/mapa/cuba-completo-260922.pmtiles
MAPA_COMPLETO_BYTES=49204814
MAPA_COMPLETO_SHA256=b78bf65ee38c69db42222dfec0acb955428b768ffc64f837e3dfa4949388eff4
MAPA_DETALLADO_URL=https://archivos.procovar.cloud/reparto/mapa/cuba-detallado-260922.pmtiles
MAPA_DETALLADO_BYTES=101663628
MAPA_DETALLADO_SHA256=0c1c988f5a2ae758b6d71d4c98416ea412fdad8c63117f06660ee0aa608ba5ba
```

> **La mudanza a MinIO, tal como se hizo el 22/09/2026.** No fue «cambiar una URL y ya»: el
> orden importa y es éste, porque cada paso deja el anterior comprobado.
>
> 1. Subir los ficheros al bucket (§5.4) y **comprobar las cuatro cosas** —`sha256`, bytes,
>    `206` y la magia `PMTiles`— en la URL nueva, **antes de tocar nada de la api**. Mientras
>    la api siga anunciando las URL viejas, los aparatos siguen descargando de donde siempre
>    y una prueba fallida no le cuesta el mapa a nadie.
> 2. Cambiar **sólo las tres `MAPA_<NIVEL>_URL`** en el entorno de `reparto-api`
>    (`applicationId 0iQ8gLv5ZIHD1n_DRlzOa`). **`BYTES` y `SHA256` no se tocan**: es el mismo
>    fichero, así que **si cambiaran sería que algo se estropeó al subir, y entonces no se
>    anuncia**. Por la API de Dokploy, `application.saveEnvironment` quiere además
>    `buildArgs`, `buildSecrets` y `createEnvFile` o contesta 400; se releen de
>    `application.one` y se devuelven tal cual.
> 3. Desplegar la api y **esperar a `done`**.
> 4. Y la comprobación que vale: tomar las URL **de lo que contesta `/api/mapa`** —no de lo
>    que uno cree haber puesto— bajarlas enteras desde dentro del servidor y comparar el
>    `sha256` con el que anuncia el propio JSON. Hecho: los tres niveles coincidieron.
>
> Lo de antes se queda de red hasta que Jose baje el mapa en su teléfono, y se barre con el
> `rm` del §5.4.

> **El nombre lleva la fecha, y por eso.** Los de antes se llamaban `cuba-<nivel>.pmtiles` a
> secas y siguen en la carpeta del host. Colgar el nuevo encima del viejo son dos fallos en
> uno: mientras se sube, la api está anunciando un `sha256` que el fichero de debajo ya no
> tiene —y cualquiera que descargue en esa ventana se lleva un paquete que rechaza su propia
> comprobación—, y si algo sale mal no queda a qué volver. Con la fecha en el nombre el viejo
> se queda quieto sirviendo hasta que las variables apuntan al nuevo, y el cambio es atómico:
> lo hace el despliegue de la api, no el `scp`.

> **Y una advertencia sobre la carpeta**, que ya se llenó una vez: cada juego son ~157 MB en
> el disco del host. Los de días anteriores se borran **cuando nadie los anuncia y ha pasado
> una descarga entera**, no el mismo día.

> **Ojo con la versión.** Estos tres paquetes traen capas que los de antes no tenían, así que
> `MAPA_VERSION` **tiene que cambiar** aunque el `.pbf` fuera el mismo día: si no, los aparatos
> que ya tienen el mapa se quedan con el viejo para siempre y nadie ve una manzana. Lo dice el
> §7: misma versión y otra huella también avisa, pero misma versión y misma huella no avisa
> nada — y aquí la huella cambia, así que avisaría igual; lo que no puede pasar es colgar
> estos ficheros con la versión de antes **y** el fichero de antes al lado.

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
      "url": "https://archivos.procovar.cloud/reparto/mapa/cuba-basico.pmtiles"
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

**Qué se dibuja**, y **en este orden**, que es el que manda un mapa: al revés el agua tapa las
carreteras que la cruzan y las manzanas tapan las calles.

```
suelo  →  agua  →  costa  →  edificio  →  tren  →  carretera  →  poblacion
```

- `suelo`: mancha rellena por clase (`parque`, `bosque`, `humedal`, `hierba`, `urbano`,
  `industrial`, `portuario`). Es el fondo de todo.
- `agua` rellena y `costa` como línea.
- `edificio`: mancha rellena, una sola clase. Sólo hay en z14 y z15.
- `tren`: línea, clases `tren` y `via_estrecha`.
- `carretera`: grosor y color por clase.
- `poblacion`: el punto y su nombre, lo último porque va encima de todo.

Las clases exactas y desde qué zoom aparece cada una están en la tabla del §3. **Una clase que
el pintor no conozca no se deja sin pintar en silencio**: se pinta con el color de por defecto
de su capa, que se ve raro y se arregla, en vez de dejar un hueco que nadie nota.

**Y eso es justo lo que pasó con `humedal`**, la clase de la tarde del 21/09/2026: durante un
día el pintor no la conocía, así que caía en el `_ =>` de su tabla y la Ciénaga de Zapata se
pintaba del color de `hierba`. Se arregló el 22/09/2026 con su línea en la tabla y su entrada
en `ColoresDelMapa` —`humedal` es `#CCE3DB`—, y el `_ =>` se queda donde está para la
siguiente.

Lo que la regla no traía, y ahora sí: **una prueba que compare las dos listas**. Un `_ =>` con
color evita el hueco, pero no avisa de nada —por eso estuvo un día mintiendo—. La que avisa es
`app/test/mapa/colores_del_suelo_test.dart`, que lee `clasesDeSuelo` **del propio
`niveles.go`** y exige que cada clase que escribe el generador tenga su color en el pintor. Es
la regla del §3-bis de `CLAUDE.md` aplicada aquí: dos sitios que tienen que decir lo mismo se
atan con una prueba, no con un comentario.

**Los agujeros ya funcionan y no hay nada que tocar**, pero conviene saber por qué: `_camino`
mete todos los trozos del rasgo en un solo `Path`, y un `Path` de Flutter rellena con
`PathFillType.nonZero` de por defecto. Con el contorno girando para un lado y el agujero para
el otro —que es lo que garantiza el generador desde el §3-bis— `nonZero` deja el hueco solo.
**Cambiar ese `Path` a `evenOdd`, o dibujar cada trozo en su propio `Path`, rompe los
agujeros** sin que salte nada: la laguna se pintaría de verde.

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
- [x] **Decidir dónde se cuelgan los ficheros** y poner las `MAPA_*`. Hecho el 22/09/2026, y
      **cerrado de verdad**: están en **MinIO** (`https://archivos.procovar.cloud/reparto/mapa/`),
      con los bytes en `/var/lib/procovar/minio` del host y el montaje comprobado en el
      servicio que corre —no en el panel—, así que ningún despliegue se los puede llevar.
      `/api/mapa` los anuncia con sus bytes y su `sha256` (§5.5) y los **tres** se bajaron
      enteros por el dominio desde dentro del servidor, con la huella anunciada, la magia
      `PMTiles` y `206` a la petición por rango. Lo único pendiente es **barrer las copias
      viejas** cuando Jose confirme la descarga en su teléfono (§5.4).

Y tres de más adelante:

- [x] **Coser los multipolígonos.** Hecho el 21/09/2026 por la tarde: entran 5.939 de las
      8.208 `type=multipolygon`, con sus agujeros de verdad, y con ellos la Ciénaga de Zapata
      —que además estrena clase propia, `humedal`—. Las `type=boundary` se miraron una a una y
      se quedan fuera: ninguna aporta a las capas de hoy. Lo que costó está medido en el §4 y
      el sentido de giro de los anillos, en el §3-bis.
- [x] **Darle color a `humedal` en el pintor.** Hecho el 22/09/2026: `ColoresDelMapa.humedal`
      es `#CCE3DB`, un verde azulado flojo que queda a 70 grados de tono de la `hierba` y a 44
      del `agua`, y su línea está en la tabla de `suelo` de `fondo_del_paquete.dart`. Lo sujetan
      dos pruebas de distinta altura: `app/test/mapa/colores_del_suelo_test.dart` ata la
      decisión —y ata además **la lista de clases del generador con la tabla del pintor**, que
      es lo que habría cazado esto el mismo día—, y la sonda de
      `app/test/mapa/sonda_dibujo_test.dart` dibuja la tesela de la Ciénaga de Zapata con el
      paquete de verdad al lado: 33.233 de sus 65.536 píxeles salen del color del humedal.
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
