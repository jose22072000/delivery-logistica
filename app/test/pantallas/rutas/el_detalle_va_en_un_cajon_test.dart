// EN EL MÓVIL, EL DETALLE DE UNA RUTA VA EN UN CAJÓN.
//
// Jose, 22/09/2026:
//
// > «cuando estoy viendo un detalle de una ruta me puedo mover por los
// > diferentes tabs eso no lo quiero ponlo en un drawer en el movil para ver eso
// > y asi queda mejor para no andar navegando»
//
// Son dos quejas en una frase, y hacen falta las dos pruebas:
//
//  1. **Lo que se ve.** El detalle sustituía a la lista DENTRO de la misma
//     pantalla, así que la cabecera de la lista —el título, el buscador, los
//     filtros y las pestañas— seguía clavada arriba encima de un detalle donde
//     ya no sirve para nada. Medido en el teléfono de Jose (2340 px de alto):
//     ~1050 px de cabecera, y el mapa de la ruta en una rendija de ~270 px con
//     sus mandos de + / − y el de pantalla completa fuera de la vista.
//  2. **Lo que se puede hacer.** El carrusel de pestañas seguía vivo debajo del
//     detalle: con una ruta abierta se podía deslizar a `Historial` y acabar
//     mirando el detalle de una ruta que ya no está en la lista de debajo. Eso
//     es «andar navegando» desde dentro de un detalle.
//
// Un cajón arregla las dos: es una ruta modal, o sea que tapa la pantalla entera
// y se come todos los gestos de lo que hay debajo. Y al cerrarlo la lista sigue
// donde estaba, porque nunca se fue.
//
// **En escritorio no se toca nada** y esta prueba lo vigila también: ahí el
// detalle va en el panel de la derecha y no hay ningún cajón.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/pedidos/vista/kit.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/pantalla_rutas.dart';
import 'package:reparto/idioma.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

