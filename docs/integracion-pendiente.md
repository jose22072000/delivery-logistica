# Integración: lo que hay que cerrar cuando todos entreguen

Lista viva. Sale de lo que cada agente encontró trabajando en su módulo y no pudo cerrar
porque tocaba fichero de otro. **Ninguna de estas es opcional.**

## Grave — rompe el trabajo sin conexión

- [x] ~~**`/api/sync/cambios` NO PUEDE SERVIR LOS PEDIDOS.**~~ — **cerrado (14/09/2026).**
      `orders` sale de `faltan` y se sirve de verdad, con sus `puestos` y sus `quitados`.
      Lo que hubo que poner, y por qué:

      - **`DiferenciasDePedidos`** en `db/queries/orders.sql`, por sucursal y desde una
        marca. La marca por la que filtra y que devuelve **no es `o.updated_at`**: es
        `cambiado_at`, el más nuevo del pedido y de sus renglones. Si cambia una línea
        —PEDIDO reescribe los renglones con lo que dijo la factura— el pedido no se toca,
        así que sin esto el aparato se quedaría con la lista de mercancía vieja y el
        despacho prepararía lo de ayer. Los renglones viajan dentro del pedido, no como un
        aviso suelto.
      - **`quitados` de verdad**, que no es sólo lo borrado. Son tres casos y sólo uno se
        veía en la tabla:
        * **archivado** en PEDIDO — su fila sigue ahí con `updated_at` movido, así que sale
          en las diferencias y se manda a `quitados` (nunca a `puestos` con la bandera
          puesta: eso confía en que el aparato la mire, y el día que no la mire el pedido
          archivado sigue en el tablero y alguien lo carga en el camión);
        * **borrado** — ya no hay fila que mirar;
        * **mudado de sucursal** — su fila está intacta pero con OTRA sucursal, así que no
          sale en ninguna consulta acotada a la vieja.
        Los dos últimos no se pueden contestar mirando `orders`, y por eso hay una
        migración nueva (`00003_bajada_pedidos.sql`) con la tabla de lápidas
        `orders_fuera_de_alcance` y su trigger. Al **Super Admin**, que ve las ocho, sólo
        se le mandan los borrados: un pedido que se mudó de Santiago a Holguín no se le ha
        ido de la vista, y borrárselo sería quitarle del aparato un pedido que existe.
      - **El tope ya no pierde nada.** La consulta ordena por la marca y, cuando no cabe
        todo, la respuesta devuelve como `hasta` **la de la última fila servida** y no el
        reloj. Con el reloj, el aparato pediría la próxima vez «a partir de ahora» y lo que
        no cupo no lo pediría nadie nunca más. El corte además no parte un grupo de filas
        con la misma marca (`now()` es la del inicio de la transacción: una tanda del
        espejo son 200 filas con el mismo microsegundo).
      - `hasta` y `tope` de la query **se obedecen**, que es lo que el sincronizador ya
        mandaba y esto ignoraba.

      Con prueba de cada cosa en `internal/api/espejo_test.go`.

- [ ] **`warehouses` SIGUE DECLARADO EN `faltan`, y es una decisión, no un pendiente que se
      olvidó.** Los almacenes viven en Accesos y se podrían pedir allí en cada bajada
      (`s.accesos.AlmacenesDeSucursal`); lo que lo impide no es la llamada de red: **Accesos
      no da ninguna marca de cambio ni dice qué borró**. Sin marca no hay diferencias, y sin
      saber qué se fue, `quitados` sería siempre `[]` — un almacén retirado se quedaría en
      el aparato para siempre. Y desde el almacén se mide lo que se le cobra al cliente por
      el domicilio, así que uno viejo cobra mal cada entrega del día y no se nota hasta
      cuadrar la caja. Declarado, el aparato puede decir en pantalla «los almacenes son los
      de la última vez que hubo red», que es la verdad.

      **Qué lo desbloquearía:** que Accesos devuelva un `actualizado_at` por almacén y un id
      estable SIEMPRE presente (hoy es opcional). Con eso se sirve como las demás.

