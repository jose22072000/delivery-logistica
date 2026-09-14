import 'package:flutter/material.dart';

/// Una tabla con **su propio** desplazamiento horizontal.
///
/// El pliego (§11) lo pide literalmente para Clientes y para las tablas del
/// pre-despacho: *«se desplaza la tabla, no la pagina»*. Sin esto, una tabla de
/// 736 px en una pantalla de 390 px empuja la pagina entera de lado y el menu,
/// la barra y el reloj de datos se van con ella.
class TablaAncha extends StatelessWidget {
  const TablaAncha({required this.child, this.anchoMinimo = 736, super.key});

  final Widget child;
  final double anchoMinimo;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, medidas) {
      final ancho = medidas.maxWidth;
      // Si cabe entera no se envuelve en un scroll: un `Scrollable` de mas se
      // come los gestos de las filas que se pueden pulsar.
      if (ancho >= anchoMinimo) return child;
      return Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: anchoMinimo, child: child),
        ),
      );
    },
  );
}
