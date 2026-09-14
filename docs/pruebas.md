# Guion de QA · reparto

Método: `/qa-como-usuario`. Esto es el guion del dominio — los casos concretos, que la
skill no puede saber. **Este manda sobre el ejemplo de la skill.**

Regla de la skill que aquí importa más que en ningún sitio: **un caso que no se ejecutó es
PENDIENTE, nunca «pasa»**. Y nada de «funciona correctamente» sin el dato al lado.

---

## 0 · El entorno, antes del primer caso

Hay que dejar dicho qué corre y **a qué apunta**. Una variable que quedó de otra prueba hace
fallar todo por una razón que no tiene nada que ver.

| Qué | Dónde | Comprobar |
|---|---|---|
| `delivery` (Next) — **el patrón** | `delivery.procovar.cloud` | responde y contra qué base |
| `api` (Go) | el suyo | responde y contra qué base |
| `sync` (Go) | el suyo | responde |
| `app` web (Flutter) | el suyo | carga |
| `app` APK | **un teléfono de verdad** | no el navegador encogido |
| auth | `auth.procovar.cloud` | el endpoint de token contesta |

**Las dos bases tienen que ser la misma o dos copias idénticas.** Si no, cualquier
diferencia de números es del dato, no del código, y el informe entero no vale.

Un servicio caído o mal apuntado **no es un fallo del cambio**: va aparte, en su propio
apartado.

---

## 1 · Paridad con Next — el eje principal

> **El criterio de terminado es dar los mismos números que la de Next.**

Por eso `delivery` se queda en pie. No se prueba «si parece bien»: se comparan las dos.

Para cada caso: la misma entrada a las dos, y las dos salidas tienen que ser **idénticas**,
no parecidas.

| # | Caso | Evidencia que hay que pegar |
|---|---|---|
| P1 | Cotizar un domicilio de un cliente cualquiera | el importe de cada una, literal |
| P2 | Cotizar uno **sin coordenadas** | qué contesta cada una |
| P3 | Cotizar uno a 0 km del almacén | el importe de cada una |
| P4 | Armar una ruta con los mismos 8 pedidos | orden de visita, km totales, peso, precio |
| P5 | Armar una que **pasa** de la capacidad del vehículo | el mensaje de rechazo, literal |
| P6 | Armar una con un pedido que ya está en otra ruta | el mensaje, literal |
| P7 | El post-despacho de la misma ruta | columnas y totales, uno al lado del otro |
| P8 | Emparejar productos de una factura de Ventra | qué casó y qué no, en las dos |
| P9 | La lista de pedidos por repartir, sin filtros | el número total, y los 10 primeros en orden |
| P10 | La misma lista con los 9 filtros puestos | el número total |

> Estos diez son los que de verdad importan. Un error aquí **no revienta**: da un número
> distinto y nadie se entera hasta que no cuadra el inventario. Es exactamente lo que nos
> pasó este mes con las asignaciones.

---

## 2 · El alcance por sucursal — es seguridad

Un fallo aquí enseña los datos de una sucursal a otra. Y hay un modo de fallo peor, que ya
pasó en producción: un id de sucursal que no existe **devuelve cero con un 200 y sin una
sola traza**, que desde dentro es indistinguible de «no hay nada todavía».

| # | Caso | Qué tiene que pasar |
|---|---|---|
| A1 | Entrar como logístico de Camagüey y recorrer las 7 pantallas | en ninguna aparece nada de otra sucursal |
| A2 | Pedirle por API un pedido de Holguín por su id | no lo devuelve |
| A3 | Cerrar una ruta de otra sucursal por API | la rechaza |
| A4 | Entrar con una sucursal que no existe | **no** devuelve cero: se comporta como «todas» y deja ver el problema |
| A5 | El mismo recorrido como Super Admin | las ve todas |

**Por los dos lados, siempre.** Que la pantalla no lo enseñe no significa que el API no lo
dé: si el API contesta y la pantalla lo esconde, el fallo está y es grave.

---

## 3 · Sin conexión — el día entero

La prueba que de verdad importa, y hay que hacerla como se vive, en un teléfono.

```
1. con red     abrir, entrar, que baje el día
2. sin red     CERRAR la aplicación y volver a abrirla      ← aquí se rompe
3. sin red     preparar el tablero: mover pedidos a columnas
4. sin red     armar una ruta desde una columna
5. sin red     cerrar esa ruta, parada por parada
6. sin red     APAGAR el aparato y encenderlo               ← y aquí
7. sin red     comprobar que sigue todo lo marcado
8. con red     que suba solo
```

