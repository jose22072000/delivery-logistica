// LA FORMA DEL ASISTENTE «Nueva Ruta»: barra de progreso, una tarjeta por paso,
// la lista en su propia caja y el pie siempre a la vista.
//
// Esto no prueba el armado —de eso van `armado_test.dart` y
// `disponibles_test.dart`—, prueba **dónde queda cada cosa en la pantalla**, que
// es justo lo que se rompió. Palabras de Jose, 17/09/2026:
//
//   «¿y el botón de empezar, confirmar la ruta planificada, dónde está? […] no
//   me digas que está abajo del todo y tengo que bajar por todos los pedidos,
//   que es una lista larga a la cual no me le has puesto ni paginación»
//   «eso que hay ahí es un wizard, no la mierda que hiciste tú»
//   «con posibilidad de viajar entre los pasos por si quiero cambiar algo de
//   algún paso»
//
// Un fallo de colocación no rompe ninguna consulta ni deja ningún error en el
// registro: la aplicación funciona y **no se puede usar**. Por eso se mide con
// coordenadas —`getRect`— y no leyendo el código.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/impresion/vista_previa.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/asistente_nueva_ruta.dart';
import 'package:reparto/textos/textos.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// UNA sucursal, un almacén con coordenadas y un camión de 1.000 kg.
  ///
  /// Con una sola sucursal el paso 1 se autocompleta y el asistente abre ya en
  /// el 3, que es por donde se entra a lo que aquí se mide. `sembrarCatalogo`
  /// no vale para esto: siembra dos sucursales y entonces el paso 1 se queda
  /// esperando a que alguien elija.
  Future<void> sembrarLoBasico() async {
    await base
        .into(base.branches)
        .insert(
          BranchesCompanion.insert(
            id: 'B1',
            name: 'Camagüey',
            lat: 21.38,
            lng: -77.91,
            externalId: const Value('CAM'),
          ),
        );
    await base
        .into(base.warehouses)
        .insert(
          WarehousesCompanion.insert(
            id: 'W1',
            sucursalCodigo: 'CAM',
            nombre: 'Almacén central',
            lat: const Value(21.38),
            lng: const Value(-77.91),
            principal: const Value(true),
          ),
        );
    await base
        .into(base.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: 'V1',
            name: 'Camión 1',
            capacity: const Value(1000),
            plate: const Value('P-001'),
            branchId: const Value('B1'),
          ),
        );
  }

  /// N pedidos elegibles, cada uno con SU hora, para que el orden de la lista
  /// sea el mismo en cada vuelta (la consulta ordena por fecha descendente).
  /// «Cliente 000» es siempre el primero.
  Future<void> sembrarPedidos(int cuantos) async {
    for (var i = 0; i < cuantos; i++) {
      await sembrarPedido(
        base,
        id: 'p$i',
        cliente: 'Cliente ${i.toString().padLeft(3, '0')}',
        endLat: 21.38,
        endLng: -77.91,
        fecha: ahora.subtract(Duration(minutes: i)),
      );
    }
  }

  /// Monta el asistente con la base YA sembrada.
  ///
  /// Se siembra antes de montar a propósito: `disponiblesProvider` es un
  /// `FutureProvider` y su respuesta es la de cuando se pinta. Sembrar después
  /// probaría otra cosa (eso lo vigila `llega_la_bajada_test.dart`).
  Future<void> pintar(WidgetTester tester, {required Size pantalla}) async {
    tester.view.physicalSize = pantalla;
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
          home: const Scaffold(body: AsistenteNuevaRuta()),
        ),
      ),
    );
    await asentar(tester);
  }

  /// Del arranque al paso 4: con sucursal y almacén resueltos el asistente abre
  /// ya en el 3, así que sólo queda elegir camión y seguir.
  Future<void> llegarAlPaso4(WidgetTester tester) async {
    expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(3)), findsOneWidget);
    await tester.tap(find.text('Elige el vehículo…'));
    await asentar(tester);
    await tester.tap(find.widgetWithText(MenuItemButton, 'Camión 1'));
    await asentar(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Siguiente'));
    await asentar(tester);
    expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(4)), findsOneWidget);
  }

  /// Si esto está entero dentro de la pantalla. Es la pregunta de Jose —«¿dónde
  /// está?»— escrita en números.
  bool aLaVista(WidgetTester tester, Finder que) {
    final sitio = tester.getRect(que);
    final pantalla = tester.view.physicalSize / tester.view.devicePixelRatio;
    return sitio.top >= 0 &&
        sitio.bottom <= pantalla.height &&
        sitio.left >= 0 &&
        sitio.right <= pantalla.width;
  }

  final generarRuta = find.widgetWithText(FilledButton, 'Generar Ruta');
  final laCaja = find.byKey(AsistenteNuevaRuta.claveDeLaLista);
  final elResumen = find.byKey(AsistenteNuevaRuta.claveDelResumen);

  /// Baja hasta que la caja de la lista entra entera en la pantalla.
  Future<void> hastaLaLista(WidgetTester tester, double alto) async {
    for (var vuelta = 0; vuelta < 12; vuelta++) {
      if (tester.getRect(laCaja).bottom <= alto) break;
      await tester.dragFrom(const Offset(8, 400), const Offset(0, -260));
      await tester.pump();
    }
  }

  /// Arrastra el cuerpo del paso hasta abajo del todo, con el dedo.
  ///
  /// El dedo empieza en el MARGEN izquierdo (x = 8), fuera de la tarjeta: si
  /// empezara en el centro, el gesto se lo quedaría la caja de la lista, que
  /// tiene desplazamiento propio.
  Future<ScrollPosition> hastaElFinalDelPaso(WidgetTester tester) async {
    final cuerpo = tester
        .state<ScrollableState>(
          find.ancestor(of: laCaja, matching: find.byType(Scrollable)).first,
        )
        .position;
    for (var vuelta = 0; vuelta < 20; vuelta++) {
      if (cuerpo.pixels >= cuerpo.maxScrollExtent) break;
      final antes = cuerpo.pixels;
      await tester.dragFrom(const Offset(8, 400), const Offset(0, -260));
      await tester.pump();
      if (cuerpo.pixels <= antes) break;
    }
    return cuerpo;
  }

  testWidgets(
    'con 300 pedidos, el resumen y el botón de generar siguen en pantalla',
    (tester) async {
      await sembrarLoBasico();
      await sembrarPedidos(300);
      await pintar(tester, pantalla: const Size(1440, 1100));
      await llegarAlPaso4(tester);

      expect(find.text('Pedidos disponibles (300)'), findsOneWidget);

      // LA CAJA NO CRECE CON LA LISTA. Sin el tope, 300 filas son más de 20.000
      // px y todo lo que va debajo se va con ellas.
      expect(
        tester.getSize(laCaja).height,
        lessThanOrEqualTo(AsistenteNuevaRuta.altoDeLaLista),
        reason:
            'La caja de la lista creció con los pedidos en vez de acotarlos. '
            'Todo lo que va debajo —el resumen, el pre-despacho— se va con '
            'ella, y hay que recorrer los 300 para llegar.',
      );

      // Y por eso lo de debajo se queda donde estaba.
      expect(
        aLaVista(tester, elResumen),
        isTrue,
        reason:
            'La línea de resumen se fue de la pantalla: la lista está '
            'empujando hacia abajo en vez de desplazarse dentro de su caja.',
      );
      expect(
        aLaVista(tester, generarRuta),
        isTrue,
        reason:
            'El botón «Generar Ruta» no está a la vista con la lista larga. Es '
            'literalmente la queja de Jose: «¿y el botón de empezar, confirmar '
            'la ruta planificada, dónde está?».',
      );

      await desmontar(tester);
    },
  );

  testWidgets('la lista se desplaza DENTRO de su caja, sin mover nada más', (
    tester,
  ) async {
    await sembrarLoBasico();
    await sembrarPedidos(300);
    await pintar(tester, pantalla: const Size(1440, 1100));
    await llegarAlPaso4(tester);

    final desplazable = find.descendant(
      of: laCaja,
      matching: find.byType(Scrollable),
    );
    expect(
      desplazable,
      findsOneWidget,
      reason:
          'La caja de la lista no tiene desplazamiento propio. Sin él, los 300 '
          'pedidos vuelven a empujar el resumen y el pie fuera de la pantalla.',
    );

    final resumenAntes = tester.getRect(elResumen);
    final pieAntes = tester.getRect(generarRuta);
    final posicion = tester.state<ScrollableState>(desplazable).position;
    expect(posicion.pixels, 0);

    await tester.drag(desplazable, const Offset(0, -240));
    await tester.pump();

    expect(
      posicion.pixels,
      greaterThan(200),
      reason: 'La lista no se movió: el gesto se lo llevó otro desplazamiento.',
    );
    // Y lo de fuera de la caja, quieto. Si la lista viviera en el
    // desplazamiento del cajón, el resumen se habría ido hacia arriba con ella.
    expect(tester.getRect(elResumen), resumenAntes);
    expect(tester.getRect(generarRuta), pieAntes);

    await desmontar(tester);
  });

  testWidgets('volver a un tramo ya hecho conserva lo elegido', (tester) async {
    await sembrarLoBasico();
    await sembrarPedidos(6);
    await pintar(tester, pantalla: const Size(1440, 1100));
    await llegarAlPaso4(tester);

    await tester.tap(find.byType(CheckboxListTile).at(0));
    await asentar(tester);
    await tester.tap(find.byType(CheckboxListTile).at(1));
    await asentar(tester);
    expect(find.textContaining('2 pedidos seleccionados'), findsOneWidget);

    // Al paso 1 por su tramo de la barra, que es lo que Jose pidió: «con
    // posibilidad de viajar entre los pasos por si quiero cambiar algo».
    await tester.tap(find.byKey(AsistenteNuevaRuta.claveDelTramo(1)));
    await asentar(tester);
    expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(1)), findsOneWidget);
    expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(4)), findsNothing);

    // Y de vuelta al 4, con los dos pedidos donde estaban.
    await tester.tap(find.byKey(AsistenteNuevaRuta.claveDelTramo(4)));
    await asentar(tester);
    expect(
      find.byKey(AsistenteNuevaRuta.claveDelPaso(4)),
      findsOneWidget,
      reason:
          'No se puede volver al paso 4 por su tramo. O el tramo dejó de estar '
          'hecho —porque se soltó lo elegido al salir— o no se puede pulsar.',
    );
    expect(
      find.textContaining('2 pedidos seleccionados'),
      findsOneWidget,
      reason:
          'Dar un paseo por los pasos soltó los pedidos elegidos. Volver atrás '
          'es para corregir un dato, no para empezar de cero.',
    );
    expect(
      tester
          .widget<CheckboxListTile>(find.byType(CheckboxListTile).at(0))
          .value,
      isTrue,
    );

    await desmontar(tester);
  });

  testWidgets('la línea de resumen dice cuántos van y cuánto pesan', (
    tester,
  ) async {
    await sembrarLoBasico();
    // 10 kg cada uno (el de `sembrarPedido`) y un camión de 1.000 kg.
    await sembrarPedidos(6);
    await pintar(tester, pantalla: const Size(1440, 1100));
    await llegarAlPaso4(tester);

    expect(find.textContaining('0 pedidos seleccionados'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byType(CheckboxListTile).at(i));
      await asentar(tester);
    }

    final resumen = find.descendant(of: elResumen, matching: find.byType(Text));
    expect(
      find.descendant(
        of: elResumen,
        matching: find.textContaining('3 pedidos seleccionados'),
      ),
      findsOneWidget,
      reason: 'El resumen no dice cuántos pedidos van.',
    );
    expect(
      find.descendant(of: elResumen, matching: find.text('30.0 / 1000 kg')),
      findsOneWidget,
      reason:
          'El resumen no dice el peso contra la capacidad. Es el número con el '
          'que se decide si el camión sale o no.',
    );
    expect(resumen, findsNWidgets(2));

    await desmontar(tester);
  });

  testWidgets('en móvil el pre-despacho cae DEBAJO de la lista', (
    tester,
  ) async {
    await sembrarLoBasico();
    await sembrarPedidos(6);
    await pintar(tester, pantalla: const Size(390, 844));
    await llegarAlPaso4(tester);

    final preDespacho = find.byKey(AsistenteNuevaRuta.claveDelPreDespacho);
    expect(preDespacho, findsOneWidget);
    expect(
      tester.getRect(preDespacho).top,
      greaterThanOrEqualTo(tester.getRect(laCaja).bottom),
      reason:
          'En un teléfono el pre-despacho está al lado de la lista: dos '
          'columnas en 390 px son dos columnas de palabras partidas.',
    );

    await desmontar(tester);
  });

  // A 390×844, que es un teléfono de verdad. A 1440×1100 cabe todo y esto no
  // sale nunca: el corte de abajo sólo existe cuando la pantalla es corta.
  //
  // Jose, 17/09/2026, sobre esta misma trampa en el detalle de ruta: «me corta
  // parte de abajo, esto hasta del mapa, no solo de la última card, no puedo ver
  // el final». En un asistente de cuatro pasos es peor: si el armazón se va con
  // el desplazamiento, para volver a un paso hay que subir por toda la lista.
  testWidgets('a 390×844 se llega al final del paso y el armazón no se mueve', (
    tester,
  ) async {
    await sembrarLoBasico();
    await sembrarPedidos(40);
    await pintar(tester, pantalla: const Size(390, 844));

    // Paso 3: su «Siguiente» se ve sin desplazar nada. Los pasos cortos caben.
    expect(
      aLaVista(tester, find.widgetWithText(FilledButton, 'Siguiente')),
      isTrue,
      reason: 'El «Siguiente» del paso 3 queda cortado por abajo en un móvil.',
    );
    await llegarAlPaso4(tester);

    final tramo4 = find.byKey(AsistenteNuevaRuta.claveDelTramo(4));
    final barraAntes = tester.getRect(tramo4);
    final pieAntes = tester.getRect(generarRuta);
    expect(aLaVista(tester, tramo4), isTrue);
    expect(aLaVista(tester, generarRuta), isTrue);

    // SE LLEGA AL ÚLTIMO PEDIDO Y SE PUEDE TOCAR. No basta con que esté en el
    // árbol: lo que Jose no podía era alcanzarlo.
    //
    // El paso 4 en un teléfono NO cabe de una vez, y ahí está la trampa: la
    // caja de la lista arranca por debajo del borde de la pantalla.
    await hastaLaLista(tester, 844);
    expect(
      aLaVista(tester, laCaja),
      isTrue,
      reason: 'No se llega a ver la caja de la lista desplazando el paso.',
    );
    await tester.scrollUntilVisible(
      find.text('Cliente 039'),
      120,
      scrollable: find.descendant(
        of: laCaja,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Cliente 039'));
    await asentar(tester);
    expect(find.textContaining('1 pedidos seleccionados'), findsOneWidget);

    // Y SE LLEGA AL FINAL DEL PASO: el pre-despacho, que en un móvil es lo
    // último de todo, se alcanza entero.
    final cuerpo = await hastaElFinalDelPaso(tester);
    expect(cuerpo.maxScrollExtent, greaterThan(0));
    final preDespacho = find.byKey(AsistenteNuevaRuta.claveDelPreDespacho);
    expect(
      aLaVista(tester, preDespacho),
      isTrue,
      reason:
          'El final del paso 4 queda cortado por abajo: no se llega a ver el '
          'pre-despacho entero ni desplazándose hasta el tope.',
    );

    // EL ARMAZÓN NO SE HA MOVIDO NI UN PÍXEL. Ni la barra de pasos ni el pie.
    expect(
      tester.getRect(tramo4),
      barraAntes,
      reason:
          'La barra de pasos se fue con el desplazamiento. Es por donde se '
          'vuelve a un paso anterior: tiene que estar siempre a la vista.',
    );
    expect(tester.getRect(generarRuta), pieAntes);

    await desmontar(tester);
  });

  // La hoja del pre-despacho traía un `SizedBox(height: 640)` escrito a mano. A
  // 390×844 el cuerpo del cajón ronda los 635, así que la caja no cabía y
  // quedaban dos desplazamientos verticales uno dentro del otro: con el dedo
  // encima manda el de dentro, el de fuera no se mueve, y el final de la hoja
  // no se alcanza nunca.
  testWidgets('la hoja del pre-despacho cabe en el cajón de un teléfono', (
    tester,
  ) async {
    await sembrarLoBasico();
    await sembrarPedidos(3);
    await pintar(tester, pantalla: const Size(390, 844));
    await llegarAlPaso4(tester);

    await hastaLaLista(tester, 844);
    await tester.tap(find.byType(CheckboxListTile).first);
    await asentar(tester);
    // El pre-despacho es lo último del paso en un móvil: hay que bajar hasta él.
    await hastaElFinalDelPaso(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Ver e imprimir'));
    await asentar(tester);

    final hoja = find.byType(VistaPreviaPdf);
    expect(hoja, findsOneWidget);

    // Y ahora la pantalla de un teléfono pequeño, de los que hay en el almacén.
    // La hoja tiene que encoger CON ella: si mide un número escrito a mano, no
    // encoge, y entonces el cuerpo del cajón se vuelve un segundo desplazable
    // vertical por debajo del de la hoja.
    tester.view.physicalSize = const Size(390, 640);
    await tester.pump();

    final cuerpoDeLaHoja = tester
        .state<ScrollableState>(
          find.ancestor(of: hoja, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(
      cuerpoDeLaHoja.maxScrollExtent,
      0,
      reason:
          'La hoja pide más alto del que tiene el cajón, así que el cuerpo del '
          'cajón se ha vuelto desplazable por debajo de la hoja. Con el dedo '
          'encima manda el de dentro: el de fuera no se mueve nunca y el final '
          'de la hoja no se alcanza.',
    );
    expect(aLaVista(tester, hoja), isTrue);

    await desmontar(tester);
  });

  testWidgets('en escritorio el pre-despacho va AL LADO de la lista', (
    tester,
  ) async {
    await sembrarLoBasico();
    await sembrarPedidos(6);
    await pintar(tester, pantalla: const Size(1440, 1100));
    await llegarAlPaso4(tester);

    final preDespacho = find.byKey(AsistenteNuevaRuta.claveDelPreDespacho);
    expect(
      tester.getRect(preDespacho).left,
      greaterThanOrEqualTo(tester.getRect(laCaja).right),
    );
    expect(
      tester.getRect(preDespacho).top,
      lessThan(tester.getRect(laCaja).bottom),
    );

    await desmontar(tester);
  });
}
