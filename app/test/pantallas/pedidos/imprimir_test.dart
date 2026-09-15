// Los dos botones `Ver e imprimir` de Pedidos.
//
// No falta ninguna funcion: el PDF del pre-despacho existe y esta probado
// (`test/impresion/pdf_test.dart`). Lo que faltaba era el boton que lo llama, y
// sin el no hay papel con el que bajar al almacen. Por eso esto se comprueba
// **hasta los bytes**: que el boton salga no vale de nada si lo que abre no es
// una hoja de verdad.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:reparto/impresion/vista_previa.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/pedidos/datos/filtros_pedidos.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';
import 'package:reparto/pantallas/pedidos/vista/pantalla_pedidos.dart';
import 'package:reparto/textos/textos.dart';

import '../../apoyo/base_de_prueba.dart';
import 'sembrar.dart';

/// `pumpAndSettle` no vale: el indicador giratorio es una animacion que no para
/// nunca. Se bombean unos fotogramas y basta.
Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Dos pasadas, no una: el temporizador que cierra los `watch()` de Drift nace
/// al final del primer fotograma del desmontaje. Con una sola pasada la suite
/// no falla — **se cuelga**, que es peor.
Future<void> desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() async {
    base = baseDePrueba();
    await sembrarLosOnce(base);
    for (final coleccion in const [
      Colecciones.pedidos,
      Colecciones.renglones,
      Colecciones.productos,
    ]) {
      await RegistroDeFrescura(
        base,
        reloj: () => ahora,
      ).marcar(coleccion, hasta: null, bajadaAt: ahora);
    }
  });

  tearDown(() => base.close());

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        // Con los idiomas montados, como en `lib/app.dart`: la vista previa
        // del PDF lee sus etiquetas de ahi y sin ellos revienta al pintarse.
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          home: const Scaffold(body: PantallaPedidos()),
        ),
      ),
    );
    await asentar(tester);
  }

  testWidgets(
    'marcando un pedido sale `Ver e imprimir` y abre la hoja del almacen',
    (tester) async {
      await pintar(tester);

      // Sin nada marcado no hay tarjeta de lo elegido: el unico
      // `Ver e imprimir` que hay es el del bloque de lo filtrado.
      expect(find.text('Ver e imprimir'), findsOneWidget);

      // La casilla de la cabecera marca toda la pagina: 8 pedidos, que con el
      // arranque acotado es lo que puede subir a un camion.
      await tester.tap(find.byType(Checkbox).first);
      await asentar(tester);

      // Ahora hay dos, como en la de Next: lo marcado y lo filtrado.
      expect(find.text('Ver e imprimir'), findsNWidgets(2));
      expect(find.textContaining('8 pedido(s) elegidos'), findsOneWidget);

      await tester.tap(find.text('Ver e imprimir').first);
      await asentar(tester);

      // Y lo que abre es la vista previa de un PDF, en un cajon.
      expect(find.text('Pre-despacho'), findsOneWidget);
      expect(find.byType(VistaPreviaPdf), findsOneWidget);

      // La prueba de que llama al PDF que ya existe: se le pide la hoja a la
      // propia vista y sale un PDF de verdad, sin salir a la red.
      final vista = tester.widget<VistaPreviaPdf>(find.byType(VistaPreviaPdf));
      final bytes = await vista.armar(PdfPageFormat.a4);
      expect(latin1.decode(bytes.take(5).toList()), '%PDF-');

      await desmontar(tester);
    },
  );

  testWidgets('el pre-despacho de lo filtrado tambien se imprime', (
    tester,
  ) async {
    await pintar(tester);

    // Cerrado no se ha sumado nada todavia: el boton esta, pero apagado. Una
    // hoja en blanco no es una hoja.
    final boton = find.widgetWithText(TextButton, 'Ver e imprimir');
    expect(tester.widget<TextButton>(boton).onPressed, isNull);

    await tester.tap(find.text('Pre-despacho de lo filtrado'));
    await asentar(tester);

    expect(tester.widget<TextButton>(boton).onPressed, isNotNull);
    await tester.tap(boton);
    await asentar(tester);

    expect(find.byType(VistaPreviaPdf), findsOneWidget);
    await desmontar(tester);
  });

  group('la hoja que se manda al PDF', () {
    test('lleva la sucursal, el dia y la cabecera de la de Next', () {
      final totales = TotalesPreDespacho(
        const [
          LineaPreDespacho(
            producto: 'Arroz',
            empaques: 5,
            unidades: 50,
            pesoKg: 125,
          ),
          // Sin peso resuelto: en el papel son cero kilos, que es lo que pesa
          // lo que no sabemos.
          LineaPreDespacho(producto: 'Frijol', empaques: 1, unidades: 10),
        ],
        pedidos: 2,
        pesoDeLosPedidos: 300,
      );

      final hoja = hojaDePreDespacho(
        totales: totales,
        sucursal: 'Camagüey',
        dia: '2026-09-03',
      );

      expect(hoja.sucursal, 'Camagüey');
      // Pedidos no sabe de camiones: la hoja sale del almacen, no de una ruta.
      expect(hoja.vehiculo, '');
      expect(hoja.dia, '2026-09-03');
      expect(hoja.pedidos, 2);
      expect(hoja.pesoKg, 300);
      expect(hoja.lineas.first.formatos, 5);
      expect(hoja.lineas.last.pesoKg, 0);
    });

    test('el dia sólo se escribe cuando el rango ES un dia', () {
      final unDia = DateTime(2026, 9, 3);
      expect(
        diaDeLaHoja(FiltrosPedidos(desde: unDia, hasta: unDia)),
        '2026-09-03',
      );
      // Un rango de varios dias no escribe ninguno: poner uno de los dos seria
      // mentir sobre lo que hay debajo.
      expect(
        diaDeLaHoja(FiltrosPedidos(desde: unDia, hasta: DateTime(2026, 9, 5))),
        isNull,
      );
      expect(diaDeLaHoja(const FiltrosPedidos()), isNull);
    });
  });
}
