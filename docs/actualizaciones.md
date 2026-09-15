# Cómo le llega una versión nueva a los diez logísticos

La web se actualiza sola. Los aparatos no: alguien tiene que bajarse un fichero e
instalarlo. Este documento dice cómo se anuncia que hay una versión nueva, cómo se entera
el aparato y —la parte que hoy está mal y hay que arreglar antes de repartir nada— **con
qué clave se firma el APK**.

Compilar los ficheros es lo de antes y está aparte: **`docs/compilar.md`**.

Lo que hay montado:

```
docs/compilar.md                   cómo se saca cada salida y desde qué máquina
api/internal/api/version.go        GET /api/version: qué hay publicado y de dónde se baja
api/internal/config/config.go      de dónde sale ese anuncio (§ Publicada)
app/lib/nucleo/actualizacion/      la comprobación en el aparato
docs/actualizaciones.md            esto
```

---

## 1. Las tres reglas

Están escritas en el código, cada una en el sitio donde se cumple, y ninguna es una
preferencia de estilo.

### 1.1 No se actualiza con cola pendiente

Si al logístico le queda el cierre de la tarde sin subir, la aplicación **se niega** y dice
por qué: primero sube, después actualiza.

El motivo es concreto, no una precaución genérica. La base local es **la fuente de verdad**
de la aplicación: lo que se hizo sin red vive ahí y sólo ahí hasta que la cola de salida lo
sube (`app/lib/nucleo/cola/cola_salida.dart`). Una instalación que salga mal —o, en
Android, una que obligue a desinstalar (§4)— se lleva esa base por delante. Lo que se
pierde no es «la configuración»: es el trabajo del día de una persona, y no hay de dónde
sacarlo otra vez.

En el código: `ComprobadorDeActualizacion.comprobar()` mira
`BaseLocal.cuantosPendientes()` y devuelve `PrimeroSube` con **cuántos** quedan. Con el
número se puede decir «te quedan 14 cosas por subir», que es accionable; «no puedes
actualizar» no lo es.

La cuenta se mira **la última**, sólo cuando de verdad hay algo más nuevo que instalar.
Mandar a alguien a buscar señal para subir la cola cuando no hay ninguna versión nueva es
mandarle a buscar señal por nada.

### 1.2 Nunca se fuerza

Se avisa; decide la persona. No hay descarga automática, no hay instalación automática, no
hay pantalla que no se pueda cerrar y no hay versión mínima que bloquee la entrada.

Quien usa esto está en el patio de un almacén, con un camión delante y a lo mejor con la
señal justa. Que la aplicación decida por él que ahora toca bajarse 40 MB es peor que
cualquier versión vieja.

En el código: `comprobar()` hace **una** petición `GET` y devuelve un estado. No baja
nada, no abre nada y no instala nada; la prueba
`app/test/nucleo/actualizacion/comprobador_test.dart` lo comprueba contando las peticiones
que salieron.

### 1.3 La web se actualiza sola y no entra aquí

La web recarga y ya está con la última: no descarga nada, no instala nada y no tiene una
base que una instalación pueda romper. Meterle este aviso sería enseñarle a alguien un
«hay una versión nueva» que no puede hacer nada con él.

En el código: `Plataforma.deEsteAparato()` devuelve `ninguna` en web, y `comprobar()` sale
en la primera línea **sin llamar siquiera al servidor**. Ojo con el orden: `kIsWeb` se mira
antes que `defaultTargetPlatform`, porque en web esa última devuelve el sistema del
navegador —`android` en un teléfono— y sin esa línea la web abierta en un móvil se creería
una APK.

---

## 2. El anuncio: `GET /api/version`

La ruta ya existía y va **sin sesión** (la consulta el aparato antes de entrar). Lo que se
le añadió es el bloque `ultima`.

```jsonc
{
  "version": "a3f9c21",            // la de ESTE servicio, la del -ldflags. Ya estaba.
  "ultima": {                       // null mientras no haya nada publicado
    "version": "1.5.0",
    "compilacion": 12,              // el versionCode de Android; null si no se dijo
    "notas": "El cierre de ruta ya no pierde las fotos.",
    "publicadaAt": "2026-09-15T00:00:00Z",
    "descargas": {
      "android": "https://…/reparto-1.5.0.apk",
      "windows": "https://…/reparto-1.5.0-windows.zip",
      "linux":   "https://…/reparto-1.5.0-linux.tar.gz"
    }
  }
}
```

