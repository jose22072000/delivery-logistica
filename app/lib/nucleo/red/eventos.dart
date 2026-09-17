import 'eventos_stub.dart'
    if (dart.library.js_interop) 'eventos_web.dart'
    if (dart.library.io) 'eventos_io.dart'
    as destino;

// EL ORDEN DE LAS CLAUSULAS IMPORTA: Dart se queda con la PRIMERA que se cumple.
// `dart.library.js_interop` va delante para que la web siga eligiendo la suya
// pase lo que pase; `dart.library.io` coge la APK, el escritorio y las pruebas
// —que corren en la maquina virtual—. El `eventos_stub.dart` de la izquierda es
// lo que queda para un destino que no sea ninguno de los dos, y hoy no hay
// ninguno.

/// LO QUE CAMBIO EN EL SERVIDOR, en cuanto cambia.
///
/// ## Por que existe
///
/// Hasta hoy, lo que hacia una persona no aparecia en la pantalla de otra hasta
/// que pasaba el temporizador: **dos minutos en la web, cinco en la APK**. Con
/// dos personas trabajando el mismo tablero —una armando zonas en el telefono y
/// otra mirandolas desde el navegador— eso no es trabajar juntos, es trabajar
/// por turnos sin saberlo.
///
/// Jose, 16/09/2026: «hice un tablero en el movil, movi cosas, y en la web no
/// salio en tiempo real, ¿por que razon si eso debe pasar?».
///
/// El canal ya existia en el servidor (`GET /api/eventos`, SSE) desde el
/// principio. Lo que no habia era **nadie escuchandolo**: ni la web ni la APK.
/// Medio protocolo, otra vez.
///
/// ## Que NO hace
///
/// **No trae datos.** El aviso dice «los pedidos cambiaron», no cuales. Quien lo
/// recibe vuelve a pedir su lista, y esa si va acotada a su sucursal — si el
/// aviso llevara las filas dentro, habria que acotarlas aqui y seria un segundo
/// sitio donde equivocarse con el alcance.
///
/// **No sustituye al temporizador.** Es una mejora, no un cimiento: si el canal
/// se cae —un proxy que corta, una red que se va— el reloj sigue ahi y el trabajo
/// llega igual, sólo que mas tarde. Por eso esto nunca lanza: un aviso que no
/// llega no puede dejar a nadie sin sincronizar.
typedef EscuchaDeEventos = Stream<String> Function(
  String urlBase,
  Future<String?> Function() token, {
  Future<void> Function()? renovarSesion,
});

/// Abre el canal y devuelve el TIPO de cada cambio: `pedidos`, `rutas`,
/// `tablero`, `catalogo`, `clientes`.
///
/// El `listo` del principio y los latidos no salen por aqui: son del transporte y
/// no le dicen nada a una pantalla.
///
/// En los destinos donde todavia no hay implementacion devuelve un stream vacio,
/// y entonces manda el temporizador, que es exactamente lo de antes.
///
/// [token] se pide AL ABRIR, no antes, y otra vez en cada reconexion: el par de
/// tokens se renueva cada quince minutos y uno cogido al construir el proveedor
/// estaria caducado a la tercera vuelta.
///
/// [renovarSesion] es lo que se llama cuando el servidor contesta **401**, que
/// es lo que pasa cuando ese token de quince minutos caduca con el canal ya
/// abierto. No es un rechazo permanente y por eso no cierra el canal: se renueva
/// y se vuelve a abrir. Un 403 o un 404 si lo cierran para siempre. Por dentro es
/// el `Renovador`, con su candado de una sola renovacion en vuelo. Si no se
/// pasa, un 401 cierra el canal como cualquier otro 4xx.
///
/// Esto importa mas de lo que parece: el consuelo de «queda el temporizador» es
/// FALSO para Vehiculos y para Almacenes, que piden a la red y no viven de la
/// base local, asi que el ciclo no las repinta. Con el canal caido se quedan
/// clavadas hasta salir y volver a entrar.
///
/// **Como viaja ese token es lo unico distinto entre los dos destinos.** En la
/// web va por la cookie porque `EventSource` no sabe mandar cabeceras; en la APK
/// y el escritorio va en `Authorization: Bearer …`, que es lo normal y lo que ya
/// hace el resto de la aplicacion.
Stream<String> escucharEventos(
  String urlBase,
  Future<String?> Function() token, {
  Future<void> Function()? renovarSesion,
}) => destino.escucharEventos(urlBase, token, renovarSesion: renovarSesion);

/// `true` donde el canal esta implementado. Sirve para poder DECIRLO —y para que
/// una prueba no compruebe algo que en ese destino no existe—.
bool get hayCanalDeEventos => destino.hayCanalDeEventos;
