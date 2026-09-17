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

      final v =
          (await informes.mirar(const FiltroDeInforme()).first).porVehiculo;
      expect(v.map((f) => f.nombre).toList(), ['F-350', 'Ford 600']);
      expect(v.last.ordenes, 2);
      expect(v.last.ingresos, 40);
      expect(v.last.peso, 150);
      expect(v.last.promedioPorOrden, 20);
      expect(v.last.placa, 'B-123');
    });

    // LA GUARDA: la clave del grupo es el ID, nunca el nombre.
    //
    // Se agrupaba por nombre, y entonces dos camiones que se llaman igual —el
    // de siempre y su sustituto, o uno por sucursal— se fundian en UNA fila con
    // los ingresos de los dos sumados. Este error ya se cazo una vez en este
    // proyecto. Si vuelve, esta prueba lo dice con esas palabras.
    test('dos camiones que se llaman igual NO se funden en una fila', () async {
      // `v3` se llama exactamente igual que `v1`. Son dos camiones distintos.
      await base
          .into(base.vehicles)
          .insert(
            VehiclesCompanion.insert(
              id: 'v3',
              name: 'Ford 600',
              plate: const Value('B-777'),
              branchId: const Value('stg'),
            ),
          );
      await base
          .into(base.routes)
          .insert(
            RoutesCompanion.insert(
              id: 'r4',
              routeCode: const Value('STG-0913'),
              vehicleId: const Value('v3'),
              branchId: const Value('stg'),
            ),
          );

      await pedido('a', rutaId: 'r1', precio: 30, peso: 100); // v1
      await pedido('b', rutaId: 'r4', precio: 70, peso: 20); // v3

      final v =
          (await informes.mirar(const FiltroDeInforme()).first).porVehiculo;

      expect(
        v.length,
        2,
        reason:
            'Los dos «Ford 600» se fundieron en una sola fila: se esta '
            'agrupando por NOMBRE y no por el id del vehiculo. Sus ingresos '
            'quedan sumados en un camion que no existe.',
      );
      expect(v.map((f) => f.id).toSet(), {'v1', 'v3'});
      // Y cada uno con lo suyo, no con la suma de los dos.
      expect({for (final f in v) f.id: f.ingresos}, {'v1': 30.0, 'v3': 70.0});
      expect(
        {for (final f in v) f.id: f.placa},
        {'v1': 'B-123', 'v3': 'B-777'},
      );
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
    test('`hasta` incluye el DIA ENTERO, contado en UTC', () async {
      // Las 23:00 y las 02:00 UTC: el mismo dia 14 para uno y ya el 15 para el
      // otro. Escritos en UTC a proposito, para que la prueba diga lo mismo
      // este el portatil en Cuba o donde sea.
      await pedido('tarde', creado: DateTime.utc(2026, 9, 14, 23), precio: 5);
      await pedido('manana', creado: DateTime.utc(2026, 9, 15, 2), precio: 5);

      final i = await informes
          .mirar(FiltroDeInforme(hasta: DateTime(2026, 9, 14)))
          .first;
      // Sin el fin del dia, pedir «hasta el 14» dejaria fuera todo el 14.
      // Cortando en hora local entraria ademas el de las 02:00 UTC del 15, que
      // aqui son las 22:00 del 14 — y ese es justo el pedido que el informe
      // del servidor NO cuenta.
      expect(i.filas.map((f) => f.id).toList(), ['tarde']);
    });

    test('`desde` corta por abajo, tambien en UTC', () async {
      await pedido('viejo', creado: DateTime.utc(2026, 9, 9, 22), precio: 5);
      await pedido('nuevo', creado: DateTime.utc(2026, 9, 10, 1), precio: 5);

      final i = await informes
          .mirar(FiltroDeInforme(desde: DateTime(2026, 9, 10)))
          .first;
      // Las 22:00 UTC del 9 son todavia el dia 9, aunque aqui sean las 18:00
      // de ese mismo dia y aunque en un huso al este ya fuera el 10.
      expect(i.filas.map((f) => f.id).toList(), ['nuevo']);
    });

    test('sin rango no se filtra por fecha', () async {
      await pedido('viejo', creado: DateTime(2020, 1, 1));
      await pedido('nuevo', creado: DateTime(2026, 9, 12));

      final i = await informes.mirar(const FiltroDeInforme()).first;
      expect(i.filas.length, 2);
    });

    // LA GUARDA, sin base de por medio: los dos limites son instantes UTC.
    //
    // Es lo que iguala el corte con el de la de Next (`new Date('2026-09-14')`
    // y `new Date(to + 'T23:59:59.999Z')`). En hora local, con Cuba a −4, se
    // colaban o se perdian hasta cinco horas de pedidos en cada extremo, y el
    // informe del aparato y el del servidor daban dos totales distintos para el
    // mismo dia.
    test('los dos limites del rango son UTC, no la hora de aqui', () {
      final desde = ConsultasInformes.comienzoDelDia(DateTime(2026, 9, 14, 3));
      expect(desde!.isUtc, isTrue);
      expect(desde, DateTime.utc(2026, 9, 14));

      final hasta = ConsultasInformes.finDelDia(DateTime(2026, 9, 14, 3));
      expect(hasta!.isUtc, isTrue);
      expect(hasta, DateTime.utc(2026, 9, 14, 23, 59, 59, 999));

      expect(ConsultasInformes.comienzoDelDia(null), isNull);
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

    final i = await informes
        .mirar(const FiltroDeInforme(), sucursalId: 'hol')
        .first;
    expect(i.filas.map((f) => f.id).toList(), ['b']);
  });
}
