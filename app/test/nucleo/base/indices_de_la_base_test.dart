// Los índices de la copia (`BaseLocal.indicesDeLaBase`) y las consultas que los
// usan tienen que tener la MISMA forma. Un índice con las columnas en otro orden
// no falla: se crea, ocupa sitio y el planificador lo ignora, y el buscador de
// «Sin colocar» vuelve a tardar 44 segundos sin que nada se ponga rojo. Por eso
// se pregunta a SQLite qué plan elige, no si el índice existe.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  late BaseLocal base;

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<String> plan(String sql) async {
    final filas = await base.customSelect('EXPLAIN QUERY PLAN $sql').get();
    return filas.map((f) => f.read<String>('detail')).join('\n');
  }

  test('se crean al abrir, también en una base que ya existía', () async {
    final filas = await base
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    final nombres = filas.map((f) => f.read<String>('name')).toSet();
    for (final i in [
      'order_items_order_idx',
      'orders_sucursal_fecha_idx',
      'orders_ultima_ruta_idx',
      'apuntes_estado_idx',
    ]) {
      expect(
        nombres,
        contains(i),
        reason:
            '$i no está en la base: BaseLocal.beforeOpen ya no crea los '
            'índices de indicesDeLaBase',
      );
    }
  });

  test(
    'el buscador de «Sin colocar» mira los renglones por el índice',
    () async {
      final p = await plan(
        "SELECT o.id FROM orders o WHERE EXISTS (SELECT 1 FROM order_items oi "
        "WHERE oi.order_id = o.id AND oi.description LIKE '%malta%')",
      );
      expect(
        p,
        contains('order_items_order_idx'),
        reason:
            'sin el índice de order_items(order_id), cada pedido recorre TODOS '
            'los renglones: 44 s con 20.000 pedidos. Plan:\n$p',
      );
    },
  );

  test('la página de Pedidos sale del índice, ya ordenada', () async {
    final p = await plan(
      "SELECT * FROM orders WHERE branch_id = 'x' "
      'ORDER BY order_date DESC, created_at DESC LIMIT 50 OFFSET 5000',
    );
    expect(p, contains('orders_sucursal_fecha_idx'), reason: 'Plan:\n$p');
    expect(
      p,
      isNot(contains('TEMP B-TREE')),
      reason:
          'el índice ya no tiene el orden de RepositorioPedidos.pagina y '
          'SQLite ordena a mano toda la sucursal por cada página. Plan:\n$p',
    );
  });

  test('las paradas de una ruta salen del índice, ya en su orden', () async {
    final p = await plan(
      "SELECT * FROM orders WHERE ultima_ruta_id = 'r' ORDER BY stop_order",
    );
    expect(p, contains('orders_ultima_ruta_idx'), reason: 'Plan:\n$p');
  });
}
