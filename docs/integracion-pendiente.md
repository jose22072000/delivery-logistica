# Integración: lo que hay que cerrar cuando todos entreguen

Lista viva. Sale de lo que cada agente encontró trabajando en su módulo y no pudo cerrar
porque tocaba fichero de otro. **Ninguna de estas es opcional.**

## Grave — rompe el trabajo sin conexión

- [ ] **`/api/sync/cambios` NO PUEDE SERVIR LOS PEDIDOS.** Ninguna consulta de pedidos
      devuelve `updated_at`, así que no hay diferencias posibles — y los pedidos son
      justamente lo que el logístico necesita bajarse cada mañana.
      Hoy el endpoint los declara en `faltan` en vez de mandar `{"puestos":[],"quitados":[]}`,
      **y eso está bien**: un vacío le diría al aparato «no cambió ningún pedido» y el
      logístico prepararía el día con la foto de ayer. Hay que añadir `updated_at` a las
      consultas de pedidos y servirlos de verdad. `warehouses` igual (viven en Accesos).

## Corrección de datos

- [ ] **`optimized` acaba en `true` aunque se respete el orden del logístico**, porque
      `FijarTotalesDeRuta` lo fija así en el SQL. La spec del tablero (§5.4) pide `false`.
      Toca `db/queries/routes.sql`.
- [ ] **El almacén del tablero sale de `saved_origins`**, no de Accesos. `clientes.go` ya
      trajo `Accesos.AlmacenesDeSucursal` y `almacenDeReferencia`, que es lo correcto
      según la spec. Hay que enganchar el tablero a eso.

## Limpieza que el compilador no ve

- [ ] **`kmHaversine` está duplicada** en `clientes.go` y como `kmDelTablero` en
      `tablero.go`. Misma fórmula, dos copias. Borrar una.
- [ ] **Unificar los métodos con prefijo** `Tablero…`/`Espejo…` de
      `internal/alcance/tablero.go` con los de `consultas.go`. Se les puso prefijo para no
      chocar mientras se escribía en paralelo.

## Variables de paquete que deberían ser campos del Servidor

Se pusieron así porque `servidor.go` estaba ocupado por otro. Al integrarlas hay que
bajarlas a campos:

- [ ] `api.Ventra` (el lector de Ventra, en `espejo.go`).
- [ ] `api.Accesos` (el cliente de Accesos con firma HMAC, en `almacenes.go`).

## Configuración

- [ ] **Subir a `config.Cargar` y a `.env.example`** las variables que hoy se leen con
      `os.Getenv` porque `config.go` estaba ocupado: `PEDIDO_API_URL` (obligatoria para
      `admin/recompute`), `DELIVERY_URL` y `CATALOGO_CADA_MS`.
- [ ] **`api.Ventra` es variable de paquete** y debería ser campo de `Servidor`. Mientras
      sea `nil`, `products/sync` contesta 502 — que es lo correcto, nunca 200 con ceros.

## Pruebas

- [ ] **`TestTokenConFirmaCambiadaEs401` es inestable, ~1 de cada 16.** Sustituye el último
      carácter de la firma por `"X"`, y ese carácter sólo codifica 4 bits: si el original
      ya era `0101`, la firma decodificada es idéntica y el token sigue valiendo → 200.
      Reproducido 3 de 20. El arreglo es una línea: cambiar un bit de la firma
      **decodificada**, no un carácter del base64.

## Enrutado

- [ ] **Llamar a los `rutasX`** desde `servidor.go`. Cada módulo dejó la suya escrita y sin
      enchufar, a propósito, para no pelearse por el fichero.
- [ ] `PUT /api/board/columns/orden` **se reparte dentro de** `PUT /api/board/columns/{id}`
      y no como patrón propio: con los dos registrados, el proceso se cae al arrancar. La
      URL del contrato queda intacta.

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

- [ ] **El lote cotiza pero NO guarda.** Falta el método de alta de pedidos del espejo en
      `consultas.go` (la consulta sí está en sqlc). Cada resultado sale con
      `persisted:false, reason:"espejo-no-montado"` y deja un ERROR en el registro —
      degrada diciéndolo, nunca con un número inventado.
- [ ] `CatalogoDePesos` sin montar: `weightsSource` sale `"none"`, valor que el contrato
      ya prevé.

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

- [x] **El 405 del router hacía que el proceso no arrancara.** Registraba un patrón SIN
      método, que choca con cualquier ruta con `{id}` — ninguno es más específico y
      ServeMux entra en pánico al montar. Afectaba a pedidos, al tablero, y habría
      afectado a `/api/routes/{id}/results`. Ahora se registra el 405 por método.
