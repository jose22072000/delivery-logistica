import 'package:flutter/material.dart';

import 'colores.dart';
import 'tema.dart';

/// Cargando, con su texto. El texto lo pone quien llama porque el pliego lo
/// escribe distinto en cada pantalla (`Cargando...`, `Cargando reporte...`) y
/// esos literales se comparan uno a uno contra la de Next.
class Cargando extends StatelessWidget {
  const Cargando(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: Colores.primario,
          ),
        ),
        const SizedBox(height: Aire.md),
        Text(
          texto,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Colores.tintaSuave),
        ),
      ],
    ),
  );
}
