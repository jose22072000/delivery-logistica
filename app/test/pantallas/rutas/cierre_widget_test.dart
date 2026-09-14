// El cierre de ruta, pintado. Lo que aqui se comprueba no se ve en un test de
// datos: que pulsar dos veces el mismo boton DESMARCA, que `Todas:` marca de
// golpe, que la ✕ de cerrar esta siempre, y —lo que mas importa— que **al
// reabrir se parte de lo ya guardado**.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/reloj.dart';
import 'package:reparto/pantallas/rutas/vista/cierre_de_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

/// Un indicador giratorio es una animacion que no para, asi que `pumpAndSettle`
/// no terminaria nunca. Se bombean unos fotogramas y basta.
Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Al desmontarse, los `watch()` de Drift programan un temporizador de cero para
/// cerrarse. Si el test acaba antes de que corra, el marco lo cuenta como
/// pendiente y falla.
Future<void> desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  late BaseLocal base;
  final laHoraDelPatio = DateTime(2026, 9, 14, 16, 5);

  setUp(() async {
    base = baseDePrueba();
    await sembrarCatalogo(base);
    await sembrarRuta(
      base,
      id: 'R1',
      estado: EstadoRuta.enCurso,
      codigo: 'RT-20260914-001',
    );
    for (final (i, nombre) in <String>['Ana', 'Beto', 'Carla'].indexed) {
      await sembrarPedido(
        base,
        id: 'p${i + 1}',
        cliente: nombre,
        rutaId: 'R1',
        orden: i + 1,
      );
      await sembrarRenglon(
        base,
        id: 'ri${i + 1}',
        pedidoId: 'p${i + 1}',
        producto: 'Arroz',
        unidades: 10,
        empaques: 2,
      );
    }
  });

  tearDown(() => base.close());

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => laHoraDelPatio),
        ],
        child: const MaterialApp(home: CierreDeRuta(rutaId: 'R1')),
      ),
    );
    await asentar(tester);
  }

  /// El boton de una parada concreta. Hacen falta indices porque `Entregado`
  /// aparece cuatro veces: una por parada y una en la fila de atajos.
  Finder botonDeParada(String texto, int parada) =>
      find.widgetWithText(OutlinedButton, texto).at(parada + 1);

  testWidgets('la cabecera, la ✕ y el pie salen con su texto literal', (
    tester,
  ) async {
    await pintar(tester);

    expect(find.text('Cierre de ruta'), findsOneWidget);
    expect(find.text('RT-20260914-001 · 3 parada(s)'), findsOneWidget);
    expect(find.text(CierreDeRuta.cabecera), findsOneWidget);
    // La ✕ que nunca desaparece: esta fuera del cuerpo desplazable.
    expect(find.byTooltip('Cerrar'), findsOneWidget);
    // Con 0 marcadas, Guardar esta deshabilitado.
    expect(find.text('Guardar 0 marcada(s)'), findsOneWidget);
    final guardar = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Guardar 0 marcada(s)'),
    );
    expect(guardar.onPressed, isNull);
    // Las tres sin marcar cuentan como que siguen arriba.
    expect(
      find.text('3 sin marcar · cuentan como que siguen en el camión'),
      findsOneWidget,
    );
    await desmontar(tester);
  });

  testWidgets('pulsar el mismo boton dos veces DESMARCA', (tester) async {
    await pintar(tester);

    await tester.tap(botonDeParada('Entregado', 0));
    await asentar(tester);
    expect(find.text('Guardar 1 marcada(s)'), findsOneWidget);

    // Otra vez el mismo: se desmarca. Es como se corrige un dedazo sin recargar
    // nada.
    await tester.tap(find.widgetWithText(FilledButton, 'Entregado'));
    await asentar(tester);
    expect(find.text('Guardar 0 marcada(s)'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('`Devuelto` pide el motivo y `Todas:` marca de golpe', (
    tester,
  ) async {
    await pintar(tester);

    await tester.tap(botonDeParada('Devuelto', 0));
    await asentar(tester);
    expect(
      find.text(
        '¿Por qué volvió? (el cliente cerró, no lo quiso, no había nadie…)',
      ),
      findsOneWidget,
    );

    // El atajo es el PRIMER `Entregado` de la pantalla: la fila `Todas:`.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Entregado').first);
    await asentar(tester);
    expect(find.text('Guardar 3 marcada(s)'), findsOneWidget);
    // Con todo entregado no queda nada en el camion.
    expect(find.text('Nada: se entregó todo lo que salió.'), findsOneWidget);
    // Y el campo de motivo desaparece, porque ya no hay ninguna devuelta.
    expect(
      find.text(
        '¿Por qué volvió? (el cliente cerró, no lo quiso, no había nadie…)',
      ),
      findsNothing,
    );
    await desmontar(tester);
  });

  testWidgets('la vista previa dice lo que QUEDA, incluido lo sin marcar', (
    tester,
  ) async {
    await pintar(tester);

    await tester.tap(botonDeParada('Entregado', 0));
    await asentar(tester);
    // Salieron 6 empaques de arroz; se entrego 1 parada (2), quedan 4: los 2 de
    // la devuelta... o mas bien los 4 de las dos sin marcar.
    expect(find.text('Arroz ×4'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('guardar encola el cierre y AL REABRIR se ve marcado', (
    tester,
  ) async {
    await pintar(tester);

    await tester.tap(botonDeParada('Entregado', 0));
    await asentar(tester);
    await tester.tap(botonDeParada('Devuelto', 1));
    await asentar(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Guardar 2 marcada(s)'));
    await asentar(tester);

    // El cierre esta en la cola, con la hora del aparato, sin haber hablado con
    // ningun servidor.
    final cola = ColaDeSalida(base, reloj: () => laHoraDelPatio);
    final pendientes = await cola.pendientes().first;
    expect(pendientes.length, 1);
    expect(pendientes.single.ruta, '/routes/R1/results');
    expect(pendientes.single.hechoAt, laHoraDelPatio);

    // Y se le dice a la persona lo que paso, con el texto del pliego.
    expect(find.text(CierreDeRuta.exito), findsOneWidget);

    await desmontar(tester);

    // Se vuelve a abrir el cajon: **se parte de lo ya guardado**, no de cero.
    await pintar(tester);
    expect(find.text('Guardar 2 marcada(s)'), findsOneWidget);
    expect(
      find.text('1 sin marcar · cuentan como que siguen en el camión'),
      findsOneWidget,
    );
    await desmontar(tester);
  });
}
