// DE UNA RUTA ELEGIDA SE TIENE QUE PODER SALIR.
//
// Jose, 17/09/2026: «toqué una ruta hecha para ver detalles y no puedo salir de
// esa ruta señalada, arregla eso también».
//
// Era literal. `rutaElegidaProvider` se ponía al tocar una tarjeta y el ÚNICO
// sitio que lo soltaba era completar la ruta. Una ruta ya completada no se puede
// completar otra vez, así que quien abría una del `Historial` se quedaba dentro.
// Y en el teléfono duele el doble, porque ahí el detalle **sustituye** a la
// lista: no queda nada de la pantalla anterior a lo que volver.
//
// Son dos salidas y hacen falta las dos:
//
//  * la ✕ de la cabecera del detalle, que se ve y no desaparece nunca (regla 4
//    de la casa), y que a cualquier ancho deselecciona;
//  * el botón de atrás del sistema, que en un teléfono es lo primero que se
//    pulsa — y que tiene que soltar la ruta SIN sacar de Rutas.
//
// Que completar una ruta siga soltándola lo vigila
// `pestana_sigue_a_la_ruta_test.dart`, y no se toca.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/pestanas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/pantalla_rutas.dart';
import 'package:reparto/textos/textos.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() => base = baseDePrueba());

  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> pintar(WidgetTester tester, {required double ancho}) async {
    // SE SIEMBRA AQUÍ, DENTRO DE LA PRUEBA, y no en el `setUp`: el `setUp` corre
    // fuera del reloj falso del `tester` y lo que Drift deja empezado allí no
    // avanza dentro — la prueba se cuelga en vez de fallar (CLAUDE.md §5).
    await sembrarCatalogo(base);
    // Una ruta YA COMPLETADA, que es el caso exacto que contó Jose: no tiene
    // botón de completar, así que antes no había ninguna forma de soltarla.
    await sembrarRuta(
      base,
      id: 'R3',
      codigo: 'RT-VIEJA',
      estado: EstadoRuta.completada,
      creada: ahora,
    );
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);

    tester.view.physicalSize = Size(ancho, 1200);
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
          home: const Scaffold(body: PantallaRutas()),
        ),
      ),
    );
    await asentar(tester);
    // A la pestaña donde está la ruta completada, **y se llega distinto según
    // el ancho**: en un teléfono hay carrusel y sólo se ve la actual, así que
    // se avanza con la flecha; en un monitor están las tres a la vez y se pulsa
    // la suya (`PestanasQueCaben`, desde el 17/09/2026).
    if (find.byKey(ClavesDePestanas.adelante).evaluate().isEmpty) {
      await tester.tap(find.textContaining('Historial'));
      await asentar(tester);
    } else {
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(ClavesDePestanas.adelante));
        await asentar(tester);
      }
    }
    // Y se elige, que es el gesto que dejaba encerrado.
    await tester.tap(find.text('RT-VIEJA'));
    await asentar(tester);
  }

  testWidgets('en un TELÉFONO la barra de volver devuelve a la lista', (
    tester,
  ) async {
    await pintar(tester, ancho: 420);

    // Dentro: el detalle ha sustituido a la lista.
    expect(find.byType(DetalleDeRuta), findsOneWidget);
    expect(
      find.byKey(claveDeVolverALaLista),
      findsOneWidget,
      reason:
          'la barra de «Volver a la lista» no puede faltar: en el teléfono el '
          'detalle sustituye a la lista y es la única salida que se ve',
    );

    await tester.tap(find.byKey(claveDeVolverALaLista));
    await asentar(tester);

    expect(
      find.byType(DetalleDeRuta),
      findsNothing,
      reason: 'pulsar la ✕ tiene que soltar la ruta elegida',
    );
    expect(
      find.text('RT-VIEJA'),
      findsOneWidget,
      reason: 'y devolver la lista, que es de donde se venía',
    );

    await desmontar(tester);
  });

  testWidgets('el botón de ATRÁS suelta la ruta y NO sale de Rutas', (
    tester,
  ) async {
    await pintar(tester, ancho: 420);
    expect(find.byType(DetalleDeRuta), findsOneWidget);

    await tester.binding.handlePopRoute();
    await asentar(tester);

    expect(
      find.byType(DetalleDeRuta),
      findsNothing,
      reason:
          'en un teléfono, atrás es lo primero que se pulsa para salir de algo',
    );
    expect(
      find.byType(PantallaRutas),
      findsOneWidget,
      reason:
          'y lo que suelta es la ruta, NO la pantalla: salir de Rutas entera '
          'deja a quien sólo quería cerrar un detalle fuera de donde estaba',
    );
    expect(find.text('RT-VIEJA'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets(
    'si la ruta DESAPARECE con la pantalla abierta, se dice y se puede volver',
    (tester) async {
      // En el orden de la vida real: se entra en la ruta y ALGUIEN LA BORRA
      // después, sin volver a montar nada. Sembrar el hueco antes de montar es
      // justo el caso que el código roto también resolvía bien (§3-ter).
      await pintar(tester, ancho: 420);
      expect(find.byType(DetalleDeRuta), findsOneWidget);
      expect(find.text('RT-VIEJA'), findsWidgets);

      await (base.delete(base.routes)..where((r) => r.id.equals('R3'))).go();
      await asentar(tester);

      expect(
        find.textContaining('Esta ruta ya no está'),
        findsOneWidget,
        reason:
            'una ruta que ya no existe NO es una ruta que todavía no ha '
            'llegado: «Cargando...» ahí es una rueda que no para nunca, que es '
            'lo que le pasó a Jose en el teléfono',
      );
      expect(
        find.text('Cargando...'),
        findsNothing,
        reason: 'y desde luego no las dos cosas a la vez',
      );

      // Y la salida, que es la mitad que importa: sin ella se queda mirando el
      // cartel con la ruta todavía elegida.
      await tester.tap(find.byKey(claveDeVolverDeLaQueNoEsta));
      await asentar(tester);
      expect(find.byType(DetalleDeRuta), findsNothing);

      await desmontar(tester);
    },
  );

  testWidgets('en ESCRITORIO también se puede deseleccionar', (tester) async {
    // Con la lista y el detalle a la vez el encierro no se nota, pero soltar la
    // ruta tampoco se podía, y el detalle se quedaba hablando de algo que ya no
    // se estaba mirando.
    await pintar(tester, ancho: 1400);

    expect(find.byType(DetalleDeRuta), findsOneWidget);
    // En escritorio no hay barra de volver —la lista se ve al lado—: lo que hay
    // es la ✕ de la cabecera del detalle, que deselecciona.
    await tester.tap(find.byKey(claveDeLaEquisDelDetalle));
    await asentar(tester);

    expect(find.byType(DetalleDeRuta), findsNothing);
    expect(
      find.text('Selecciona una ruta para ver el detalle'),
      findsOneWidget,
    );

    await desmontar(tester);
  });
}
