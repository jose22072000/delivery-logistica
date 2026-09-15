// La pestaña se va CON la ruta.
//
// Iniciar una ruta la saca de `Activas` —bien: ya no está activa, está en
// curso— y hasta ahora nadie tocaba la pestaña, así que la ruta le desaparecía
// de delante a quien acababa de arrancarla: se quedaba mirando un hueco en
// `Activas` convencido de que el botón no había hecho nada. La de Next lleva a
// la pestaña nueva en los dos casos (`routes/page.tsx:447` y `463-464`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/pantalla_rutas.dart';
import 'package:reparto/textos/textos.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() async {
    base = baseDePrueba();
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', codigo: 'RT-001', creada: ahora);
    await sembrarPedido(base, id: 'p1', cliente: 'Ana', rutaId: 'R1', orden: 1);
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);
  });

  tearDown(() => base.close());

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: const Scaffold(body: PantallaRutas()),
        ),
      ),
    );
    await asentar(tester);
    // La ruta, elegida: el detalle con sus botones sale a la derecha.
    await tester.tap(find.text('RT-001'));
    await asentar(tester);
  }

  testWidgets('al INICIAR, la pestaña pasa a `En curso` y la ruta se ve', (
    tester,
  ) async {
    await pintar(tester);

    expect(find.text('Activas (1)'), findsOneWidget);
    expect(find.text('En curso (0)'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar ruta'));
    await asentar(tester);

    // Los contadores dicen que se movió...
    expect(find.text('Activas (0)'), findsOneWidget);
    expect(find.text('En curso (1)'), findsOneWidget);
    // ...y lo que importa: **sigue delante**. Si la pestaña no se hubiera
    // movido, la lista de `Activas` estaría vacía y la tarjeta no saldría.
    // (Sale dos veces: la insignia de la tarjeta y la cabecera del detalle.)
    expect(find.text('RT-001'), findsNWidgets(2));
    expect(find.text('Sin rutas activas. Crea la primera.'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('al COMPLETAR, la pestaña pasa a `Historial` y suelta la ruta', (
    tester,
  ) async {
    await pintar(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar ruta'));
    await asentar(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Marcar como completada'),
    );
    await asentar(tester);

    expect(find.text('Historial (1)'), findsOneWidget);
    expect(find.text('RT-001'), findsOneWidget);
    // Y la ruta elegida se suelta: quedarse con el detalle de algo que ya se
    // cerró deja la pantalla hablando de lo que ya no va.
    expect(
      find.text('Selecciona una ruta para ver el detalle'),
      findsOneWidget,
    );

    await desmontar(tester);
  });
}
