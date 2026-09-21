// EL BOTON `Exportar a Excel`, DESDE LA PANTALLA.
//
// Lo que se comprueba aquí y no en `excel_del_informe_test.dart`: que el botón
// esté apagado cuando el pliego dice y **diga por qué**, que al pulsarlo salga
// un fichero de verdad por la costura de entrega, y que los importes de ese
// fichero sean los MISMOS que está leyendo en pantalla quien lo pulsó.
//
// Esa última es la que importa. La moneda se elige arriba, en la barra, y el
// Excel se pide abajo: si las dos mitades se desincronizan, sale un fichero con
// la cabecera «(CUP)» encima de dólares —o al revés— y nadie lo nota, porque un
// número en otra moneda se lee perfectamente bien.

import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/informes/datos/entrega_del_excel.dart';
import 'package:reparto/pantallas/informes/datos/hoja_de_calculo.dart';
import 'package:reparto/pantallas/informes/registro.dart';
import 'package:reparto/pantallas/informes/vista/boton_exportar.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo/leer_xlsx.dart';

/// La costura con el aparato, de mentira: se queda con lo que le entregan para
/// poder abrirlo y mirarlo dentro.
class EntregaDeMentira implements EntregaDeFichero {
  EntregaDeMentira({this.falla});

  /// Si no es `null`, esto es lo que se contesta en vez de entregar nada.
  final String? falla;

  int veces = 0;
  Uint8List? bytes;
  String? nombre;
  String? tipoMime;

