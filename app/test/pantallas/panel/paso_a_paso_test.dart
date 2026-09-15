/// EL PASO A PASO DE LA PUESTA EN MARCHA.
///
/// Lo que se prueba aqui es lo que decide si alguien se va al almacen a dar de
/// alta un camion que ya existe:
///
///  * con todo configurado **no sale**;
///  * faltando el vehiculo sale y señala ESE paso;
///  * **vacio y no-bajado se dicen distinto**;
///  * y el paso de la tasa no ofrece un boton que no lleva a ningun sitio.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/colores.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/panel/datos/configuracion_pendiente.dart';
import 'package:reparto/pantallas/panel/vista/paso_a_paso.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  // ───────────────────────── sembrar ─────────────────────────

  Future<void> bajada(String coleccion) =>
      base
          .into(base.frescura)
          .insertOnConflictUpdate(
            FrescuraCompanion.insert(
              coleccion: coleccion,
              bajadaAt: Value(DateTime(2026, 9, 15, 8)),
              completa: const Value(true),
            ),
          );

  Future<void> sucursal({
    String id = 'b1',
    String codigo = 'STG',
    bool conPunto = true,
  }) => base
      .into(base.branches)
      .insertOnConflictUpdate(
        BranchesCompanion.insert(
          id: id,
          name: 'Santiago',
          lat: 20.02,
          lng: -75.82,
          externalId: Value(codigo),
          originConfigured: Value(conPunto),
        ),
      );

  Future<void> vehiculo({String id = 'v1', String? sucursalId = 'b1'}) => base
      .into(base.vehicles)
      .insertOnConflictUpdate(
        VehiclesCompanion.insert(
          id: id,
          name: 'Camión #1',
          branchId: Value(sucursalId),
        ),
      );

  Future<void> almacen({
    String id = 'a1',
    String codigo = 'STG',
    bool conPunto = true,
    bool activo = true,
  }) => base
      .into(base.warehouses)
      .insertOnConflictUpdate(
        WarehousesCompanion.insert(
          id: id,
          sucursalCodigo: codigo,
          nombre: 'Almacén central',
          lat: Value(conPunto ? 20.02 : null),
          lng: Value(conPunto ? -75.82 : null),
          principal: const Value(true),
          activo: Value(activo),
        ),
      );

  Future<void> tasa({DateTime? cuando, double cupRate = 320}) => base
      .into(base.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(
          id: const Value(1),
          cupRate: Value(cupRate),
          cupRateUpdatedAt: Value(cuando),
        ),
      );

  /// Todo bajado y todo puesto: el aparato de una sucursal que ya trabaja.
  Future<void> todoEnSuSitio() async {
    for (final c in [
      Colecciones.sucursales,
      Colecciones.vehiculos,
      Colecciones.almacenes,
      Colecciones.ajustes,
    ]) {
      await bajada(c);
    }
    await sucursal();
    await vehiculo();
    await almacen();
    await tasa(cuando: DateTime(2026, 9, 15, 7));
  }

  Future<ElPasoAPaso> mirar({String? sucursalId}) =>
      ConfiguracionPendiente(base).mirar(sucursalId: sucursalId).first;

  // ───────────────────────── el detector ─────────────────────────

  group('que detecta', () {
    test('con todo configurado NO hay paso a paso', () async {
      await todoEnSuSitio();

      final estado = await mirar();
      expect(estado.pendientes, isEmpty);
      expect(estado.seEnsena, isFalse, reason: 'no falta nada: no se pinta');
    });

    test('faltando el vehiculo sale, y señala ESE paso', () async {
      await todoEnSuSitio();
      await base.delete(base.vehicles).go();

      final estado = await mirar();
      expect(estado.seEnsena, isTrue);
      expect(estado.pendientes.map((p) => p.clave), [ClaveDePaso.vehiculo]);
      expect(estado.paso(ClaveDePaso.vehiculo).como, ComoVa.falta);
      expect(estado.hechos, hasLength(3));
    });

    test('VACIO y NO BAJADO no son lo mismo', () async {
      await todoEnSuSitio();

      // 1) La coleccion se bajo y no hay ninguno: FALTA. Hay que dar de alta.
      await base.delete(base.vehicles).go();
      expect((await mirar()).paso(ClaveDePaso.vehiculo).como, ComoVa.falta);

      // 2) La coleccion NO se bajo: no se sabe. Se arregla trayendo el dia, y
      //    la fila de vehiculos podria existir en el servidor perfectamente.
      await (base.delete(
        base.frescura,
      )..where((f) => f.coleccion.equals(Colecciones.vehiculos))).go();
      final sinBajar = await mirar();
      expect(sinBajar.paso(ClaveDePaso.vehiculo).como, ComoVa.sinSaber);
      expect(
        sinBajar.paso(ClaveDePaso.vehiculo).explicacion,
        PasoDeConfiguracion.textoSinDescargar,
      );
      // Y el de al lado, que si se bajo, sigue diciendo lo suyo.
      expect(sinBajar.paso(ClaveDePaso.almacen).como, ComoVa.hecho);
    });

    test('un aparato recien puesto no ensena el paso a paso', () async {
      // Nada bajado: los cuatro pasos en «no se sabe». Lo primero es traer el
      // dia, y de eso se ocupa `EstadoDelDia`.
      final estado = await mirar();
      expect(estado.noSeSabeNada, isTrue);
      expect(estado.seEnsena, isFalse);
    });

    test('la sucursal sin punto de partida se caza', () async {
      await todoEnSuSitio();
      await sucursal(conPunto: false);

      final estado = await mirar();
      expect(estado.paso(ClaveDePaso.puntoDePartida).como, ComoVa.falta);
      // Y NO ofrece boton: no se arregla en esta aplicacion.
      expect(estado.paso(ClaveDePaso.puntoDePartida).ruta, isNull);
      expect(
        estado.paso(ClaveDePaso.puntoDePartida).dondeSeArregla,
        isNotNull,
      );
    });

    test('con dos sucursales, una sin punto deja el paso pendiente', () async {
      await todoEnSuSitio();
      await sucursal(id: 'b2', codigo: 'HAB', conPunto: false);

      // Mirando TODAS: el paso no esta hecho, porque en una no lo esta.
      expect((await mirar()).paso(ClaveDePaso.puntoDePartida).como, ComoVa.falta);
      // Mirando sólo la que si lo tiene: hecho.
      expect(
        (await mirar(sucursalId: 'b1')).paso(ClaveDePaso.puntoDePartida).como,
        ComoVa.hecho,
      );
    });

    test('un almacen SIN coordenadas no cuenta: desde ahi no se mide', () async {
      await todoEnSuSitio();
      await almacen(conPunto: false);

      expect((await mirar()).paso(ClaveDePaso.almacen).como, ComoVa.falta);
    });

    test('un almacen inactivo tampoco cuenta', () async {
      await todoEnSuSitio();
      await almacen(activo: false);

      expect((await mirar()).paso(ClaveDePaso.almacen).como, ComoVa.falta);
    });

    test('el almacen de OTRA sucursal no tapa el hueco', () async {
      await todoEnSuSitio();
      await base.delete(base.warehouses).go();
      await almacen(id: 'a9', codigo: 'HAB');

      expect((await mirar(sucursalId: 'b1')).paso(ClaveDePaso.almacen).como,
          ComoVa.falta);
    });

    test('el vehiculo de OTRA sucursal no tapa el hueco', () async {
      await todoEnSuSitio();
      await base.delete(base.vehicles).go();
      await vehiculo(id: 'v9', sucursalId: 'b2');

      expect((await mirar(sucursalId: 'b1')).paso(ClaveDePaso.vehiculo).como,
          ComoVa.falta);
    });

    test('la tasa se mide por la MARCA, no por el 320 del esquema', () async {
      await todoEnSuSitio();
      // Una fila de ajustes bajada sin tasa: `cupRate` se queda en su 320 por
      // defecto. Eso NO es una tasa puesta.
      await tasa(cuando: null);

      expect((await mirar()).paso(ClaveDePaso.tasa).como, ComoVa.falta);
    });

    test('el paso de la tasa dice donde se arregla y NO lleva a ningún sitio',
        () async {
      await todoEnSuSitio();
      await tasa(cuando: null);

      final paso = (await mirar()).paso(ClaveDePaso.tasa);
      expect(paso.ruta, isNull, reason: 'no hay pantalla que lo arregle');
      expect(paso.textoDelBoton, isNull);
      expect(paso.dondeSeArregla, contains('Accesos'));
    });
  });

  // ───────────────────────── lo que se ve ─────────────────────────

  group('lo que se pinta', () {
    Future<void> pintar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [baseProvider.overrideWithValue(base)],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: PasoAPaso()),
            ),
          ),
        ),
      );
      // Sin `await` sobre el primer valor del stream: se bombea y se mira lo
      // pintado. Esperar un stream de Drift dentro de un test de widget cuelga
      // la prueba entera.
      await tester.pump();
      await tester.pump();
    }

    Future<void> desmontar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
    }

    testWidgets('con todo configurado no se pinta NADA', (tester) async {
      await todoEnSuSitio();
      await pintar(tester);

      expect(find.text('Falta configurar esta sucursal'), findsNothing);
      await desmontar(tester);
    });

    testWidgets('faltando el vehiculo sale su paso, con su botón', (
      tester,
    ) async {
      await todoEnSuSitio();
      await base.delete(base.vehicles).go();
      await pintar(tester);

      expect(find.text('Falta configurar esta sucursal'), findsOneWidget);
      expect(find.text('Al menos un vehículo'), findsOneWidget);
      expect(find.textContaining('paso 3 del asistente'), findsOneWidget);
      expect(find.text('Agregar el primer vehículo'), findsOneWidget);
      // Los tres que ya estan salen en una linea y sin botón.
      expect(find.text('La tasa de cambio de la sucursal'), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('no-bajado se dice con OTRAS palabras y en otro color', (
      tester,
    ) async {
      await todoEnSuSitio();
      await (base.delete(
        base.frescura,
      )..where((f) => f.coleccion.equals(Colecciones.vehiculos))).go();
      await pintar(tester);

      // El texto es el de «no se ha descargado», no el de «no hay ninguno».
      expect(
        find.textContaining('no lo ha descargado todavía'),
        findsOneWidget,
      );
      expect(find.textContaining('paso 3 del asistente'), findsNothing);
      // Y NO se ofrece dar de alta nada: esto se arregla trayendo el día.
      expect(find.text('Agregar el primer vehículo'), findsNothing);

      // Azul, no ámbar: son dos cosas distintas y se ven distintas.
      final linea = tester.widget<Text>(
        find.textContaining('no lo ha descargado todavía'),
      );
      expect(linea.style?.color, Colores.azul);
      await desmontar(tester);
    });

    testWidgets('el paso de la tasa no pinta ningún botón', (tester) async {
      await todoEnSuSitio();
      await tasa(cuando: null);
      await pintar(tester);

      expect(find.text('La tasa de cambio de la sucursal'), findsOneWidget);
      expect(find.textContaining('la mantiene Accesos'), findsOneWidget);
      // Ni encendido ni apagado: ninguno.
      expect(find.byType(FilledButton), findsNothing);
      await desmontar(tester);
    });
  });
}
