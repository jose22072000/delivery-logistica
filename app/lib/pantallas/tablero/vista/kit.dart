import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Las cuatro piezas de pintar que usa el tablero. Viven aqui, dentro de la
/// pantalla, porque el kit comun de `lib/diseno/` todavia no esta escrito; el
/// dia que lo este, esto se cambia por aquello y nada mas.
abstract final class ColoresTablero {
  /// El ambar del pliego: «mira esto». Sólo para lo que de verdad puede
  /// enganar, porque pintarlo todo en ambar es no pintar nada.
  static const ambar = Color(0xFFB45309);

  /// Hoy no sale.
  static const rojo = Color(0xFFB91C1C);

  static const verde = Color(0xFF15803D);
}

final _km = NumberFormat('#,##0.0', 'es');
final _peso = NumberFormat('#,##0', 'es');
final _dinero = NumberFormat('#,##0.##', 'es');

String kmBonito(double km) => km.isFinite ? '${_km.format(km)} km' : 'sin ubicar';

String pesoBonito(double kg) => '${_peso.format(kg)} kg';

String dineroBonito(double usd) => '${_dinero.format(usd)} \$';

String horaBonita(DateTime cuando) => DateFormat('H:mm').format(cuando);

/// UN CAJON EN EL MOVIL, UN MODAL EN EL ESCRITORIO — y la ✕ no desaparece
/// nunca.
///
/// Es la regla de la casa para todos los proyectos de Procovar. Con el dedo, un
/// cajon que sube desde abajo se alcanza; un dialogo centrado, no. Y la ✕ se
/// queda siempre porque «toca fuera para cerrar» no se ve, no se adivina y en
/// una pantalla pequena no hay «fuera».
Future<T?> mostrarCajon<T>({
  required BuildContext context,
  required String titulo,
  required WidgetBuilder contenido,
}) {
  final anchoPantalla = MediaQuery.sizeOf(context).width;
  if (anchoPantalla < 720) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (contexto) => _Envoltorio(titulo: titulo, hijo: contenido(contexto)),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (contexto) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: _Envoltorio(titulo: titulo, hijo: contenido(contexto)),
      ),
    ),
  );
}

class _Envoltorio extends StatelessWidget {
  const _Envoltorio({required this.titulo, required this.hijo});

  final String titulo;
  final Widget hijo;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                titulo,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cerrar',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: hijo,
        ),
      ),
    ],
  );
}

/// Una insignia pequena. En rojo lo que hoy no sale, en ambar lo que sale
/// distinto.
class Insignia extends StatelessWidget {
  const Insignia(this.texto, {required this.color, super.key});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      texto,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: color, height: 1.2),
    ),
  );
}
