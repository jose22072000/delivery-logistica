// QUE BOTON SALE EN CADA ESTADO DE LA RUTA, Y QUE HACE EL DE COMPLETAR.
//
// Esta prueba la escribe quien NO escribio la pantalla, a proposito: una guarda
// que rompe el mismo que la puso no es una guarda (`CLAUDE.md`, la regla de los
// agentes). El cajon del cierre por dentro lo cubre
// `cierre_al_completar_test.dart`; aqui se mira lo de fuera.
//
// La regla, de Jose el 17/09/2026: «ese estado se pone cuando están en ruta, no
// completados; ahí el cierre ya viene con el estado de cuando le van a dar a
// completado, es que se pregunta ese estado».
//
//   planificada  → `Iniciar ruta`. Ni cierre ni completar: no hay nada que
//                  cerrar de una ruta que no ha salido.
//   en curso     → `Cierre (N)` —N es lo que queda por marcar, o sea una tarea—
//                  y `Marcar como completada`.
//   completada   → `Ver cierre`, **sin la cuenta**, y nada mas. En una ruta
//                  cerrada «sin marcar» no es una tarea: es como acabo.
//
// Y el gesto que lo une todo: con paradas sin marcar, `Marcar como completada`
// **pregunta antes** en vez de cerrar la ruta a espaldas de nadie.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/cierre_de_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';
import 'package:reparto/textos/textos.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Siembra **dentro del cuerpo de la prueba**, nunca en el `setUp`: allí corre
  /// fuera del reloj falso y la prueba se cuelga en vez de fallar (§5).
  Future<void> sembrar({
    required String estado,
    int paradas = 3,
    int marcadas = 0,
  }) async {
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', codigo: 'RT-001', estado: estado);
    for (var i = 0; i < paradas; i++) {
      await sembrarPedido(
        base,
        id: 'p${i + 1}',
        cliente: 'Cliente ${i + 1}',
        rutaId: 'R1',
        orden: i + 1,
        resultado: i < marcadas ? ResultadoParada.entregado : null,
      );
    }
  }

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
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
          home: const Scaffold(body: DetalleDeRuta(rutaId: 'R1')),
        ),
      ),
    );
    await asentar(tester);
  }

  Future<String?> estadoDeLaRuta() async {
    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals('R1'))).getSingleOrNull();
    return ruta?.status;
  }

  testWidgets('planificada: ni cierre ni completar', (tester) async {
    await sembrar(estado: EstadoRuta.planificada);
    await pintar(tester);

    expect(find.text('Iniciar ruta'), findsOneWidget);
    expect(find.byKey(claveDelCierre), findsNothing);
    expect(find.byKey(claveDeCompletar), findsNothing);
    expect(find.text('Ver cierre'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('en curso: `Cierre (N)` con la cuenta, y completar', (
    tester,
  ) async {
    await sembrar(estado: EstadoRuta.enCurso, marcadas: 1);
    await pintar(tester);

    // Dos de las tres sin marcar: eso es lo que queda por hacer, y se dice.
    expect(find.text('Cierre (2)'), findsOneWidget);
    expect(find.text('Ver cierre'), findsNothing);
    expect(find.byKey(claveDeCompletar), findsOneWidget);
    expect(find.text('Iniciar ruta'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('completada: `Ver cierre` SIN la cuenta, y nada mas', (
    tester,
  ) async {
    await sembrar(estado: EstadoRuta.completada, marcadas: 1);
    await pintar(tester);

    expect(find.text('Ver cierre'), findsOneWidget);
    // **Sin el numero.** Un `Cierre (2)` en una ruta cerrada parece una tarea
    // pendiente que ya nadie puede hacer.
    expect(find.text('Cierre (2)'), findsNothing);
    expect(find.textContaining('Cierre ('), findsNothing);
    // Y no se puede volver a completar ni iniciar.
    expect(find.byKey(claveDeCompletar), findsNothing);
    expect(find.text('Iniciar ruta'), findsNothing);

    // Y ABRE EN SOLO LECTURA, que es la mitad que el texto del boton no
    // demuestra: sin esto, dejarlo abriendo en modo de marcar pasa en silencio
    // y la ruta cerrada se sigue pudiendo tocar.
    await tester.tap(find.byKey(claveDelCierre));
    await asentar(tester);
    expect(find.text(CierreDeRuta.cabeceraSoloLectura), findsOneWidget);
    expect(find.text(CierreDeRuta.cabecera), findsNothing);
    expect(find.textContaining('Guardar'), findsNothing);

    await desmontar(tester);
  });

  testWidgets(
    'con paradas sin marcar, completar PREGUNTA antes de cerrar la ruta',
    (tester) async {
      await sembrar(estado: EstadoRuta.enCurso, marcadas: 1);
      await pintar(tester);

      await tester.tap(find.byKey(claveDeCompletar));
      await asentar(tester);

      // Se abre el cierre en su modo de completar...
      expect(find.text(CierreDeRuta.cabeceraAlCompletar), findsOneWidget);
      expect(find.text('Guardar y completar'), findsOneWidget);
      // ...y la ruta **todavia no se ha completado**. Cerrarla antes de
      // preguntar seria darla por cuadrada sin saber que bajo del camion.
      expect(await estadoDeLaRuta(), EstadoRuta.enCurso);

      await desmontar(tester);
    },
  );

  testWidgets('con todo marcado, completar no abre ningun cajon', (
    tester,
  ) async {
    await sembrar(estado: EstadoRuta.enCurso, paradas: 3, marcadas: 3);
    await pintar(tester);

    // Sin nada que preguntar el boton no lleva cuenta...
    expect(find.text('Cierre'), findsOneWidget);
    await tester.tap(find.byKey(claveDeCompletar));
    await asentar(tester);

    // ...y se completa y ya: abrir un cajon para no preguntar nada es friccion.
    expect(find.text(CierreDeRuta.cabeceraAlCompletar), findsNothing);
    expect(await estadoDeLaRuta(), EstadoRuta.completada);

    await desmontar(tester);
  });
}
