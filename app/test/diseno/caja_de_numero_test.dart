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

  // ---------------------------------------------------------------------------
  // LOS TOPES QUE NO PUEDEN SER — 24/09/2026, probando la web con el navegador.
  //
  // Van EN PAREJA, las dos mitades de cada regla: que el aviso salte cuando toca
  // y que **no** salte cuando no. Un aviso que sale siempre deja de leerse, y
  // entonces tampoco se lee el día que importa (`CLAUDE.md` §3-quinquies).
  // ---------------------------------------------------------------------------

  testWidgets('un tope NEGATIVO se rechaza y se dice por qué', (tester) async {
    final aplicados = await montar(tester, valor: 20);

    await tester.enterText(find.byType(TextField).first, '-5');
    await salirDelCampo(tester);

    expect(
      aplicados,
      isEmpty,
      reason:
          'un `km máx. = -5` no lo cumple ningún pedido: la lista se quedaría '
          'en blanco sin que nada lo explique',
    );
    expect(find.text('20'), findsOneWidget, reason: 'el tope de verdad se queda');
    expect(
      find.text(CajaDeNumero.noPuedeSerNegativo),
      findsOneWidget,
      reason: 'y se dice, que un rebote mudo se lee como que el teclado no va',
    );
  });

  testWidgets('la otra mitad: un tope bueno NO saca ningún aviso', (
    tester,
  ) async {
    final aplicados = await montar(tester, valor: 20);

    await tester.enterText(find.byType(TextField).first, '35');
    await salirDelCampo(tester);

    expect(aplicados, [35.0]);
    expect(find.text(CajaDeNumero.noPuedeSerNegativo), findsNothing);
    expect(find.text(CajaDeNumero.noEsUnNumero), findsNothing);
  });

  testWidgets('el aviso se va en cuanto se corrige', (tester) async {
    await montar(tester, valor: 20);

    await tester.enterText(find.byType(TextField).first, '-5');
    await salirDelCampo(tester);
    expect(find.text(CajaDeNumero.noPuedeSerNegativo), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '5');
    await tester.pumpAndSettle();
    expect(
      find.text(CajaDeNumero.noPuedeSerNegativo),
      findsNothing,
      reason: 'a quien ya está corrigiendo no se le sigue diciendo lo que hizo',
    );
  });

  testWidgets('«NaN» y «Infinity» no son topes, aunque Dart los sepa leer', (
    tester,
  ) async {
    // `double.tryParse('NaN')` devuelve `NaN`, y un tope `NaN` no lo cumple
    // nadie —ni siquiera es igual a sí mismo—. Se colaba entero.
    for (final texto in const ['NaN', 'Infinity', '-Infinity']) {
      final aplicados = await montar(tester, valor: 20);
      await tester.enterText(find.byType(TextField).first, texto);
      await salirDelCampo(tester);
      expect(aplicados, isEmpty, reason: '«$texto» no es un tope');
      expect(find.text(CajaDeNumero.noEsUnNumero), findsOneWidget);
    }
  });

  testWidgets('LO QUE SE APLICA ES LO QUE SE LEE: «1,500» se aplica 1.5', (
    tester,
  ) async {
    // Quien escribe `1,500` pensando en mil quinientos se quedaba con el campo
    // diciendo `1,500` y el filtro puesto en 1.5. La pantalla enseñaba un tope
    // y aplicaba otro, que es justo lo que este widget viene a impedir.
    final aplicados = await montar(tester);

    await tester.enterText(find.byType(TextField).first, '1,500');
    await salirDelCampo(tester);

    expect(aplicados, [1.5]);
    expect(
      find.text('1.5'),
      findsOneWidget,
      reason: 'el campo dice lo que de verdad está filtrando',
    );
    expect(find.text('1,500'), findsNothing);
  });

  testWidgets('la otra mitad: un número ya bien escrito NO se reescribe', (
    tester,
  ) async {
    final aplicados = await montar(tester);

    await tester.enterText(find.byType(TextField).first, '3.5');
    await salirDelCampo(tester);

    expect(aplicados, [3.5]);
    expect(find.text('3.5'), findsOneWidget);
  });

  test('numeroDe deja fuera lo que no puede ser un tope', () {
    expect(CajaDeNumero.numeroDe('3,5'), 3.5);
    expect(CajaDeNumero.numeroDe('NaN'), isNull);
    expect(CajaDeNumero.numeroDe('Infinity'), isNull);
    expect(CajaDeNumero.numeroDe('-Infinity'), isNull);
    expect(CajaDeNumero.porQueNoVale(''), isNull, reason: 'vacío quita el tope');
    expect(CajaDeNumero.porQueNoVale('0'), isNull, reason: 'cero es un tope');
    expect(CajaDeNumero.porQueNoVale('-1'), CajaDeNumero.noPuedeSerNegativo);
    expect(CajaDeNumero.porQueNoVale('veinte'), CajaDeNumero.noEsUnNumero);
  });
}
