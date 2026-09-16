---
name: auditar-el-reparto
description: Audita un cambio de delivery-logistica antes de darlo por bueno. Comprueba ejecutando y rompiendo guardas a propósito, no leyendo el diff. Úsala siempre que se termine un trozo de trabajo en api/, sync/ o app/, y siempre antes de decir que algo está hecho.
---

# Auditar el reparto

Tu trabajo es **encontrar el fallo que va a aparecer en el teléfono de Jose**, no
aprobar un diff. Un cambio que compila, pasa `./comprobar.sh` y rompe producción
es el caso normal aquí, no el raro: ha pasado tres veces en un día.

No felicites. No resumas lo que hace el cambio: eso ya se sabe. Di qué está mal,
en `fichero:línea`, con el caso concreto que lo rompe.

## La regla que manda: verde no es prueba

`./comprobar.sh` diciendo «Todo en verde» **no demuestra nada** por sí solo. Las
tres cosas que se colaron con todo en verde:

1. El filtro de cobro del domicilio preguntaba por la columna equivocada. La
   prueba **sembraba esa misma columna**, así que salía verde mientras en el
   teléfono el filtro daba 0 de 307 con el importe a la vista.
2. `VeTodasLasSucursales` pasó a mirar el rol. De las **tres** personas
   sintéticas de servicio se actualizaron dos. La tercera llevaba horas
   contestando 403: 84 lotes de PEDIDO rechazados, ninguna prueba roja.
3. `reparto-sync` mandaba `X-Persona` y `X-Sucursal` y **la API no las leía**.
   Medio protocolo escrito y nadie al otro lado. La cola del tablero no subió
   nunca.

Ninguna de las tres la habría cazado leer el diff. Las tres se cazan ejecutando.

## Lo que tienes que hacer, en este orden

### 1. Correr la comprobación

```bash
cd /mnt/datos/Work/procovar/delivery-logistica && ./comprobar.sh
```

Si no dice «Todo en verde», para aquí y dilo. Lo demás no importa todavía.

### 2. Romper cada guarda nueva a propósito

Por cada `if`, `where`, comparación de rol o condición que el cambio añada o
toque:

1. Inviértela o quítala en el código.
2. Corre la prueba que dice cubrirla.
3. Comprueba que **falla** y que **el mensaje se entiende sin leer el código**.
4. Deshaz la mutación y confirma que vuelve a verde.

Una guarda cuya mutación no rompe ninguna prueba **no está probada**, aunque
haya un test con su nombre al lado. Dilo así.

### 3. Comprobar que la prueba no siembra por donde pregunta

Mira el fixture de cada prueba nueva. Si el dato se escribe **por la misma
columna, campo o cabecera** por la que luego se pregunta, la prueba no comprueba
esa elección: comprueba que Drift y sqlc funcionan.

Busca el segundo testigo: lo que ve el usuario. Si la tarjeta pinta
`pedidoCosto` y el filtro consulta `deliveryPrice`, la prueba tiene que sembrar
como siembra producción y preguntar como pregunta la pantalla.

### 4. Buscar a los hermanos que se quedaron atrás

Cuando el cambio toca una regla compartida —un predicado de alcance, una
constante de rol, un formateador, un nombre de cabecera— **enumera todos los
sitios que la usan** y di uno por uno si se actualizaron:

```bash
grep -rn "<el nombre>" api/ sync/ app/lib/ --include=*.go --include=*.dart | grep -v _test
```

No vale «parece que sí». Lista los sitios con `fichero:línea` y el veredicto de
cada uno. Ésta es la que se saltó las tres puertas de servicio.

### 5. Comprobar que el protocolo tiene los dos extremos

Por cada cabecera, campo JSON o parámetro que el cambio **escriba**, demuestra
que alguien lo **lee**, y al revés:

```bash
grep -rn "X-Loquesea" api/ sync/ app/lib/
```

Un campo que se escribe y nadie lee es trabajo que se pierde en silencio. Un
campo que se lee y nadie escribe es una función que nunca se ejecuta.

### 6. Pedir un tope y comprobar el resultado

Si el cambio pide un `limit`, `tope`, `LIMIT` o una página: ¿se comprueba si se
alcanzó? ¿Hay forma de pedir la siguiente tanda? ¿Avanza el cursor?

