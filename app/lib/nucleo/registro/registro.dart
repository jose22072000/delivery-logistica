import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// El registro de la aplicacion.
///
/// Existe como pieza propia y no como `print` suelto por una razon del pliego:
/// «nada se descarta en silencio». Un fallo que sólo se ve en la consola de
/// depuracion no se ve en el patio de un almacen, asi que todo lo que pasa por
/// aqui tiene un sitio donde acabar (hoy la consola; manana el registro del
/// aparato que lee `GET /sync/estado`).
abstract final class Registro {
  static void info(String mensaje) => _escribir('info', mensaje);

  static void aviso(String mensaje) => _escribir('aviso', mensaje);

  static void fallo(String mensaje, [Object? error, StackTrace? pila]) =>
      _escribir('fallo', mensaje, error, pila);

  static void _escribir(
    String nivel,
    String mensaje, [
    Object? error,
    StackTrace? pila,
  ]) {
    if (kReleaseMode && nivel == 'info') return;
    developer.log(
      mensaje,
      name: 'reparto.$nivel',
      error: error,
      stackTrace: pila,
    );
  }
}
