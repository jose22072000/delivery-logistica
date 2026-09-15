// La pantalla de Pedidos, pintada.
//
// Lo que se comprueba aqui es lo que un test de datos no puede ver: que una lista
// vacia de algo que nunca se bajo se dice con OTRAS palabras (caso S7), que la
// franja azul del arranque acotado sale con su texto literal, y que el reloj de
// datos esta arriba.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/frescura/reloj_de_datos.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/pedidos/vista/pantalla_pedidos.dart';

import '../../apoyo/base_de_prueba.dart';
import 'sembrar.dart';

/// `pumpAndSettle` no vale aqui: mientras una consulta esta en vuelo la
/// pantalla pinta un indicador giratorio, que es una animacion que no para
/// nunca, asi que «esperar a que no quede nada por animar» no termina jamas. Se
/// bombean unos cuantos fotogramas y ya.
Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Desmontar a mano y bombear una vez mas.
///
/// Al desmontarse, los `watch()` de Drift programan un temporizador de cero
/// para cerrarse; si el test acaba antes de que corra, el marco de pruebas lo
/// cuenta como temporizador pendiente y falla. Esto le da ese fotograma.
Future<void> desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() {
    base = baseDePrueba();
  });

  tearDown(() => base.close());

  Future<void> pintar(WidgetTester tester) async {
    // Una pantalla ancha: asi salen las 13 columnas y se comprueba lo que de
    // verdad se ve en el escritorio del despacho.
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        // La pantalla ya NO trae `Scaffold` propio —lo pone el armazon—, asi que
        // aqui se monta con el suyo: sin el, un `TextField` no encuentra ningun
        // `Material` encima y la pantalla ni se pinta.
        child: const MaterialApp(
          home: Scaffold(body: PantallaPedidos()),
        ),
      ),
    );
    await asentar(tester);
  }

  testWidgets(
    'sin descargar NO es «no hay pedidos»: son dos textos distintos',
    (tester) async {
      await sembrarCatalogo(base);
      await pintar(tester);

      expect(find.text(SinDescargar.textoDeLaPantallaVacia), findsOneWidget);
      // Y el reloj de arriba lo dice tambien, en ambar.
      expect(find.text('Sin descargar todavía'), findsOneWidget);
      // Lo que NO puede salir es el vacio de «no hay nada».
      expect(
        find.text('Aún no hay pedidos. Crea una ruta con pedidos.'),
        findsNothing,
      );
      await desmontar(tester);
    },
  );

  testWidgets('con datos sale la franja azul del arranque acotado', (
    tester,
  ) async {
    await sembrarLosOnce(base);
    await RegistroDeFrescura(base, reloj: () => ahora).marcar(
      Colecciones.pedidos,
      hasta: '2026-09-14T16:00:00Z',
      bajadaAt: ahora.subtract(const Duration(minutes: 20)),
    );
    for (final coleccion in const [
      Colecciones.renglones,
      Colecciones.productos,
    ]) {
      await RegistroDeFrescura(base, reloj: () => ahora).marcar(
        coleccion,
        hasta: '2026-09-14T16:00:00Z',
        bajadaAt: ahora.subtract(const Duration(minutes: 20)),
      );
    }

    await pintar(tester);

    expect(find.text(PantallaPedidos.franjaAzul), findsOneWidget);
    expect(find.text('Ver todos los pedidos'), findsOneWidget);
    // 8 de los 11: el arranque deja fuera lo archivado y lo no facturado.
    expect(
      find.textContaining('8 pedidos, del más nuevo al más viejo'),
      findsOneWidget,
    );
    // El reloj de datos, arriba y siempre visible.
    expect(find.text('Datos de las 15:45'), findsOneWidget);
    // Y la tabla, con sus cabeceras.
    expect(find.text('Cliente'), findsOneWidget);
    expect(find.text('Dirección'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('`Ver todos los pedidos` quita los dos filtros del arranque', (
    tester,
  ) async {
    await sembrarLosOnce(base);
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.pedidos, hasta: null, bajadaAt: ahora);
    await pintar(tester);

    await tester.tap(find.text('Ver todos los pedidos'));
    await asentar(tester);

    expect(find.text(PantallaPedidos.franjaAzul), findsNothing);
    expect(
      find.textContaining('11 pedidos, del más nuevo al más viejo'),
      findsOneWidget,
    );
    await desmontar(tester);
  });
}