- [ ] **El sincronizador ignora el `hasta` que devuelve el reparto, y con `truncado` eso
      pierde trabajo.** `sync/internal/reparto/reparto.go` decodifica sólo `cambios` y
      `truncado`; `sync/internal/sincro/bajada.go` anota `bajada_hasta` con el `hasta` que
      él mismo mandó, salga truncada o no. Así, lo que no cupo en la tanda queda por debajo
      del próximo `desde` y no se vuelve a pedir nunca. El reparto ya hace su parte —con
      `truncado` devuelve la marca de la última fila servida—; falta que el sincronizador la
      lea y anote ÉSA. **No se tocó `sync/` en este cambio.**

- [ ] **`products` y `customers` truncan sin bajar el `hasta`.** Es el mismo fallo de
      arriba pero dentro del reparto: sus consultas (`ListarProductos`, `ListarClientes`) no
      ordenan por la marca, así que «los 2.000 primeros» son 2.000 cualesquiera y no hay
      última fila servida que devolver. Se arregla igual que se arregló `orders`: ordenar
      por la marca en el SQL y cortar por ella.

## Corrección de datos

- [ ] **`optimized` acaba en `true` aunque se respete el orden del logístico**, porque
      `FijarTotalesDeRuta` lo fija así en el SQL. La spec del tablero (§5.4) pide `false`.
      Toca `db/queries/routes.sql`.
- [ ] **El almacén del tablero sale de `saved_origins`**, no de Accesos. `clientes.go` ya
      trajo `Accesos.AlmacenesDeSucursal` y `almacenDeReferencia`, que es lo correcto
      según la spec. Hay que enganchar el tablero a eso.

## Limpieza que el compilador no ve

- [x] ~~**`kmHaversine` está duplicada** en `clientes.go` y como `kmDelTablero` en
      `tablero.go`~~ — **hecho.** Eran TRES: también `haversineKm` en `rutas.go`. Queda
      una sola, `kmHaversine` en `clientes.go`. En `rutas.go` se dejó escrito lo que no se
      podía perder de allí: se usa SIN redondear, porque redondear antes de ordenar cambia
      el orden de visita cuando dos paradas caen casi a la misma distancia.
- [ ] **Unificar los métodos con prefijo** `Tablero…`/`Espejo…` de
      `internal/alcance/tablero.go` con los de `consultas.go`. Se les puso prefijo para no
      chocar mientras se escribía en paralelo.
- [ ] **Queda un CUARTO cajón**: `lib/pantallas/pedidos/vista/kit.dart` tiene su propio
      `Cajon` + `abrirCajon` + `AnchoCajon` + `anchoEscritorio`, y de ahí tiran pedidos y
      **todo** `pantallas/rutas/`. No se tocó el 15/09/2026 porque esas dos carpetas las
      estaba escribiendo otro a la vez. Es equivalente al de `lib/diseno/` salvo en tres
      detalles: lleva `elevation: 8`, el pie va con padding 12 (el del kit, 16) y el
      parámetro del cuerpo se llama `cuerpo` y no `child`. Al unificarlo, `Cajon` y
      `abrirPanel` de `lib/diseno/cajon.dart` ya cubren lo que necesita.

## Variables de paquete que deberían ser campos del Servidor

Se pusieron así porque `servidor.go` estaba ocupado por otro. Al integrarlas hay que
bajarlas a campos:

- [x] ~~`api.Ventra` (el lector de Ventra, en `espejo.go`)~~ — **hecho.** Es `s.ventra`, y
      se enchufa con `s.PonerLectorDeVentra(...)`. Mientras sea nil, `products/sync` sigue
      contestando 502 y no 200 con ceros.
