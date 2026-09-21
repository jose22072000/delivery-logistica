// LAS TRES PESTAÑAS DEL REPORTE, CON FLECHAS Y CON EL DEDO.
//
// Aquí el `TabBarView` ya se deslizaba solo desde el primer día —es un
// `PageView` por dentro—, así que lo que faltaba eran las flechas: en un
// teléfono las tres etiquetas no caben (`isScrollable: true`) y «Detalle de
// Órdenes» se queda fuera de la pantalla. Sin flechas, para llegar a ella hay
// que empujar la tira de pestañas a ciegas.
//
// Se comprueban las dos cosas, porque las dos se pueden romper por separado: que
// las flechas lleven a donde dicen, y que deslizar el cuerpo siga cambiando de
// pestaña.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/diseno/pestanas.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/informes/registro.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  final ahora = DateTime(2026, 9, 14, 10, 0);

  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> bajadaEntera(DateTime cuando) async {
    for (final coleccion in Colecciones.todas) {
      await base
          .into(base.frescura)
          .insert(
            FrescuraCompanion.insert(
              coleccion: coleccion,
              bajadaAt: Value(cuando),
              hasta: Value(cuando.toIso8601String()),
            ),
          );
    }
  }

  Future<void> pedido(String id) => base
      .into(base.orders)
      .insert(
        OrdersCompanion.insert(
          id: id,
          customerName: 'Cliente $id',
          address: 'Calle $id',
          price: const Value(10),
          createdAt: Value(DateTime(2026, 9, 13)),
        ),
      );

  /// Un teléfono: es donde las tres pestañas no caben y las flechas hacen falta.
  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: RepartoApp(
          enrutador: crearEnrutador(
            pantallas: [registrarInformes()],
            inicial: '/reports',
          ),
        ),
      ),
    );
    // LAS TIPOGRAFÍAS, ANTES DEL PRIMER FOTOGRAMA PINTADO.
    //
    // `google_fonts` saca los .ttf embebidos por `rootBundle`, que es asíncrono
    // DE VERDAD: dentro del reloj falso de un `testWidgets` esa carga no avanza
    // nunca. Sin esto, el primer fotograma que pinta este fichero se mide con la
    // tipografía de respaldo y se pinta con la buena, y Flutter lo caza con
    // `'debugSize == size': is not true` — un rojo que no habla de esta pantalla
    // y que encima se come el mensaje, porque el volcado del árbol revienta al
    // describir el párrafo a medio medir.
    //
    // Saltó el 21/09/2026, al meter el botón de `Exportar a Excel` en el bloque
    // de filtros: una etiqueta más en el primer fotograma y ya bastó. La misma
    // línea está en `exportar_test.dart`, por lo mismo.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  IconButton flecha(WidgetTester tester, Key cual) =>
      tester.widget<IconButton>(find.byKey(cual));

  testWidgets('las flechas recorren las tres pestañas, y se apagan al final', (
    tester,
  ) async {
    await bajadaEntera(ahora);
    await pedido('o-1');
    await montar(tester);

    // `Resumen`, la primera: no hay nada a la izquierda.
    expect(find.text('Total Órdenes'), findsOneWidget);
    expect(
      flecha(tester, ClavesDePestanas.atras).onPressed,
      isNull,
      reason: 'en la primera pestaña no hay a dónde ir hacia atrás',
    );

    await tester.tap(find.byKey(ClavesDePestanas.adelante));
    await tester.pumpAndSettle();
    expect(
      find.text('No hay datos de vehículos para los filtros seleccionados.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(ClavesDePestanas.adelante));
    await tester.pumpAndSettle();
    expect(
      flecha(tester, ClavesDePestanas.adelante).onPressed,
      isNull,
      reason: 'en la última pestaña la flecha no puede quedarse encendida',
    );
    expect(flecha(tester, ClavesDePestanas.atras).onPressed, isNotNull);

    await desmontar(tester);
  });

  testWidgets('deslizar el cuerpo también cambia de pestaña', (tester) async {
    await bajadaEntera(ahora);
    await pedido('o-1');
    await montar(tester);

    expect(find.text('Total Órdenes'), findsOneWidget);

    await tester.fling(find.byType(TabBarView), const Offset(-250, 0), 1000);
    await tester.pumpAndSettle();

    expect(
      find.text('No hay datos de vehículos para los filtros seleccionados.'),
      findsOneWidget,
      reason: 'el gesto del teléfono de toda la vida tiene que funcionar aquí',
    );
    // Y la flecha de atrás se entera: si la fila de arriba no escuchara al
    // controlador, seguiría apagada como en la primera pestaña.
    expect(flecha(tester, ClavesDePestanas.atras).onPressed, isNotNull);

    await desmontar(tester);
  });
}
