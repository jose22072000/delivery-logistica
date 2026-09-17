// EL CARRUSEL DE PESTAÑAS, CON EL DEDO DE VERDAD.
//
// Jose, 17/09/2026: «el slice te lo pedí con las opciones sin que aparezcan, que
// salga la que está, y entonces que salgan las bolas para que muestre como que
// hay otras opciones».
//
// O sea, tres cosas que se comprueban aquí, y ninguna leyendo el árbol de lejos:
//
//  1. **las demás pestañas NO se ven** — sólo el rótulo de la actual;
//  2. hay **tantas bolitas como sitios**, y la marcada es la de ahora;
//  3. deslizar a un lado y al otro cambia de pestaña, y la marca se mueve con
//     ella.
//
// Y las dos que no se pueden romper: deslizar en VERTICAL desplaza la lista sin
// cambiar de pestaña, y en los extremos no se puede seguir.
//
// Que el deslizamiento no se coma el arrastre de una tarjeta vive en
// `test/pantallas/tablero/deslizar_no_se_come_el_arrastre_test.dart`, porque el
// arrastre es del tablero.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/pestanas.dart';

void main() {
  /// Un banco de pruebas con lo mínimo: tres pestañas, su carrusel y tres listas
  /// largas dentro, para que haya algo que desplazar hacia abajo.
  Future<void> montar(WidgetTester tester, {int cuantas = 3}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_Banco(cuantas: cuantas));
    await tester.pumpAndSettle();
  }

  /// En qué pestaña estamos, leído de lo que se ve y no del estado interno: si
  /// el número dijera una cosa y la pantalla otra, la prueba tiene que fallar.
  int dondeEstamos(WidgetTester tester) {
    for (var i = 0; i < 9; i++) {
      if (find.textContaining('P$i-').evaluate().isNotEmpty) return i;
    }
    return -1;
  }

  IconButton flecha(WidgetTester tester, Key cual) =>
      tester.widget<IconButton>(find.byKey(cual));

  /// El tamaño de una bolita. La de la pestaña actual se ve más que las otras, y
  /// eso es lo que hace de marca.
  double tamanoDeBola(WidgetTester tester, int i) => tester
      .widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byKey(ClavesDePestanas.bola(i)),
          matching: find.byType(AnimatedContainer),
        ),
      )
      .first
      .constraints!
      .maxWidth;

  testWidgets('sólo se ve la pestaña en la que estás', (tester) async {
    await montar(tester);

    expect(find.text('Pestaña 0'), findsOneWidget);
    expect(
      find.text('Pestaña 1'),
      findsNothing,
      reason:
          'las opciones que no son la actual NO se enseñan: es exactamente lo '
          'que pidió Jose al corregir la fila de botones',
    );
    expect(find.text('Pestaña 2'), findsNothing);

    // Y al moverse cambia el rótulo: sigue habiendo uno solo.
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Pestaña 1'), findsOneWidget);
    expect(find.text('Pestaña 0'), findsNothing);
  });

  testWidgets('hay una bolita por pestaña y la marcada es la de ahora', (
    tester,
  ) async {
    await montar(tester);

    for (var i = 0; i < 3; i++) {
      expect(
        find.byKey(ClavesDePestanas.bola(i)),
        findsOneWidget,
        reason: 'las bolitas son lo único que dice que hay más pestañas',
      );
    }
    expect(find.byKey(ClavesDePestanas.bola(3)), findsNothing);

    expect(
      tamanoDeBola(tester, 0) > tamanoDeBola(tester, 1),
      isTrue,
      reason: 'la de la pestaña actual se ve más que las otras',
    );

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();

    expect(
      tamanoDeBola(tester, 1) > tamanoDeBola(tester, 0),
      isTrue,
      reason: 'y la marca se mueve con el dedo, o marca donde no estás',
    );
  });

  testWidgets('pulsar una bolita lleva a su pestaña', (tester) async {
    await montar(tester);

    await tester.tap(find.byKey(ClavesDePestanas.bola(2)));
    await tester.pumpAndSettle();

    expect(dondeEstamos(tester), 2);
    expect(find.text('Pestaña 2'), findsOneWidget);
  });

  testWidgets('deslizar a la izquierda avanza y a la derecha retrocede', (
    tester,
  ) async {
    await montar(tester);
    expect(dondeEstamos(tester), 0);

    // El dedo se va hacia la izquierda: llega la de la derecha.
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(
      dondeEstamos(tester),
      1,
      reason:
          'deslizar hacia la izquierda tiene que traer la pestaña siguiente',
    );

    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(dondeEstamos(tester), 0, reason: 'y hacia la derecha, la anterior');
  });

  testWidgets('las flechas cambian de pestaña', (tester) async {
    await montar(tester);

    await tester.tap(find.byKey(ClavesDePestanas.adelante));
    await tester.pumpAndSettle();
    expect(dondeEstamos(tester), 1);

    await tester.tap(find.byKey(ClavesDePestanas.atras));
    await tester.pumpAndSettle();
    expect(dondeEstamos(tester), 0);
  });

  testWidgets('en los extremos la flecha está APAGADA, no muerta', (
    tester,
  ) async {
    await montar(tester);

    expect(
      flecha(tester, ClavesDePestanas.atras).onPressed,
      isNull,
      reason:
          'en la primera pestaña la flecha de atrás no puede llevar a ningún '
          'sitio: apagada, no encendida sin hacer nada',
    );
    expect(flecha(tester, ClavesDePestanas.adelante).onPressed, isNotNull);

    await tester.tap(find.byKey(ClavesDePestanas.bola(2)));
    await tester.pumpAndSettle();

    expect(flecha(tester, ClavesDePestanas.atras).onPressed, isNotNull);
    expect(
      flecha(tester, ClavesDePestanas.adelante).onPressed,
      isNull,
      reason: 'en la última no hay a dónde seguir',
    );
  });

  testWidgets('con una sola pestaña no hay ni bolitas ni flechas', (
    tester,
  ) async {
    await montar(tester, cuantas: 1);

    expect(
      find.byKey(ClavesDePestanas.bola(0)),
      findsNothing,
      reason: 'un carrusel de uno no es un carrusel, y una bolita sola engaña',
    );
    expect(find.byKey(ClavesDePestanas.atras), findsNothing);
    expect(find.byKey(ClavesDePestanas.adelante), findsNothing);
    // El rótulo se queda: hay que saber qué se está mirando.
    expect(find.text('Pestaña 0'), findsOneWidget);
  });

  testWidgets('deslizar en VERTICAL desplaza la lista y NO cambia de pestaña', (
    tester,
  ) async {
    await montar(tester);
    expect(find.text('P0-0'), findsOneWidget);

    // El dedo sube: la lista baja. Es el gesto de todos los días.
    await tester.drag(find.byType(PageView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(
      find.text('P0-0'),
      findsNothing,
      reason:
          'el desplazamiento vertical de la lista es lo que más se usa: si el '
          'deslizamiento de pestañas se lo come, se cambió un fallo por otro',
    );
    expect(
      dondeEstamos(tester),
      0,
      reason: 'y arriba o abajo NO es cambiar de pestaña',
    );
  });
}

class _Banco extends StatefulWidget {
  const _Banco({required this.cuantas});

  final int cuantas;

  @override
  State<_Banco> createState() => _BancoState();
}

class _BancoState extends State<_Banco> {
  int _cual = 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          CarruselDePestanas(
            indice: _cual,
            cuantas: widget.cuantas,
            titulo: 'Pestaña $_cual',
            etiquetas: [for (var i = 0; i < widget.cuantas; i++) 'Pestaña $i'],
            alCambiar: (i) => setState(() => _cual = i),
          ),
          Expanded(
            child: CuerpoDeslizable(
              indice: _cual,
              cuantas: widget.cuantas,
              alCambiar: (i) => setState(() => _cual = i),
              pagina: (contexto, i) => ListView.builder(
                itemCount: 30,
                itemBuilder: (contexto, j) =>
                    SizedBox(height: 60, child: Text('P$i-$j')),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