- [ ] `api.Accesos` — **a medias, y a propósito.** El campo ya existe (`s.accesos`) y por
      él pasan `almacenes.go` y `clientes.go`. La variable de paquete **sigue viva porque
      `cotizacion.go` la usa** (`almacenesDeCotizacion`) y ese fichero lo estaba
      escribiendo otro. Es UNA sola instancia —`NuevoServidor` mete esa misma en el
      campo—, así que no hay dos recuerdos de almacenes. **Cuando `cotizacion.go` se
      libere: esa llamada pasa a `s.accesos` y se borra `var Accesos`.**

## El espejo — dónde vive ahora

La pieza que trae los datos es **`cmd/espejo`** (lógica en `internal/espejo`), un binario
aparte de la API y no una tarea dentro de ella: un barrido del histórico tarda minutos y
dentro de la API compartiría el plazo de las peticiones, tumbándola de día, que es cuando se
usa. Lee su marca de agua y su posición de barrido por `alcance.Acotado` —sin persona, con
alcance «todas»— y mete los pedidos por `POST /api/quote/batch`, que es la única puerta.

- [ ] **Los CLIENTES no tienen ruta de entrada** y por eso el espejo los escribe por
      `alcance.EspejoGuardarCliente`. Si algún día se expone un endpoint, que sea el único
      camino, como pasa con los pedidos.
- [ ] **Falta el Dockerfile del espejo** y su servicio en Dokploy. Hasta entonces se corre a
      mano: `espejo --once` hace una pasada.

## Configuración

- [x] ~~**Subir a `config.Cargar` y a `.env.example`** las variables que hoy se leen con
      `os.Getenv`~~ — **hecho.** `PEDIDO_API_URL`, `DELIVERY_URL`, `CATALOGO_CADA_MS`,
      `ALMACENES_CACHE_MS` y las tres `PROCOVAR_AUTH_*`. Ya no queda ningún `os.Getenv`
      fuera de `internal/config`.

      **`PEDIDO_API_URL` NO se puso obligatoria para arrancar**, y es una decisión: sin
      ella el servicio hace todo lo demás y las dos cosas que la necesitan lo DICEN —el
      canal devuelve `ok:false` con el motivo y lo deja en el registro, el recosteo un 500
      con el nombre de la variable—. Lo que sí se valida al arrancar es la FORMA: una URL
      sin `http://` no falla al concatenar, falla dentro de una goroutine de fondo, y lo
      único que se ve es un aviso que no llegó. Y el arranque avisa cuando falta.
- [x] ~~**`api.Ventra` es variable de paquete**~~ — hecho, ver arriba.

## Pruebas

- [x] ~~**`TestTokenConFirmaCambiadaEs401` es inestable, ~1 de cada 16.**~~ — **hecho.**
      Ahora se decodifica la firma, se le cambia un bit (`^= 0x01`) y se vuelve a
      codificar, con una comprobación de que el token roto no salió igual que el bueno.
      Pasa 200 de 200.

## Enrutado

- [ ] **Llamar a los `rutasX`** desde `servidor.go`. Cada módulo dejó la suya escrita y sin
      enchufar, a propósito, para no pelearse por el fichero.
- [ ] `PUT /api/board/columns/orden` **se reparte dentro de** `PUT /api/board/columns/{id}`
      y no como patrón propio: con los dos registrados, el proceso se cae al arrancar. La
      URL del contrato queda intacta.

## Actualizar los aparatos (15/09/2026)

Todo lo de `docs/actualizaciones.md` está montado y probado **menos lo que toca pantalla**,
que no se tocó a propósito.

- [ ] **Nadie mira `actualizacionProvider`.** Está en `app/lib/nucleo/proveedores.dart`, con
      sus pruebas, y no lo lee ninguna pantalla: hace falta una que haga
      `ref.watch(actualizacionProvider)` y pinte los cinco casos de `EstadoDeActualizacion`
      —cajón en móvil, modal en escritorio, como todo lo demás—. Mientras no exista, la
      comprobación no se ejecuta nunca y el aviso no llega a nadie.
- [ ] **Al terminar una subida, `ref.invalidate(actualizacionProvider)`.** Sin eso, un
      `PrimeroSube` se queda puesto hasta el siguiente arranque aunque la cola ya esté
      vacía, y la persona hizo justo lo que se le pidió.