**`version` y `ultima.version` no son el mismo número y no tienen por qué coincidir
nunca.** `version` es la de la api; `ultima` es la de la aplicación. Se despliegan por
separado. Si el aparato comparase lo suyo contra `version`, cada despliegue de la api
mandaría a diez personas a reinstalar una aplicación que no ha cambiado.

Detalles que importan:

- **`ultima: null` es lo normal** mientras no haya un fichero colgado de verdad. El aparato
  entonces no avisa de nada. Es mejor que inventarse una versión y mandar a diez personas a
  un enlace que no existe.
- **Una plataforma sin fichero no aparece en `descargas`.** No sale con la cadena vacía:
  eso sería un enlace en la pantalla de alguien que al pulsarlo no lleva a ninguna parte.
- **No hay clave `web`** y no la va a haber (regla 1.3).
- Sigue siendo **síncrono y sin tocar Postgres**: los diez aparatos llaman aquí a la vez, al
  arrancar, la mañana que vuelve la señal.
- Sigue saliendo con `Cache-Control: no-store, must-revalidate`, que lo pone el middleware
  `httpx.SinCache`.

## 3. Cómo se publica una versión

Publicar son **dos actos separados**, y en este orden:

1. **Colgar los ficheros.** Se compilan a mano (`docs/compilar.md`) y alguien tiene que
   ponerlos en un sitio con URL estable y accesible desde la calle. *Ese sitio todavía no
   está decidido* — ver §6.
2. **Anunciarlos**, poniéndole a la api estas variables y volviéndola a desplegar:

| Variable | ¿Obligatoria? | Qué es |
|---|---|---|
| `APP_ULTIMA_VERSION` | la que manda | El número de `pubspec.yaml` sin el `+`: `1.5.0`. Vacía = no se anuncia nada. |
| `APP_ULTIMA_COMPILACION` | muy recomendable | El número de después del `+`, el mismo `versionCode` del APK. |
| `APP_DESCARGA_ANDROID` | al menos una | URL del `.apk`. |
| `APP_DESCARGA_WINDOWS` | al menos una | URL del `.zip` del escritorio de Windows. |
| `APP_DESCARGA_LINUX` | al menos una | URL del paquete del escritorio de Linux. |
| `APP_ULTIMA_NOTAS` | no | Una línea de qué trae. Si está vacía, el aviso no la enseña. |
| `APP_ULTIMA_PUBLICADA` | no | `2026-09-15` o `2026-09-15T10:00:00Z`. Se guarda normalizada. |

**Media configuración no arranca el servicio**, y es a propósito
(`api/internal/config/config.go`, `leerPublicada`):

- URL puesta y `APP_ULTIMA_VERSION` vacía → no se anunciaría nada nunca, sin un solo error
  a la vista. Desde fuera se ve como «los aparatos no avisan».
- Versión puesta y ninguna URL → diez personas enteradas de que tienen que actualizar y
  ningún sitio de donde bajarlo.
- URL sin `http://` ni `https://`, o `APP_ULTIMA_COMPILACION` que no es un número → tampoco
  arranca: una errata ahí hace que el aviso no funcione nunca y no se parece en nada a un
  error de configuración cuando se descubre.

Las dos cosas paran el arranque, que es el momento en que lo ve quien despliega. Y si no se
anuncia nada, el registro lo dice al arrancar:

```
APP_ULTIMA_VERSION vacía: /api/version no anuncia ninguna versión de la aplicación,
así que ningún aparato avisará de que hay una nueva
```

### Por qué el entorno y no la base

Publicar es un acto del despliegue, no un dato del reparto: no tiene alcance por sucursal,
no lo edita nadie desde una pantalla y no hace falta una migración para cambiarlo. Además
así el manejador no toca Postgres, que es lo que permite que lo llamen los diez aparatos a
la vez.

## 4. La firma del APK — HOY ESTÁ MAL

> **`app/android/app/build.gradle.kts` firmaba el APK de release con la clave de
> DEPURACIÓN.** Venía así de la plantilla de `flutter create`, con su `TODO` puesto.

Por qué no es un detalle:

- La clave de depuración (`~/.android/debug.keystore`) **la genera Android sola** en cada
  máquina, y **se regenera** si se borra, si se reinstala el sistema o si un día el APK sale
  de otro equipo. No es «una clave floja»: es una clave que no se controla.
