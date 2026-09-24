// EL BUSCADOR DEL TABLERO PEDÍA INTRO, y nadie pulsa Intro en un buscador.
//
// Jose, 22/09/2026: «tengo q dar enter para q el filtro funcione». Medido el
// mismo día en la web: se escribe `DAYLIS` en la caja de la mitad izquierda y
// **no pasa nada** hasta pulsar Intro.
//
// Dónde estaba: `panel_sin_colocar.dart` tenía un `TextField` a pelo con
// `onSubmitted` y NADA más. `onSubmitted` sólo salta con Intro, así que el
// filtro no estaba atado a lo que se escribe: estaba atado a la tecla.
//
// Estas pruebas son de TIEMPO. El reloj de un `testWidgets` no corre solo: se
// escribe, se avanza el reloj del `tester` y se mira si la lista filtró.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/caja_de_busqueda.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';
import 'package:reparto/pantallas/tablero/vista/panel_sin_colocar.dart';

TarjetaPedido _tarjeta(String cliente) => TarjetaPedido(
  pedidoId: 'p-$cliente',
  customerName: cliente,
  address: 'Calle 1',
  weight: 10,
  kmAlAlmacen: 1,
  mismoCliente: 1,
);

const _clientes = ['DAYLIS', 'CHAPLIN', 'MARIELA'];

/// Quien pinta el panel de verdad: lee los filtros y le pasa la lista YA
/// filtrada. Es el viaje que hacía falta cerrar —caja, filtro, lista— y por el
/// que se perdían las letras cuando volvía.
class _Anfitrion extends ConsumerWidget {
  const _Anfitrion({required this.busquedas});

  final List<String> busquedas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtros = ref.watch(filtrosTableroProvider);
    final q = (filtros.q ?? '').trim().toUpperCase();
    final visibles = [
      for (final c in _clientes)
        if (q.isEmpty || c.contains(q)) _tarjeta(c),
    ];
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 900,
          child: PanelSinColocar(
            tablero: Tablero(
              sucursalId: 'suc-stg',
              sucursalNombre: 'Santiago',
              almacen: const AlmacenOrigen(
                id: 'a1',
                nombre: 'Principal',
                lat: 20,
                lng: -75,
              ),
              columnas: const <ColumnaTablero>[],
              colocados: const <TarjetaColocada>[],
              avisos: const AvisosTablero(),
              sinColocar: MitadIzquierda(
                pedidos: visibles,
                total: visibles.length,
              ),
              desaparecidos: const <PedidoDesaparecido>[],
            ),
            alPulsarTarjeta: (_) {},
            alDevolver: (_) {},
          ),
        ),
      ),
    );
  }
}

void main() {
  late ProviderContainer contenedor;
  late List<String> busquedas;

  setUp(() {
    contenedor = ProviderContainer.test();
    busquedas = <String>[];
    contenedor.listen<FiltrosSinColocar>(
      filtrosTableroProvider,
      (antes, ahora) => busquedas.add(ahora.q ?? ''),
    );
  });

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: contenedor,
        child: _Anfitrion(busquedas: busquedas),
      ),
    );
    await tester.pump();
  }

  String enLaCaja() =>
      (find
                  .descendant(
                    of: find.byType(CajaDeBusqueda),
                    matching: find.byType(TextField),
                  )
                  .evaluate()
                  .single
                  .widget
              as TextField)
          .controller!
          .text;

  testWidgets('se escribe SIN Intro y la lista filtra sola', (tester) async {
    await pintar(tester);
    expect(find.text('DAYLIS'), findsOneWidget);
    expect(find.text('CHAPLIN'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'DAYLIS');
    await tester.pump();

    // Todavía no: el respiro es lo que evita repintar 274 tarjetas seis veces
    // por palabra.
    expect(busquedas, isEmpty);

    await tester.pump(CajaDeBusqueda.esperaPorDefecto);

    expect(
      busquedas,
      ['DAYLIS'],
      reason: 'sin esto había que pulsar Intro, y nadie lo pulsa',
    );
    expect(find.text('CHAPLIN'), findsNothing, reason: 'la lista filtró');
    expect(find.text('DAYLIS'), findsWidgets);
  });

  testWidgets('escribir rápido filtra UNA vez y con la palabra entera', (
    tester,
  ) async {
    await pintar(tester);

    for (final trozo in [
      'C',
      'CH',
      'CHA',
      'CHAP',
      'CHAPL',
      'CHAPLI',
      'CHAPLIN',
    ]) {
      await tester.enterText(find.byType(TextField).first, trozo);
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pump(CajaDeBusqueda.esperaPorDefecto);

    expect(
      busquedas,
      ['CHAPLIN'],
      reason: 'seis filtrados por palabra se notan en el teléfono de allá',
    );
    expect(
      enLaCaja(),
      'CHAPLIN',
      reason: 'se tecleó CHAPLIN y el campo se quedaba en CH',
    );
    expect(find.text('CHAPLIN'), findsWidgets);
    expect(find.text('MARIELA'), findsNothing);
  });

  testWidgets('Intro sigue funcionando, y no busca dos veces', (tester) async {
    await pintar(tester);

    await tester.enterText(find.byType(TextField).first, 'MARIELA');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(busquedas, ['MARIELA'], reason: 'quien ya da Intro no sale perdiendo');

    // Y el respiro que quedaba en el aire no dispara una segunda búsqueda
    // encima de la que ya salió.
    await tester.pump(CajaDeBusqueda.esperaPorDefecto);
    expect(busquedas, ['MARIELA']);

    // Ni al revés: buscar por el respiro y DESPUÉS pulsar Intro sobre lo
    // mismo tampoco vuelve a filtrar.
    await tester.enterText(find.byType(TextField).first, 'DAYLIS');
    await tester.pump(CajaDeBusqueda.esperaPorDefecto);
    expect(busquedas, ['MARIELA', 'DAYLIS']);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(CajaDeBusqueda.esperaPorDefecto);
    expect(
      busquedas,
      ['MARIELA', 'DAYLIS'],
      reason: 'sería una segunda consulta encima de la que ya está pintada',
    );
  });

  testWidgets('la caja arranca con lo que traiga el enlace `?q=`', (
    tester,
  ) async {
    contenedor
        .read(filtrosTableroProvider.notifier)
        .poner(const FiltrosSinColocar(q: 'CHAPLIN'));
    await pintar(tester);

    expect(enLaCaja(), 'CHAPLIN');
    expect(find.text('DAYLIS'), findsNothing);
  });
}
