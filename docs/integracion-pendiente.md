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

## Ya cerrado

- [x] **El 405 del router hacía que el proceso no arrancara.** Registraba un patrón SIN
      método, que choca con cualquier ruta con `{id}` — ninguno es más específico y
      ServeMux entra en pánico al montar. Afectaba a pedidos, al tablero, y habría
      afectado a `/api/routes/{id}/results`. Ahora se registra el 405 por método.