- Android **no acepta como actualización** un APK firmado con una clave distinta de la del
  APK instalado. No es un aviso: el sistema lo rechaza. La única salida es **desinstalar**.
- **Desinstalar borra la base local.** Y la base local es el trabajo del día sin subir.

O sea: repartir hoy un APK «nuevo» le puede costar a un logístico el trabajo de la tarde, y
el aviso que verá es un «la aplicación no se pudo instalar» que no explica nada.

Lo que se cambió: el fichero ahora usa una clave de verdad **si la hay**, y si no la hay
sigue compilando con la de depuración pero lo avisa desde Gradle:

```
AVISO: no hay android/key.properties, así que este APK va firmado con la
clave de DEPURACIÓN. Android NO lo acepta como actualización de uno firmado
con otra clave: obliga a desinstalar, y desinstalar BORRA LA BASE LOCAL (el
trabajo del día sin subir). No se reparte. Ver docs/actualizaciones.md.
```

Compilar sin clave tiene que seguir funcionando —hace falta para `flutter run --release` y
para que cualquiera pueda clonar el repositorio y compilar—; lo que no puede pasar es que
salga un APK firmado con depuración y alguien lo reparta creyéndolo bueno.

> **Y ojo con esto, que se comprobó el 15/09/2026 y no es lo que uno esperaría:** con
> `flutter build apk --release` **el aviso NO se ve**. La herramienta de Flutter se traga la
> salida corriente de Gradle y sólo la enseña cuando el build falla. El aviso sale con
> `flutter build apk --release -v`, o llamando a Gradle directo.
>
> Por eso **la comprobación que vale es la de abajo, `apksigner`**, y no «no me salió
> ningún aviso».

### Cómo se configura la clave de verdad

**No se genera aquí ninguna clave y no se inventa ninguna contraseña.** Esto lo hace Jose,
una vez, en su equipo, y las contraseñas las elige y las guarda él.

**1. Crear el almacén de claves** (una sola vez en la vida del proyecto; `keytool` viene con
el JDK):

```bash
keytool -genkey -v \
  -keystore ~/procovar-reparto.jks \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias reparto
```

Pide dos contraseñas —la del almacén y la del alias— y unos datos de identificación.
Elígelas tú y guárdalas donde van las cosas de esta casa: `procovar/.secretos/`, con
permisos 600.

> **Este fichero es irreemplazable.** Si se pierde, **no hay forma** de publicar una
> actualización que Android acepte encima de lo instalado: habría que desinstalar en los
> diez aparatos, y eso es borrar la base local de los diez. Copia de seguridad fuera del
> portátil, y fuera del repositorio.
>
> `10000` días son unos 27 años. Una validez corta caduca y deja el mismo problema.

**2. En el equipo de quien compila**, crear `app/android/key.properties` (ya está en
`.gitignore`, junto con `*.jks`):

```properties
storeFile=/ruta/absoluta/a/procovar-reparto.jks
storePassword=<la que elegiste para el almacén>
keyAlias=reparto
keyPassword=<la que elegiste para el alias>
```

Con eso, `flutter build apk --release` sale firmado con la buena y el aviso desaparece.

**3. Comprobar con qué clave salió.** Esto se mira **en el APK ya hecho**, que es el único
sitio donde la respuesta es segura (`apksigner` viene con el SDK de Android, en
`$ANDROID_HOME/build-tools/<version>/`):

