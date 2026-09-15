import 'dart:convert';

import 'package:web/web.dart' as web;

import '../registro/registro.dart';
import 'almacen_sesion.dart';
import 'sesion.dart';

/// Web: el par de tokens, en el almacen del navegador.
///
/// **Por que aqui tambien se guarda el par.** El plan era que en web mandara la
/// cookie del login unico de auth (ver [AlmacenPorCookie], que se deja escrita
/// abajo para el dia que eso exista). Hoy no existe: la web del reparto entra
/// por la MISMA puerta que la APK —usuario y contrasena contra
/// `POST /api/auth/token`— y si aqui no se guardara nada, el interceptor no
/// tendria token que poner en las peticiones y cada recarga de la pagina
/// devolveria a la pantalla de acceso. Eso no es «mas seguro»: es la aplicacion
/// sin datos, que es lo que se vio al abrirla.
///
/// `localStorage` y no `sessionStorage`: el logistico recarga, cierra la pestana
/// y vuelve, y la regla de la casa es que quien entro sigue dentro. Lo que se
/// guarda es exactamente lo mismo que guarda la APK en el Keystore, con la
/// diferencia conocida de que en el navegador no hay Keystore — por eso el
/// acceso dura lo que dura el refresh y un 401 lo borra entero.
AlmacenDeSesion abrirAlmacenDeSesion() => const AlmacenDelNavegador();

class AlmacenDelNavegador implements AlmacenDeSesion {
  const AlmacenDelNavegador();

  static const clave = 'reparto.sesion';

  /// **No lanza nunca** — ver la regla en `almacen_sesion.dart`.
  @override
  Future<Sesion?> leer() async {
    final String? crudo;
    try {
      crudo = _caja?.getItem(clave);
    } on Object catch (e) {
      Registro.fallo('el navegador no dejo leer la sesion: $e');
      return null;
    }
    if (crudo == null) return null;
    try {
      return Sesion.deJson(jsonDecode(crudo) as Map<String, Object?>);
    } on Object {
      // Guardado ilegible: se trata como «no hay sesion», no como un fallo. Lo
      // peor que puede pasar es que la persona entre otra vez.
      await borrar();
      return null;
    }
  }

  /// Guarda el par **y comprueba que se puede volver a leer**, igual que la
  /// APK. En el navegador el modo de fallo es otro —ventana privada, sitio sin
  /// permiso para guardar, cuota llena— pero el resultado es el mismo: una
  /// promesa de trabajar sin senal que no se cumple. Ver `almacen_sesion.dart`.
  @override
  Future<bool> guardar(Sesion sesion) async {
    final texto = jsonEncode(sesion.aJson());
    final caja = _caja;
    if (caja == null) return false;
    try {
      caja.setItem(clave, texto);
      return caja.getItem(clave) == texto;
    } on Object catch (e) {
      Registro.fallo('el navegador no dejo guardar la sesion: $e');
      return false;
    }
  }

  @override
  Future<void> borrar() async {
    try {
      _caja?.removeItem(clave);
    } on Object catch (e) {
      Registro.aviso('el navegador no dejo borrar la sesion: $e');
    }
  }

  @override
  Future<SaludDelAlmacen> comprobar() async {
    final caja = _caja;
    if (caja == null) {
      return const SaludDelAlmacen.rota(
        'Este navegador no deja guardar la sesión.',
      );
    }
    const claveDePrueba = 'reparto.comprobacion';
    final testigo = DateTime.now().microsecondsSinceEpoch.toString();
    try {
      caja.setItem(claveDePrueba, testigo);
      final vuelta = caja.getItem(claveDePrueba);
      caja.removeItem(claveDePrueba);
      if (vuelta == testigo) return const SaludDelAlmacen.bien();
    } on Object catch (e) {
      Registro.aviso('el navegador no sirve para guardar la sesion: $e');
    }
    return const SaludDelAlmacen.rota(
      'Este navegador no deja guardar la sesión.',
    );
  }

  /// `localStorage` puede no estar: en modo privado de algunos navegadores el
  /// acceso lanza. Sin el, la aplicacion se comporta como si no hubiera sesion
  /// guardada —hay que entrar otra vez— en vez de no arrancar.
  static web.Storage? get _caja {
    try {
      return web.window.localStorage;
    } on Object catch (e) {
      Registro.aviso('el navegador no deja guardar la sesion: $e');
      return null;
    }
  }
}

/// El almacen del login unico, para cuando auth deje su cookie en la web.
///
/// Con el, `leer()` devolver `null` NO es «no hay sesion»: es «la sesion no la
/// llevo yo», y quien decide es el servidor al contestar. Mientras la web entre
/// con usuario y contrasena, el que se usa es [AlmacenDelNavegador].
class AlmacenPorCookie implements AlmacenDeSesion {
  const AlmacenPorCookie();

  @override
  Future<Sesion?> leer() async => null;

  @override
  Future<bool> guardar(Sesion sesion) async => true;

  /// Cerrar sesion en web lo hace `POST /logout` de auth, que retira su cookie.
  @override
  Future<void> borrar() async {}

  /// La lleva el navegador en su cookie, asi que no hay nada que comprobar.
  @override
  Future<SaludDelAlmacen> comprobar() async => const SaludDelAlmacen.bien();
}
