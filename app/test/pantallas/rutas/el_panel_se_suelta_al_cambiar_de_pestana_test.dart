// EL PANEL DE LA DERECHA NO PUEDE ENSEÑAR UNA RUTA QUE NO ESTÁ EN LA LISTA.
//
// Medido el 22/09/2026 en un monitor: con `RT-…-002` abierta en el panel de la
// derecha, pulsar la pestaña `Historial` cambiaba la lista de la izquierda y
// **dejaba el panel enseñando esa misma ruta**, con su botón `Iniciar ruta`
// vivo. Media pantalla hablando de una cosa y la otra media de otra, y sin nada
// que avisara: la ruta del panel ya no estaba en la lista de al lado, así que no
// había forma de volver a ella ni de saber de dónde había salido.
//
// La regla: el panel de la derecha es el detalle de algo de ESTA lista. Si se
// cambia de lista a mano, no hay nada abierto.
//
// # Y la otra mitad, que es la que hace difícil la regla
//
// Hay un cambio de pestaña que **no** puede soltar la ruta: `Iniciar ruta` mueve
// la pestaña a `En curso` y **se lleva la ruta consigo** a propósito, para que no
// le desaparezca de delante a quien acaba de arrancarla (la de Next hace lo
// mismo, `routes/page.tsx:447`). Por eso el soltar va en el gesto de la persona
// y no dentro de `PestanaElegida`: desde dentro del provider los dos cambios son
// idénticos.
//
// Las dos pruebas van en pareja, y la segunda es la que de verdad cuesta: sin
// ella, «soltar siempre que cambie la pestaña» sale verde y rompe el arranque de
// una ruta.
//
// Esto es **de escritorio**. En el móvil el detalle va en un cajón que tapa las
// pestañas, así que este choque no existe (`el_detalle_va_en_un_cajon_test.dart`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/pantalla_rutas.dart';
import 'package:reparto/textos/textos.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

/// El cartel del panel vacío. Escrito una vez: la misma frase copiada a mano en
/// dos sitios se separa en cuanto alguien cambie uno.
const sinNadaAbierto = 'Selecciona una ruta para ver el detalle';

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

  /// Dentro del cuerpo de la prueba, nunca en el `setUp` (CLAUDE.md §5).
  Future<void> sembrar() async {
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', codigo: 'RT-001', creada: ahora);
    await sembrarPedido(base, id: 'p1', cliente: 'Ana', rutaId: 'R1', orden: 1);
    // Una en el `Historial`, para que al cambiar de pestaña haya algo distinto
    // que mirar y no se confunda «se soltó» con «no hay nada».
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
  }

  /// Un monitor: la lista a la izquierda, el detalle a la derecha y **las tres
  /// pestañas a la vez** (`PestanasQueCaben`, desde 900 px).
  Future<void> pintar(WidgetTester tester) async {
    await sembrar();

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
          home: const Scaffold(body: PantallaRutas()),
        ),
      ),
    );
    await asentar(tester);

    // La ruta planificada, abierta en el panel de la derecha: es el caso exacto
    // del 22/09/2026, con su `Iniciar ruta`.
    await tester.tap(find.text('RT-001'));
    await asentar(tester);
    expect(find.byType(DetalleDeRuta), findsOneWidget);
    expect(find.text('Iniciar ruta'), findsOneWidget);
  }

  testWidgets('pulsar otra pestaña SUELTA la ruta del panel', (tester) async {
    await pintar(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Historial (1)'));
    await asentar(tester);

    expect(
      find.byType(DetalleDeRuta),
      findsNothing,
      reason:
          'EL PANEL SE QUEDÓ ENSEÑANDO UNA RUTA QUE YA NO ESTÁ EN LA LISTA. La '
          'izquierda dice `Historial` y la derecha sigue con la ruta '
          'planificada de la pestaña anterior: no hay forma de volver a ella ni '
          'de saber de dónde salió',
    );
    expect(find.text(sinNadaAbierto), findsOneWidget);
    expect(
      find.text('Iniciar ruta'),
      findsNothing,
      reason:
          'y con ella se va su botón: arrancar desde el `Historial` una ruta '
          'que no se está mirando es el gesto más caro que deja este fallo',
    );
    // La lista sí cambió, que es lo que se pidió al pulsar.
    expect(find.text('RT-VIEJA'), findsOneWidget);
    expect(find.text('RT-001'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('y deslizando la lista, igual', (tester) async {
    // La pestaña también se cambia arrastrando la lista a lo ancho, y ahí el
    // aviso llega por otro sitio (`CuerpoDeslizable`). Sin esta, la guarda se
    // puede poner sólo en los botones y el arrastre se queda fuera.
    await pintar(tester);

    await tester.fling(find.byType(PageView), const Offset(-250, 0), 1000);
    await asentar(tester);

    expect(find.byType(DetalleDeRuta), findsNothing);
    expect(find.text(sinNadaAbierto), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('pero `Iniciar ruta` mueve la pestaña y NO suelta la ruta', (
    tester,
  ) async {
    // LA OTRA MITAD DEL PAR. Iniciar saca la ruta de `Planificadas` —bien: ya no
    // está planificada, está en curso— y la pantalla se va con ella. Si el
    // soltar viviera dentro de `PestanaElegida`, este cambio sería
    // indistinguible del de arriba y la ruta le desaparecería de delante a quien
    // acaba de arrancarla, que es el fallo que se arregló el 17/09/2026.
    await pintar(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar ruta'));
    await asentar(tester);

    expect(
      find.widgetWithText(FilledButton, 'En curso (1)'),
      findsOneWidget,
      reason: 'la pestaña se movió con la ruta',
    );
    expect(
      find.byType(DetalleDeRuta),
      findsOneWidget,
      reason:
          'SE LE SOLTÓ LA RUTA A QUIEN ACABABA DE ARRANCARLA: el detalle tiene '
          'que seguir delante, con su `Cierre` y su `Marcar como completada`',
    );
    expect(find.text(sinNadaAbierto), findsNothing);
    expect(find.text('Marcar como completada'), findsOneWidget);
    // Y sigue en la lista de al lado, que es donde acaba de caer.
    expect(find.text('RT-001'), findsNWidgets(2));

    await desmontar(tester);
  });
}
