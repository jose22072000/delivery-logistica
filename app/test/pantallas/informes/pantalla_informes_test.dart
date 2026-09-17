import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/diseno/estado_vacio.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/informes/registro.dart';
import 'package:reparto/pantallas/informes/vista/pantalla_informes.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  final ahora = DateTime(2026, 9, 14, 10, 0);

  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// Deja TODAS las colecciones marcadas como bajadas a [cuando]. Hacen falta
  /// todas: la barra se queda con la mas vieja, y una sin bajar es «sin
  /// descargar» aunque las otras ocho esten al dia.
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

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
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
    await tester.pumpAndSettle();
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  Future<void> pedido(String id, {double precio = 10}) => base
      .into(base.orders)
      .insert(
        OrdersCompanion.insert(
          id: id,
          customerName: 'Cliente $id',
          address: 'Calle $id',
          price: Value(precio),
          createdAt: Value(DateTime(2026, 9, 13)),
        ),
      );

  testWidgets('sin nada descargado NO se pinta ninguna tabla de ceros', (
    tester,
  ) async {
    await montar(tester);

    // Una tabla de ceros se leeria como «no hubo ventas», que es lo contrario
    // de lo que pasa.
    expect(find.text(TextosNuevosDeInformes.sinNadaQueCuadrar), findsOneWidget);
    expect(find.byType(PantallaSinDescargar), findsOneWidget);
    expect(find.text('Resumen'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('con datos de hace mas de un dia lo dice: no sirve para cerrar', (
    tester,
  ) async {
    await bajadaEntera(DateTime(2026, 9, 12, 7, 0));
    await pedido('a');
    await montar(tester);

    expect(
      find.textContaining(TextosNuevosDeInformes.noSirveSinEstarAlDia),
      findsOneWidget,
    );
    // Aun asi se puede mirar: se avisa, no se esconde.
    expect(find.text('Resumen'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('al dia, dice de cuando son los datos y de donde salen', (
    tester,
  ) async {
    await bajadaEntera(DateTime(2026, 9, 14, 7, 42));
    await pedido('a');
    await montar(tester);

    expect(
      find.text(TextosNuevosDeInformes.cuadradoConElAparato('14/9/2026, 7:42')),
      findsOneWidget,
    );
    expect(
      find.textContaining(TextosNuevosDeInformes.noSirveSinEstarAlDia),
      findsNothing,
    );

    await desmontar(tester);
  });

  testWidgets('las pestanas y los filtros son los literales del pliego', (
    tester,
  ) async {
    await bajadaEntera(DateTime(2026, 9, 14, 7, 42));
    await pedido('a');
    await montar(tester);

    expect(find.text('Filtros'), findsOneWidget);
    expect(find.text('Desde'), findsOneWidget);
    expect(find.text('Hasta'), findsOneWidget);
    expect(find.text('Todos los vehículos'), findsOneWidget);
    // LAS TRES PESTANAS DEL PLIEGO, Y AQUI SALEN LAS TRES: esto se monta a
    // 1440, o sea un monitor. El carrusel —el rotulo de una y unas bolitas— es
    // del telefono, donde tres etiquetas no caben. Jose, 17/09/2026: «los tabs
    // así como están eran para el móvil, que casi no tiene espacio».
    expect(find.text('Resumen'), findsOneWidget);
    expect(find.text('Por Vehículo'), findsOneWidget);
    expect(find.text('Detalle de Órdenes'), findsOneWidget);
    // Las cuatro tarjetas del resumen, que es la pestana en la que se entra.
    expect(find.text('Total Órdenes'), findsOneWidget);
    expect(find.text('Ingresos Totales'), findsOneWidget);
    expect(find.text('Precio Promedio'), findsOneWidget);
    expect(find.text('Peso Total'), findsOneWidget);
    // `Limpiar` no sale si no hay ningun filtro puesto.
    expect(find.text('Limpiar'), findsNothing);
    // Y se cambia pulsandolas, que es lo que se hace en un monitor.
    for (final siguiente in ['Por Vehículo', 'Detalle de Órdenes']) {
      await tester.tap(find.widgetWithText(OutlinedButton, siguiente));
      await tester.pumpAndSettle();
      // La marcada es la que se acaba de pulsar.
      expect(find.widgetWithText(FilledButton, siguiente), findsOneWidget);
    }

    await desmontar(tester);
  });

  testWidgets('sin ordenes salen los tres vacios, cada uno con su texto', (
    tester,
  ) async {
    await bajadaEntera(DateTime(2026, 9, 14, 7, 42));
    await montar(tester);

    expect(
      find.text('No hay órdenes para los filtros seleccionados.'),
      findsOneWidget,
    );

    // A 1440 las tres pestañas están a la vista, así que se pulsa la suya. El
    // carrusel con flechas es del teléfono.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Por Vehículo'));
    await tester.pumpAndSettle();
    expect(
      find.text('No hay datos de vehículos para los filtros seleccionados.'),
      findsOneWidget,
    );

    await desmontar(tester);
  });
}
