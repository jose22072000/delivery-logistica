import 'sesion.dart';

export 'almacen_sesion_stub.dart'
    if (dart.library.io) 'almacen_sesion_nativo.dart'
    if (dart.library.js_interop) 'almacen_sesion_web.dart';

/// Donde vive el par de tokens.
///
/// Son dos mundos distintos a proposito (`identidad.md`):
///
///  * **APK** → el almacen seguro del sistema (Keystore). La APK no lleva
///    ninguna clave dentro: manda usuario y contrasena por HTTPS y recibe el
///    par. Una APK se descompila.
///  * **Web** → no se guarda NADA. El login unico de auth deja su cookie y Dio
///    va con `withCredentials`. Por eso el almacen de web devuelve `null` y no
///    es un fallo: es que ahi el navegador ya lleva la sesion.
abstract interface class AlmacenDeSesion {
  Future<Sesion?> leer();
  Future<void> guardar(Sesion sesion);
  Future<void> borrar();
}

/// En memoria. Para los tests y para el destino que no tenga donde guardar.
class AlmacenEnMemoria implements AlmacenDeSesion {
  AlmacenEnMemoria([this._sesion]);

  Sesion? _sesion;

  @override
  Future<Sesion?> leer() async => _sesion;

  @override
  Future<void> guardar(Sesion sesion) async => _sesion = sesion;

  @override
  Future<void> borrar() async => _sesion = null;
}
