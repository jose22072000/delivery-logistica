# reparto-api

La API de reparto, en Go. Sustituye a las 35 rutas de `delivery` (Next.js).

**No se toca `delivery`.** Ese proyecto se queda en pie, entero, hasta el final: es el
pliego —dice qué hace cada pantalla, con qué filtros y contra qué endpoint— y es el patrón
contra el que comparar. Terminado aquí significa **da los mismos números que la de Next**.

## Por qué se puede reconstruir entera

Delivery no está en uso: el piloto de Santiago no se ha encendido. Sin usuarios no hay nada
que migrar, ni convivencia, ni despliegue sucursal por sucursal, ni obligación de que cada
paso deje algo funcionando. Se construye al lado y se enciende una vez.

## Lo que hay que respetar

- **El alcance por sucursal es la regla de seguridad.** Quien pertenece a una sucursal ve
  sólo la suya. Va en la base del servicio, no repetido en cada endpoint.
- **Los mensajes de error son visibles y están en español.** Se conservan literales.
- **`updatedAt` en los 11 modelos.** Hoy sólo lo tienen 6. Sin esa marca no hay bajada por
  diferencias posible, y como no hay nada en producción esto no es una migración: es
  escribirlo bien a la primera.
- **Lo delicado se compara antes de darlo por bueno:** precios, cotización de domicilio y
  cuadre con Ventra. Ahí un error no revienta — da un número distinto y nadie se entera.

Plan completo: `../docs/`

---

## Cómo está montado

```
cmd/api/            arranque y apagado ordenado
internal/config/    el entorno, validado AL ARRANCAR (si falta algo, no levanta)
internal/store/     el pool de pgx sobre el Querier de sqlc; lo único que sabe que hay un Postgres
internal/httpx/     router (net/http a secas), middlewares y el formato {"error": "..."}
internal/auth/      validación del JWT de auth. Aquí NO se comprueban contraseñas
internal/alcance/   EL ALCANCE POR SUCURSAL — la regla de seguridad
internal/api/       los manejadores
db/                 migraciones (goose) y consultas (sqlc)   ← el contrato, no se toca
```

Montados: `/health`, `/version`, `/api/version`, `/api/branches`, `/api/vehicles`,
`/api/vehicle-types` y `/api/settings`. Los demás recursos faltan; el patrón está
en `internal/api/servidor.go`.

## El patrón, para copiarlo

1. **El manejador no ve nunca un `sqlc.Querier`.** Recibe `*alcance.Acotado` con
   `alcance.De(r)`, y por ahí llega a las consultas. La consulta que falte se añade en
   `internal/alcance/consultas.go`, que es quien rellena el parámetro de sucursal — el
   manejador no lo escribe, así que no puede olvidarlo ni poner el de otra.
2. **La ruta declara sus middlewares** en `Rutas()`: `conSesion`, `conAlcance`, `admin`.
   Se ve de un vistazo cuál lleva alcance y cuál no, en una sola pantalla.
3. **Los mensajes de error son los literales** de `../docs/contratos-api.md`, como
   constantes en `internal/httpx`.
4. **La forma de la respuesta se declara** en un tipo `…Salida`; no se devuelve la fila
   de sqlc tal cual.
5. **Varias escrituras van en `a.EnTx(...)`.** A medias no vale.

## Lo que se aparta del contrato de delivery, y por qué

- **`/api/vehicle-types`** es nuevo. Allí los tipos se mandaban dentro de
  `PUT /api/settings` con la clave `tiposVehiculo`, un campo que **nunca existió en el
  esquema**: se creaban, se guardaban y se perdían sin un error. Ahora es tabla.
- **`_count.members`** ya no sale en las sucursales, y `DELETE /api/branches/[id]` no
  desasocia miembros: aquí no hay tabla de personas. Viven en auth, y allí hay que
  moverlas (queda avisado en el registro).
- **`GET /api/settings` ya no crea la fila.** La clave primaria es un booleano con
  `CHECK (id)` y la migración deja la fila puesta; dos filas de ajustes eran media
  aplicación mirando una y media mirando la otra.
- **`currencies`** se sigue aceptando con la misma forma en el `PUT`, pero cada moneda
  va a su fila.

## Correr y probar

```bash
cp .env.example .env     # DATABASE_URL y JWT_SECRET son obligatorias
go build ./... && go vet ./... && go test ./...
go run ./cmd/api
```

Las pruebas del alcance **no necesitan base de datos**: usan un doble del `Querier` —para
eso `sqlc.yaml` lleva `emit_interface: true`— así que corren en cada compilación y no
«cuando haya un Postgres a mano».
