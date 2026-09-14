import 'package:flutter/material.dart';

/// Los colores del pliego, con nombre y con motivo.
///
/// Van aqui y no sueltos por las pantallas porque el ambar **significa algo** en
/// esta aplicacion: «mira esto, puede que te este enganando». Si cada pantalla
/// elige su tono, deja de ser una senal y pasa a ser decoracion.
abstract final class Colores {
  /// El primario. Es la semilla del tema y el color de lo que esta bien.
  static const indigo = Color(0xFF4F46E5);

  /// AMBAR = atencion. Lo usan: datos de mas de un dia, pedidos sin ruta,
  /// rutas `planned`, capacidad al 80 % y los informes que no estan al dia.
  static const ambar = Color(0xFFB45309);
  static const ambarFondo = Color(0xFFFEF3C7);

  /// VERDE = cerrado, cobrado, entregado.
  static const verde = Color(0xFF15803D);
  static const verdeFondo = Color(0xFFDCFCE7);

  /// AZUL = en marcha.
  static const azul = Color(0xFF1D4ED8);
  static const azulFondo = Color(0xFFDBEAFE);

  /// ROJO = rechazado o pasado de capacidad. No es lo mismo que ambar: el ambar
  /// avisa, el rojo impide.
  static const rojo = Color(0xFFB91C1C);
  static const rojoFondo = Color(0xFFFEE2E2);

  /// GRIS = lo normal, lo que no hay que mirar.
  static const gris = Color(0xFF6B7280);
  static const grisFondo = Color(0xFFF3F4F6);
  static const borde = Color(0xFFE5E7EB);
  static const fondo = Color(0xFFF9FAFB);
}

/// El tema de la aplicacion.
ThemeData temaDeReparto() {
  final esquema = ColorScheme.fromSeed(seedColor: Colores.indigo);
  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: Colores.fondo,
    dividerColor: Colores.borde,
    // Sin efecto de rebote en las tablas: con desplazamiento horizontal propio
    // el rebote hace creer que la tabla se acabo cuando queda media a la derecha.
    splashFactory: InkSparkle.splashFactory,
  );
}
