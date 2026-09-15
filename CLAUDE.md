# delivery-logistica — lo que hay que saber antes de tocar nada

Este fichero se carga solo al abrir cualquier cosa de este repo. El de
`procovar/CLAUDE.md` sigue mandando sobre lo del servidor y las credenciales;
esto es lo de **este** proyecto.

---

## 1. LA REGLA QUE MANDA SOBRE TODAS: qué trabaja sin conexión y qué no

Son **tres** formas de la misma aplicación y **no se comportan igual**. Esto no
es un detalle de implementación: es la razón de existir del proyecto, y Jose lo
ha tenido que repetir tres veces.

### La web NO trabaja sin conexión. Nunca.

> «el trabajo sin conexion es solo para las aplicaciones cojone la web siempre va
> a estar en internet»
> «la web siempre va a tener el internet por q esta en la nube eso es para la apk
> y la desktop quitame eso de la web»

En la web **no se enseña nada** del aparato de sin-conexión: ni «Configurando
Reparto», ni el botón de traer o entregar el día, ni la franja de «trabajando sin
conexión», ni el aviso de que el aparato no guarda la sesión. Se entra y ya se
está dentro.

La base local y la sincronización **siguen ahí por dentro** —las siete pantallas
leen de Drift, no del servidor, así que quitarlas dejaría la web en blanco— pero
son una caché de la que nadie habla. Se sincroniza sola y callada.

Lo que sí se dice en la web es que **ahora mismo** no hay conexión, si la pierde
a mitad. Lo que se quita es el aparato de **prepararse** para no tenerla.

### La APK de Android y la de escritorio SÍ, y tienen que hacerlo perfecto

> «las apk la de androide y la de desktop»

Ahí está todo: la configuración inicial con su porcentaje, traer el día,
entregarlo, trabajar la jornada entera sin señal, y que la sesión sobreviva a
cerrar la aplicación. **Es su razón de ser y no se negocia.**

La regla de la sesión, de `docs/identidad.md`:

> Para entrar hace falta conexión. Una vez dentro, no.

Y su contrapartida, que hay que tener presente al tocar esto: el par de tokens
dura 30 días (el de acceso, 15 minutos). Pasados ésos, o si Accesos rechaza la
renovación, la sesión muere y se vuelve a la puerta. Quien sea dado de baja deja
de entrar **en cuanto su aparato tenga señal**, no antes.

### Cómo se decide, en una pregunta

**¿Esto le sirve a alguien que abre un navegador con internet?** Si la respuesta
es «le explica algo que en su caso nunca pasa», fuera de la web.

---

## 2. El patrón se sigue SALVO donde se equivoca

`/mnt/datos/Work/procovar/delivery` (Next) es el patrón y casi siempre tiene
razón: sus comentarios largos guardan incidentes de verdad que costaron dinero.
Pero copiarlo con los ojos cerrados también trae sus fallos.

Cuando nos separemos del patrón, **se escribe por qué en el código**, con el caso
concreto. Ya hay tres así:

- **Reportes SÍ va en el menú.** El Next no lo tiene en su barra lateral y sólo
  se llega desde las acciones rápidas del Panel. Copiado fielmente, Jose no
  encontró la pantalla.
- **Un tipo de vehículo sin costo por km se deja VACÍO, no en cero.** El Next
  escribe `0`, y un cero guardado se lee como «el kilómetro es gratis»: un número
  creíble y equivocado. Un hueco se ve y se rellena.
- **Los avisos del armador son aviso, no bloqueo.** Los datos reales tenían 657
  de 686 domicilios sin costo: bloquear habría dejado la aplicación inservible.

---

## 3. Pedir un tope y no comprobar el resultado

**En un día cazamos tres veces el mismo fallo**, y por eso está aquí:

1. La bajada del aparato se quedaba en **2.000 clientes clavados** de 8.034: el
   servidor servía `LIMIT 2000` sin desplazamiento y marcaba `truncado`, y la
   tanda siguiente pedía exactamente lo mismo.
