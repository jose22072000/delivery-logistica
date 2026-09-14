import 'package:flutter/material.dart';

import 'colores.dart';

/// La caja de siempre: borde fino, fondo blanco, esquinas suaves.
class Tarjeta extends StatelessWidget {
  const Tarjeta({
    required this.child,
    this.titulo,
    this.relleno = const EdgeInsets.all(16),
    this.alPulsar,
    super.key,
  });

  final Widget child;
  final String? titulo;
  final EdgeInsetsGeometry relleno;
  final VoidCallback? alPulsar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final contenido = Padding(
      padding: relleno,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (titulo != null) ...[
            Text(
              titulo!,
              style: tema.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );

    return Material(
      color: tema.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: alPulsar,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colores.borde),
            borderRadius: BorderRadius.circular(12),
          ),
          child: contenido,
        ),
      ),
    );
  }
}

/// La tarjeta de cifra del Panel: etiqueta, numero grande y subtexto.
class TarjetaDeCifra extends StatelessWidget {
  const TarjetaDeCifra({
    required this.etiqueta,
    required this.valor,
    this.subtexto,
    this.color,
    this.icono,
    super.key,
  });

  final String etiqueta;
  final String valor;
  final String? subtexto;

  /// En ambar cuando hay algo que mirar; en primario cuando no. Lo decide la
  /// pantalla, no la tarjeta.
  final Color? color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final tinte = color ?? tema.colorScheme.primary;
    return Tarjeta(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  etiqueta,
                  style: tema.textTheme.bodySmall?.copyWith(color: Colores.gris),
                ),
                const SizedBox(height: 4),
                Text(
                  valor,
                  style: tema.textTheme.headlineSmall?.copyWith(
                    color: tinte,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtexto != null)
                  Text(
                    subtexto!,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: Colores.gris,
                    ),
                  ),
              ],
            ),
          ),
          if (icono != null) Icon(icono, color: tinte.withValues(alpha: 0.5)),
        ],
      ),
    );
  }
}