- [ ] **LA CLAVE DE FIRMA DEL APK.** Hoy sale firmado con la de DEPURACIÓN. Android rechaza
      como actualización un APK firmado con otra clave: obliga a desinstalar, y desinstalar
      **borra la base local** — el trabajo del día sin subir. `build.gradle.kts` ya usa la
      buena si existe y grita si no; falta crearla (`docs/actualizaciones.md` §4). **Cuanto
      más tarde se haga, más aparatos habrá que desinstalar el día que se haga.**
- [ ] **Dónde se cuelgan los ficheros.** Se compilan a mano (`docs/compilar.md`); falta
      decidir a qué URL estable van. Hasta entonces `APP_ULTIMA_VERSION` se queda vacía, que
      es el estado seguro: no se anuncia nada.

## La regla de Jose, 14/09/2026 — y lo que se cerró con ella

> «Delivery no se encarga de calcular nada. Él sólo pone en ruta los pedidos —o pedidos
> cambiados por factura— que tengan domicilio y estén calculados.»
> «El lat siempre lo va a traer, eso viene siempre en el pedido: si no, no se podría montar
> en el camión porque no hay cómo localizarlo.»

Lo que ya era así: el armador **no calcula**, suma `pedido_costo`, que lo puso la APK de
Entrega.

Lo que NO era así y se arregló: ese `price: pedido_costo || 0`. Un pedido con domicilio y
sin calcular no reventaba nada — entraba en la ruta **valiendo cero**, el total de la ruta
salía más bajo y nadie se enteraba hasta cuadrar la caja. En la lista de disponibles
«cotizado» es un filtro que el logístico marca si quiere; **al armar no puede serlo**.

Ahora hay guarda (`mensajeSinCalcular` en `rutas.go`), con 409 que dice cuáles y cuántos, y
que mira **las dos señales** de domicilio: `requiere_domicilio` (la casilla que alguien
marcó) y `factura_domicilio` (lo que se cobró en el mostrador, que es la fiable). Con una
sola se escapan casos por los dos lados. El que no lleva domicilio pasa sin costo, que es
lo correcto: se recoge en el almacén.

## Rarezas de la cotización — heredadas, conservadas a propósito

Todas están implementadas **igual que en Next**, porque el criterio es dar el mismo número.
Pero son decisiones de negocio, no técnicas, y alguien tiene que mirarlas:

- [x] ~~Un `{"lat": null}` cotiza desde la latitud 0~~ — **resuelto por Jose el 14/09/2026:
      las coordenadas vienen SIEMPRE con el pedido**, porque sin ellas no hay manera de
      localizar al cliente y el pedido no se podría montar en el camión. El armador ya lo
      exige (`end_lat IS NOT NULL`), así que el caso no se da por esa puerta.
- [x] ~~0 km o 0 kg dan `usd: 0`~~ — **cerrado por otra vía.** Ver «La regla de Jose» abajo:
      un pedido con domicilio y sin calcular ya no entra en la ruta, así que el `|| 0` del
      armador no puede cobrar cero sin que nadie se entere.

- [ ] (queda la nota original) **0 km o 0 kg dan `usd: 0`, no vacío.** Es lo que dice la regla §7 y tiene sentido,
      pero **es la única puerta por la que un domicilio sale gratis**: si un pedido entra
      con peso 0 por falta de dato y alguien cotiza igual, se cobra cero. Hoy lo tapa el
      400 de `pesoKg > 0` en `home-delivery`, y el lote no cotiza, así que no está expuesto.
- [ ] **`!tarifaBaseCup` rechaza el 0 pero no un negativo ni un infinito** (en JavaScript
      son «verdaderos»). Conservado.
- [ ] **`quoted` siempre vale 0** en la respuesta del lote: la variable se declara y nunca
      se incrementa. Conservado porque está en el contrato inventariado.
- [ ] **Dos reglas de «desde dónde se mide»**: `clientes.go` elige su almacén principal por
      su cuenta en vez de pasar por `cotizar.ElegirAlmacen`. Unificar.

