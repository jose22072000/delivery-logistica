// LOS RENGLONES LLEGAN DESPUÉS QUE LOS PEDIDOS, Y LA COLUMNA TIENE QUE
// ENTERARSE. Es el §3-ter otra vez, en un quinto sitio.
//
// En la bajada el orden es el de `Colecciones.todas`: `orders` primero,
// `order_items` después y `products` más tarde todavía. `renglonesDePaginaProvider`
// era un `FutureProvider` que esperaba a la página, o sea que se recalculaba
// **cuando cambiaba la tabla de pedidos**; cuando los renglones entraban, esa
// tabla ya no se tocaba y la respuesta no se volvía a pedir nunca.
//
// Lo que quedaba en pantalla: la columna `Artículos` en «—» encima de un pedido
// con doce líneas. Y «—» no se lee como «todavía no ha llegado»: se lee como
// **«este pedido no lleva nada»**.
//
// La forma de la prueba es la que manda el `CLAUDE.md` §3-ter y no otra:
// **montar con la base VACÍA y sembrar DESPUÉS, sin volver a montar.** Sembrar
// en el `setUp` es justo el caso que un `Future` resuelve bien, y por eso las
// pruebas que había no lo cazaban.
//
// Va en pareja: que la columna se rellene cuando los renglones llegan tarde, y
// que siga diciendo «—» cuando el pedido de verdad no lleva ninguno.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/idioma.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/pedidos/vista/pantalla_pedidos.dart';

import '../../apoyo/base_de_prueba.dart';
import 'sembrar.dart';

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> pintar(WidgetTester tester) async {
    // Ancha: la columna `Artículos` sólo sale a partir de 1024 px, que es el
    // escritorio del despacho donde se arma la ruta.
    tester.view.physicalSize = const Size(1600, 1400);
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
          home: const Scaffold(body: PantallaPedidos()),
        ),
      ),
    );
    await asentar(tester);
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  /// Un pedido, y NADA más. Los renglones van aparte a propósito.
  Future<RegistroDeFrescura> soloElPedido() async {
    await sembrarCatalogo(base);
    await sembrarPedido(
      base,
      id: 'o1',
      cliente: 'Ana',
      fecha: DateTime(2026, 9, 1),
      peso: 100,
      distancia: 5,
    );
    final registro = RegistroDeFrescura(base, reloj: () => ahora);
    await registro.marcar(
      Colecciones.pedidos,
      hasta: '2026-09-14T16:00:00Z',
      bajadaAt: ahora,
    );
    return registro;
  }

  testWidgets(
    'los renglones entran con la pantalla abierta y la columna «Artículos» '
    'se rellena sola, sin recargar',
    (tester) async {
      // 1. Como abre la web: base vacía.
      await pintar(tester);

      // 2. Llegan los PEDIDOS. Todavía sin renglones: «—» es la verdad aquí.
      final registro = await soloElPedido();
      await asentar(tester);
      expect(
        find.textContaining('Arroz'),
        findsNothing,
        reason: 'los renglones aún no han bajado',
      );

      // 3. Y AHORA los renglones, **sin tocar la tabla de pedidos ni
      //    remontar**, que es el orden exacto de la bajada.
      await sembrarRenglon(
        base,
        id: 'i1',
        pedidoId: 'o1',
        producto: 'Arroz',
        unidades: 20,
        empaques: 2,
        productoId: 'p1',
      );
      await registro.marcar(
        Colecciones.renglones,
        hasta: '2026-09-14T16:00:00Z',
        bajadaAt: ahora,
      );
      await asentar(tester);

      expect(
        find.textContaining('Arroz'),
        findsOneWidget,
        reason:
            'con un `Future` esto se quedaba en «—» para siempre, y «—» se lee '
            'como «este pedido no lleva nada»',
      );
      await desmontar(tester);
    },
  );

  testWidgets(
    'LA OTRA MITAD: un pedido que de verdad no tiene renglones sigue en «—»',
    (tester) async {
      // Sin esto, «arreglar» la columna poniéndole cualquier cosa también
      // pasaría la prueba de arriba. Un pedido sin líneas tiene que verse.
      await pintar(tester);
      final registro = await soloElPedido();
      await registro.marcar(
        Colecciones.renglones,
        hasta: '2026-09-14T16:00:00Z',
        bajadaAt: ahora,
      );
      await asentar(tester);

      expect(find.textContaining('Arroz'), findsNothing);
      expect(
        find.text('—'),
        findsWidgets,
        reason: 'la colección bajó y el pedido no lleva líneas: eso es «—»',
      );
      await desmontar(tester);
    },
  );
}
