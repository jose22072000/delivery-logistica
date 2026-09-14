import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/panel/datos/consultas_panel.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';

/// Las cifras del Panel contra una base sembrada con los casos limite.
///
/// El valor de este test no es que sume: es que **no sume lo que no debe**. Las
/// seis combinaciones de abajo son las que se cuelan si la definicion de
/// REPARTIBLE se escribe de memoria en vez de copiarla del contrato.
void main() {
  late BaseLocal base;
  late RelojFalso reloj;
  late ConsultasPanel panel;

  // El dia que vive la persona, con el reloj del aparato.
  final hoy = DateTime(2026, 9, 14, 10, 0);

  setUp(() async {
    base = baseDePrueba();
    reloj = RelojFalso(hoy);
    panel = ConsultasPanel(base, reloj: reloj.leer);

    await base
        .into(base.branches)
        .insert(
          BranchesCompanion.insert(
            id: 'stg',
            name: 'Santiago',
            lat: 20.02,
            lng: -75.82,
          ),
        );
    await base
        .into(base.branches)
        .insert(
          BranchesCompanion.insert(
            id: 'hol',
            name: 'Holguín',
            lat: 20.88,
            lng: -76.26,
          ),
        );
  });

  tearDown(() => base.close());

  Future<void> pedido(
    String id, {
    String? sucursal = 'stg',
    String? rutaId,
    double? endLat = 20.0,
    String? factura = 'igual',
    double peso = 10,
    double? costo,
    DateTime? entregadoEn,
    String? vehiculo,
  }) => base
      .into(base.orders)
      .insert(
        OrdersCompanion.insert(
          id: id,
          customerName: 'Cliente $id',
          address: 'Calle $id',
          branchId: Value(sucursal),
          routeId: Value(rutaId),
          endLat: Value(endLat),
          facturaEstado: Value(factura),
          weight: Value(peso),
          pedidoCosto: Value(costo),
          deliveredAt: Value(entregadoEn),
          vehicleId: Value(vehiculo),
        ),
      );

  Future<void> ruta(String id, String estado, {String? sucursal = 'stg'}) => base
      .into(base.routes)
      .insert(
        RoutesCompanion.insert(
          id: id,
          status: Value(estado),
          branchId: Value(sucursal),
        ),
      );

  Future<void> vehiculo(String id, {String? sucursal = 'stg'}) => base
      .into(base.vehicles)
      .insert(
        VehiclesCompanion.insert(
          id: id,
          name: 'Camión $id',
          branchId: Value(sucursal),
        ),
      );

  group('los seis casos limite de REPARTIBLE', () {
    setUp(() async {
      // 1. repartible de verdad
      await pedido('p1', peso: 100, costo: 5);
      // 2. factura `cambiado` TAMBIEN es repartible
      await pedido('p2', factura: 'cambiado', peso: 50, costo: 5);
      // 3. sin ruta pero SIN endLat: no se puede repartir lo que no se sabe donde va
      await pedido('p3', endLat: null, peso: 999, costo: 5);
      // 4. factura `sin_factura`: no cuadra, no sale
      await pedido('p4', factura: 'sin_factura', peso: 999, costo: 5);
      // 5. factura NULL: NULL no es «sin factura», es «no cotejado». Tampoco sale
      await pedido('p5', factura: null, peso: 999, costo: 5);
      // 6. ya tiene ruta: esta ocupado
      await pedido('p6', rutaId: 'r1', peso: 999, costo: 5, vehiculo: 'v1');
    });

    test('sinRuta cuenta 2, no 6', () async {
      final c = await panel.cifras().first;
      expect(c.sinRuta, 2);
      expect(c.totalPedidos, 6);
    });

    test('pesoPendiente suma SOLO lo repartible', () async {
      final c = await panel.cifras().first;
      expect(c.pesoPendiente, 150);
    });

    test('totalDomicilios suma TODO el alcance, repartible o no', () async {
      // Es lo cobrado en PEDIDO, no lo que queda por mover.
      final c = await panel.cifras().first;
      expect(c.totalDomicilios, 30);
    });
  });

  group('entregadosHoy, con el reloj del aparato', () {
    test('ayer a las 23:59 NO cuenta; hoy a las 00:01 SI', () async {
      await pedido('ayer', entregadoEn: DateTime(2026, 9, 13, 23, 59));
      await pedido('hoy', entregadoEn: DateTime(2026, 9, 14, 0, 1));
      await pedido('sinEntregar');

      final c = await panel.cifras().first;
      expect(c.entregadosHoy, 1);
    });

    test('al pasar la medianoche el contador se reinicia solo', () async {
      await pedido('hoy', entregadoEn: DateTime(2026, 9, 14, 0, 1));
      expect((await panel.cifras().first).entregadosHoy, 1);

      // El aparato amanece: lo de ayer deja de ser de hoy.
      reloj.ahora = DateTime(2026, 9, 15, 6, 0);
      expect((await panel.cifras().first).entregadosHoy, 0);
    });
  });

  group('rutas y vehiculos', () {
    test('rutasActivas: ni completadas ni canceladas', () async {
      await ruta('r1', 'planned');
      await ruta('r2', 'in_progress');
      await ruta('r3', 'completed');
      await ruta('r4', 'cancelled');

      final c = await panel.cifras().first;
      expect(c.rutasActivas, 2);
    });

    test('vehiculosEnRuta: los que llevan pedidos de una ruta viva', () async {
      await vehiculo('v1');
      await vehiculo('v2');
      await vehiculo('v3');
      await ruta('r1', 'in_progress');
      await ruta('r2', 'completed');
      // v1 con dos pedidos de la misma ruta: cuenta UNA vez.
      await pedido('a', rutaId: 'r1', vehiculo: 'v1');
      await pedido('b', rutaId: 'r1', vehiculo: 'v1');
      // v2 en una ruta ya cerrada: no esta en ruta.
      await pedido('c', rutaId: 'r2', vehiculo: 'v2');

      final c = await panel.cifras().first;
      expect(c.totalVehiculos, 3);
      expect(c.vehiculosEnRuta, 1);
    });
  });

  group('alcance por sucursal', () {
    setUp(() async {
      await pedido('s1', peso: 10);
      await pedido('s2', peso: 20);
      await pedido('h1', sucursal: 'hol', peso: 300);
    });

    test('sin sucursal elegida suma todas', () async {
      final c = await panel.cifras().first;
      expect(c.sinRuta, 3);
      expect(c.pesoPendiente, 330);
    });

    test('con una sucursal elegida suma solo la suya', () async {
      final c = await panel.cifras(sucursalId: 'hol').first;
      expect(c.sinRuta, 1);
      expect(c.pesoPendiente, 300);
    });
  });

  group('pendiente por sucursal', () {
    test('ordenado de mas a menos pedidos, con su nombre', () async {
      await pedido('h1', sucursal: 'hol', peso: 5);
      await pedido('h2', sucursal: 'hol', peso: 5);
      await pedido('h3', sucursal: 'hol', peso: 5);
      await pedido('s1', peso: 100);

      final filas = await panel.porSucursal().first;
      expect(filas.map((f) => f.sucursal).toList(), ['Holguín', 'Santiago']);
      expect(filas.first.pedidos, 3);
      expect(filas.first.pesoKg, 15);
    });

    test('un pedido sin sucursal se agrupa y SE DICE, no desaparece', () async {
      // Si se cayera de la agrupacion, la tarjeta no cuadraria con la cifra de
      // arriba y nadie sabria por que.
      await pedido('x', sucursal: null);

      final filas = await panel.porSucursal().first;
      expect(filas.single.sucursal, 'Sin sucursal');
      expect(filas.single.pedidos, 1);
    });

    test('solo lo repartible entra en el desglose', () async {
      await pedido('s1');
      await pedido('s2', rutaId: 'r9');

      final filas = await panel.porSucursal().first;
      expect(filas.single.pedidos, 1);
    });
  });
}
