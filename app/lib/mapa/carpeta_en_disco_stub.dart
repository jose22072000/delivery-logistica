import 'carpeta_del_mapa.dart';

/// EN LA WEB NO HAY CARPETA DE MAPA. Regla 1: quien abre un navegador tiene
/// servidor detras, siempre, asi que guardarse Cuba en el navegador no le ahorra
/// nada a nadie.
///
/// Se lanza en vez de devolver una carpeta vacia para que, si esto llega a
/// llamarse en web, se vea y se arregle donde toca — en vez de dejar una
/// pantalla de descargas que no descarga nunca y no dice por que.
Future<CarpetaDelMapa> abrirLaCarpetaDelMapa() => throw UnsupportedError(
  'el paquete de mapa sin conexión es de la APK y del escritorio; en la web no '
  'hay ninguno',
);
