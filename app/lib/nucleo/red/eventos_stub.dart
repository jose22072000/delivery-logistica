/// SIN CANAL EN VIVO. La APK y el escritorio, de momento.
///
/// No es un olvido: en el aparato el canal costaria una conexion abierta todo el
/// dia contra la red de alla, y ahi lo que de verdad hace falta es push del
/// sistema (FCM), que despierta la aplicacion sin mantener nada vivo. Mientras
/// tanto manda el temporizador del vigia, que es lo que habia.
///
/// Devuelve un stream que se cierra al momento: quien escuche no se queda
/// esperando un aviso que no va a llegar.
Stream<String> escucharEventos(
  String urlBase,
  Future<String?> Function() token,
) => const Stream<String>.empty();

bool get hayCanalDeEventos => false;
