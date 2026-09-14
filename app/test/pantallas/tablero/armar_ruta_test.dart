import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo.dart';

/// §5: de una columna sale una ruta, tambien sin conexion.
void main() {
  late BaseLocal base;
  late ConsultasTablero consultas;
  late ColaDeSalida cola;
  late RepositorioTablero repo;
  late AlmacenOrigen origen;
  late String centro;

  setUp(() async {
    base = baseDePrueba();
    consultas = ConsultasTablero(base);
    cola = ColaDeSalida(base);
    repo = RepositorioTablero(base, cola);
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarCamion(base, id: 'v1', capacidad: 2000);
    origen = await consultas.almacenDe(sucursalStg);
    centro = await repo.crearColumna(
      sucursalId: sucursalStg,
      nombre: 'Centro',
      vehiculoId: 'v1',
    );
  });

  tearDown(() => base.close());

  test('respeta el orden que puso el logístico y no llama a nadie', () async {
    for (var i = 1; i <= 3; i++) {
      await sembrarPedido(base, id: 'p$i', peso: 100.0 * i);
      await repo.colocar(pedidoId: 'p$i', columnaId: centro);
    }
    // El de en medio pasa a ser el primero: él conoce las calles.
    await repo.colocar(pedidoId: 'p3', columnaId: centro, posicion: 1);

    final rutaId = await repo.armarRuta(
      columnaId: centro,
      origen: origen,
      sucursalId: sucursalStg,
    );

    expect(rutaId, startsWith('local-'));
    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals(rutaId))).getSingle();
    expect(ruta.name, 'Centro');
    expect(ruta.vehicleId, 'v1');
    expect(ruta.totalWeight, 600);
    expect(ruta.originLat, origen.lat);
    // El orden del logistico gana al greedy por defecto: la ruta nace sin
    // optimizar, y eso tiene que quedar dicho.
    expect(ruta.optimized, isFalse);

    final pedidos = await base.select(base.orders).get();
    final porId = {for (final p in pedidos) p.id: p};
    expect(porId['p3']!.stopOrder, 1);
    expect(porId['p1']!.stopOrder, 2);
    expect(porId['p2']!.stopOrder, 3);
    expect(porId['p3']!.routeId, rutaId);
    // `ultimaRutaId` no se libera nunca: un devuelto suelta `routeId` pero
    // conserva esta.
    expect(porId['p3']!.ultimaRutaId, rutaId);

    // La columna se queda; lo que se vacía es lo que llevaba dentro hoy.
    expect((await consultas.columnas(sucursalStg)).single.pedidos, 0);
    expect(await consultas.colocados(sucursalStg, origen), isEmpty);

    final ultimo = (await cola.lote()).last;
    expect(ultimo.metodo, 'POST');
    expect(ultimo.ruta, '/api/board/columns/$centro/route');
    expect(ultimo.provisional, rutaId);
    expect(jsonDecode(ultimo.cuerpo), {
      'vehiculoId': 'v1',
      'optimizar': false,
    });
  });

  test('los que no se pueden repartir se quedan puestos y marcados', () async {
    await sembrarPedido(base, id: 'bueno');
    await sembrarPedido(
      base,
      id: 'malo',
      facturaEstado: EstadoFactura.sinFactura,
    );
    await repo.colocar(pedidoId: 'bueno', columnaId: centro);
    await repo.colocar(pedidoId: 'malo', columnaId: centro);

    await repo.armarRuta(
      columnaId: centro,
      origen: origen,
      sucursalId: sucursalStg,
    );

    final quedan = await consultas.colocados(sucursalStg, origen);
    expect(quedan.single.pedido.pedidoId, 'malo');
    expect(quedan.single.pedido.marcas, [MarcaTarjeta.sinFactura]);
  });

  test('sin nada repartible no se crea una ruta vacía, y se dice por qué',
      () async {
    await sembrarPedido(
      base,
      id: 'sin-cotejar',
      cliente: 'Bodega La Palma',
      operacion: 'SC06-1257',
      facturaEstado: null,
    );
    await sembrarPedido(base, id: 'archivado', archivado: true);
    await repo.colocar(pedidoId: 'sin-cotejar', columnaId: centro);
    await repo.colocar(pedidoId: 'archivado', columnaId: centro);

    await expectLater(
      repo.armarRuta(
        columnaId: centro,
        origen: origen,
        sucursalId: sucursalStg,
      ),
      throwsA(
        isA<RechazoDelTablero>()
            .having(
              (e) => e.mensaje,
              'mensaje',
              'La columna no tiene ningún pedido que se pueda repartir hoy',
            )
            // Nombrados: una columna que produce una ruta mas corta sin
            // explicacion es la manera mas rapida de que el logistico deje de
            // fiarse.
            .having(
              (e) => e.detalles.join(' | '),
              'detalles',
              contains('SC06-1257 · Bodega La Palma: Sin cotejar'),
            ),
      ),
    );

    expect(await base.select(base.routes).get(), isEmpty);
    expect((await consultas.colocados(sucursalStg, origen)).length, 2);
  });
}
