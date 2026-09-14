import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  late BaseLocal base;

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  test('la base arranca en el esquema 1 con todas las tablas', () async {
    expect(base.schemaVersion, 1);
    final nombres = base.allTables.map((t) => t.actualTableName).toSet();
    expect(
      nombres,
      containsAll(<String>[
        'orders',
        'order_items',
        'routes',
        'customers',
        'products',
        'vehicles',
        'vehicle_types',
        'branches',
        'warehouses',
        'settings',
        'currencies',
        'apuntes',
        'equivalencias',
        'frescura',
        'preferencias',
      ]),
    );
  });

  test('los nombres de columna son los del servidor', () async {
    // Si esto cambia, la bajada deja de ser un `insertOnConflictUpdate` y hace
    // falta un traductor en medio.
    final columnas = base.orders.$columns.map((c) => c.name).toSet();
    expect(
      columnas,
      containsAll(<String>[
        'route_id',
        'ultima_ruta_id',
        'pedido_costo',
        'factura_estado',
        'end_lat',
        'order_date',
        'pedido_updated_at',
      ]),
    );
  });

  test('`quitados` borra de verdad', () async {
    for (final id in ['p1', 'p2', 'p3']) {
      await base
          .into(base.orders)
          .insert(
            OrdersCompanion.insert(id: id, customerName: 'C', address: 'D'),
          );
    }
    // Sin esto la lista local sólo crece: un pedido archivado se queda en el
    // aparato para siempre.
    await (base.delete(base.orders)..where((o) => o.id.isIn(['p1', 'p3']))).go();

    final quedan = await base.select(base.orders).get();
    expect(quedan.map((o) => o.id), ['p2']);
  });

  test(
    'cerrar sesion borra el dominio y NO toca la cola (regla 8, caso I7)',
    () async {
      final cola = ColaDeSalida(base);
      await base
          .into(base.orders)
          .insert(
            OrdersCompanion.insert(
              id: 'p1',
              customerName: 'Cliente',
              address: 'Calle con su número',
            ),
          );
      await base
          .into(base.customers)
          .insert(
            CustomersCompanion.insert(
              id: 'c1',
              name: 'Cliente',
              lat: 19.83,
              lng: -75.82,
            ),
          );
      await base
          .into(base.frescura)
          .insert(
            FrescuraCompanion.insert(
              coleccion: Colecciones.pedidos,
              hasta: const Value('2026-09-14T11:02:31.481Z'),
            ),
          );
      final clave = await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes',
        cuerpo: const {},
      );

      await base.borrarTodoLoDelDominio();

      // Los clientes con sus direcciones se van: el telefono puede cambiar de
      // manos.
      expect(await base.select(base.orders).get(), isEmpty);
      expect(await base.select(base.customers).get(), isEmpty);
      expect(await base.select(base.frescura).get(), isEmpty);
      // El trabajo sin subir, NO. Quien decide es la persona.
      expect(await cola.porClave(clave), isNotNull);
      expect(await base.cuantosPendientes(), 1);
    },
  );

  test('las fechas van y vuelven con su hora, no redondeadas', () async {
    // Se guardan como texto ISO-8601 a proposito: un entero de segundos pierde
    // los milisegundos y la zona.
    final momento = DateTime(2026, 9, 14, 16, 4, 22, 481);
    await base
        .into(base.apuntes)
        .insert(
          ApuntesCompanion.insert(
            clave: 'k1',
            hechoAt: momento,
            metodo: 'POST',
            ruta: '/x',
            cuerpo: '{}',
          ),
        );
    final fila = await base.select(base.apuntes).getSingle();
    expect(fila.hechoAt, momento);
  });
}
