import 'package:intl/intl.dart';

/// Formato de numeros para pintar, **provisional**.
///
/// Lo definitivo es `nucleo/formato/` (Dinero, Peso, Distancia), que es de otra
/// ola y trae la conversion USD/CUP con la tasa por sucursal. Mientras no este,
/// estas cuatro funciones evitan que cada pantalla invente su propio
/// `toStringAsFixed`, que es como acaban dos tablas dando dos numeros distintos
/// para la misma suma.
abstract final class Numeros {
  static final _entero = NumberFormat.decimalPattern('es');
  static final _dos = NumberFormat('#,##0.00', 'es');
  static final _uno = NumberFormat('#,##0.0', 'es');

  static String entero(num v) => _entero.format(v);

  /// Importes: **2 decimales siempre**, como el Excel del pliego.
  static String importe(num v) => _dos.format(v);

  /// Pesos: **1 decimal**, como el pliego (`<n.n> kg`).
  static String kg(num v) => '${_uno.format(v)} kg';

  /// Los kg del panel van REDONDEADOS, sin decimales: es el subtexto de una
  /// tarjeta, no una factura.
  static String kgRedondeado(num v) => '${_entero.format(v.round())} kg';

  static String km(num v) => '${_uno.format(v)} km';
}
