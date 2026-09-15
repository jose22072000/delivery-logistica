import 'package:flutter/material.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';

/// Los controles de arriba: `◀ <pagina> / <paginas> ▶`, junto al subtitulo.
class PaginacionCorta extends StatelessWidget {
  const PaginacionCorta({
    required this.pagina,
    required this.paginas,
    required this.alIr,
    super.key,
  });

  final int pagina;
  final int paginas;
  final ValueChanged<int> alIr;

  @override
  Widget build(BuildContext context) {
    if (paginas <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Anterior',
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          color: Colores.tintaSuave,
          onPressed: pagina > 1 ? () => alIr(pagina - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          '$pagina / $paginas',
          style: Tipos.mono(tamano: 12.5, color: Colores.tintaSuave),
        ),
        IconButton(
          tooltip: 'Siguiente',
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          color: Colores.tintaSuave,
          onPressed: pagina < paginas ? () => alIr(pagina + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

/// Los del pie: `<desde>–<hasta> de <total>` con `Anterior` / `Siguiente`.
///
/// Son DOS juegos a proposito (`pantallas.md` §4): con 50 filas, quien llega
/// abajo no quiere subir hasta arriba para pasar de pagina, y quien acaba de
/// filtrar no quiere bajar 50 filas para lo mismo.
class PaginacionLarga extends StatelessWidget {
  const PaginacionLarga({
    required this.pagina,
    required this.paginas,
    required this.desde,
    required this.hasta,
    required this.total,
    required this.alIr,
    super.key,
  });

  final int pagina;
  final int paginas;
  final int desde;
  final int hasta;
  final int total;
  final ValueChanged<int> alIr;

  @override
  Widget build(BuildContext context) {
    // Con cero no se pinta nada: una barra de paginacion sobre una lista vacia
    // sugiere que hay mas paginas donde mirar.
    if (total == 0) return const SizedBox.shrink();
    // `px-4 py-3 border-t bg-white`: va DENTRO de la caja de la tabla, que es
    // quien pone la linea de arriba.
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Aire.lg,
        vertical: Aire.md,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Aire.lg,
        runSpacing: Aire.sm,
        children: [
          Text.rich(
            TextSpan(
              style: Tipos.texto(tamano: 13, color: Colores.tintaSuave),
              children: [
                TextSpan(
                  text: '$desde–$hasta',
                  style: Tipos.mono(
                    tamano: 13,
                    peso: FontWeight.w600,
                    color: Colores.tinta,
                  ),
                ),
                const TextSpan(text: ' de '),
                TextSpan(
                  text: '$total',
                  style: Tipos.mono(
                    tamano: 13,
                    peso: FontWeight.w600,
                    color: Colores.tinta,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: pagina > 1 ? () => alIr(pagina - 1) : null,
                child: const Text('Anterior'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Aire.sm),
                child: Text(
                  '$pagina / $paginas',
                  style: Tipos.mono(tamano: 13, color: Colores.tintaSuave),
                ),
              ),
              TextButton(
                onPressed: pagina < paginas ? () => alIr(pagina + 1) : null,
                child: const Text('Siguiente'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
