import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';

import '../../apoyo/base_de_prueba.dart';

/// LA ACTUALIZACIÓN NO PUEDE LLEVARSE EL TRABAJO QUE YA ESTÁ EN LOS TELÉFONOS.
///
/// `nacio_aqui` entra con `ALTER TABLE … DEFAULT 0` en las bases que ya existen, y ese 0 es
/// lo prudente para casi todo: la inmensa mayoría de esas filas vino del servidor. Pero hay
/// un subconjunto que **con seguridad no está arriba**, y sin rescatarlo la versión que
/// arregla el fallo se lleva por delante justo el caso que lo originó — el teléfono de Jose,
/// con su zona «Vista» y sus cinco pedidos, en cuanto pulse «actualizar».
///
/// Marcar de más no hace daño: lo peor que pasa es que el tablero pida subir antes de
/// refrescar. Marcar de menos es trabajo perdido.
void main() {
  late BaseLocal base;

  /// El esquema ANTERIOR, sin `nacio_aqui`. Es lo que hay hoy en los teléfonos.
  Future<void> esquemaViejo() async {
    await base.customStatement('''
CREATE TABLE board_columns (
  id TEXT NOT NULL PRIMARY KEY, branch_id TEXT NOT NULL, nombre TEXT NOT NULL,
  posicion INTEGER NOT NULL, vehicle_id TEXT, creado_por TEXT,
  created_at TEXT, updated_at TEXT
)''');
    await base.customStatement('''
CREATE TABLE board_placements (
  order_id TEXT NOT NULL PRIMARY KEY REFERENCES orders(id) ON DELETE CASCADE,
  column_id TEXT NOT NULL REFERENCES board_columns(id) ON DELETE RESTRICT,
  posicion INTEGER NOT NULL, colocado_por TEXT, colocado_at TEXT, updated_at TEXT
)''');
  }

  Future<void> pedido(String id) => base
      .into(base.orders)
      .insertOnConflictUpdate(
        OrdersCompanion.insert(
          id: id,
          customerName: 'Cliente',
          address: 'Calle 1',
        ),
      );

  Future<int> marcaDe(String tabla, String columna, String valor) async {
    final f = await base
        .customSelect(
          'SELECT nacio_aqui AS n FROM $tabla WHERE $columna = ?1',
          variables: [Variable<String>(valor)],
        )
        .getSingle();
    return f.read<int>('n');
  }

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  test(
    'una zona «local-…» del esquema viejo se rescata: NO está arriba',
    () async {
      await esquemaViejo();
      await base.customStatement(
        "INSERT INTO board_columns (id, branch_id, nombre, posicion) "
        "VALUES ('local-vista', 'hab-1', 'Vista', 1)",
      );
      await pedido('p1');
      await base.customStatement(
        "INSERT INTO board_placements (order_id, column_id, posicion) "
        "VALUES ('p1', 'local-vista', 0)",
      );

      // La actualización de la aplicación.
      await EsquemaTablero.asegurar(base);

      expect(
        await marcaDe('board_columns', 'id', 'local-vista'),
        1,
        reason:
            'un id «local-…» significa que el servidor nunca devolvió el suyo',
      );
      expect(
        await marcaDe('board_placements', 'order_id', 'p1'),
        1,
        reason: 'su zona no existe arriba, así que la tarjeta tampoco',
      );
    },
  );

  test('una zona que SÍ vino del servidor se queda a 0', () async {
    // Marcar de más pide subir de balde; marcarlo todo bloquearía el tablero de
    // todo el mundo para siempre.
    await esquemaViejo();
    await base.customStatement(
      "INSERT INTO board_columns (id, branch_id, nombre, posicion) "
      "VALUES ('c-de-verdad', 'hab-1', 'Centro', 1)",
    );

    await EsquemaTablero.asegurar(base);

    expect(await marcaDe('board_columns', 'id', 'c-de-verdad'), 0);
  });

  test('una tarjeta con apunte en la cola se rescata, aunque su zona esté arriba', () async {
    // Se arrastró sin señal sobre una zona que sí existe arriba. En el esquema
    // viejo no había ninguna señal en la fila: lo único que lo dice es su apunte.
    await esquemaViejo();
    await base.customStatement(
      "INSERT INTO board_columns (id, branch_id, nombre, posicion) "
      "VALUES ('c-de-verdad', 'hab-1', 'Centro', 1)",
    );
    await pedido('p9');
    await base.customStatement(
      "INSERT INTO board_placements (order_id, column_id, posicion) "
      "VALUES ('p9', 'c-de-verdad', 0)",
    );
    await ColaDeSalida(base).encolar(
      metodo: 'PUT',
      ruta: '/board/placements/p9',
      cuerpo: const {'columnaId': 'c-de-verdad', 'posicion': 0},
    );

    await EsquemaTablero.asegurar(base);

    expect(await marcaDe('board_placements', 'order_id', 'p9'), 1);
  });

  test('asegurar dos veces no revienta', () async {
    // El `Expando` que evita repetirlo es por `BaseLocal`, no por fichero: dos
    // instancias sobre el mismo sqlite entran las dos, y un `ALTER TABLE`
    // repetido da «duplicate column name».
    await EsquemaTablero.asegurar(base);
    await EsquemaTablero.asegurar(baseDePrueba());
    await base.customStatement('ALTER TABLE board_columns ADD COLUMN zz TEXT');
    // Y sobre la misma base, forzando el camino del ALTER otra vez.
    await expectLater(EsquemaTablero.asegurar(base), completes);
  });
}