Esto ya costó **2.284 pedidos perdidos con 200 OK** y **2.000 clientes clavados
de 8.034**. Está escrito en `CLAUDE.md` §3 y sigue vivo en
`api/internal/api/espejo.go:349`.

Su pariente: **una respuesta vacía no es una respuesta buena.** Un catálogo
vacío es un error, no «no hay productos».

### 7. Las reglas de la casa que no se negocian

Lee `CLAUDE.md` de este repo y el de `procovar/`. Comprueba a mano:

- **Web ≠ APK ≠ escritorio.** La web nunca enseña el aparato de prepararse para
  no tener señal. La APK sí, y tiene que hacerlo perfecto.
- **El alcance sale de quién pregunta, no de lo que mande el cliente.** Una
  sucursal que llega por parámetro sólo puede ESTRECHAR, nunca ampliar. Sin
  sucursal **no** es «todas»: sólo lo es para `SUPER ADMIN` y `DESARROLLADOR`.
  Los otros cinco roles pertenecen a una.
- **La tasa es POR SUCURSAL.** Sin la de esa sucursal no se convierte nada: ni se
  cae a la de otra ni a un número por defecto.
- **Nada se descarta en silencio.** Un apunte rechazado se queda con su motivo
  hasta que una persona decida. Si algo falla, la pantalla no se queda verde.
- **Quitar algo es quitarlo entero**: tipos, llamadas, enlaces, entrada de menú y
  pruebas. `grep` del nombre hasta que no quede una referencia.
- **Los colores salen de la paleta.** Nada escrito a mano, y nada en la mitad
  fría (tono 170–290): el logo no tiene azul.

### 8. Mirar producción, que es donde se ve

Si el cambio tocó `api/` o `sync/` y ya está desplegado, **el registro del
servidor es la única prueba que vale**. Todo desde dentro del servidor, en UNA
orden (cada `ssh` le manda un correo a Jose):

```bash
ssh vps 'docker service logs --since 15m reparto-api-xzlmhw 2>&1 | python3 -c "
import sys,json
for l in sys.stdin:
    i=l.find(\"{\")
    if i<0: continue
    try: d=json.loads(l[i:])
    except Exception: continue
    if d.get(\"msg\")==\"peticion\":
        print(d.get(\"codigo\"), d.get(\"metodo\"), d.get(\"ruta\"))
" | sort | uniq -c | sort -rn | head -20'
```

**Cualquier 4xx o 5xx repetido es un fallo vivo**, aunque nadie se haya quejado.
Así aparecieron los 84 × 403 y el 401 del tablero.

Y cuando el cambio dice que algo se guarda, cuéntalo en la base:

```bash
ssh vps "C=\$(docker ps --format '{{.Names}}' | grep -i postgres | head -1); \
  docker exec \$C psql -U procovar -d procovar_reparto -tAc 'select count(*) from board_columns;'"
```

**NADA de peticiones a un dominio de Procovar desde este PC.** Todo dentro del
servidor. A la oficina le bloquearon la IP por eso.

## Cómo se contesta

Findings ordenados por gravedad. Cada uno:

```
GRAVE  api/internal/api/cotizacion.go:309
  La persona sintética del espejo no lleva Rol.
  Rompe así: PEDIDO manda su lote con la llave buena → VeTodasLasSucursales
  devuelve false → 403. 84 rechazos en 15 minutos, ninguna prueba roja.
  Comprobado: mutación puesta, la prueba X no se enteró.
```

Gravedades:

- **GRAVE** — se pierden datos, alguien ve lo que no es suyo, o una pantalla
  miente. Va antes que nada.
- **SERIO** — funciona pero hay un caso real que lo rompe, o una guarda sin
  probar de verdad.
- **MENOR** — el código o el comentario engañan a quien lo lea mañana.

Al final, una línea: **`LISTO`** o **`NO LISTO`**, y si es que no, qué falta.

No inventes hallazgos para parecer útil. Si de verdad está bien, di `LISTO` y
enumera **qué comprobaste ejecutando** —las mutaciones que hiciste y qué pasó—,
para que se vea que no te limitaste a leer.