/// Un teléfono de verdad: 390x844, que es el tamaño con el que están medidos los
/// demás fallos de esta pantalla.
const telefono = Size(390, 844);

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

  /// Siembra **dentro del cuerpo de la prueba**, nunca en el `setUp`: allí corre
  /// fuera del reloj falso y lo que Drift deja empezado no avanza dentro — la
  /// prueba se cuelga en vez de fallar (CLAUDE.md §5).
  Future<void> sembrar() async {
    await sembrarCatalogo(base);
    await sembrarRuta(base, id: 'R1', codigo: 'RT-001', creada: ahora);
    await sembrarPedido(
      base,
      id: 'p1',
      cliente: 'Ana',
      rutaId: 'R1',
      orden: 1,
      endLat: 21.39,
      endLng: -77.92,
    );
    // Una en cada una de las otras dos pestañas: así se nota si el deslizamiento
    // llegó a alguna parte.
    await sembrarRuta(
      base,
      id: 'R2',
      codigo: 'RT-ENCURSO',
      estado: EstadoRuta.enCurso,
      creada: ahora,
    );
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

  Future<void> pintar(WidgetTester tester, {Size tamano = telefono}) async {
    await sembrar();

    tester.view.physicalSize = tamano;
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
  }

  Future<void> abrirLaRuta(WidgetTester tester) async {
    await tester.tap(find.text('RT-001'));
    await asentar(tester);
  }

  testWidgets('tocar una ruta abre un CAJÓN con su detalle', (tester) async {
    await pintar(tester);
    expect(find.byType(Cajon), findsNothing, reason: 'todavía no se ha tocado nada');

    await abrirLaRuta(tester);

    expect(find.byType(Cajon), findsOneWidget);
    expect(find.byType(DetalleDeRuta), findsOneWidget);
    // Con el código de la ruta por título, que es lo que se viene a mirar.
    expect(find.text('RT-001'), findsWidgets);

    // UNA SOLA ✕, la del cajón. La cabecera del detalle trae la suya para el
    // panel de escritorio, y aquí sobra: dos aspas seguidas que hacen lo mismo
    // en una pantalla de 390 px son ruido y una duda («¿ésta cierra el panel o
    // cierra otra cosa?»), justo encima del alto que se venía a recuperar.
    expect(
      find.byKey(claveDeLaEquisDelDetalle),
      findsNothing,
      reason:
          'dentro del cajón manda la ✕ de la cabecera del cajón, que es la que '
          'no se puede perder de vista',
    );
    expect(
      find.descendant(
        of: find.byType(Cajon),
        matching: find.byTooltip('Cerrar'),
      ),
      findsOneWidget,
    );

    await desmontar(tester);
  });

  testWidgets('una ruta YA elegida al encoger la ventana también abre el cajón', (
    tester,
  ) async {
    // El caso que `ref.listen` no ve: no hay cambio que escuchar porque la ruta
    // ya estaba elegida antes de que esta forma de la pantalla naciera. Pasa al
    // encoger la ventana del navegador —lo de aquí— y pasa **al armar una ruta
    // con el asistente**, que la elige él y luego se cierra
    // (`asistente_nueva_ruta.dart`). Sin abrirlo también desde `initState`, la
    // ruta queda elegida y en el teléfono no se ve absolutamente nada.
    await pintar(tester, tamano: const Size(1600, 1400));
    await abrirLaRuta(tester);
    expect(find.byType(Cajon), findsNothing, reason: 'en escritorio no hay cajón');

    tester.view.physicalSize = telefono;
    await asentar(tester);

    expect(
      find.byType(Cajon),
      findsOneWidget,
      reason:
          'LA RUTA SE QUEDÓ ELEGIDA Y SIN ENSEÑAR: en el móvil la columna es '
          'sólo la lista, así que si el cajón no se abre no hay ningún sitio '
          'donde salga el detalle',
    );
    expect(find.byType(DetalleDeRuta), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets(
    'el detalle empieza ARRIBA DEL TODO: la cabecera de la lista ya no se lo come',
    (tester) async {
      await pintar(tester);
      await abrirLaRuta(tester);

      final arriba = tester.getTopLeft(find.byType(DetalleDeRuta)).dy;
      expect(
        arriba,
        lessThan(120),
        reason:
            'ENCIMA DEL DETALLE SÓLO PUEDE ESTAR LA CABECERA DEL CAJÓN. Antes '
            'el detalle vivía dentro de la pantalla de la lista, debajo del '
            'título, del reloj de datos, del botón de «+ Nueva Ruta», de las '
            'tres pestañas, del buscador y de los filtros — todos ellos de la '
            'LISTA, que ahí ya no hace falta. En el teléfono de Jose eso eran '
            '~1050 px de 2340 gastados en nada, con el mapa de la ruta metido '
            'en una rendija',
      );

      // Y el cajón ocupa el ancho ENTERO del teléfono: un panel de 672 px sobre
      // una pantalla de 390 sería un panel recortado.
      final ancho = tester.getSize(find.byType(DetalleDeRuta)).width;
      expect(ancho, greaterThan(telefono.width * 0.85));

      await desmontar(tester);
    },
  );

  testWidgets('con el cajón abierto NO se cambia de pestaña deslizando', (
    tester,
  ) async {
    await pintar(tester);
    await abrirLaRuta(tester);

    // El mismo gesto que en `deslizar_entre_pestanas_test.dart` pasa de página.
    // Aquí no puede: el velo del cajón se lo come.
    //
    // `warnIfMissed: false` **porque fallar el blanco es justo lo que se está
    // comprobando**: el `PageView` sigue en el árbol, debajo, pero el dedo ya no
    // llega hasta él. Sin esto, `fling` escupe un aviso de media pantalla
    // diciendo que «otro widget lo está tapando», que es exactamente lo que
    // queremos que pase.
    await tester.fling(
      find.byType(PageView),
      const Offset(-250, 0),
      1000,
      warnIfMissed: false,
    );
    await asentar(tester);

    expect(
      find.byType(Cajon),
      findsOneWidget,
      reason: 'el cajón sigue abierto: deslizar ahí no es navegar a ningún lado',
    );
    expect(
      find.textContaining('Planificadas'),
      findsOneWidget,
      reason:
          'LA LISTA DE DEBAJO NO SE MOVIÓ. Jose: «me puedo mover por los '
          'diferentes tabs eso no lo quiero». Si el rótulo dijera «En curso», '
          'el detalle abierto estaría hablando de una ruta que ya no está en la '
          'lista que hay debajo',
    );
    expect(find.textContaining('En curso ('), findsNothing);

    await desmontar(tester);
  });

  testWidgets('y SIN el cajón, ese mismo gesto SÍ cambia de pestaña', (
    tester,
  ) async {
    // La otra mitad del par: si el deslizamiento no funcionara nunca, la prueba
    // de arriba saldría verde sin demostrar nada.
    await pintar(tester);

    await tester.fling(find.byType(PageView), const Offset(-250, 0), 1000);
    await asentar(tester);

    expect(find.textContaining('En curso ('), findsOneWidget);
    expect(find.text('RT-ENCURSO'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('cerrar el cajón devuelve a la lista EN LA PESTAÑA donde estaba', (
    tester,
  ) async {
    await pintar(tester);

    // Se cambia a `Historial` ANTES de abrir: lo que se comprueba es que
    // cerrar el cajón no devuelve a la primera pestaña, sino a donde se estaba.
    await tester.fling(find.byType(PageView), const Offset(-250, 0), 1000);
    await asentar(tester);
    await tester.fling(find.byType(PageView), const Offset(-250, 0), 1000);
    await asentar(tester);
    expect(find.text('RT-VIEJA'), findsOneWidget);

    await tester.tap(find.text('RT-VIEJA'));
    await asentar(tester);
    expect(find.byType(Cajon), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(Cajon),
        matching: find.byTooltip('Cerrar'),
      ),
    );
    await asentar(tester);

    expect(find.byType(Cajon), findsNothing);
    expect(
      find.textContaining('Historial'),
      findsOneWidget,
      reason:
          'se mira la ruta, se cierra el cajón, y se vuelve a la lista DONDE SE '
          'ESTABA: la lista nunca se fue, estaba debajo',
    );
    expect(find.text('RT-VIEJA'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('EN ESCRITORIO no hay cajón: el detalle va al lado', (
    tester,
  ) async {
    await pintar(tester, tamano: const Size(1600, 1400));
    await abrirLaRuta(tester);

    expect(find.byType(DetalleDeRuta), findsOneWidget);
    expect(
      find.byType(Cajon),
      findsNothing,
      reason:
          'el cajón es del móvil. En un monitor la lista y el detalle caben a '
          'la vez, y taparle la lista a quien tiene sitio para verla sería '
          'cambiar un fallo por otro',
    );
    // Y la lista sigue a la vista, que es de lo que va el panel de al lado.
    expect(find.text('RT-ENCURSO'), findsNothing, reason: 'otra pestaña');
    expect(find.text('RT-001'), findsNWidgets(2));

    await desmontar(tester);
  });
}
