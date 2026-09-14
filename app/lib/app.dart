import 'package:flutter/material.dart';

/// El armazon de la aplicacion.
///
/// Hoy no pinta ninguna pantalla **a proposito**: las siete van despues del
/// nucleo (PLAN.md §2 — «ninguna pantalla se empieza sin las cinco piezas en
/// pie, porque las siete dependen de las cinco y arreglarlas despues significa
/// reescribir las siete»).
class RepartoApp extends StatelessWidget {
  const RepartoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Reparto',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F46E5)),
      useMaterial3: true,
    ),
    home: const _Nucleo(),
  );
}

class _Nucleo extends StatelessWidget {
  const _Nucleo();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Núcleo en pie: base local, cola, red, identidad y frescura.\n'
          'Las pantallas van después.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
