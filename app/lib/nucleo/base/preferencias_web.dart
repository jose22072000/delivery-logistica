import 'package:web/web.dart' as web;

import '../registro/registro.dart';

/// En la web, a `localStorage`: la base del navegador es en memoria y se vacia
/// en cada recarga. Es el mismo sitio donde ya vive la sesion.
bool get fueraDeLaBase => true;

String? leer(String clave) {
  try {
    final v = web.window.localStorage.getItem(_nombre(clave));
    return (v == null || v.isEmpty) ? null : v;
  } on Object catch (e) {
    // En modo privado de algunos navegadores `localStorage` lanza al tocarlo. Una
    // preferencia que no se puede leer no puede impedir entrar.
    Registro.info('no se pudo leer la preferencia $clave: $e');
    return null;
  }
}

void escribir(String clave, String? valor) {
  try {
    if (valor == null || valor.isEmpty) {
      web.window.localStorage.removeItem(_nombre(clave));
      return;
    }
    web.window.localStorage.setItem(_nombre(clave), valor);
  } on Object catch (e) {
    Registro.info('no se pudo anotar la preferencia $clave: $e');
  }
}

/// Con prefijo para no chocar con `reparto.sesion` ni con nada de otra
/// aplicacion servida desde el mismo dominio.
String _nombre(String clave) => 'reparto.pref.$clave';