Los pasos 2 y 6 son los que distinguen «guarda en memoria» de «vive en el aparato». Si se
saltan, la prueba no prueba nada.

| # | Caso | Qué tiene que pasar |
|---|---|---|
| S1 | El recorrido de arriba, entero | nada se pierde |
| S2 | **La hora.** Marcar a las 16:04, subir a las 19:30 | en PEDIDO dice **16:04** |
| S3 | El orden. Marcar una parada «entregado», luego corregir a «devuelto», subir | queda **devuelto** |
| S4 | Armar ruta sin red, cerrarla sin red, subir las dos | el cierre va a la ruta de verdad, no a `local-…` |
| S5 | Cortar la conexión justo después de que el servidor guarde y reintentar | `repetido`, **no** se duplica |
| S6 | Subir un cierre de una ruta que otro ya tocó | `rechazado` con motivo, visible, **no** desaparece |
| S7 | Una pantalla que no se descargó nunca | dice que no está descargada; no una lista vacía |
| S8 | Arriba, siempre | **de qué hora son los datos que se están viendo** |

---

## 4 · La sesión — deja a gente fuera

| # | Caso | Qué tiene que pasar |
|---|---|---|
| I1 | Recuperar señal con **20 apuntes** en la cola | **una sola** renovación, no veinte |
| I2 | Después de I1 | la sesión sigue viva y la cola sube |
| I3 | Arrancar sin red con sesión guardada | entra |
| I4 | Arrancar sin red **sin** sesión | dice que hace falta conexión, no un error raro |
| I5 | Un 401 del servidor | al login |
| I6 | Un 5xx o un corte de red | **conserva** los tokens y reintenta |
| I7 | Cerrar sesión con cosas sin subir | avisa antes, no borra en silencio |
| I8 | Cerrar sesión | lo local se borra: clientes, direcciones, pedidos |

> I1 es el caso más peligroso de todo el proyecto. Si falla, el servidor lee las
> renovaciones simultáneas como robo y **revoca todas las sesiones de la cuenta** — el
> logístico se queda fuera justo cuando iba a subir el trabajo del día.

---

## 5 · Las pantallas, contra las de Next

Las 7, una por una. Mismas columnas, mismos filtros, mismos valores por defecto, misma
paginación, y las **etiquetas en español literales**.

Ejes de la skill que aplican aquí:

- **Alta:** crear una ruta dejando vacío todo lo opcional. Y con el mínimo imprescindible.
- **Edición:** abrir una ruta y **guardar sin tocar nada** — tiene que quedar igual.
- **Baja:** borrar una ruta. ¿Pregunta? ¿Dice qué pasa con los pedidos que llevaba?
- **Listado:** cero pedidos, uno, y muchos. En producción son doce mil: la pantalla no puede
  quedarse esperando.
- **Filtros:** los 9 de pedidos por repartir. ¿La URL los refleja? ¿Un enlace compartido los
  reproduce? ¿Limpiar los deshace?
- **Coherencia:** el mismo pedido en la lista y dentro de la ruta, ¿dice lo mismo? ¿Y lo
  cotizado frente a lo impreso en el post-despacho?
- **Datos que cruzan:** un pedido elegido en el tablero, ¿llega a la ruta por los dos
  caminos?
- **Móvil:** cajones en móvil, modal en escritorio, y la **✕ que nunca desaparece**.

---

## 6 · Antes de dar por bueno

- La suite de cada proyecto, entera.
- Que compila lo que se despliega: web **y** APK.
- El agente `go-parity-reviewer` sobre los cambios de la API en Go — comprueba corriéndolo
  y mutando las guardas, no leyendo el diff.
- Entorno como estaba: scripts temporales borrados, lo sembrado dado de baja, `git status`
  limpio.

---

## El informe

Una tabla, un caso por fila: número, qué se probó en una frase, **PASA / FALLA /
PENDIENTE**, y la evidencia **literal** — el texto que salió, el número que devolvió el API,
la fila de la base.

Tres cosas separadas y sin mezclar: **fallo del cambio**, **fallo preexistente** y
**problema de entorno**. Mezclarlas convierte el informe en ruido.

Y si algo falla, se reporta **antes** de arreglarlo, con lo que se vio.
