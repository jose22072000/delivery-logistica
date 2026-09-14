import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/navegacion/franja_de_estado.dart';
import 'package:reparto/nucleo/proveedores.dart';

import 'apoyo/base_de_prueba.dart';

/// El humo: la aplicacion de verdad, con el REGISTRO de verdad, arranca y pinta
/// su armazon.
///
/// (Este fichero venia del `flutter create` con el test del contador y una
/// `MyApp` que en este proyecto no ha existido nunca: no compilaba y ensuciaba
/// `flutter analyze`. Se sustituye por algo que sirva.)
void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets('arranca en el Panel, con la franja de estado arriba', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final base = baseDePrueba();
    addTearDown(base.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 14, 8, 30)),
        ],
        child: const RepartoApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Panel'), findsWidgets);
    expect(find.byType(FranjaDeEstado), findsOneWidget);

    // Desmontar aqui y no en un `tearDown`: las consultas de Drift sueltan un
    // temporizador al cancelarse y flutter_test lo comprueba antes.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  });
}