  @override
  Future<Entregado> entregar({
    required Uint8List bytes,
    required String nombre,
    required String tipoMime,
  }) async {
    veces++;
    this.bytes = bytes;
    this.nombre = nombre;
    this.tipoMime = tipoMime;
    if (falla != null) return Entregado.noSePudo(falla!);
    return Entregado.hecho('Excel guardado en /descargas/$nombre');
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  final ahora = DateTime(2026, 9, 14, 10, 36);
  const tasaDeHoy = 700.0;

  late BaseLocal base;
  late EntregaDeMentira entrega;
  setUp(() {
    base = baseDePrueba();
    entrega = EntregaDeMentira();
  });
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

  Future<void> sucursal(String id, String nombre, {double? cupRate}) => base
      .into(base.branches)
      .insertOnConflictUpdate(
        BranchesCompanion.insert(
          id: id,
          name: nombre,
          lat: 20,
          lng: -75,
          cupRate: Value(cupRate),
          cupRateTraidoAt: Value(cupRate == null ? null : DateTime(2026, 9, 9)),
        ),
      );

  Future<void> pedido(
    String id, {
    double precio = 10,
    double peso = 1,
    String? sucursalId,
  }) => base
      .into(base.orders)
      .insert(
        OrdersCompanion.insert(
          id: id,
          customerName: 'Cliente $id',
          address: 'Calle $id',
          weight: Value(peso),
          price: Value(precio),
          branchId: Value(sucursalId),
          createdAt: Value(DateTime(2026, 9, 13)),
        ),
      );

  Future<ProviderContainer> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
          entregaDeFicheroProvider.overrideWithValue(entrega),
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
    // `'debugSize == size': is not true` — un rojo que no es de esta pantalla y
    // que además se come el mensaje del error de verdad, porque el volcado del
    // árbol revienta al describirlo.
    //
    // `runAsync` es lo único que le da tiempo real a esa carga. Va aquí y no en
    // el `setUpAll` porque allí no hay `tester`.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(RepartoApp)));
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  Finder elBoton() =>
      find.widgetWithText(FilledButton, TextosDeExportar.etiqueta);

  bool estaApagado(WidgetTester tester) =>
      tester.widget<FilledButton>(elBoton()).onPressed == null;

  // ---------------------------------------------------------------------------
  // El botón, y POR QUÉ está apagado
  // ---------------------------------------------------------------------------

  group('el botón Exportar a Excel', () {
    testWidgets('está en los Filtros, como dice el pliego', (tester) async {
      await bajadaEntera(ahora);
      await pedido('a');
      await montar(tester);

      expect(elBoton(), findsOneWidget);
      expect(estaApagado(tester), isFalse);

      await desmontar(tester);
    });

    testWidgets('sin nada descargado está apagado, y dice que no hay nada', (
      tester,
    ) async {
      await montar(tester);

      expect(
        estaApagado(tester),
        isTrue,
        reason:
            'Sin nada descargado no hay nada que exportar, y el botón tiene '
            'que estar apagado (pliego §7).',
      );
      expect(
        find.byTooltip(TextosDeExportar.sinDescargar),
        findsOneWidget,
        reason:
            'El botón está gris y no dice por qué. Los motivos no se arreglan '
            'igual —esperar, cambiar los filtros, o avisar a la oficina—, así '
            'que uno gris y mudo se pulsa tres veces y vuelve como «el Excel '
            'no funciona».',
      );

      await desmontar(tester);
    });

    testWidgets('con filtros que no dejan ni una orden, lo dice', (
      tester,
    ) async {
      await bajadaEntera(ahora);
      await montar(tester);

      expect(estaApagado(tester), isTrue);
      expect(find.byTooltip(TextosDeExportar.sinOrdenes), findsOneWidget);
      // Y NO el de «no hay nada descargado»: aquí sí bajó, lo que pasa es que
      // los filtros no dejan nada. Son dos problemas distintos.
      expect(find.byTooltip(TextosDeExportar.sinDescargar), findsNothing);

      await desmontar(tester);
    });

    testWidgets('encendido, el rótulo promete la moneda que se está mirando', (
      tester,
    ) async {
      await bajadaEntera(ahora);
      await sucursal('hab', 'La Habana', cupRate: tasaDeHoy);
      await pedido('a', sucursalId: 'hab');
      final contenedor = await montar(tester);
      contenedor.read(monedaMiradaProvider.notifier).mirar('CUP');
      await tester.pumpAndSettle();

      expect(
        find.byTooltip(TextosDeExportar.enQueMoneda('CUP')),
        findsOneWidget,
        reason:
            'El botón no dice en qué moneda va a salir el fichero. Es el único '
            'aviso que tiene delante quien lo pulsa.',
      );

      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // Pulsarlo: sale un fichero, y se dice qué pasó con él
  // ---------------------------------------------------------------------------

  group('al pulsar Exportar a Excel', () {
    testWidgets('entrega un .xlsx con las tres hojas y el nombre del pliego', (
      tester,
    ) async {
      await bajadaEntera(ahora);
      await pedido('a', precio: 10);
      await pedido('b', precio: 5);
      await montar(tester);

      await tester.tap(elBoton());
      await tester.pumpAndSettle();

      expect(entrega.veces, 1);
      expect(entrega.nombre, 'reporte-procovar-2026-09-14.xlsx');
      expect(entrega.tipoMime, tipoMimeXlsx);

      final libro = leerXlsx(entrega.bytes!);
      expect(libro.keys.toList(), [
        'Resumen',
        'Por Vehículo',
        'Detalle de Órdenes',
      ]);
      expect(libro['Resumen']![5], ['Total Órdenes', 2]);

      // Y se dice qué pasó con el fichero: nada se hace en silencio.
      expect(
        find.text('Excel guardado en /descargas/${entrega.nombre}'),
        findsOneWidget,
      );

      await desmontar(tester);
    });

    testWidgets('si la entrega falla NO se queda verde: sale el motivo', (
      tester,
    ) async {
      entrega = EntregaDeMentira(
        falla: 'No se pudo guardar el Excel: disco lleno',
      );
      await bajadaEntera(ahora);
      await pedido('a');
      await montar(tester);

      await tester.tap(elBoton());
      await tester.pumpAndSettle();

      expect(
        find.text('No se pudo guardar el Excel: disco lleno'),
        findsOneWidget,
        reason:
            'Un botón que no hace nada y no dice nada es la pantalla quedándose '
            'verde sobre un fallo (regla 4). Y el motivo va LITERAL: «disco '
            'lleno» le dice a alguien qué hacer, «no se pudo» no.',
      );

      await desmontar(tester);
    });

    // -------------------------------------------------------------------------
    // LA MONEDA: lo del fichero y lo de la pantalla son el MISMO número
    // -------------------------------------------------------------------------

    testWidgets('los importes salen en la moneda que se está mirando', (
      tester,
    ) async {
      await bajadaEntera(ahora);
      await sucursal('hab', 'La Habana', cupRate: tasaDeHoy);
      await pedido('a', precio: 10, sucursalId: 'hab');
      await pedido('b', precio: 5, sucursalId: 'hab');
      final contenedor = await montar(tester);
      contenedor.read(monedaMiradaProvider.notifier).mirar('CUP');
      await tester.pumpAndSettle();

      // Lo que se está viendo en la tarjeta de `Ingresos Totales`, tal cual.
      final enPantalla = contenedor
          .read(tasaDeLaMiradaProvider)
          .importe(15, contenedor.read(monedaEfectivaProvider));
      expect(enPantalla, '10.500 CUP');
      expect(find.text(enPantalla), findsWidgets);

      await tester.tap(elBoton());
      await tester.pumpAndSettle();

      final resumen = leerXlsx(entrega.bytes!)['Resumen']!;
      expect(resumen[3], [
        'Moneda',
        'CUP',
      ], reason: 'El fichero no dice en qué moneda están sus importes.');
      expect(
        resumen[6],
        ['Ingresos Totales (CUP)', 10500],
        reason:
            'La pantalla enseña $enPantalla y el fichero trae otro número. Los '
            'importes se guardan en USD y el CUP se calcula al pintarlo: si el '
            'Excel escribe los dólares crudos, sale una cifra 700 veces menor '
            'bajo una cabecera que pone «(CUP)». Se lee perfectamente bien y '
            'está mal, que es lo peor que puede pasarle a un número que '
            'alguien va a cobrar.',
      );

      await desmontar(tester);
    });

    testWidgets('en una sucursal SIN tasa el fichero sale en USD, no en CUP', (
      tester,
    ) async {
      await bajadaEntera(ahora);
      await sucursal('hab', 'La Habana', cupRate: tasaDeHoy);
      await sucursal('gr', 'Granma');
      await pedido('a', precio: 10, sucursalId: 'gr');
      final contenedor = await montar(tester);
      contenedor.read(sucursalMiradaProvider.notifier).mirar('gr');
      contenedor.read(monedaMiradaProvider.notifier).mirar('CUP');
      await tester.pumpAndSettle();

      await tester.tap(elBoton());
      await tester.pumpAndSettle();

      final resumen = leerXlsx(entrega.bytes!)['Resumen']!;
      expect(
        resumen[3],
        ['Moneda', 'USD'],
        reason:
            'Granma no tiene tasa y el fichero salió marcado en CUP: se está '
            'usando la tasa de La Habana. Es el caso de PEDIDO, literal.',
      );
      expect(resumen[6], ['Ingresos Totales (USD)', 10]);

      await desmontar(tester);
    });
  });
}