## Lo que la cotización deja enganchado a medias

- [x] ~~**El lote cotiza pero NO guarda.**~~ **Cerrado (14/09/2026).**
      `alcance.EspejoGuardarPedido` escribe el pedido y sus renglones en la MISMA
      transacción, y `api.GuardarPedidoDelEspejo` viene montada de fábrica:
      `/api/quote/batch` es la puerta de entrada de los pedidos, no un cotizador. Tres cosas
      cambiaron con ello:
      - El alta es **un `ON CONFLICT (source, external_id)`** y ya no tres consultas.
        `orders_origen_idx` y `customers_origen_idx` SON únicos en la migración, y con
        buscar-y-escribir dos pasadas simultáneas creaban el mismo pedido dos veces.
      - Los renglones van a **`order_items`**, una fila por línea. Con eso se fue
        `productosTexto`: era una copia a mano de los nombres, al lado del JSON, para poder
        buscar «malta» sin leerse los cincuenta mil pedidos.
      - El cuerpo del lote lee ahora **`pedidoUpdatedAt`**, `estado`, `fechaComprometida` y
        los cuatro campos de factura. Sin el primero, `pedido_updated_at` se quedaba nulo,
        el espejo no tenía `since` y cada ciclo volvía a barrer el año entero.
- [ ] `CatalogoDePesos` sin montar: `weightsSource` sale `"none"`, valor que el contrato
      ya prevé.

## Lo que salió al DESPLEGARLO de verdad (15/09/2026)

Ninguno de estos lo habrían encontrado las 398 pruebas: las piezas estaban bien probadas
por dentro, lo que faltaba era enchufarlas.

- [ ] **No hay pantalla de acceso.** Está toda la maquinaria de identidad —guardar la
      sesión, el renovador con su candado— pero no hay dónde entrar, y el armazón no exige
      sesión: entra directo al Panel. Sin sesión no se descarga nada, así que todas las
      pantallas dicen «no se ha descargado todavía» y la aplicación parece rota.
- [ ] **No hay lector de Ventra.** `POST /api/products/sync` contesta
      `502 «este servicio todavía no tiene lector de Ventra configurado»`. Hay interfaz
      (`LectorDeVentra`) y hay dónde enchufarlo (`PonerLectorDeVentra`), pero nadie escribió
      la implementación. Sin catálogo no hay pesos y el pre-despacho sale incompleto.
- [x] **La almohadilla en la URL.** Flutter web enruta con `#` por defecto. Quitado con
      `usePathUrlStrategy()`; el nginx ya servía `index.html` en cualquier ruta, que es lo
      que hace falta para que recargar no dé 404.
- [ ] **Se ve como Material, no como delivery.** Jose lo dijo al abrirlo: «muy cambiado a
      como está el de Next».

### Y las trampas del propio despliegue, que costaron seis intentos

Están explicadas en `montar-en-dokploy.md`. En una línea: **todo lo que se copie de
`.secretos/delivery_env_local.txt` está mal**, porque es la configuración de desarrollo —
su `localhost:8400` dentro de un contenedor es el contenedor mismo, y su clave de servicio
no es la de producción. Los valores se leen del contenedor que ya funciona.

Dos más, y la segunda es la que más tiempo escondió:

- **El contexto de construcción tiene que ser `.`**, no vacío: los Dockerfile viven en
  `deploy/` pero hacen `COPY api/`.
- **Las sucursales hay que sembrarlas ANTES de que el espejo traiga nada.** Sin ellas
  rechaza todos los pedidos con `sucursal-no-mapeada` — 491 en un lote — y la base se queda
  vacía sin que nada parezca roto. Los clientes sí entran, y eso despista.

### Un error mío que conviene no repetir

Leí las variables de un contenedor **distroless** con `printenv`, que no existe ahí. El
comando devolvió vacío, y guardé ese vacío encima de la configuración buena: la API se
quedó con dos variables de doce. **Se lee del spec del servicio**
(`docker service inspect … .Spec.TaskTemplate.ContainerSpec.Env`) o de Dokploy, nunca del
contenedor.

