import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/anchos.dart';
import 'package:reparto/diseno/cajon.dart';

void main() {
  Widget conAncho(double ancho, Widget hijo) => MediaQuery(
    data: MediaQueryData(size: Size(ancho, 800)),
    child: MaterialApp(home: Scaffold(body: hijo)),
  );

  testWidgets(
    'en escritorio el cajon `lg` mide 672 px, no la pantalla entera',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        conAncho(1440, const Cajon(titulo: 'Detalle', child: Text('cuerpo'))),
      );

      final caja = tester.getSize(
        find.descendant(
          of: find.byType(Cajon),
          matching: find.byType(SizedBox).first,
        ),
      );
      expect(caja.width, AnchoCajon.lg.px);
    },
  );

  testWidgets('en movil ocupa la pantalla entera', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      conAncho(390, const Cajon(titulo: 'Detalle', child: Text('cuerpo'))),
    );

    final caja = tester.getSize(
      find.descendant(
        of: find.byType(Cajon),
        matching: find.byType(SizedBox).first,
      ),
    );
    expect(caja.width, 390);
  });

  testWidgets('la ✕ siempre esta, y cierra', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (contexto) => TextButton(
              onPressed: () => abrirCajon<void>(
                contexto,
                titulo: 'Detalle del pedido',
                cuerpo: (_) => const Text('renglones'),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Detalle del pedido'), findsOneWidget);

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Detalle del pedido'), findsNothing);
  });
}
