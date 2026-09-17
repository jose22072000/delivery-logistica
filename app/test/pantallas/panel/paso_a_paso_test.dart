/// EL PASO A PASO DE LA PUESTA EN MARCHA.
///
/// Lo que se prueba aqui es lo que decide si alguien se va al almacen a dar de
/// alta un camion que ya existe:
///
///  * con todo configurado **no sale**;
///  * faltando el vehiculo sale y señala ESE paso;
///  * **vacio y no-bajado se dicen distinto**;
///  * y el paso de la tasa no ofrece un boton que no lleva a ningun sitio.
///
/// Y con **las ocho a la vista**, que es donde esto mentia: un paso esta hecho
/// sólo si lo esta en TODAS, el aviso dice en cuantas falta, y lo que cuenta el
/// paso a paso es lo mismo que cuenta el asistente de rutas — no un comentario
/// que lo promete (`CLAUDE.md` §3-bis).
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
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  // ───────────────────────── sembrar ─────────────────────────

  Future<void> bajada(String coleccion) => base
      .into(base.frescura)
      .insertOnConflictUpdate(
        FrescuraCompanion.insert(
          coleccion: coleccion,
          bajadaAt: Value(DateTime(2026, 9, 15, 8)),
          completa: const Value(true),
        ),
      );

  /// [tasaTraidaAt] es lo que demuestra que hay tasa: la FECHA que dio Accesos,
  /// no el numero. La tasa vive en la sucursal, no en los ajustes globales.
  Future<void> sucursal({
    String id = 'b1',
    String codigo = 'STG',
    String nombre = 'Santiago',
    bool conPunto = true,
    DateTime? tasaTraidaAt,
    double? cupRate,
  }) => base
      .into(base.branches)
      .insertOnConflictUpdate(
        BranchesCompanion.insert(
          id: id,
          name: nombre,
          lat: 20.02,
          lng: -75.82,
          externalId: Value(codigo),
          originConfigured: Value(conPunto),
          cupRate: Value(cupRate ?? (tasaTraidaAt != null ? 700 : null)),
          cupRateTraidoAt: Value(tasaTraidaAt),
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

  /// La tasa de UNA sucursal. Antes esto escribia en `settings`, que es la
  /// global y vieja — la que hacia que Granma enseñara la de La Habana.
  Future<void> tasa({
    DateTime? cuando,
    double cupRate = 700,
    String id = 'b1',
    String codigo = 'STG',
    String nombre = 'Santiago',
  }) => sucursal(
    id: id,
    codigo: codigo,
    nombre: nombre,
    tasaTraidaAt: cuando,
    cupRate: cuando != null ? cupRate : null,
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

  /// LAS OCHO DE PROCOVAR, con sus codigos (`procovar/CLAUDE.md` §5). Los ids
  /// van en el orden alfabetico del NOMBRE, que es el que devuelve la consulta y
  /// por tanto el orden en el que se nombran las que faltan.
  const lasOcho = <(String, String, String)>[
    ('b1', 'CAM', 'Camagüey'),
    ('b2', 'GR', 'Granma'),
    ('b3', 'GTO', 'Guantánamo'),
    ('b4', 'HOL', 'Holguín'),
    ('b5', 'HAB', 'La Habana'),
    ('b6', 'TUN', 'Las Tunas'),
    ('b7', 'SS', 'Sancti Spíritus'),
    ('b8', 'STG', 'Santiago'),
  ];

  /// Las ocho bajadas y **todas completas**. Cada prueba quita despues lo que
  /// quiere probar: asi lo que se mide es el hueco y no el montaje.
  Future<void> lasOchoEnSuSitio() async {
    for (final c in [
      Colecciones.sucursales,
      Colecciones.vehiculos,
      Colecciones.almacenes,
      Colecciones.ajustes,
    ]) {
      await bajada(c);
    }
    for (final (id, codigo, nombre) in lasOcho) {
      await sucursal(
        id: id,
        codigo: codigo,
        nombre: nombre,
        tasaTraidaAt: DateTime(2026, 9, 15, 7),
      );
      await vehiculo(id: 'v-$id', sucursalId: id);
      await almacen(id: 'a-$id', codigo: codigo);
    }
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
      expect(estado.paso(ClaveDePaso.puntoDePartida).dondeSeArregla, isNotNull);
    });

    test('con dos sucursales, una sin punto deja el paso pendiente', () async {
      await todoEnSuSitio();
      await sucursal(id: 'b2', codigo: 'HAB', conPunto: false);

      // Mirando TODAS: el paso no esta hecho, porque en una no lo esta.
      expect(
        (await mirar()).paso(ClaveDePaso.puntoDePartida).como,
        ComoVa.falta,
      );
      // Mirando sólo la que si lo tiene: hecho.
      expect(
        (await mirar(sucursalId: 'b1')).paso(ClaveDePaso.puntoDePartida).como,
        ComoVa.hecho,
      );
    });

    test(
      'un almacen SIN coordenadas no cuenta: desde ahi no se mide',
      () async {
        await todoEnSuSitio();
        await almacen(conPunto: false);

        expect((await mirar()).paso(ClaveDePaso.almacen).como, ComoVa.falta);
      },
    );

    test('un almacen inactivo tampoco cuenta', () async {
      await todoEnSuSitio();
      await almacen(activo: false);

      expect((await mirar()).paso(ClaveDePaso.almacen).como, ComoVa.falta);
    });

    test('el almacen de OTRA sucursal no tapa el hueco', () async {
      await todoEnSuSitio();
      await base.delete(base.warehouses).go();
      await almacen(id: 'a9', codigo: 'HAB');

      expect(
        (await mirar(sucursalId: 'b1')).paso(ClaveDePaso.almacen).como,
        ComoVa.falta,
      );
    });

    test('el vehiculo de OTRA sucursal no tapa el hueco', () async {
      await todoEnSuSitio();
      await base.delete(base.vehicles).go();
      await vehiculo(id: 'v9', sucursalId: 'b2');

      expect(
        (await mirar(sucursalId: 'b1')).paso(ClaveDePaso.vehiculo).como,
        ComoVa.falta,
      );
    });

    test('la tasa se mide por la MARCA, no por el 320 del esquema', () async {
      await todoEnSuSitio();
      // Una fila de ajustes bajada sin tasa: `cupRate` se queda en su 320 por
      // defecto. Eso NO es una tasa puesta.
      await tasa(cuando: null);

      expect((await mirar()).paso(ClaveDePaso.tasa).como, ComoVa.falta);
    });

    test(
      'el paso de la tasa dice donde se arregla y NO lleva a ningún sitio',
      () async {
        await todoEnSuSitio();
        await tasa(cuando: null);

        final paso = (await mirar()).paso(ClaveDePaso.tasa);
        expect(paso.ruta, isNull, reason: 'no hay pantalla que lo arregle');
        expect(paso.textoDelBoton, isNull);
        expect(paso.dondeSeArregla, contains('Accesos'));
      },
    );
  });

  // ───────────────────────── lo que se ve ─────────────────────────

  // ─────────────────── con las ocho sucursales a la vista ───────────────────

  group('con «Todas las sucursales» arriba', () {
    test('un solo camión en Santiago NO tapa el hueco de las otras siete', () async {
      await lasOchoEnSuSitio();
      await base.delete(base.vehicles).go();
      await vehiculo(id: 'v-b8', sucursalId: 'b8');

      // Esto es lo que contaba mal: `COUNT(*) FROM vehicles > 0` daba «hecho»
      // por ese único camión y dejaba a siete sin poder armar una ruta.
      final todas = await mirar();
      expect(
        todas.paso(ClaveDePaso.vehiculo).como,
        ComoVa.falta,
        reason: 'siete sucursales no pueden armar una ruta',
      );
      expect(todas.paso(ClaveDePaso.vehiculo).lasQueFaltan, hasLength(7));
      expect(
        todas.paso(ClaveDePaso.vehiculo).enCuantasFalta,
        'Falta en 7 de las 8 sucursales.',
      );

      // Y con ESA una elegida arriba, el paso está hecho: ahí sí lo tiene. Con
      // una sola a la vista no cambia ni un ápice respecto a antes.
      final santiago = await mirar(sucursalId: 'b8');
      expect(santiago.paso(ClaveDePaso.vehiculo).como, ComoVa.hecho);
      expect(santiago.paso(ClaveDePaso.vehiculo).enCuantasFalta, isNull);
    });

    test('un solo almacén bueno tampoco tapa el de las otras siete', () async {
      await lasOchoEnSuSitio();
      await base.delete(base.warehouses).go();
      await almacen(id: 'a-b8', codigo: 'STG');

      final todas = await mirar();
      expect(todas.paso(ClaveDePaso.almacen).como, ComoVa.falta);
      expect(todas.paso(ClaveDePaso.almacen).lasQueFaltan, hasLength(7));

      expect(
        (await mirar(sucursalId: 'b8')).paso(ClaveDePaso.almacen).como,
        ComoVa.hecho,
      );
    });

    test('sólo Habana y Santiago con tasa: el título dice 6 de las 8', () async {
      await lasOchoEnSuSitio();
      // Como está hoy en Accesos: las otras seis sin tasa.
      for (final (id, codigo, nombre) in lasOcho) {
        if (id == 'b5' || id == 'b8') continue;
        await tasa(id: id, codigo: codigo, nombre: nombre, cuando: null);
      }

      final todas = await mirar();
      expect(
        todas.paso(ClaveDePaso.tasa).como,
        ComoVa.falta,
        reason:
            'con dos de las ocho no basta: las otras seis se quedan en dólares',
      );
      // Las cuentas son las de verdad: 8 miradas, 2 con tasa, 6 sin ella.
      expect(todas.sucursales, 8);
      expect(todas.pendientes.map((p) => p.clave), [ClaveDePaso.tasa]);
      expect(todas.paso(ClaveDePaso.tasa).lasQueFaltan, hasLength(6));
      expect(todas.sucursalesConAlgoQueFalta, 6);
      expect(
        tituloDeLoQueFalta(todas),
        'Faltan cosas por configurar en 6 de las 8 sucursales',
      );
      expect(
        todas.paso(ClaveDePaso.tasa).enCuantasFalta,
        'Falta en 6 de las 8 sucursales.',
      );
      // El porqué no se pierde: es lo que hace que alguien lo arregle hoy.
      expect(
        todas.paso(ClaveDePaso.tasa).explicacion,
        contains('convertir sin tasa es inventarse un número'),
      );
    });

    test('con UNA elegida, el título es LITERALMENTE el de hoy', () async {
      // Las ocho en la base —el caso del Super Admin— pero mirando una sola.
      // Es el caso que usa todo el mundo: arreglar «todas» no puede rozarlo.
      await lasOchoEnSuSitio();
      await base.delete(base.vehicles).go();

      final una = await mirar(sucursalId: 'b8');
      expect(una.sucursales, 1);
      expect(tituloDeLoQueFalta(una), 'Falta configurar esta sucursal');
      expect(una.paso(ClaveDePaso.vehiculo).enCuantasFalta, isNull);
      expect(
        una.paso(ClaveDePaso.vehiculo).explicacion,
        'Sin ninguno no se puede terminar el paso 3 del asistente de rutas, '
        'y una columna del tablero no puede llevar camión.',
      );
    });

    test('con pocas se dice CUÁLES, que es lo que no decía', () async {
      await lasOchoEnSuSitio();
      await (base.delete(
        base.vehicles,
      )..where((v) => v.branchId.isIn(['b2', 'b6']))).go();

      final paso = (await mirar()).paso(ClaveDePaso.vehiculo);
      expect(
        paso.enCuantasFalta,
        'Falta en 2 de las 8 sucursales: Granma y Las Tunas.',
      );
      expect(paso.explicacion, contains('paso 3 del asistente'));
    });

    test('lo que no ha bajado no acusa a ninguna sucursal', () async {
      // Las ocho puestas, pero los vehículos NO han bajado: la tabla está vacía
      // y no se sabe si es que no hay o es que no llegó. Eso no es «falta en 8
      // de las 8» — es el segundo de la web recién cargada, y contarlo mandaría
      // a ocho sitios a dar de alta camiones que ya existen.
      await lasOchoEnSuSitio();
      await base.delete(base.vehicles).go();
      await (base.delete(
        base.frescura,
      )..where((f) => f.coleccion.equals(Colecciones.vehiculos))).go();

      final todas = await mirar();
      expect(todas.paso(ClaveDePaso.vehiculo).como, ComoVa.sinSaber);
      expect(todas.paso(ClaveDePaso.vehiculo).enCuantasFalta, isNull);
      expect(
        todas.sucursalesConAlgoQueFalta,
        0,
        reason: 'lo que no se ha mirado no acusa a nadie de estar a medias',
      );
      expect(todas.faltaAlgoDeVerdad, isFalse);
    });

    // ESTA ES LA QUE ATA LAS DOS PREGUNTAS (`CLAUDE.md` §3-bis).
    //
    // El paso a paso y el asistente de rutas contestan lo mismo: «¿hay camión?»
    // y «¿hay almacén del que salir?». Si uno dijera «hecho» y el otro «no hay
    // ninguno», la que alguien cree es siempre la equivocada. Un comentario
    // prometiéndolo ya había ahí, y no falló cuando dejó de ser verdad.
    test('el paso a paso y el asistente cuentan IGUAL, sucursal por sucursal', () async {
      await lasOchoEnSuSitio();
      await base.delete(base.vehicles).go();
      await vehiculo(id: 'v-b8', sucursalId: 'b8');
      await vehiculo(id: 'v-b5', sucursalId: 'b5');
      await base.delete(base.warehouses).go();
      await almacen(id: 'a-b8', codigo: 'STG');
      await almacen(id: 'a-b5', codigo: 'HAB');
      // Estos dos no cuentan para nadie, y tienen que no contar en los DOS
      // sitios: uno sin coordenadas y otro dado de baja.
      await almacen(id: 'a-b2', codigo: 'GR', conPunto: false);
      await almacen(id: 'a-b3', codigo: 'GTO', activo: false);

      final consultas = ConsultasRutas(base);
      for (final (id, codigo, nombre) in lasOcho) {
        final pasos = await mirar(sucursalId: id);

        final camiones = await consultas.vehiculos(sucursalId: id).first;
        expect(
          pasos.paso(ClaveDePaso.vehiculo).como == ComoVa.hecho,
          camiones.isNotEmpty,
          reason:
              'vehículos de $nombre: el paso a paso dice una cosa y el '
              'asistente de rutas otra',
        );

        // El paso 2 del asistente: los activos de la sucursal, con punto.
        final salidas = (await consultas.almacenesDe(
          codigo,
        )).where((a) => a.lat != null && a.lng != null);
        expect(
          pasos.paso(ClaveDePaso.almacen).como == ComoVa.hecho,
          salidas.isNotEmpty,
          reason:
              'almacenes de $nombre: el paso a paso dice una cosa y el paso 2 '
              'del asistente otra',
        );
      }

      // Y con las ocho a la vista, hecho sólo si lo está en todas.
      final todas = await mirar();
      expect(todas.paso(ClaveDePaso.vehiculo).como, ComoVa.falta);
      expect(todas.paso(ClaveDePaso.almacen).como, ComoVa.falta);
      expect(todas.sucursalesConAlgoQueFalta, 6);
    });
  });

  group('lo que se pinta', () {
    /// [mirando] es la sucursal de la barra superior: `null` = todas.
    Future<void> pintar(WidgetTester tester, {String? mirando}) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(base),
            sucursalMiradaProvider.overrideWith(() => _Mirando(mirando)),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: PasoAPaso())),
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
      expect(linea.style?.color, Colores.enCurso);
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

    testWidgets('con las OCHO a la vista el título dice en cuántas falta', (
      tester,
    ) async {
      // Lo que Jose ve en la web: «Todas las sucursales (8)» arriba y el Panel
      // diciendo «Falta configurar esta sucursal». No hay «esta»: hay ocho.
      await lasOchoEnSuSitio();
      await base.delete(base.vehicles).go();
      await vehiculo(id: 'v-b8', sucursalId: 'b8');
      await pintar(tester);

      expect(find.text('Falta configurar esta sucursal'), findsNothing);
      expect(
        find.text('Faltan cosas por configurar en 7 de las 8 sucursales'),
        findsOneWidget,
      );
      // Y el paso dice en cuántas falta él, sin perder el porqué.
      expect(find.textContaining('Falta en 7 de las 8 sucursales'), findsOneWidget);
      expect(find.textContaining('paso 3 del asistente'), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('con UNA elegida arriba, la pantalla es la de siempre', (
      tester,
    ) async {
      // Las ocho en la base, pero mirando Santiago: el caso de todos los días.
      // Palabra por palabra lo de hoy, o arreglar «todas» estropea lo normal.
      await lasOchoEnSuSitio();
      await base.delete(base.vehicles).go();
      await pintar(tester, mirando: 'b8');

      expect(find.text('Falta configurar esta sucursal'), findsOneWidget);
      expect(find.textContaining('de las 8 sucursales'), findsNothing);
      expect(
        find.text(
          'Sin ninguno no se puede terminar el paso 3 del asistente de rutas, '
          'y una columna del tablero no puede llevar camión.',
        ),
        findsOneWidget,
      );
      await desmontar(tester);
    });
  });
}

/// La sucursal de la barra superior, fijada para la prueba. `null` = todas.
class _Mirando extends SucursalMirada {
  _Mirando(this._id);

  final String? _id;

  @override
  String? build() => _id;
}
