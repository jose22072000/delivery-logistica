import 'cliente_api.dart';
import 'fallos.dart';

/// LA ESCRITURA DE LA WEB: se manda al servidor y SE ESPERA.
///
/// ## Por qué existe — medido en producción el 22/09/2026
///
/// Se armaba una ruta con tres pedidos en el navegador: el asistente se cerraba,
/// no salía ni un mensaje, y tras un F5 no había ruta. Se colocaba una tarjeta en
/// el Tablero: la ficha se cerraba, la tarjeta se quedaba donde estaba y
/// «Vista (0)» seguía en 0. La traza decía por qué: al pulsar «Generar Ruta» la
/// **única** petición que salía era `POST /sync/aparato`, y contestaba **401**.
///
/// La cadena entera, de arriba abajo:
///
///  1. `acciones_rutas.dart` y `tablero/datos/repositorio.dart` escribían en la
///     base local y **encolaban**. Es lo correcto en la APK y en el escritorio.
///  2. La cola sube por `/sync`, y para eso hace falta un aparato dado de alta.
///     En la web no hay par de tokens que guardar —la sesión es la cookie de
///     Accesos— así que el alta contestaba 401 y la cola **no salía nunca**.
///  3. Y la base de la web es **en memoria**: nace vacía en cada carga. O sea que
///     el apunte y su fila morían con la pestaña, sin que ninguna pantalla lo
///     desmintiera.
///
/// Es «el dato está y no se escribe» en la vista que usa el de la oficina.
///
/// ## Lo que hace esta pieza
///
/// `CLAUDE.md` §1, palabras de Jose: «la web siempre está en vivo porque saca de
/// la base de datos de la nube, no de una extra». Así que en la web el gesto
/// **va primero al servidor** y sólo se pinta si el servidor dijo que sí. No hay
/// cola, no hay id provisional y no hay nada que subir después.
///
/// **No hacía falta ni un endpoint nuevo.** Se midió antes de elegir camino: la
/// api ya tiene las cinco escrituras de Rutas (`POST /api/routes`,
/// `PATCH /api/routes/{id}` ×2, `DELETE /api/routes/{id}`,
/// `POST /api/routes/{id}/results`, en `api/internal/api/rutas.go`) y las siete
/// del Tablero (`api/internal/api/tablero.go`). Van montadas en su propio
/// fichero y no en `servidor.go`, que es donde no se ven.
///
/// Y la web **ya sabe autenticarse contra `/api/*`**: la cookie `token` viaja en
/// cada petición porque `InterceptorSesion.onRequest` pone
/// `options.extra['withCredentials'] = true` cuando `kIsWeb`
/// (`nucleo/red/interceptor_sesion.dart`), y el servidor la lee en
/// `auth.Verificador.DelaPeticion`. Es el mismo camino por el que ya funcionan
/// las treinta y tantas lecturas. Por eso esto no toca la puerta de nadie.
///
/// ## Cualquier fallo sale como un «no» CON SU MOTIVO
///
/// `CLAUDE.md` §3-quinquies: «en la web, lo que el servidor rechaza se dice, y
/// con su motivo literal». Un gesto que no llegó tampoco se puede pintar como
/// hecho, así que los tres fallos de `fallos.dart` salen por la misma puerta y
/// con el texto que cada uno sabe decir:
///
/// | Lo que pasó | Lo que se dice |
/// |---|---|
/// | 4xx que no es 401 | el literal del servidor, tal cual |
/// | red, tiempo agotado, 5xx | «Sin conexión con el servidor.» |
/// | 401 después de renovar | «La sesión terminó. Hay que entrar otra vez.» |
///
/// El 401 además ya disparó `alMorirLaSesion` dentro del interceptor, así que la
/// persona va camino de la puerta; lo que aquí se garantiza es que **el gesto no
/// se dio por hecho** mientras tanto.
class EscrituraEnVivo {
  const EscrituraEnVivo(this._cliente);

  final ClienteApi _cliente;

  /// Manda el gesto y espera la respuesta. Devuelve el cuerpo, o `null` si no
  /// vino ninguno (un `204`, por ejemplo).
  ///
  /// **Lanza [RechazoDelServidor] ante cualquier fallo.** Quien llama no puede
  /// escribir una sola fila hasta que esto vuelva sin lanzar: ése es el contrato
  /// entero de esta clase y lo que impide que la pantalla mienta.
  Future<Object?> mandar({
    required String metodo,
    required String ruta,
    Map<String, Object?> cuerpo = const <String, Object?>{},
  }) async {
    try {
      return await _cliente.mandar<Object?>(metodo, ruta, cuerpo);
    } on FalloApi catch (fallo) {
      throw RechazoDelServidor(
        fallo.mensaje,
        codigo: fallo is Rechazo ? fallo.codigo : null,
        cuerpo: fallo is Rechazo ? fallo.cuerpo : null,
      );
    }
  }
}

/// EL «NO», ya traducido a algo que se pinta.
///
/// [motivo] es **literal**: si vino del servidor, es su frase entera y sin
/// envolver. «Ese pedido ya va en otra ruta» le dice a alguien qué hacer; «no se
/// pudo guardar» no le dice nada (`CLAUDE.md` §3-quinquies).
class RechazoDelServidor implements Exception {
  const RechazoDelServidor(this.motivo, {this.codigo, this.cuerpo});

  /// El texto que se le enseña a la persona, tal cual.
  final String motivo;

  /// El cuerpo entero del «no», para los que traen una lista nombrada al lado
  /// de la frase (`descartados`, `pedidos`). Ver [Rechazo.cuerpo]. `null`
  /// cuando el fallo no fue un rechazo del servidor —red o sesión muerta—.
  final Object? cuerpo;

  /// El código HTTP, cuando el servidor llegó a contestar. `null` es que no
  /// contestó nadie (red) o que la sesión murió.
  final int? codigo;

  @override
  String toString() => 'RechazoDelServidor($codigo, $motivo)';
}
