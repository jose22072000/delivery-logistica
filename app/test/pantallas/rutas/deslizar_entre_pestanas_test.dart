// LAS TRES PESTAÑAS DE RUTAS, CON FLECHAS Y CON EL DEDO.
//
// `Activas · En curso · Historial` eran tres botones y nada más: para cambiar
// había que acertarle a uno. Ahora hay una flecha a cada lado y la lista se
// pasa deslizando, igual que en el Tablero y en Reportes.
//
// Lo que esto vigila, además del gesto: que la lista que se ve sea la de la
// pestaña que se ve. Mientras el dedo arrastra se asoman DOS listas a la vez, y
// si las dos le preguntaran al provider «¿cuál está elegida?» pintarían lo
// mismo y el deslizamiento parecería no hacer nada hasta soltar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/pestanas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/pantalla_rutas.dart';
import 'package:reparto/idioma.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() async {
    base = baseDePrueba();
    await sembrarCatalogo(base);
    // Una de cada: así cada pestaña tiene algo suyo y se nota cuál se ve.
    await sembrarRuta(base, id: 'R1', codigo: 'RT-ACTIVA', creada: ahora);
    await sembrarRuta(
      base,
      id: 'R2',
      codigo: 'RT-ENCURSO',
      estado: EstadoRuta.enCurso,
      creada: ahora,
    );
    await sembrarRuta(
      base,
      id: 'R3',
      codigo: 'RT-VIEJA',
      estado: EstadoRuta.completada,
      creada: ahora,
    );
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);
  });

  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Un teléfono: una sola columna, sin detalle al lado.
  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1200);
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
  }

  IconButton flecha(WidgetTester tester, Key cual) =>
      tester.widget<IconButton>(find.byKey(cual));

  testWidgets('deslizando se recorren las tres pestañas', (tester) async {
    await pintar(tester);
    expect(find.text('RT-ACTIVA'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-250, 0), 1000);
    await asentar(tester);
    expect(
      find.text('RT-ENCURSO'),
      findsOneWidget,
      reason: 'deslizar a la izquierda tiene que traer `En curso`',
    );
    expect(
      find.text('RT-ACTIVA'),
      findsNothing,
      reason:
          'y dejar atrás la anterior: si las tres páginas leyeran la pestaña '
          'elegida en vez de la suya, pintarían todas lo mismo',
    );

    await tester.fling(find.byType(PageView), const Offset(-250, 0), 1000);
    await asentar(tester);
    expect(find.text('RT-VIEJA'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(250, 0), 1000);
    await asentar(tester);
    expect(find.text('RT-ENCURSO'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('a MEDIO deslizar ya se ve la lista de la que llega', (
    tester,
  ) async {
    await pintar(tester);

    // El dedo a medio camino, SIN soltar: se ven las dos páginas, la que se va
    // por un lado y la que llega por el otro.
    final gesto = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    // En dos tirones: el primero se lo come el umbral con el que Flutter
    // decide que esto es un arrastre y no un toque, así que con uno solo la
    // página de al lado no llega a asomar.
    await gesto.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesto.moveBy(const Offset(-180, 0));
    await tester.pump();

    expect(
      find.text('RT-ACTIVA'),
      findsOneWidget,
      reason: 'la que se está dejando sigue a la vista',
    );
    expect(
      find.text('RT-ENCURSO'),
      findsOneWidget,
      reason:
          'y la que llega tiene que traer LO SUYO. Si las tres páginas le '
          'preguntaran al provider cuál está elegida, la de al lado pintaría '
          'otra vez `Activas` y el deslizamiento parecería no hacer nada hasta '
          'soltar',
    );

    await gesto.up();
    await asentar(tester);

    await desmontar(tester);
  });

  testWidgets('las flechas cambian de pestaña y se apagan en los extremos', (
    tester,
  ) async {
    await pintar(tester);

    expect(
      flecha(tester, ClavesDePestanas.atras).onPressed,
      isNull,
      reason: '`Activas` es la primera: por la izquierda no hay nada',
    );

    await tester.tap(find.byKey(ClavesDePestanas.adelante));
    await asentar(tester);
    expect(find.text('RT-ENCURSO'), findsOneWidget);
    expect(flecha(tester, ClavesDePestanas.atras).onPressed, isNotNull);

    await tester.tap(find.byKey(ClavesDePestanas.adelante));
    await asentar(tester);
    expect(find.text('RT-VIEJA'), findsOneWidget);
    expect(
      flecha(tester, ClavesDePestanas.adelante).onPressed,
      isNull,
      reason: '`Historial` es la última',
    );

    await tester.tap(find.byKey(ClavesDePestanas.atras));
    await asentar(tester);
    expect(find.text('RT-ENCURSO'), findsOneWidget);

    await desmontar(tester);
  });
}
