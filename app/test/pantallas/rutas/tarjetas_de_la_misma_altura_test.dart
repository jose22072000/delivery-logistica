// LAS TARJETAS DE LA LISTA DE RUTAS MIDEN TODAS LO MISMO.
//
// Jose, 17/09/2026, comparando con el patrón: «ves, está más limpio, más
// organizado, más uniformes, todas las cajas misma altura, los cuerpos no se
// desintegran ni nada de eso ni se deforman».
//
// El fallo era un solo párrafo con los cinco datos pegados por puntos. Un
// párrafo envuelve según lo largo que sea el nombre del camión y la dirección,
// así que dos rutas seguidas salían de alturas distintas y la columna se veía
// temblando.
//
// Por eso la prueba **mide**: compara el alto de dos tarjetas con datos de
// largos muy distintos. Un `findsOneWidget` no dice nada de esto.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/lista_rutas.dart';
import 'package:reparto/textos/textos.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> pintar(WidgetTester tester) async {
    // ANCHO DE TELEFONO. A 1200 cabe cualquier dirección en una línea y el
    // fallo no existe: es justo lo que lo tapó hasta hoy.
    tester.view.physicalSize = const Size(390, 844);
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
          home: const Scaffold(
            body: ListaDeRutas(deLaPestana: PestanaRutas.enCurso),
          ),
        ),
      ),
    );
    await asentar(tester);
  }

  testWidgets('dos rutas con datos de largos muy distintos miden lo mismo', (
    tester,
  ) async {
    await sembrarCatalogo(base);
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);

    // La corta: todo cabe de sobra.
    await sembrarRuta(
      base,
      id: 'R1',
      codigo: 'RT-001',
      estado: EstadoRuta.enCurso,
      creada: ahora,
    );
    // La larga: una dirección que en un párrafo se llevaría tres líneas.
    await sembrarRuta(
      base,
      id: 'R2',
      codigo: 'RT-002',
      estado: EstadoRuta.enCurso,
      creada: ahora,
    );
    await (base.update(base.routes)..where((r) => r.id.equals('R2'))).write(
      const RoutesCompanion(
        originAddress: Value(
          '2da Paralela entre Simón Reyes y Beneficencia, Reparto La Caridad, '
          'Camagüey, Cuba, esquina al almacén viejo',
        ),
      ),
    );
    await pintar(tester);

    final altos = tester
        .widgetList<Card>(find.byType(Card))
        .map((c) => tester.getSize(find.byWidget(c)).height)
        .toList();
    expect(altos.length, 2, reason: 'tienen que salir las dos rutas');
    expect(
      altos.first,
      altos.last,
      reason:
          'LAS TARJETAS SE DESINTEGRAN: una dirección larga hace la tarjeta '
          'más alta que la de al lado. Medido con el renglón envolviendo: 152 '
          'contra 216, 64 píxeles de diferencia entre dos tarjetas seguidas. '
          'Cada dato va en su renglón de una línea, y lo que no cabe se corta '
          'con puntos suspensivos.',
    );

    await desmontar(tester);
  });

  testWidgets('la tarjeta dice cuántas paradas lleva, y no un cero de relleno', (
    tester,
  ) async {
    await sembrarCatalogo(base);
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);
    await sembrarRuta(
      base,
      id: 'R1',
      codigo: 'RT-001',
      estado: EstadoRuta.enCurso,
      creada: ahora,
    );
    for (var i = 0; i < 2; i++) {
      await sembrarPedido(
        base,
        id: 'p${i + 1}',
        cliente: 'Cliente ${i + 1}',
        rutaId: 'R1',
        orden: i + 1,
      );
    }
    // Y otra con UNA sola parada, para el singular.
    await sembrarRuta(
      base,
      id: 'R2',
      codigo: 'RT-002',
      estado: EstadoRuta.enCurso,
      creada: ahora,
    );
    await sembrarPedido(
      base,
      id: 'p3',
      cliente: 'Cliente 3',
      rutaId: 'R2',
      orden: 1,
    );
    await pintar(tester);

    // Como el patrón: «2 paradas · 0.0 km · …».
    expect(find.textContaining('2 paradas'), findsOneWidget);
    // Y LA DE UNA SOLA, EN SINGULAR. «1 paradas» se lee como un fallo de la
    // pantalla, y quien lo lee deja de fiarse del resto de los números.
    expect(find.textContaining('1 parada ·'), findsOneWidget);
    expect(find.textContaining('1 paradas'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('una ruta sin vehículo lo DICE, en vez de enseñar una raya', (
    tester,
  ) async {
    await sembrarCatalogo(base);
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);
    await sembrarRuta(
      base,
      id: 'R1',
      codigo: 'RT-001',
      estado: EstadoRuta.enCurso,
      vehiculoId: null,
      creada: ahora,
    );
    await pintar(tester);

    // Una raya no dice si falta el dato o si no hay camión asignado.
    expect(find.text('Sin vehículo'), findsOneWidget);

    await desmontar(tester);
  });
}
