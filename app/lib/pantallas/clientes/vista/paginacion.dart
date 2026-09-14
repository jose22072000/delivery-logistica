import 'package:flutter/material.dart';

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
          onPressed: pagina > 1 ? () => alIr(pagina - 1) : null,
          icon: const Text('◀'),
        ),
        Text('$pagina / $paginas'),
        IconButton(
          tooltip: 'Siguiente',
          onPressed: pagina < paginas ? () => alIr(pagina + 1) : null,
          icon: const Text('▶'),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          Text('$desde–$hasta de $total'),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: pagina > 1 ? () => alIr(pagina - 1) : null,
                child: const Text('Anterior'),
              ),
              Text('$pagina / $paginas'),
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
