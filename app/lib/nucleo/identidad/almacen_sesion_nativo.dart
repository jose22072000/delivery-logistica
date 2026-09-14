import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'almacen_sesion.dart';
import 'sesion.dart';

/// APK: Keystore / `EncryptedSharedPreferences`.
AlmacenDeSesion abrirAlmacenDeSesion() => AlmacenSeguro();

class AlmacenSeguro implements AlmacenDeSesion {
  AlmacenSeguro([FlutterSecureStorage? caja])
    : _caja =
          caja ??
          const FlutterSecureStorage(
            // Los valores por defecto de la version 11 ya son los buenos:
            // clave envuelta con RSA en el Keystore y datos con AES-GCM. Se
            // dejan a proposito SIN biometria: el logistico abre la aplicacion
            // con guantes en el patio de un almacen.
            aOptions: AndroidOptions(),
          );

  static const _clave = 'reparto.sesion';

  final FlutterSecureStorage _caja;

  @override
  Future<Sesion?> leer() async {
    final crudo = await _caja.read(key: _clave);
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

  @override
  Future<void> guardar(Sesion sesion) =>
      _caja.write(key: _clave, value: jsonEncode(sesion.aJson()));

  @override
  Future<void> borrar() => _caja.delete(key: _clave);
}
