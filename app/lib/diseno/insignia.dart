import 'package:flutter/material.dart';

import 'colores.dart';
import 'tema.dart';

/// Una etiqueta pequena de estado: pastilla de fondo tenue y la palabra del
/// color, en 11 px semibold. La misma de `RouteSummaryCard.tsx`
/// (`px-2 py-1 rounded-full text-xs font-medium`).
///
/// Nada de emojis: color y palabra.
class Insignia extends StatelessWidget {
  const Insignia(
    this.texto, {
    this.color = Colores.tintaSuave,
    this.fondo,
    this.tooltip,
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
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final pinta = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        // Sin `fondo` explicito se tinta el propio color al 10 %: asi una
        // insignia con un color nuevo no sale con el gris de otra.
        color: fondo ?? color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radios.pastilla),
      ),
      child: Text(
        texto,
        style: Tipos.texto(
          tamano: 11,
          peso: FontWeight.w600,
          color: color,
          interletra: 0.1,
        ),
      ),
    );
    return tooltip == null ? pinta : Tooltip(message: tooltip!, child: pinta);
  }
}
