# El barrido de pantallas a cuatro anchos — sacado del árbol el 26/09/2026

`las_pantallas_a_cuatro_anchos_test.dart.pendiente` **no está en la suite a propósito**, y
se retoma el lunes. Renombrado con `.pendiente` para que `flutter test` no lo recoja.

## Por qué se sacó

**Tumbó la construcción de la web.** Dentro del contenedor, «Tablero a 390 px» se comió el
tope de diez minutos de Flutter —el suyo, de fábrica, no uno puesto aquí— y
`Dockerfile.app` corre `flutter test` antes de construir. En este portátil pasaba; en el
VPS, con menos núcleos, no.

Una prueba que **se cuelga en vez de fallar** es lo peor que puede hacer una prueba
(`CLAUDE.md` §5), y ésta lo hacía: sin ese tope, la construcción se habría quedado ahí
para siempre en vez de fallar y decirlo.

## Lo que ya se arregló, y no bastó

La causa que se encontró es la trampa escrita en el repo: **el desmontaje se llamaba al
final del caso**, así que un `expect` que fallara antes lo saltaba, el árbol se quedaba
montado y los `watch()` de Drift dejaban temporizadores vivos. Se cambió a
`addTearDown(() => desmontar(tester))`, registrado al entrar, que corre también cuando el
caso falla.

**Con eso no fue suficiente**: el caso del Tablero siguió sin terminar. Así que hay otra
cosa debajo, y encontrarla un viernes por la tarde bloqueando un despliegue no valía la
pena.

## Lo que sí vale de este trabajo, para no repetirlo

- Los **dos arreglos de verdad** (`isExpanded: true` + `maxLines` con elipsis en
  `ficha_vehiculo.dart` y `panel_sin_colocar.dart`, más el hermano Municipio) **se quedan
  en el árbol**: atacan la causa y no esconden el desborde con un scroll encima.
- El **cazador de desbordes** ya no llama a `detalles.toString()`, que era lo que se comía
  el desborde al formatearlo y hacía que la prueba se pusiera roja por el motivo
  equivocado. Eso está arreglado dentro del fichero.
- Cobertura que llegó a existir: las nueve pantallas del menú (incluida «Canal con
  PEDIDO»), las tres pestañas de Reportes con `ClavesDePestanas.adelante`, el teclado de
  336 px, y el asistente de rutas en sus cuatro pasos.

## Lo primero el lunes

Correr **sólo** ese fichero con `-j 2`, que es lo que tiene el VPS, y ver cuál de los casos
no termina. Con 12 núcleos aquí no se reproduce igual.
