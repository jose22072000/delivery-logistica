import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/sincro/recuento.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';

/// LA GUARDA DE «QUE ME FALTA», suelta y sin red.
///
/// Es la pieza que decide si la pantalla puede ponerse verde. Se prueba aqui
/// sola, sin ciclo ni servidor, porque la regla que defiende no es de red: es
/// «no digas que lo tienes si no lo tienes».
void main() {
  late BaseLocal base;
  late RelojFalso reloj;
  late RegistroDeFrescura frescura;
  late Recontador recontador;

  setUp(() {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime(2026, 9, 15, 8, 14));
    frescura = RegistroDeFrescura(base, reloj: reloj.leer);
    recontador = Recontador(base, frescura);
  });

  tearDown(() => base.close());

  Future<void> marcar(List<String> colecciones) async {
    for (final c in colecciones) {
      await frescura.marcar(c, hasta: null, bajadaAt: reloj.ahora);
    }
  }

  Future<void> sembrarProducto(String id) => base
      .into(base.products)
      .insert(ProductsCompanion.insert(id: id, name: 'Producto $id'));

  Future<void> sembrarCliente(String id) => base
      .into(base.customers)
      .insert(
        CustomersCompanion.insert(
          id: id,
          name: 'Cliente $id',
          lat: 20,
          lng: -75,
        ),
      );

  Future<void> sembrarSucursal(String id) => base
      .into(base.branches)
      .insert(
        BranchesCompanion.insert(
          id: id,
          name: 'Sucursal $id',
          lat: 20,
          lng: -75,
        ),
      );

  Future<void> sembrarAlmacen(String id) => base
      .into(base.warehouses)
      .insert(
        WarehousesCompanion.insert(
          id: id,
          sucursalCodigo: 'STG',
          nombre: 'Almacén $id',
        ),
      );

  /// Un aparato que bajo el dia entero y de verdad.
  Future<void> elDiaEntero() async {
    await sembrarProducto('p-1');
    await sembrarCliente('c-1');
    await sembrarSucursal('s-1');
    await sembrarAlmacen('a-1');
    await marcar(Colecciones.todas);
  }

  group('un aparato recien instalado', () {
    test('no tiene NADA, y las nueve se dicen sin bajar', () async {
      final r = await recontador.ahora();

      expect(r.laMasVieja, isNull, reason: 'sin bajar no hay hora que ensenar');
      final faltan = Faltas.de(r);
      expect(faltan, hasLength(Colecciones.todas.length));
      expect(
        faltan.every((f) => f.porQue == PorQueFalta.nuncaSeBajo),
        isTrue,
        reason:
            'una coleccion sin bajar no es una coleccion vacia: un cero '
            'ahi se lee como un dato y esto es un fallo',
      );
    });
  });

  group('con el dia entero bajado', () {
    test('no falta nada y la hora es la de la bajada', () async {
      await elDiaEntero();
      final r = await recontador.ahora();

      expect(Faltas.de(r), isEmpty);
      expect(r.laMasVieja, DateTime(2026, 9, 15, 8, 14));
      expect(r.cuantas(Colecciones.productos), 1);
    });

    test(
      'los pedidos, las rutas y los vehiculos a CERO no son una falta',
      () async {
        // Una sucursal puede amanecer sin nada que repartir y sin ninguna ruta
        // armada. Avisar aqui seria gritar todas las mannanas por algo que no
        // tiene arreglo, y el dia que grite de verdad ya no lo leeria nadie.
        await elDiaEntero();
        final r = await recontador.ahora();

        expect(r.cuantas(Colecciones.pedidos), 0);
        expect(r.cuantas(Colecciones.rutas), 0);
        expect(r.cuantas(Colecciones.vehiculos), 0);
        expect(Faltas.de(r), isEmpty);
      },
    );
  });

  group('lo que este fichero existe para cazar', () {
    test('el catalogo bajo VACIO: falta, y se dice que se rompe sin el', () async {
      // El caso silencioso: el servidor contesta 200, `cambios` viene sin
      // `products`, las nueve quedan marcadas y el catalogo esta vacio. No hay
      // ningun fallo que mirar — lo unico que lo delata es contar las filas.
      await sembrarCliente('c-1');
      await sembrarSucursal('s-1');
      await sembrarAlmacen('a-1');
      await marcar(Colecciones.todas);

      final faltan = Faltas.de(await recontador.ahora());

      expect(faltan, hasLength(1));
      expect(faltan.single.coleccion, Colecciones.productos);
      expect(faltan.single.porQue, PorQueFalta.vacia);
      expect(faltan.single.queEs, 'el catálogo de productos');
      expect(
        faltan.single.consecuencia,
        contains('los pesos'),
        reason: 'el aviso tiene que decir QUE se rompe, no solo que falta',
      );
    });

    test('la bajada se corto antes de los almacenes: falta esa y solo esa', () async {
      // El ciclo que se va a mitad: los pedidos entraron y quedaron marcados, y
      // `GET /almacenes` —que es la ultima peticion y va fuera de la
      // transaccion— no llego. Es «bajaron los pedidos pero no los almacenes».
      await sembrarProducto('p-1');
      await sembrarCliente('c-1');
      await sembrarSucursal('s-1');
      await marcar([
        for (final c in Colecciones.todas)
          if (c != Colecciones.almacenes) c,
      ]);

      final r = await recontador.ahora();
      final faltan = Faltas.de(r);

      expect(faltan, hasLength(1));
      expect(faltan.single.coleccion, Colecciones.almacenes);
      expect(faltan.single.porQue, PorQueFalta.nuncaSeBajo);
      expect(
        r.laMasVieja,
        isNull,
        reason:
            'con una sin bajar no se puede decir «datos de las 8:14»: seria '
            'la hora de una parte leida como la del todo',
      );
    });

    test('faltan DOS: se nombran las dos, no «hubo un error»', () async {
      await sembrarCliente('c-1');
      await marcar(Colecciones.todas);

      final faltan = Faltas.de(await recontador.ahora());
      final cuales = faltan.map((f) => f.coleccion).toList();

      expect(
        cuales,
        containsAll([Colecciones.productos, Colecciones.almacenes]),
      );
      expect(cuales, contains(Colecciones.sucursales));
      expect(cuales, isNot(contains(Colecciones.clientes)));
    });
  });

  group('las cuentas son de la BASE', () {
    test('cuenta filas de verdad, no lo que nadie dijo que mando', () async {
      await sembrarProducto('p-1');
      await sembrarProducto('p-2');
      // Un `insertOnConflictUpdate` del mismo id no suma una fila: el servidor
      // pudo mandar tres y quedar dos.
      await base
          .into(base.products)
          .insertOnConflictUpdate(
            ProductsCompanion.insert(
              id: 'p-2',
              name: 'Producto p-2',
              weight: const Value(3),
            ),
          );
      await marcar(Colecciones.todas);

      expect((await recontador.ahora()).cuantas(Colecciones.productos), 2);
    });
  });
}
