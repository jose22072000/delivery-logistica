import 'almacen_sesion.dart';
import 'sesion.dart';

/// Web: **no se guarda nada**.
///
/// El login unico de auth deja su cookie y Dio va con `withCredentials: true`.
/// Meter el par de tokens en `localStorage` seria dejarlo al alcance de
/// cualquier script de la pagina, y ademas duplicaria la sesion que el navegador
/// ya lleva.
///
/// Que `leer()` devuelva `null` aqui NO es «no hay sesion»: es «la sesion no la
/// llevo yo». Quien decide si hay sesion en web es el servidor al contestar.
AlmacenDeSesion abrirAlmacenDeSesion() => const AlmacenPorCookie();

class AlmacenPorCookie implements AlmacenDeSesion {
  const AlmacenPorCookie();

  @override
  Future<Sesion?> leer() async => null;

  @override
  Future<void> guardar(Sesion sesion) async {}

  /// Cerrar sesion en web lo hace `POST /logout` de auth, que retira su cookie.
  @override
  Future<void> borrar() async {}
}
