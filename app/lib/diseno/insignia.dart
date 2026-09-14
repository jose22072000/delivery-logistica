import 'package:flutter/material.dart';

import 'colores.dart';

/// Una etiqueta pequena de estado. Texto corto, fondo tenue, letra del color.
class Insignia extends StatelessWidget {
  const Insignia(
    this.texto, {
    this.color = Colores.gris,
    this.fondo,
    super.key,
  });

  /// Las tres de ruta del pliego (§9.3): `planned` ambar, `in_progress` azul,
  /// `completed` verde. Estan aqui para que las cinco pantallas que pintan
  /// estado de ruta no elijan cada una su tono.
  factory Insignia.deEstadoDeRuta(String estado) => switch (estado) {
    'planned' => const Insignia(
      'planned',
      color: Colores.ambar,
      fondo: Colores.ambarFondo,
    ),
    'in_progress' => const Insignia(
      'in progress',
      color: Colores.azul,
      fondo: Colores.azulFondo,
    ),
    'completed' => const Insignia(
      'completed',
      color: Colores.verde,
      fondo: Colores.verdeFondo,
    ),
    // Lo desconocido se pinta, no se esconde: la base guarda el texto del
    // servidor tal cual para que un valor nuevo no reviente nada.
    _ => Insignia(estado.replaceAll('_', ' ')),
  };

  final String texto;
  final Color color;
  final Color? fondo;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: fondo ?? Colores.grisFondo,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      texto,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: color, fontWeight: FontWeight.w600),
    ),
  );
}
