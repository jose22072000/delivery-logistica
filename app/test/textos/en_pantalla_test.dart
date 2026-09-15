/// Que los textos lleguen de verdad a una pantalla.
///
/// Los otros dos ficheros miran los `.arb` y la clase generada por separado.
/// Esto monta un árbol de widgets de verdad, que es donde se descubre que
/// faltaba una delegación o que el idioma del aparato no cae donde debe.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/textos/textos.dart';

/// Una pantalla mínima que lee un texto por el atajo del `BuildContext`.
class _Pantalla extends StatelessWidget {
  const _Pantalla();

  @override
  Widget build(BuildContext context) => Text(context.textos.navPedidos);
}

Widget _app({Locale? idioma}) => MaterialApp(
  locale: idioma,
  localizationsDelegates: delegacionesDeIdioma,
  supportedLocales: idiomas,
  home: const _Pantalla(),
);

void main() {
  testWidgets('en español sale el texto en español', (WidgetTester t) async {
    await t.pumpWidget(_app(idioma: const Locale('es')));
    expect(find.text('Pedidos'), findsOneWidget);
  });

  testWidgets('en inglés sale el texto en inglés', (WidgetTester t) async {
    await t.pumpWidget(_app(idioma: const Locale('en')));
    expect(find.text('Orders'), findsOneWidget);
  });

  testWidgets('un idioma que no es ninguno de los dos cae en español', (
    WidgetTester t,
  ) async {
    // El almacén habla español: si el aparato viene en portugués, mejor español
    // que inglés.
    await t.pumpWidget(_app(idioma: const Locale('pt')));
    expect(find.text('Pedidos'), findsOneWidget);
  });

  testWidgets('las delegaciones de Material también están puestas', (
    WidgetTester t,
  ) async {
    await t.pumpWidget(_app(idioma: const Locale('es')));
    final BuildContext ctx = t.element(find.byType(Text));

    // `Cancelar`, no `Cancel`: es lo que sale en un selector de fecha.
    expect(MaterialLocalizations.of(ctx).cancelButtonLabel, 'Cancelar');
  });
}