## Error mío al repartir el trabajo — hay que corregirlo en TODAS las pantallas

- [x] ~~**El cajón va también en escritorio.**~~ CORREGIDO el 14/09/2026: quitada la rama de
      escritorio en las dos copias. **UNIFICADO el 15/09/2026**: las dos copias
      (`pantallas/vehiculos/vista/cajon.dart` y `pantallas/almacenes/vista/cajon.dart`)
      están borradas y las dos pantallas usan `lib/diseno/cajon.dart`. El kit del armazón se
      escribió BIEN desde el principio: su cabecera cita el pliego §9.2.

      Cómo se resolvió lo del título, que era el escollo. El kit pide `titulo` como
      `String` y construye el `Cajon` por dentro, llamando a `cuerpo` y a `pie` por
      separado; estas tres fichas lo pintaban dentro del cuerpo con su propio `MarcoCajon`
      y **su pie mira el estado del cuerpo** (el `Guardar` se habilita según lo escrito en
      un campo). Sacar sólo el título habría dejado el pie sin poder ver ese estado. Así
      que el kit tiene ahora `abrirPanel(contexto, constructor)` —la misma puerta, el mismo
      velo y la misma entrada que `abrirCajon`, pero es quien llama el que devuelve el
      `Cajon`—, y cada ficha devuelve su `Cajon` entero: un solo `setState` repinta
      cabecera, cuerpo y pie a la vez. Es el mismo patrón que ya usaba
      `pantallas/pedidos/vista/kit.dart`.

      Dos cambios de comportamiento que van con esto, los dos a mejor:
      - **«Tipos de vehículo» sale ahora más estrecho.** Pide `AnchoCajon.md` desde
        siempre, pero en la copia el ancho se recibía y **no se usaba** —el
        `showModalBottomSheet` lo ocupaba todo—. Con el kit el `md` es de verdad, que es
        lo que pedía §9.2.
      - Los botones del pie se alinean a la derecha con `MainAxisAlignment.end` en vez del
        `Align` + `mainAxisSize: min` que ponía `MarcoCajon`. Se ven igual.

      Lo que pasó: Les dije a los agentes «cajón en móvil, modal
      en escritorio», que es la regla general de la casa. Pero `pantallas.md:25` dice que
      **delivery es una excepción aprobada el 05/09/2026: usa SIEMPRE cajón lateral,
      también en escritorio**, y que no hay variante modal (§757).

      Apliqué la regla general sin mirar la excepción del proyecto. Afecta a todas las
      pantallas que se escribieron hoy. El arreglo es la constante `anchoDeEscritorio` y el
      `if (esEscritorio)` de `cajon.dart` — y hoy hay **dos copias** de ese fichero
      (vehículos y almacenes) porque `lib/diseno/` no existía cuando se escribieron. Al
      unificarlo en `lib/diseno/cajon.dart` se corrige de una vez.

      La ✕ que nunca desaparece sí es correcta y se queda.

## Lo que salió al traspasar los DATOS REALES (14/09/2026)

Volcado de producción: 55.495 pedidos, 85.902 renglones, 7.975 clientes, 8 sucursales.

- **HAY 22 PEDIDOS DUPLICADOS EN PRODUCCIÓN.** La carrera del espejo que el índice único
  venía a impedir **ya ocurrió**. Se ve en los propios identificadores —`cmt7p7o45002z` y
  `cmt7p7o470031`, mismo cliente, mismo día, milisegundos de diferencia—: dos pasadas
  leyeron «no existe» antes de que ninguna escribiera. De las 44 filas, **17 no están
  archivadas**, así que salen dos veces en la lista del armador. Ninguna llegó a una ruta.
  El traspaso aparta las sobrantes a `orders_duplicados` con la fila entera; no se borran.

