// LA CAJA DE UN TOPE NO PIDE INTRO, Y NO APLICA MEDIOS NÚMEROS.
//
// Viene de la misma queja que la caja de buscar, Jose el 22/09/2026 —«tengo q
// dar enter para q el filtro funcione»— y del mismo peligro de arreglarla mal:
// un número no se puede aplicar al vuelo como una palabra. Tecleando `12` un
// respiro de 400 ms aplicaría primero `1`, que es un número perfectamente
// válido y deja la lista casi vacía.
//
// Lo que se mide aquí, en pareja: que aplique sin Intro cuando el número está
// entero (al salir del campo) y que NO aplique mientras se está escribiendo.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/caja_de_numero.dart';

void main() {
  /// La caja con un botón al lado al que llevarse el foco: salir del campo es
  /// el gesto que se está midiendo, y sin otro sitio donde caer no se sale.
  Future<List<double?>> montar(
    WidgetTester tester, {
    double? valor,
    List<double?>? aplicados,
  }) async {
    final lista = aplicados ?? <double?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CajaDeNumero(
                valor: valor,
                pista: 'km máx.',
                alAplicar: lista.add,
              ),
              const TextField(key: ValueKey('otro')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return lista;
  }

  Future<void> salirDelCampo(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('otro')));
    await tester.pumpAndSettle();
  }

  testWidgets('sale del campo y el tope queda puesto, sin dar Intro', (
    tester,
  ) async {
    final aplicados = await montar(tester);

    await tester.enterText(find.byType(TextField).first, '12');
    await tester.pumpAndSettle();
    expect(
      aplicados,
      isEmpty,
      reason:
          'mientras se escribe no se aplica nada: `1` sería un tope válido '
          'y equivocado',
    );

    await salirDelCampo(tester);
    expect(aplicados, [12.0]);
  });

  testWidgets('Intro sigue aplicando, para quien tiene el hábito', (
    tester,
  ) async {
    final aplicados = await montar(tester);

    await tester.enterText(find.byType(TextField).first, '20');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(aplicados, [20.0]);
  });

  testWidgets('Intro y salir del campo no aplican el mismo tope dos veces', (
    tester,
  ) async {
    // Dos consultas iguales seguidas sobre la lista entera, y la segunda no
    // puede cambiar nada.
    final aplicados = await montar(tester);

    await tester.enterText(find.byType(TextField).first, '20');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await salirDelCampo(tester);

    expect(aplicados, [20.0]);
  });

  testWidgets('dejar el campo vacío QUITA el tope', (tester) async {
    final aplicados = await montar(tester, valor: 20);

    await tester.enterText(find.byType(TextField).first, '');
    await salirDelCampo(tester);

    expect(aplicados, [null]);
  });

  testWidgets('lo que no es un número no quita el tope ni se queda mintiendo', (
    tester,
  ) async {
    // Con `onSubmitted` puro, escribir `veinte` dejaba el campo diciendo
    // `veinte` y el filtro puesto en 20: la pantalla enseñaba un tope y
    // aplicaba otro.
    final aplicados = await montar(tester, valor: 20);

    await tester.enterText(find.byType(TextField).first, 'veinte');
    await salirDelCampo(tester);

    expect(aplicados, isEmpty, reason: 'el tope de verdad no se toca');
    expect(
      find.text('20'),
      findsOneWidget,
      reason: 'y el campo vuelve a decir lo que de verdad está aplicado',
    );
  });

  testWidgets('la coma vale como separador decimal', (tester) async {
    final aplicados = await montar(tester);

    await tester.enterText(find.byType(TextField).first, '3,5');
    await salirDelCampo(tester);

    expect(aplicados, [3.5]);
  });

  testWidgets('un tope puesto desde fuera se ve en el campo', (tester) async {
    // `Limpiar`, un enlace con otro tope, cambiar de sucursal.
    await montar(tester, valor: 20);
    expect(find.text('20'), findsOneWidget, reason: 'y sin el «.0» colgando');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CajaDeNumero(valor: null, pista: 'km máx.', alAplicar: (_) {}),
              const TextField(key: ValueKey('otro')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('20'), findsNothing, reason: '«Limpiar» vacía la caja');
  });

  testWidgets('lo que venga de fuera NO pisa lo que se está escribiendo', (
    tester,
  ) async {
    // La pareja de la de arriba, y la regla que costó cara en la caja de
    // buscar: el campo es de quien lo tiene en las manos.
    await montar(tester, valor: 20);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '35');
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CajaDeNumero(valor: 50, pista: 'km máx.', alAplicar: (_) {}),
              const TextField(key: ValueKey('otro')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('35'), findsOneWidget);
    expect(find.text('50'), findsNothing);
  });

  test('un entero se escribe sin el «.0» que le cuelga toString()', () {
    expect(CajaDeNumero.comoTexto(20), '20');
    expect(CajaDeNumero.comoTexto(3.5), '3.5');
    expect(CajaDeNumero.comoTexto(null), '');
  });
}
