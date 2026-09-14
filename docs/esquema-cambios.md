# El esquema nuevo: en qué se aparta de delivery

La migración es `api/db/migrations/00001_init.sql`. Sale del modelo de Prisma documentado
en `modelo-datos.md`, con los cambios de abajo. **Todos son deliberados y ninguno es
gratis** — si alguno no te cuadra, se discute antes de escribir código encima.

> **Sin ejecutar todavía.** No había Postgres ni acceso a docker en el equipo donde se
> escribió. Antes de darla por buena:
>
> ```
> docker run --rm -d --name pg -e POSTGRES_PASSWORD=x -e POSTGRES_DB=reparto postgres:16-alpine
> docker exec -i pg psql -U postgres -d reparto -v ON_ERROR_STOP=1 < api/db/migrations/00001_init.sql
> ```

---

## 1 · Tres JSON que pasan a ser tablas

| Antes | Ahora | Por qué |
|---|---|---|
| `Settings.tiposVehiculo` | tabla **`vehicle_types`** | **El campo nunca existió en el esquema.** La pantalla de vehículos dejaba crear tipos nuevos, los mandaba a guardar y se perdían sin un solo error. Por eso `Vehicle.type` era un conjunto que nadie podía cerrar: su catálogo no estaba en ninguna parte. |
| `Order.items` | tabla **`order_items`** | Dentro de un JSON no se busca. Por eso existía `productosTexto`, una copia de los nombres en texto plano metida a mano sólo para poder preguntar «¿qué pedidos llevan malta?». **Esa copia desaparece**: un dato copiado en dos sitios acaba discrepando, y este además se copiaba a mano. |
| `Settings.currencies` | tabla **`currencies`** | Una lista de cosas con su clave y su valor es una tabla. Así la moneda es única, se sabe cuándo cambió cada tasa, y corregir una no obliga a reescribir el array entero. |

**`Order.meta` y `Customer.meta` se quedan como `jsonb`**, y esto es a propósito: no son
datos, son **el documento original de PEDIDO sin tocar**. Nadie consulta dentro — lo que
hay que buscar tiene su columna. Está por lo que ya pasó dos veces (el municipio y el
vendedor se recuperaron de ahí cuando hicieron falta) y para poder comparar contra el
origen cuando un número no cuadra. Si prefieres que también se vayan, dilo: se pierde esa
red y hay que decidirlo a sabiendas, no por descuido.

---

## 2 · `updated_at` en las catorce tablas, con trigger

En delivery lo tenían 5 de 11. Ahora lo tienen todas, y lo mantiene un trigger
(`set_updated_at()`) en vez de la capa de aplicación: así no depende de que nadie se
acuerde, y **sin esa marca no hay bajada por diferencias**, que es lo que hace posible
trabajar sin conexión.

Las marcas de DOMINIO se quedan aparte y con su nombre: `traido_at`, `synced_at`,
`pedido_updated_at`, `cup_rate_updated_at`. Significan «cuándo lo trajo el origen», que no
es «cuándo se tocó la fila». Mezclarlas rompe el espejo.

---

## 3 · Los conjuntos cerrados pasan a ser enums

Prisma los tenía todos como `String`. Los valores salen de buscar qué escribe el código de
verdad, no de lo que el esquema declaraba: `order_status`, `stop_result`, `route_status`,
`vehicle_status`, `trip_leg`, `pedido_estado`, `factura_estado`, `procedencia`.

Dos decisiones dentro de esto:

- **`route_status` incluye `cancelled`** aunque hoy nadie lo escriba: el tablero ya lo
  excluye en sus consultas, y dejarlo fuera obligaría a un `ALTER TYPE` el día que se use.
- **`vehicle_status` NO incluye `maintenance`**: no existe en el código.

---

## 4 · Identificadores uuid

Los internos pasan de cuid a uuid. Los de sistemas ajenos —PEDIDO, Ventra— siguen siendo
`text` y se quedan como vienen: no son nuestros y no tienen por qué ser uuid.

Esto no rompe a nadie: quien consume el reparto lo hace por `external_id`, que es el id
**de PEDIDO**, no el nuestro.

---

## 5 · Reglas que pasan del comentario a la base

- **Un solo vehículo de referencia por sucursal.** En delivery era un comentario que pedía
  que «sólo uno debería tenerla en true». Ahora es un índice único parcial.
  *Hueco conocido:* los vehículos sin sucursal (`branch_id` NULL) se escapan, porque en un
  índice único los NULL son distintos entre sí. Si hace falta cerrarlo, va con
  `NULLS NOT DISTINCT`.
- **`settings` tiene una sola fila y la base lo impide** (`id boolean PRIMARY KEY CHECK
  (id)`), en vez de confiarlo a un `findFirst`. Dos filas de ajustes es media aplicación
  mirando una y media mirando la otra.

---

## 6 · `user_id` deja de ser obligatorio

En delivery, `Order`, `Product`, `Vehicle` y `Route` exigen un usuario: «quién lo creó».
Para un pedido que entra solo desde el espejo eso es un usuario inventado. Ahora es
opcional y significa lo que dice: quién lo creó **si lo creó alguien**.

`Branch.creator_id` también, y además por una razón técnica: `branches` y `users` se
apuntan la una a la otra, así que una de las dos tiene que poder existir primero.
