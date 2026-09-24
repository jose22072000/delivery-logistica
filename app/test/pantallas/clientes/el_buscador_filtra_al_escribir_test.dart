// EL BUSCADOR DE CLIENTES, SEGÚN SE ESCRIBE.
//
// Aquí el respiro ya estaba —copiado a mano, con su propio `Timer` y su propio
// `TextEditingController`—, y es justo el problema: la misma caja escrita cinco
// veces son cinco comportamientos. En el Tablero ni siquiera había respiro:
// había que dar Intro. Ahora las cinco son `CajaDeBusqueda`.
//
// Lo que se comprueba aquí es lo de esta pantalla: que sobre 8.348 clientes se
// escriba y filtre sin pulsar nada, que escribir rápido sea UNA consulta con la
// palabra entera, y que `Quitar filtros` vacíe también la caja — si no, queda
// un texto filtrando en silencio encima de una lista que ya no está filtrada.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/caja_de_busqueda.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/clientes/datos/repositorio_clientes.dart';
import 'package:reparto/pantallas/clientes/estado/estado_clientes.dart';
import 'package:reparto/pantallas/clientes/vista/pantalla_clientes.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo_clientes.dart';

void main() {
  late BaseLocal base;
  final bajada = DateTime(2026, 9, 14, 7, 42);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  /// Los clientes se siembran DENTRO del cuerpo, nunca en el `setUp`: lo que
  /// Drift deja empezado fuera del reloj falso no avanza dentro y la prueba se
  /// cuelga en vez de fallar (`CLAUDE.md` §5).
  Future<void> sembrarTres() async {
    await sembrarSucursal(base);
    await sembrarCliente(
      base,
      id: 'c1',
      nombre: 'DAYLIS PEREZ',
      lat: almacenLat,
      lng: almacenLng,
    );
    await sembrarCliente(
      base,
      id: 'c2',
      nombre: 'CHAPLIN RODRIGUEZ',
      lat: almacenLat,
      lng: almacenLng,
    );
    await sembrarCliente(
      base,
      id: 'c3',
      nombre: 'MARIELA SUAREZ',
      lat: almacenLat,
      lng: almacenLng,
    );
    await marcarBajada(base, bajada);
  }

  late ProviderContainer contenedor;

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    contenedor = ProviderContainer.test(
      overrides: [
        baseProvider.overrideWithValue(base),
        relojProvider.overrideWithValue(() => bajada),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: contenedor,
        child: const MaterialApp(home: Scaffold(body: PantallaClientes())),
      ),
    );
    await asentar(tester);
  }

  Finder laCaja() => find.descendant(
    of: find.byType(CajaDeBusqueda),
    matching: find.byType(TextField),
  );

  String enLaCaja() =>
      (laCaja().evaluate().single.widget as TextField).controller!.text;

  String? elFiltro() => contenedor.read(filtrosClientesProvider).q;

  testWidgets('se escribe SIN Intro y la lista filtra sola', (tester) async {
    await sembrarTres();
    await pintar(tester);
    expect(find.text('DAYLIS PEREZ'), findsOneWidget);
    expect(find.text('CHAPLIN RODRIGUEZ'), findsOneWidget);

    await tester.enterText(laCaja(), 'DAYLIS');
    await tester.pump();
    expect(elFiltro(), isNull, reason: 'todavía no: primero el respiro');

    await tester.pump(CajaDeBusqueda.esperaPorDefecto);
    await asentar(tester);

    expect(elFiltro(), 'DAYLIS');
    expect(find.text('DAYLIS PEREZ'), findsOneWidget);
    expect(
      find.text('CHAPLIN RODRIGUEZ'),
      findsNothing,
      reason: 'la lista tiene que haber filtrado sin pulsar nada',
    );

    await desmontar(tester);
  });

  testWidgets('escribir rápido: una sola consulta y con la palabra entera', (
    tester,
  ) async {
    await sembrarTres();
    await pintar(tester);

    final consultadas = <String?>[];
    contenedor.listen<FiltrosClientes>(
      filtrosClientesProvider,
      (antes, ahora) => consultadas.add(ahora.q),
    );

    for (final trozo in ['C', 'CH', 'CHA', 'CHAP', 'CHAPL', 'CHAPLIN']) {
      await tester.enterText(laCaja(), trozo);
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pump(CajaDeBusqueda.esperaPorDefecto);
    await asentar(tester);

    expect(
      consultadas,
      ['CHAPLIN'],
      reason: 'seis consultas sobre 8.348 clientes son seis repintados',
    );
    expect(
      enLaCaja(),
      'CHAPLIN',
      reason: 'y el campo es de la persona: no se le quitan letras',
    );
    expect(find.text('CHAPLIN RODRIGUEZ'), findsOneWidget);
    expect(find.text('MARIELA SUAREZ'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('Intro busca ya, y no dispara una segunda búsqueda', (
    tester,
  ) async {
    await sembrarTres();
    await pintar(tester);

    final consultadas = <String?>[];
    contenedor.listen<FiltrosClientes>(
      filtrosClientesProvider,
      (antes, ahora) => consultadas.add(ahora.q),
    );

    await tester.enterText(laCaja(), 'MARIELA');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await asentar(tester);

    expect(consultadas, ['MARIELA']);

    await tester.pump(CajaDeBusqueda.esperaPorDefecto);
    expect(
      consultadas,
      ['MARIELA'],
      reason: 'el respiro que quedaba en el aire no puede repetir la consulta',
    );

    // Y al revés: buscar por el respiro y DESPUÉS pulsar Intro sobre lo mismo
    // tampoco vuelve a consultar.
    await tester.enterText(laCaja(), 'DAYLIS');
    await tester.pump(CajaDeBusqueda.esperaPorDefecto);
    await asentar(tester);
    expect(consultadas, ['MARIELA', 'DAYLIS']);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(CajaDeBusqueda.esperaPorDefecto);
    await asentar(tester);
    expect(
      consultadas,
      ['MARIELA', 'DAYLIS'],
      reason: 'sería una segunda consulta encima de la que ya está pintada',
    );

    await desmontar(tester);
  });

  testWidgets('`Quitar filtros` vacía TAMBIÉN la caja', (tester) async {
    await sembrarTres();
    await pintar(tester);

    await tester.enterText(laCaja(), 'DAYLIS');
    await tester.pump(CajaDeBusqueda.esperaPorDefecto);
    await asentar(tester);
    expect(find.text('Quitar filtros'), findsOneWidget);

    await tester.tap(find.text('Quitar filtros'));
    await asentar(tester);

    expect(elFiltro(), isNull);
    expect(
      enLaCaja(),
      '',
      reason:
          'una caja con texto encima de una lista sin filtrar se lee como '
          '«esto es todo lo que hay»',
    );
    expect(find.text('CHAPLIN RODRIGUEZ'), findsOneWidget);

    await desmontar(tester);
  });
}
