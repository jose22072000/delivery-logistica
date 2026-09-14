# Identidad

Auth (`auth.procovar.cloud`) sigue mandando en personas, roles y sucursales. Nada de eso se
mueve. Lo que se añade es una puerta de entrada por token, para la APK.

El patrón está resuelto y probado en `call-center-board`, que entra directo contra
AuthCenter desde Flutter. **Se copia la forma, no el código.**

---

## La regla que lo simplifica todo

> **Para entrar hace falta conexión. Una vez dentro, no.**

No hay acceso sin conexión y no se intenta. Quien entró sigue trabajando aunque pase días
sin señal.

Esto no es una limitación, es lo correcto: validar una contraseña contra una copia guardada
en el teléfono significa que dar de baja a alguien no sirve de nada mientras ese aparato no
se conecte. Con esta regla, la baja hace efecto en el momento en que intente entrar.

Y no hay riesgo de perder trabajo. Si la sesión murió, cuando el aparato por fin conecte
**tiene conexión** —o sea, puede volver a entrar— y la cola sube igual. El trabajo nunca se
queda atrapado.

---

## Dos formas de entrar

| Cliente | Cómo | Qué guarda |
|---|---|---|
| **Web** (Flutter) | Login único de auth, como hoy: redirección y vuelta con sesión | Cookie |
| **APK** (Flutter) | Usuario y contraseña contra el endpoint de token | El par, en el almacén seguro del sistema |

### La APK no lleva ninguna clave dentro

Hoy delivery firma cada petición a auth con HMAC y una clave propia de la aplicación. Eso
funciona porque vive en un servidor. **Una APK se descompila**: esa clave dentro del
teléfono deja a cualquiera hacerse pasar por delivery ante auth.

Y hablar con la base de auth directamente sería peor: dos sitios comprobando contraseñas y
dos sitios donde dar de baja a alguien.

La APK manda usuario y contraseña por HTTPS y recibe un par de tokens. No guarda ningún
secreto de aplicación.

---

## Lo que hay que añadir en auth

```
POST /token      usuario + contraseña        → { token, refresh }
POST /refresh    refresh (un solo uso)       → { token, refresh }   ← par NUEVO
POST /logout     refresh                     → revoca
```

El token de acceso lleva dentro el `sub`, la sucursal y los roles, que es lo que la API ya
lee.

---

## Las tres reglas de la sesión

### 1 · El refresh se sustituye entero

Es de un solo uso. Guardar el viejo no es inútil: el servidor lo lee como reutilización y
**revoca todas las sesiones de esa cuenta**.

### 2 · Una sola renovación en vuelo

Quien llegue mientras otra renovación está en curso **espera a esa y reutiliza su
resultado**, en vez de lanzar la suya con el mismo refresh.

> En reparto esto es más peligroso que en cualquier otro sitio de Procovar: **el teléfono
> recupera señal y dispara la cola entera de golpe**. Varias peticiones a la vez, varias
> renovaciones a la vez, y el logístico se queda fuera de todas sus sesiones justo en el
> momento en que iba a subir el trabajo del día.

El candado va desde la primera línea, no después. Y se libera pase lo que pase: una
renovación fallida que dejara el candado puesto impediría cualquier intento posterior.

### 3 · Un 401 mata la sesión. Un fallo de red, no.

```
200        → dentro
401        → sesión muerta: limpiar y a la pantalla de acceso
red o 5xx  → CONSERVAR los tokens y reintentar luego
```

Esta es exactamente la regla del caso sin conexión. Borrar los tokens por una caída pasajera
obliga a entrar otra vez sin motivo — y en la calle eso es quedarse sin aplicación con el
trabajo del día dentro.

---

## Al arrancar

No se comprueba el token de acceso por su cuenta: dura minutos, así que casi siempre estará
caducado al abrir, y eso no significa que la sesión haya muerto. Se intenta **renovar**, que
hace las dos cosas a la vez — si el par sirve devuelve uno nuevo, y si no, no sirve.

Y si no hay red al arrancar, se entra igual con lo guardado. Ver la regla 3.

---

## Al recuperar la señal, el orden

```
1. renovar     ← primero, SIEMPRE
2. subir la cola
3. bajar diferencias
```

Ocho horas sin conexión dejan el acceso caducado. Si la cola sale con el viejo, todo
responde 401 y se para.

---

## Cuánto dura cada token — decidido

| Token | Dura | Por qué ese número |
|---|---|---|
| **Acceso** | **15 minutos** | Va en cada petición y **no se puede revocar**: una vez emitido, vale hasta que caduca. Quince minutos es el mismo valor que usa `call-center-board` y acota la ventana de un token robado a casi nada. Que caduque a media tarde no molesta a nadie: se renueva solo. |
| **Refresh** | **30 días** | Es el número que de verdad importa, y abajo está el razonamiento. |

### Por qué 30 días y no otra cosa

El refresh **se renueva cada vez que se usa**, así que este número no le afecta a quien
coge señal a menudo: un aparato que conecta cada mañana se renueva indefinidamente. Sólo
muerde al que ha estado **todo ese tiempo sin conectarse ni una vez**.

Con eso en la mano, el número se decide entre dos cosas que tiran en sentidos contrarios:

- **Muy corto molesta a quien no tiene la culpa.** Siete días no aguantan una avería de
  línea de dos semanas, ni unas vacaciones, ni una baja. Y el que se queda fuera es
  justamente el que está en el patio de un almacén en Palma, con el trabajo del día en el
  teléfono y sin nadie a quien preguntar. No se pierde nada —cuando conecta puede volver a
  entrar y la cola sube— pero le arruinas la tarde.
- **Muy largo alarga la baja.** Si das de baja a alguien, su aparato sigue funcionando
  hasta que el refresh caduque. Noventa días es demasiado tiempo para eso.

**Treinta días** cubre una ausencia de dos semanas más una racha mala, y deja la ventana de
una baja en un mes.

### Y la baja no se arregla acortando el token

Acortarlo para que las bajas hagan efecto antes es pagar todos los días por un caso que
pasa dos veces al año. Lo que sí lo arregla es que **el sincronizador sabe qué aparatos
hay**: se marca el aparato como dado de baja y a la primera conexión se le cierra la
sesión. Eso es inmediato en cuanto el aparato aparece, que es el único momento en que se le
puede hacer algo de todas formas.

Ver la tabla `aparatos` en `sincronizacion.md`.

---

## Al cerrar sesión se borra lo local

En el aparato quedan los clientes con sus direcciones y los pedidos del día. Si el teléfono
cambia de manos, eso no puede seguir ahí.

Lo que **no** se borra es la cola pendiente sin avisar: si hay trabajo sin subir, se dice
antes y se pregunta.
