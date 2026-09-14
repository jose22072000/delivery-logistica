import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/informes/datos/consultas_informes.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  late BaseLocal base;
  late ConsultasInformes informes;

  setUp(() async {
    base = baseDePrueba();
    informes = ConsultasInformes(base);

    await base
        .into(base.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: 'v1',
            name: 'Ford 600',
            plate: const Value('B-123'),
            branchId: const Value('stg'),
          ),
        );
    await base
        .into(base.vehicles)
        .insert(
          VehiclesCompanion.insert(
            id: 'v2',
            name: 'F-350',
            plate: const Value('B-999'),
            branchId: const Value('stg'),
          ),
        );
    await base
        .into(base.routes)
        .insert(
          RoutesCompanion.insert(
            id: 'r1',
            routeCode: const Value('STG-0912'),
            vehicleId: const Value('v1'),
            branchId: const Value('stg'),
          ),
        );
    await base
        .into(base.routes)
        .insert(
          RoutesCompanion.insert(
            id: 'r2',
            name: const Value('Vista Alegre'),
            vehicleId: const Value('v2'),
            branchId: const Value('stg'),
          ),
        );
    // Una ruta SIN vehiculo: sus pedidos suman en el resumen pero NO en
    // «Por Vehículo» (contrato §9).
    await base
        .into(base.routes)
        .insert(RoutesCompanion.insert(id: 'r3', branchId: const Value('stg')));
  });

  tearDown(() => base.close());

  Future<void> pedido(
    String id, {
    String? rutaId,
    double? precio,
    double? costo,
    double peso = 10,
    DateTime? creado,
    String? sucursal = 'stg',
  }) => base
      .into(base.orders)
      .insert(
        OrdersCompanion.insert(
          id: id,
          customerName: 'Cliente $id',
          address: 'Calle $id',
          routeId: Value(rutaId),
          price: Value(precio),
          pedidoCosto: Value(costo),
          weight: Value(peso),
          createdAt: Value(creado ?? DateTime(2026, 9, 10, 12)),
          branchId: Value(sucursal),
        ),
      );

  group('el ingreso de un pedido', () {
    test('es `price` cuando lo tiene', () async {
      await pedido('a', precio: 25, costo: 9);
      final i = await informes.mirar(const FiltroDeInforme()).first;
      expect(i.filas.single.importe, 25);
    });

    test('es `pedidoCosto` cuando no hay `price`', () async {
      // Es el numero que mas facil se equivoca de todo el pliego.
      await pedido('a', costo: 9);
      final i = await informes.mirar(const FiltroDeInforme()).first;
      expect(i.filas.single.importe, 9);
    });

    test('sin ninguno de los dos es 0, no nulo', () async {
      await pedido('a');
      final i = await informes.mirar(const FiltroDeInforme()).first;
      expect(i.filas.single.importe, 0);
    });
  });

  group('las cuatro cifras del resumen', () {
    test('total, ingresos, peso y promedio', () async {
      await pedido('a', rutaId: 'r1', precio: 30, peso: 100);
      await pedido('b', rutaId: 'r1', costo: 10, peso: 50);
      await pedido('c', rutaId: 'r2', precio: 20, peso: 30);

      final r = (await informes.mirar(const FiltroDeInforme()).first).resumen;
      expect(r.totalOrdenes, 3);
      expect(r.ingresos, 60);
      expect(r.peso, 180);
      expect(r.precioPromedio, 20);
    });

    test('sin ordenes el promedio es 0, no NaN', () {
      final r = ConsultasInformes.resumir(const <FilaDeInforme>[]);
      expect(r.precioPromedio, 0);
      expect(r.totalOrdenes, 0);
    });
  });

  group('por vehiculo', () {
    test('agrupa, suma y ordena de mas a menos ingreso', () async {
      await pedido('a', rutaId: 'r1', precio: 30, peso: 100);
      await pedido('b', rutaId: 'r1', precio: 10, peso: 50);
      await pedido('c', rutaId: 'r2', precio: 100, peso: 30);

      final v = (await informes.mirar(const FiltroDeInforme()).first).porVehiculo;
      expect(v.map((f) => f.nombre).toList(), ['F-350', 'Ford 600']);
      expect(v.last.ordenes, 2);
      expect(v.last.ingresos, 40);
      expect(v.last.peso, 150);
      expect(v.last.promedioPorOrden, 20);
      expect(v.last.placa, 'B-123');
    });

    test('los pedidos sin vehiculo NO hacen una fila propia', () async {
      await pedido('a', rutaId: 'r3', precio: 30); // ruta sin vehiculo
      await pedido('b', precio: 30); // sin ruta siquiera

      final i = await informes.mirar(const FiltroDeInforme()).first;
      expect(i.porVehiculo, isEmpty);
      // Pero SI suman en el resumen: el ingreso existio.
      expect(i.resumen.ingresos, 60);
    });
  });

  group('el rango de fechas', () {
    test('`hasta` incluye el DIA ENTERO', () async {
      await pedido('tarde', creado: DateTime(2026, 9, 14, 23, 30), precio: 5);
      await pedido('manana', creado: DateTime(2026, 9, 15, 0, 30), precio: 5);

      final i = await informes
          .mirar(FiltroDeInforme(hasta: DateTime(2026, 9, 14)))
          .first;
      // Sin el fin del dia, pedir «hasta el 14» dejaria fuera todo el 14.
      expect(i.filas.map((f) => f.id).toList(), ['tarde']);
    });

    test('`desde` corta por abajo', () async {
      await pedido('viejo', creado: DateTime(2026, 9, 1), precio: 5);
      await pedido('nuevo', creado: DateTime(2026, 9, 12), precio: 5);

      final i = await informes
          .mirar(FiltroDeInforme(desde: DateTime(2026, 9, 10)))
          .first;
      expect(i.filas.map((f) => f.id).toList(), ['nuevo']);
    });

    test('sin rango no se filtra por fecha', () async {
      await pedido('viejo', creado: DateTime(2020, 1, 1));
      await pedido('nuevo', creado: DateTime(2026, 9, 12));

      final i = await informes.mirar(const FiltroDeInforme()).first;
      expect(i.filas.length, 2);
    });

    test('finDelDia son las 23:59:59.999', () {
      final f = ConsultasInformes.finDelDia(DateTime(2026, 9, 14, 3, 0));
      expect(f, DateTime(2026, 9, 14, 23, 59, 59, 999));
      expect(ConsultasInformes.finDelDia(null), isNull);
    });
  });

  group('el filtro de vehiculo', () {
    test('filtra por el vehiculo DE LA RUTA', () async {
      await pedido('a', rutaId: 'r1', precio: 30);
      await pedido('b', rutaId: 'r2', precio: 30);

      final i = await informes
          .mirar(const FiltroDeInforme(vehiculoId: 'v2'))
          .first;
      expect(i.filas.map((f) => f.id).toList(), ['b']);
    });
  });

  test('el nombre de ruta es el codigo, y si no lo hay el nombre', () async {
    await pedido('a', rutaId: 'r1');
    await pedido('b', rutaId: 'r2');

    final i = await informes.mirar(const FiltroDeInforme()).first;
    final porId = {for (final f in i.filas) f.id: f.ruta};
    expect(porId['a'], 'STG-0912');
    expect(porId['b'], 'Vista Alegre');
  });

  test('el alcance por sucursal se respeta', () async {
    await pedido('a', precio: 10);
    await pedido('b', sucursal: 'hol', precio: 10);

    final i = await informes.mirar(const FiltroDeInforme(), sucursalId: 'hol').first;
    expect(i.filas.map((f) => f.id).toList(), ['b']);
  });
}