```bash
# En este equipo: ~/Android/sdk/build-tools/36.0.0/apksigner
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

Hoy, en este repositorio, eso contesta **`CN=Android Debug`** — comprobado el 15/09/2026
sobre el APK que sale de `flutter build apk --release`:

```
Signer #1 certificate DN: C=US, O=Android, CN=Android Debug
```

Cuando la clave de verdad esté puesta, ahí saldrá el nombre que hayas escrito al crearla, y
**no** `Android Debug`. El `SHA-256` que salga es la identidad del APK para Android:
**apúntalo en `procovar/.secretos/`**, que es lo que permite comprobar de un vistazo, dentro
de un año, si un APK que apareció por ahí es de los nuestros o uno de depuración que alguien
dejó suelto.

### Si algún día el APK se compila en otra máquina

No hace falta hoy —se compila en el portátil de Jose— pero la regla es la misma en
cualquier sitio: **el `.jks` y sus contraseñas no se copian a ningún servicio ajeno sin
pensarlo**. Quien tenga ese fichero y esas contraseñas puede publicar un APK que los diez
aparatos aceptarán como actualización del bueno. Si un día se automatiza, van como secretos
cifrados y nunca en el repositorio — por eso `key.properties`, `*.jks` y `*.keystore` están
en `.gitignore`.

## 5. La comprobación en el aparato

`app/lib/nucleo/actualizacion/`:

| Fichero | Qué hay |
|---|---|
| `version_publicada.dart` | `Plataforma`, `VersionInstalada`, `VersionPublicada` y `hayQueActualizar` |
| `comprobador.dart` | `ComprobadorDeActualizacion` y los cinco estados |

Y en `app/lib/nucleo/proveedores.dart`: `clienteVersionProvider`, `comprobadorProvider` y
`actualizacionProvider`.

### Los cinco estados

`EstadoDeActualizacion` es **sellado**, así que la pantalla que lo mire tiene que tratar los
cinco. Eso es lo que impide que «no se pudo comprobar» acabe pintado como «está al día».

| Estado | Qué pasó | Qué se enseña |
|---|---|---|
| `AlDia` | no hay nada más nuevo, o no se anuncia ninguna | nada |
| `NoAplica` | web, o no hay fichero para esta plataforma | nada |
| `NoSeSupo` | no hubo red, o el servidor contestó algo raro | **nada** |
| `SePuedeActualizar` | hay una nueva, con su enlace | el aviso, que se puede cerrar |
| `PrimeroSube` | hay una nueva **y queda cola** | «sube primero, te quedan N» |

`NoSeSupo` no se enseña a propósito. No saber si hay versión nueva no es una noticia para
quien está trabajando: se mira mañana.

### Dos decisiones que parecen detalles

**El cliente de esta comprobación no reintenta.** `clienteVersionProvider` monta un
`ClienteApi` propio con `ComprobadorDeActualizacion.sinEsperas`. El de las pantallas
reintenta a 1 s, 4 s, 15 s y 60 s, que es lo correcto para el trabajo de alguien y lo peor
posible aquí: ochenta segundos esperando para averiguar algo que puede esperar a mañana,
justo cuando la persona quiere entrar.

**Manda la compilación, no el número de versión.** `hayQueActualizar` compara los
`versionCode` cuando se saben los dos, porque es lo único que Android compara de verdad al
instalar encima. Sin compilación se comparan los números del `1.5.0` **tramo a tramo, como
números**: comparados como texto, `"1.10.0" < "1.9.0"`, y la 1.10 no se anunciaría nunca.
Ante la duda, `false`: un aviso de más manda a alguien a reinstalar lo que ya tiene; uno de
menos llega mañana.

## 6. Lo que falta

- [ ] **Dónde se cuelgan los ficheros.** Se compilan a mano (`docs/compilar.md`) y hay que
      ponerlos en una URL estable. No está decidido y **no se ha inventado**: mientras no lo
      esté, `APP_ULTIMA_VERSION` se queda vacía y no se anuncia nada, que es el estado
      seguro. El candidato natural es una carpeta servida por el nginx de la web en el VPS
      —ya hay un servidor de estáticos ahí y sale por el dominio de siempre—; una Release de
      GitHub daría URL estable pero el repositorio es privado y habría que ver cómo se baja
      eso desde el teléfono de un logístico.
- [ ] **La clave de firma**, §4. Hasta que exista, cualquier APK que salga de aquí es de
      usar y tirar. **Esto va primero que lo demás**: el día que haya una clave de verdad,
      el APK que ya esté instalado en los aparatos habrá que desinstalarlo igual, así que
      cuanto antes se haga, menos gente lo sufre.
- [ ] **Enchufar el aviso a una pantalla.** `actualizacionProvider` está montado y probado,
      pero **nadie lo mira todavía**: no se tocó `app/lib/pantallas/`. Lo que falta es una
      pantalla que haga `ref.watch(actualizacionProvider)` y pinte los cinco casos —con el
      cajón en móvil y el modal en escritorio, como todo lo demás—. Después de subir la cola
      conviene `ref.invalidate(actualizacionProvider)`, para que un `PrimeroSube` se
      convierta en `SePuedeActualizar` sin reiniciar.
- [ ] **Decidir si el aviso se repite.** Hoy se comprueba una vez por arranque, cuando
      alguien mira el provider. Si el aviso se cierra, no vuelve hasta el siguiente
      arranque. Puede estar bien; hay que verlo con gente usándolo.