2. El barrido del espejo pedía `limit=5000` y **no miraba cuántos venían**.
   PEDIDO corta sin decirlo: **2.284 pedidos perdidos** en una sola ventana, con
   200 OK.
3. `POST /api/admin/recompute` **sigue igual** (`api/internal/api/espejo.go:349`):
   pide 5.000 de una ventana de 30 días que hoy son ~13.000. Sin arreglar.

La regla: **si pides un tope, comprueba si lo alcanzaste**, y si no puedes seguir
paginando, dilo con un aviso que nombre lo que se quedó fuera. Un truncamiento en
silencio es el fallo que más caro sale aquí, porque no se ve.

Y su pariente: **una respuesta vacía no es una respuesta buena.** Un catálogo de
Ventra vacío es un ERROR, no «no hay productos»: una base caída devuelve `[]` sin
error.

---

## 4. Lo que no puede pasar nunca

- **Nada se descarta en silencio.** Un apunte rechazado se queda a la vista con
  su motivo hasta que una persona decida. Una colección que no bajó se dice, y se
  dice **qué se rompe sin ella**. Si algo falla, la pantalla **no se queda
  verde**.
- **El alcance sale de quién pregunta, no de lo que mande el cliente.** Si
  saliera del parámetro, el logístico de Camagüey vería las otras siete
  cambiándolo. Ya pasó en delivery: un operador de Santiago vio los precios de La
  Habana.
- **La tasa es POR SUCURSAL** y sin la de esa sucursal no se convierte nada: no
  se cae a la de otra ni a un número por defecto. En PEDIDO está contado así:
  «Granma enseñaba los 685 de La Habana como si fueran suyos: un importe así se
  lee bien y está mal, que es lo peor que puede pasarle a un número que alguien
  va a cobrar».
- **Quitar algo es quitarlo ENTERO**: sus tipos, sus llamadas, sus enlaces, su
  entrada de menú y sus pruebas.
- **Cajón siempre**, también en escritorio (excepción aprobada para este
  proyecto el 05/09/2026). Sin emojis en la interfaz.

---

## 5. Cómo se comprueba

`./comprobar.sh` desde la raíz: gofmt, vet, test, build y `sqlc diff` en `api/` y
`sync/`, y `analyze` + `test` en `app/`. Tiene que decir **«Todo en verde»**.

- `sqlc` está en `~/go/bin/sqlc`. **El código generado no se escribe a mano.**
- **Pruebas colgadas**: nada de `await` sobre el primer valor de un stream de
  Drift dentro de un widget test — el tiempo no avanza y la prueba se cuelga en
  vez de fallar. Usa `timeout 300` siempre.
- **Una prueba que copia la dirección del código que prueba no comprueba la
  dirección.** Las del Tablero repetían `/api/api/board` y todo salía verde
  mientras las diez llamadas daban 404.
- **Mutación**: rompe la guarda a propósito y comprueba que hay una prueba que la
  caza y que lo dice con un mensaje entendible. Si no la caza, la prueba no vale.

### La regla dura del entorno

`lib/nucleo/red/entorno.dart` tiene las URL de **producción** como `defaultValue`,
así que un `flutter build web` sin `--dart-define` deja una aplicación que llama a
`reparto.procovar.cloud` en cuanto alguien la abre. El `CLAUDE.md` de Procovar
prohíbe cualquier petición a un dominio de Procovar desde este PC —a la oficina le
bloquearon la IP por eso—, así que:

```bash
flutter build web --dart-define=API_URL=http://127.0.0.1:8099/api ...
grep -c "procovar\.cloud" build/web/main.dart.js   # tiene que dar 0
```

Y **cierra las pestañas y para los servidores al terminar**: una aplicación viva
dispara un ciclo de sincronización cada pocos minutos. Ya pasó.