- **`Order.items` tenía DOCE campos, no dos.** El pliego decía `{description, quantity}` y
  los datos reales traen además `packs`, `pesoKg`, `unitWeightKg`, `pesoLineaKg`,
  `weightKg`, `code`, `whName`, `matched`, `weightSource` y `descripcion`. El peso de cada
  línea estaba **guardado, no calculado**, y `weightSource` dice de dónde salió. Sin esas
  columnas habría que recalcularlo con el catálogo de hoy sobre pedidos de hace meses, y
  el papel diría un peso y el almacén otro. Añadidas en `00004_peso_por_renglon.sql`.

- [ ] **DIFERENCIA CON NEXT que hay que validar:** 5.642 renglones tienen `pesoLineaKg`
  vacío pero `weightKg` puesto. El traspaso los recupera con `coalesce`, así que el
  sistema nuevo ve un peso donde Next no ve ninguno — 229.331 kg en total. Cuando los dos
  campos están puestos **coinciden en los 80.260 casos, con cero diferencias**, o sea que
  son la misma magnitud escrita en dos sitios. Es casi seguro lo correcto, pero **es una
  diferencia de comportamiento y la decide una persona**, no yo.

- **`Vehicle.type` tiene `Camion`** en producción, escrito a mano y en español. Confirma
  que el campo aceptaba cualquier cosa. Añadido al catálogo sembrado.

- **Las coordenadas vienen SIEMPRE**: 0 de 55.495 pedidos sin `endLat`. Confirmada la
  regla de Jose contra los datos.

- **El 96% de los domicilios repartibles no tiene costo** (657 de 686), porque la APK de
  Entrega no está encendida. Por eso la guarda pasó a ser aviso.

## Hallazgos sobre delivery, el que está EN PRODUCCIÓN

No son tareas de este proyecto, pero conviene saberlos:

- **`?sucursal=` se saltaba el alcance en el catálogo.** En delivery ese parámetro tenía
  prioridad, así que un operador de Santiago veía el catálogo Y LOS PRECIOS de La Habana
  escribiéndolo en la barra del navegador. En la API nueva sólo vale cuando no hay alcance
  (Super Admin); la decisión vive en `alcance.codigoAcotado` y hay prueba de que el precio
  que llega es el de la sucursal propia.
- **`Settings.tiposVehiculo` nunca existió en el esquema** (ver `esquema-cambios.md`): la
  pantalla de vehículos creaba tipos, los mandaba a guardar y se perdían sin un error.
- **El panel contaba «los pedidos de la cuenta que mira»**, no los de la sucursal.

## Ya cerrado

- [x] **El canal de salida hacia PEDIDO ya no es un gancho vacío.** `avisarEstadoAPedido`
      es `s.aPedido` y vive en `internal/api/canal_pedido.go`: en tandas de 200 contra
      `POST {PEDIDO_API_URL}/integration/orders/status` con `x-api-key`, idempotente, y sin
      abortar en la tanda que falla. `avisarCambioDeRutas` ya estaba montado de verdad
      —`eventos.go` lo engancha al difusor en su `init()`—.

      Las tres cosas del original que había que conservar, con prueba cada una:
      **va en lote y es idempotente** (el aviso es una afirmación de estado, no un apunte
      que se suma; el repetido idéntico ni se manda); **manda la hora del suceso y no la de
      la llamada** (`at`, del `X-Hecho-At` que pone el sincronizador al reenviar la cola de
      un aparato: lo marcado a las 16:04 llega a PEDIDO como las 16:04 aunque suba a las
      19:30); y **es «lo mejor que se pueda»** — con PEDIDO caído la ruta se arma y se
      cierra igual, el parte no miente y **queda dicho en el registro**, nunca en silencio.

- [x] **El 405 del router hacía que el proceso no arrancara.** Registraba un patrón SIN
      método, que choca con cualquier ruta con `{id}` — ninguno es más específico y
      ServeMux entra en pánico al montar. Afectaba a pedidos, al tablero, y habría
      afectado a `/api/routes/{id}/results`. Ahora se registra el 405 por método.
