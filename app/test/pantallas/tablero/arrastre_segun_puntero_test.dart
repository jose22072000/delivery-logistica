import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/vista/columna.dart';
import 'package:reparto/pantallas/tablero/vista/kit.dart';
import 'package:reparto/pantallas/tablero/vista/tarjeta.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';

/// EL GESTO DEL ARRASTRE DEPENDE DEL PUNTERO, NO DEL APARATO.
///
/// Con **raton o lapiz** se arrastra del tiron. Con **el dedo** hace falta
/// mantener pulsado, porque ahi la lista se desplaza arrastrando y un arrastre
/// inmediato se la comeria.
///
/// De donde sale esto: estuvo con pulsacion larga para TODOS, y en la web no se
/// podia arrastrar nada. Jose, 17/09/2026: «en la web no tengo el drag and drop,
/// por que razon» y «no, que yo arrastre las cosas y no funcionen». El arrastre
/// estaba entero y el `PUT /api/board/placements/{id}` llegaba a contestar 200;
/// lo que no llegaba a empezar era el gesto: quien pincha y tira con el raton no
/// mantiene pulsados 200 ms jamas.
///
/// Por eso estas pruebas arrastran **de verdad**, con `startGesture` y su
/// `PointerDeviceKind`, en vez de mirar que widget hay montado: mirar el widget
/// es justo lo que no cazo el fallo, porque el `LongPressDraggable` estaba ahi y
/// se veia perfecto.
///
/// La pareja «en el movil no se arrastra» —por ancho, no por puntero— vive en
/// `sin_arrastre_en_movil_test.dart` y sigue valiendo entera: aqui todo se monta
/// por encima de [anchoDeDosMitades], que es donde el arrastre existe.
void main() {
  const pedido = TarjetaPedido(
    pedidoId: 'p-1',
    customerName: 'Yasmani Pérez',
    address: 'Calle 5 nº 12',
    weight: 12.5,
    kmAlAlmacen: 3.2,
    mismoCliente: 0,
    operationNumber: 'X-2992',
  );

  ColumnaTablero columna(String id, String nombre, int posicion) =>
      ColumnaTablero(
        id: id,
        branchId: 'suc-stg',
        nombre: nombre,
        posicion: posicion,
        pedidos: 0,
        pesoKg: 0,
        costoUsd: 0,
      );

  /// Lo que paso en cada prueba, recogido tal cual.
  late List<String> soltadas;
  late List<String> columnasSoltadas;
  late List<String> tocadas;

  setUp(() {
    soltadas = [];
    columnasSoltadas = [];
    tocadas = [];
  });

  /// El tablero en ESCRITORIO: «sin colocar» a la izquierda y una columna a la
  /// derecha, las dos a la vez, que es la unica forma en la que arrastrar tiene
  /// sentido.
  ///
  /// La columna es la de verdad ([ColumnaDelTablero]): su cabecera es la que se
  /// arrastra para reordenar zonas y su `alPulsarTarjeta` es el que la pantalla
  /// engancha a `AccionesTablero.moverTarjeta`.
  Future<void> montarTablero(
    WidgetTester tester, {
    List<TarjetaPedido> sinColocar = const [pedido],
    List<TarjetaColocada> dentro = const [],
    List<String> zonas = const ['Centro'],
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        // La cabecera de la zona ensena su importe, y el importe sale de la
        // tasa. Se da hecha: sin esto el `ProviderScope` abriria la base del
        // aparato de verdad solo para pintar un numero que estas pruebas ni
        // miran —y su stream de Drift deja el reloj sin parar nunca.
        overrides: [
          tasaDeLaMiradaProvider.overrideWithValue(
            const TasaDeLaMirada.no('en estas pruebas no hay tasa'),
          ),
        ],
        child: MaterialApp(
          theme: temaDeReparto(),
          home: Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 320,
                  child: ListView(
                    key: const Key('sin-colocar'),
                    children: [
                      for (final p in sinColocar)
                        TarjetaDePedido(
                          key: Key('suelta-${p.pedidoId}'),
                          pedido: p,
                          onTap: () => tocadas.add(p.pedidoId),
                        ),
                    ],
                  ),
                ),
                for (final (i, zona) in zonas.indexed)
                  Expanded(
                    child: ColumnaDelTablero(
                      key: Key('zona-$zona'),
                      columna: columna('col-${i + 1}', zona, i + 1),
                      // Solo la primera lleva tarjetas dentro: las pruebas del
                      // toque necesitan UNA tarjeta colocada, no varias.
                      tarjetas: i == 0 ? dentro : const [],
                      alSoltar: (datos, posicion) => soltadas.add(
                        '${datos.pedidoId}→col-${i + 1}@$posicion',
                      ),
                      alPulsarTarjeta: (t) => tocadas.add(t.pedido.pedidoId),
                      alAbrirMenu: () {},
                      alSoltarColumna: (a) =>
                          columnasSoltadas.add('${a.columnaId}→col-${i + 1}'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  final laTarjetaSuelta = find.byKey(const Key('suelta-p-1'));
  final laColumna = find.byKey(const Key('zona-Centro'));

  /// SI ALGO ESTA LEVANTADO SE VE DOS VECES: el que va pegado al puntero
  /// (`feedback`) y el hueco que deja atras. Quieto se ve una sola vez.
  ///
  /// Se cuenta asi y no buscando dentro del `Overlay` porque en una `MaterialApp`
  /// la aplicacion ENTERA cuelga del `Overlay` del `Navigator`: buscar ahi da
  /// por levantado lo que esta quieto y la prueba pasa siempre.
  bool estaLevantado(WidgetTester tester, String texto) =>
      tester.widgetList(find.text(texto)).length > 1;

  // ───────────────────────────────────────────────────────────────────────────
  // 1. CON RATON, DEL TIRON. Esta es la queja de Jose.
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('CON RATON la tarjeta se arrastra del tiron, sin esperar nada', (
    tester,
  ) async {
    await montarTablero(tester);

    final gesto = await tester.startGesture(
      tester.getCenter(laTarjetaSuelta),
      kind: PointerDeviceKind.mouse,
    );
    // NI UN MILISEGUNDO de espera: quien pincha con el raton tira en el acto.
    // Si aqui hiciera falta un `pump(Duration(...))`, el arrastre estaria roto
    // para todo el que use la web con un raton, que son todos.
    await gesto.moveTo(tester.getCenter(laColumna));
    await tester.pump();

    expect(
      estaLevantado(tester, 'Yasmani Pérez'),
      isTrue,
      reason:
          'la tarjeta tiene que estar LEVANTADA y pegada al puntero nada mas '
          'tirar de ella; si sigue quieta es que el gesto nunca empezo, que es '
          'lo que le pasaba a Jose en la web («que yo arrastre las cosas y no '
          'funcionen»)',
    );

    await gesto.up();
    await tester.pumpAndSettle();

    expect(soltadas, [
      'p-1→col-1@null',
    ], reason: 'soltada sobre la columna, el pedido tiene que acabar en ella');
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2. CON EL DEDO, DEL TIRON NO LEVANTA NADA. Y la lista sigue desplazandose.
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('CON EL DEDO, tirar del tiron NO levanta la tarjeta', (
    tester,
  ) async {
    await montarTablero(tester);

    final gesto = await tester.startGesture(
      tester.getCenter(laTarjetaSuelta),
      kind: PointerDeviceKind.touch,
    );
    await gesto.moveTo(tester.getCenter(laColumna));
    await tester.pump();

    expect(
      estaLevantado(tester, 'Yasmani Pérez'),
      isFalse,
      reason:
          'un dedo que se mueve enseguida esta DESPLAZANDO la lista, no '
          'arrastrando: levantar aqui es lo que hacia que quien bajaba a ver la '
          'tarjeta treinta se llevara una tarjeta sin querer',
    );

    await gesto.up();
    await tester.pumpAndSettle();
    expect(soltadas, isEmpty);
  });

  testWidgets('CON EL DEDO la lista se sigue desplazando', (tester) async {
    await montarTablero(
      tester,
      sinColocar: [
        for (var i = 0; i < 40; i++)
          TarjetaPedido(
            pedidoId: 'p-$i',
            customerName: 'Cliente $i',
            address: 'Calle $i',
            weight: 10,
            kmAlAlmacen: 1,
            mismoCliente: 0,
            operationNumber: 'X-$i',
          ),
      ],
    );

    final lista = find.byKey(const Key('sin-colocar'));
    final antes = tester.widget<Scrollable>(
      find.descendant(of: lista, matching: find.byType(Scrollable)),
    );
    expect(antes.controller?.position.pixels ?? 0, 0);

    // Un desplazamiento con el dedo es exactamente esto: bajar y moverse ya.
    await tester.drag(
      lista,
      const Offset(0, -400),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();

    final posicion = tester
        .state<ScrollableState>(
          find.descendant(of: lista, matching: find.byType(Scrollable)),
        )
        .position;
    expect(
      posicion.pixels,
      greaterThan(0),
      reason:
          'la lista tiene que haber bajado: el arrastre inmediato del raton no '
          'puede robarle el desplazamiento al dedo',
    );
    expect(soltadas, isEmpty, reason: 'y no puede haber movido ningun pedido');
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3. CON EL DEDO Y PULSACION LARGA, SI. Como hasta ahora.
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('CON EL DEDO y pulsacion larga la tarjeta si se arrastra', (
    tester,
  ) async {
    await montarTablero(tester);

    final gesto = await tester.startGesture(
      tester.getCenter(laTarjetaSuelta),
      kind: PointerDeviceKind.touch,
    );
    // Mantener pulsado: es el gesto de «agarrar» del movil, y sigue intacto.
    await tester.pump(const Duration(milliseconds: 400));
    await gesto.moveTo(tester.getCenter(laColumna));
    await tester.pump();

    expect(
      estaLevantado(tester, 'Yasmani Pérez'),
      isTrue,
      reason: 'con pulsacion larga el dedo SI levanta la tarjeta',
    );

    await gesto.up();
    await tester.pumpAndSettle();
    expect(soltadas, ['p-1→col-1@null']);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4. LA COLUMNA ENTERA, por su cabecera, con las mismas dos reglas.
  // ───────────────────────────────────────────────────────────────────────────

  group('la cabecera de la columna reordena el tablero', () {
    testWidgets('CON RATON se arrastra del tiron y la zona cambia de sitio', (
      tester,
    ) async {
      await montarTablero(tester, zonas: const ['Centro', 'Vista Alegre']);

      final gesto = await tester.startGesture(
        tester.getCenter(find.text('Centro (0)')),
        kind: PointerDeviceKind.mouse,
      );
      await gesto.moveTo(
        tester.getCenter(find.byKey(const Key('zona-Vista Alegre'))),
      );
      await tester.pump();

      expect(
        estaLevantado(tester, 'Centro (0)'),
        isTrue,
        reason:
            'reordenar zonas con el raton es lo mismo que mover tarjetas: se '
            'pincha y se tira, sin mantener nada pulsado',
      );

      await gesto.up();
      await tester.pumpAndSettle();

      expect(
        columnasSoltadas,
        ['col-1→col-2'],
        reason:
            '«Centro» soltada sobre «Vista Alegre» se pone donde estaba ella',
      );
    });

    testWidgets('CON EL DEDO del tiron no, y con pulsacion larga si', (
      tester,
    ) async {
      await montarTablero(tester, zonas: const ['Centro', 'Vista Alegre']);
      final cabecera = find.text('Centro (0)');
      final laOtraZona = find.byKey(const Key('zona-Vista Alegre'));

      final rapido = await tester.startGesture(
        tester.getCenter(cabecera),
        kind: PointerDeviceKind.touch,
      );
      await rapido.moveTo(tester.getCenter(laOtraZona));
      await tester.pump();
      expect(
        estaLevantado(tester, 'Centro (0)'),
        isFalse,
        reason:
            'con el dedo la tira de columnas se desplaza de lado arrastrando: '
            'levantar la zona del tiron se comeria ese desplazamiento',
      );
      await rapido.up();
      await tester.pumpAndSettle();
      expect(columnasSoltadas, isEmpty);

      final largo = await tester.startGesture(
        tester.getCenter(cabecera),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await largo.moveTo(tester.getCenter(laOtraZona));
      await tester.pump();
      expect(estaLevantado(tester, 'Centro (0)'), isTrue);
      await largo.up();
      await tester.pumpAndSettle();
      expect(columnasSoltadas, ['col-1→col-2']);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 5. TOCAR SIGUE SIENDO TOCAR, y soltar un arrastre NO es tocar.
  // ───────────────────────────────────────────────────────────────────────────

  group('el toque que abre «moverla a» sigue entero', () {
    const dentro = [
      TarjetaColocada(pedido: pedido, columnaId: 'col-1', posicion: 1),
    ];

    testWidgets('tocar la tarjeta con el RATON la sigue abriendo', (
      tester,
    ) async {
      await montarTablero(tester, sinColocar: const [], dentro: dentro);

      await tester.tap(
        find.text('Yasmani Pérez'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(
        tocadas,
        ['p-1'],
        reason:
            'pinchar sin mover no es arrastrar: el arrastre inmediato no acepta '
            'el gesto hasta que el puntero se mueve, asi que el toque que abre '
            '«moverla a» (`AccionesTablero.moverTarjeta`) se queda intacto',
      );
    });

    testWidgets('tocar la tarjeta con el DEDO la sigue abriendo', (
      tester,
    ) async {
      await montarTablero(tester, sinColocar: const [], dentro: dentro);

      await tester.tap(
        find.text('Yasmani Pérez'),
        kind: PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();

      expect(tocadas, ['p-1']);
    });

    testWidgets('soltar un arrastre NO abre «moverla a»', (tester) async {
      await montarTablero(tester);

      final gesto = await tester.startGesture(
        tester.getCenter(laTarjetaSuelta),
        kind: PointerDeviceKind.mouse,
      );
      await gesto.moveTo(tester.getCenter(laColumna));
      await tester.pump();
      await gesto.up();
      await tester.pumpAndSettle();

      expect(soltadas, ['p-1→col-1@null']);
      expect(
        tocadas,
        isEmpty,
        reason:
            'quien acaba de soltar una tarjeta en una columna NO quiere que se '
            'le abra encima el cajon de «moverla a»',
      );
    });
  });
}
