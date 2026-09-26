// SUBIR EL ESQUEMA NO PUEDE LLEVARSE LA COLA SIN SUBIR.
//
// Esta base no es la de un servidor: vive en el teléfono de alguien y ahí dentro está **el
// trabajo del día que todavía no ha subido**. Una migración que recrea tablas, o que falla
// a medias y deja la base sin abrir, es lo único que esta aplicación no puede permitirse
// —lo dice `BaseLocal.schemaVersion` y por eso se toca tan poco—.
//
// El 26/09/2026 se subió a la 3 para añadir `orders.items_origen`, que dice si los
// renglones y el peso son los del pedido o los de la FACTURA. Es un `ALTER TABLE ADD
// COLUMN`, la operación más barata que hay, y aun así se prueba: lo barato es el cambio,
// no la consecuencia de equivocarse.
//
// LA FORMA: se abre una base **en la versión vieja**, se le mete un apunte en la cola y un
// pedido, se cierra, y se vuelve a abrir con la versión de ahora. Lo que se comprueba es
// que siguen ahí. Crear directamente en la 3 no probaría nada: ése es el camino del
// aparato nuevo, que no tiene nada que perder.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';

void main() {
  test('el trabajo sin subir sobrevive al salto de esquema', () async {
    // Un fichero de verdad, no memoria: lo que se prueba es que la base se
    // **reabre** con el esquema nuevo, y una base en memoria nace otra vez.
    final fichero = await _ficheroDePrueba();
    addTearDown(() async {
      if (fichero.existsSync()) await fichero.delete();
    });

    // --- El aparato de ayer, en la versión 2 -------------------------------
    //
    // Se monta con el esquema DE VERDAD y después se le quita la columna nueva y
    // se le baja el `user_version` a mano. Declarar a mano una copia del
    // esquema viejo era peor: lo que se probaría entonces es esa copia, no la
    // base que llevan los teléfonos.
    final ayer = BaseLocal.con(NativeDatabase(fichero));
    await ayer.into(ayer.apuntes).insert(
      ApuntesCompanion.insert(
        clave: '01J8-la-zona-de-ayer',
        hechoAt: DateTime(2026, 9, 26, 9),
        metodo: 'POST',
        ruta: '/api/board/columns',
        cuerpo: '{"nombre":"Vista"}',
      ),
    );
    await ayer.customStatement(
      'INSERT INTO orders (id, customer_name, address, weight, archivado) '
      "VALUES ('ped-1', 'Bodega La Esquina', 'Calle 4', 120.5, 0)",
    );
    await ayer.customStatement('ALTER TABLE orders DROP COLUMN items_origen');
    await ayer.customStatement('PRAGMA user_version = 2');
    await ayer.close();

    // --- Y se abre con el de hoy -------------------------------------------
    final nueva = BaseLocal.con(NativeDatabase(fichero));
    addTearDown(nueva.close);

    final cola = await nueva.select(nueva.apuntes).get();
    expect(
      cola.map((a) => a.clave),
      ['01J8-la-zona-de-ayer'],
      reason:
          'la cola sin subir es el trabajo del día de una persona: una '
          'migración que se la lleve no se nota hasta que alguien la reclama',
    );

    final pedidos = await nueva.select(nueva.orders).get();
    expect(pedidos.single.customerName, 'Bodega La Esquina');
    expect(pedidos.single.weight, 120.5);

    // LA COLUMNA EXISTE, preguntándoselo a SQLite.
    //
    // Mirar sólo que el valor es nulo NO vale, y esto se descubrió mutando: con
    // el `addColumn` quitado la prueba seguía verde, porque un nulo y una
    // columna que no está se leen igual desde Dart. La que falla es ésta.
    final columnas = await nueva
        .customSelect('PRAGMA table_info(orders)')
        .get();
    expect(
      columnas.map((f) => f.read<String>('name')),
      contains('items_origen'),
      reason: 'la migración no añadió la columna y nadie se enteró',
    );

    // Y llega VACÍA, que es «no se sabe».
    expect(
      pedidos.single.itemsOrigen,
      isNull,
      reason:
          'poner «pedido» por defecto afirmaría sobre todo lo que el aparato '
          'ya tiene algo que nadie ha comprobado',
    );
  });
}

Future<File> _ficheroDePrueba() async {
  final dir = await Directory.systemTemp.createTemp('reparto-migracion');
  return File('${dir.path}/base.sqlite');
}
