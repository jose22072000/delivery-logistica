# reparto-sync

El sincronizador. Es lo que hace posible que un logístico trabaje sin conexión.

Diez logísticos, uno por sucursal. Por la mañana tienen conexión; durante el día, no.

## Tres trabajos

1. **Bajada por diferencias** — sólo lo que cambió desde la última vez, por sucursal. Sin
   esto, cada mañana se baja el mundo entero y en la conexión de allá eso no termina.
2. **Subida por lotes** — la cola del aparato entera, en orden, con la hora de cada apunte
   y clave de idempotencia. Contesta apunte por apunte: aplicado, repetido o rechazado con
   motivo.
3. **Registro de aparatos** — quién bajó, quién subió, qué le queda pendiente y qué se le
   rechazó. De aquí sale lo que hoy no existe: **ver que Palma lleva desde el martes sin
   subir**, y poder llamar.

## No es un intermediario

Los datos son de `reparto-api`. Esto reparte diferencias y recibe lotes; no es una segunda
verdad.

Protocolo: `../docs/`

---

## Lo que hay escrito

```
cmd/sync/              el binario
internal/config/       el entorno, leído UNA vez y comprobado al arrancar
internal/store/        el pool de pgx y las transacciones; las consultas son las de sqlc
internal/httpx/        cómo se contesta, y sobre todo cómo se contesta mal: {"error":"…"}
internal/identidad/    quién llama: su persona, su sucursal y si es Super Admin
internal/reparto/      la frontera con `reparto-api`, que es el dueño de los datos
internal/sincro/       el protocolo: las cuatro rutas y nada más
```

Las cuatro rutas, todas con sesión (`/salud` no):

| Ruta | Qué hace |
|---|---|
| `POST /sync/aparato` | Alta de una instalación. El uuid lo pone la base. |
| `GET /sync/bajada` | Diferencias desde una marca, por sucursal. `?aparato=&desde=` |
| `POST /sync/subida` | La cola del aparato, en orden. Contesta apunte por apunte. |
| `GET /sync/estado` | El panel: quién no ha subido, qué le queda y qué se le rechazó. |

### Las seis cosas que no pueden salir mal

Cada una tiene su prueba en `internal/sincro`, con dobles del `Querier` generado:

1. **Idempotencia** — un lote que llega dos veces contesta `repetido` con la misma
   respuesta, incluido el id que se creó (`TestUnLoteQueLlegaDosVecesNoSeAplicaDosVeces`).
2. **El orden** — los apuntes se aplican como vinieron en la cola, nunca ordenados por la
   hora del aparato (`TestElOrdenDeLaColaMandaSobreElRelojDelAparato`).
3. **Los provisionales** — lo que venga detrás referido a un `local-…` acaba en el id bueno,
   en el mismo lote y en los siguientes (`TestElCierreDeLaRutaVaAlIdDeVerdadYNoAlLocal`).
4. **Lo rechazado** — se guarda con su motivo y sale en el estado; no se borra ni se vuelve
   a evaluar (`TestLoRechazadoSeGuardaConSuMotivoYNoSeVuelveAEvaluar`).
5. **La marca de la bajada la pone el servidor** — un `desde` posterior al que se entregó no
   se acepta (`TestLaMarcaDeLaBajadaLaPoneElServidorYNoElAparato`).
6. **El alcance por sucursal** — en la bajada, en la subida y en el panel
   (`TestElAlcancePorSucursalTambienAqui`).

```bash
go build ./... && go vet ./... && go test ./...
```

### Entorno

```
DATABASE_URL       la base del sincronizador
REPARTO_URL        dónde vive `reparto-api`
REPARTO_API_KEY    la clave de servicio (`x-api-key`)
SYNC_IDENTIDAD     cabeceras          ← hay que escribirlo a mano, ver internal/identidad
SYNC_ADDR          :8081
SYNC_TOPE_BAJADA   500                cuántas filas por tanda antes de `truncado: true`
```

## Lo que queda pendiente y por qué

- **La identidad es provisional.** Hoy sale de las cabeceras que pone el verificador de
  delante (`X-Persona`, `X-Sucursal`, `X-Super-Admin`). Lo bueno es verificar aquí el token
  de auth, que ya lleva dentro el `sub`, la sucursal y los roles. Por eso `SYNC_IDENTIDAD`
  no tiene valor por defecto: confiar en una cabecera sólo es seguro si nadie más puede
  llegar a este puerto, y eso alguien lo tiene que decidir mirándolo.
- **`GET /api/sync/cambios` todavía no existe en `reparto-api`.** Es lo que la bajada le
  pide: los cambios de una sucursal en una ventana, con sus `quitados`. Hasta que esté, la
  bajada contesta 502. La ventana la decide siempre este servicio.
- **`PanelDeEstado.horas_sin_subir` no se usa.** La consulta lo calcula como
  `EXTRACT(EPOCH FROM (now() - e.subida_at)) / 3600`, que es `numeric` y **viene vacío justo
  para el aparato que nunca subió** —el que más importa, el que la consulta pone arriba con
  `NULLS FIRST`—; el tipo que genera sqlc es `int32`, que no admite vacío ni decimales, así
  que esa fila reventaría al leerse. Las horas se cuentan en Go a partir de `subida_at`. El
  arreglo es de la consulta (`::int` sobre un `COALESCE`, o devolver los segundos), y la
  consulta es contrato: no se ha tocado.
