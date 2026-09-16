import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/sincro/huerfanos.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';

import '../../apoyo/base_de_prueba.dart';

/// LO QUE EL APARATO HIZO SIN CONEXIÓN Y NO IBA A SUBIR SOLO.
///
/// El sincronizador reenviaba una COLA y nunca comparaba los dos lados. En cuanto un
/// apunte desaparecía —descartado a mano, o perdido— el dato local se quedaba huérfano:
/// existía en el teléfono, no existía arriba, y nada lo volvía a intentar jamás.
///
/// Visto el 16/09/2026 con tres pantallas diciendo cosas distintas del mismo aparato: el
/// Tablero enseñaba la zona «Vista» con sus cinco pedidos y su marca «sin subir»; entregar
/// el día decía «Todo entregado»; el Panel decía «Todo al día». Y el servidor, que era el
/// único que tenía razón: «Galaxy A16 de Jose — nunca ha subido».
///
/// Palabras de Jose: «el sync es el encargado de eso, para controlar los desfases de cada
/// lado… si no, siempre van a estar desfasadas la online, que es la de verdad, contra la
/// offline, que se fue sin conexión con unos datos que después tiene que incorporar».
void main() {
  late BaseLocal base;
  late Huerfanos huerfanos;
  late ColaDeSalida cola;

  setUp(() async {
    base = baseDePrueba();
    // Las tablas del tablero no son de Drift: las crea el propio Tablero la
    // primera vez que se abre. Aqui se piden a mano porque esta prueba las mira
    // sin pasar por esa pantalla.
    await EsquemaTablero.asegurar(base);
    huerfanos = Huerfanos(base);
    cola = ColaDeSalida(base);
  });

  tearDown(() => base.close());

  Future<void> zonaLocal(
    String id, {
    String sucursal = 'hab-1',
    String nombre = 'Vista',
    List<String> pedidos = const [],
  }) async {
    // `nacio_aqui = 1`: la creó este aparato. Es lo que dice «esto no está
    // arriba», y NO el prefijo del id — desde que el aparato pone el id
    // definitivo (UUIDv7), `local-…` no distingue nada.
    await base.customStatement(
      'INSERT INTO board_columns (id, branch_id, nombre, posicion, created_at, '
      'updated_at, nacio_aqui) '
      "VALUES (?1, ?2, ?3, 1, '2026-09-16T10:00:00.000', "
      "'2026-09-16T10:00:00.000', 1)",
      [id, sucursal, nombre],
    );
    for (var i = 0; i < pedidos.length; i++) {
      // El pedido tiene que existir: `board_placements` apunta a `orders`.
      await base
          .into(base.orders)
          .insertOnConflictUpdate(
            OrdersCompanion.insert(
              id: pedidos[i],
              customerName: 'Cliente ${pedidos[i]}',
              address: 'Calle 1',
            ),
          );
      await base.customStatement(
        'INSERT INTO board_placements (order_id, column_id, posicion, colocado_at, '
        'updated_at, nacio_aqui) '
        "VALUES (?1, ?2, ?3, '2026-09-16T10:00:00.000', "
        "'2026-09-16T10:00:00.000', 1)",
        [pedidos[i], id, i],
      );
    }
  }

  test('una zona local SIN apunte que la suba es trabajo huérfano', () async {
    await zonaLocal('local-abc', pedidos: ['p1', 'p2']);

    final visto = await huerfanos.mirar();
    expect(visto.hayAlguno, isTrue);
    expect(visto.total, 1);
    expect(
      visto.texto,
      '1 zona del tablero',
      reason: 'el aviso tiene que nombrar QUÉ hay que ir a mirar',
    );
  });

  test('con su apunte pendiente NO está huérfana: va a subir sola', () async {
    await zonaLocal('local-abc');
    await cola.encolar(
      metodo: 'POST',
      ruta: '/board/columns?branchId=hab-1',
      cuerpo: const {'nombre': 'Vista'},
      provisional: 'local-abc',
    );

    expect((await huerfanos.mirar()).hayAlguno, isFalse);
  });

  test('con su apunte RECHAZADO tampoco: está esperando a una persona', () async {
    // Un rechazo se queda a la vista con su motivo hasta que alguien decida, y esa persona
    // todavía puede reintentarlo. Contarlo como huérfano sería volver a encolarlo por
    // detrás cada cinco minutos: un bucle contra un servidor que ya dijo que no.
    await zonaLocal('local-abc');
    await cola.encolar(
      metodo: 'POST',
      ruta: '/board/columns?branchId=hab-1',
      cuerpo: const {'nombre': 'Vista'},
      provisional: 'local-abc',
    );
    // Marcado rechazado como lo deja la subida al recibir un «no» del servidor.
    await base.customStatement(
      "UPDATE apuntes SET estado = 'rechazado', motivo = ?1 "
      'WHERE provisional = ?2',
      ['el servidor dijo que no', 'local-abc'],
    );

    expect(
      (await huerfanos.mirar()).hayAlguno,
      isFalse,
      reason: 'reintentarlo solo sería un bucle, no una defensa',
    );
  });

  test('una zona YA SUBIDA no es huérfana: la bajada le quitó la marca', () async {
    await zonaLocal('col-de-verdad-1');
    await base.customStatement('UPDATE board_columns SET nacio_aqui = 0');
    expect((await huerfanos.mirar()).hayAlguno, isFalse);
  });

  test('una zona con UUIDv7 creada aquí SÍ es huérfana', () async {
    // El caso que el prefijo `local-…` dejaba pasar, y que dejaba el tablero en
    // un callejón sin salida: protegida para siempre —la bajada se negaba a
    // borrarla, bien— y sin nada que la subiera, porque esto no la veía. Lo
    // único que limpia la marca es una bajada, y la bajada estaba bloqueada.
    await zonaLocal('018f2c7e-0000-7000-8000-000000000001', pedidos: ['p1']);

    expect((await huerfanos.mirar()).hayAlguno, isTrue);
    expect(
      await huerfanos.volverAEncolar(cola),
      2,
      reason: 'el ciclo la reencola, sube, la bajada la limpia y el atasco se '
          'deshace solo',
    );
  });

  test('en un aparato sin Tablero no revienta: contesta que no hay nada', () async {
    // Las tablas del Tablero las crea la propia pantalla la primera vez que se abre, así
    // que en un aparato recién estrenado NO EXISTEN. Sin esta guarda, el ciclo entero
    // moría con «no such table: board_columns» en cuanto alguien entraba sin pasar por
    // ahí: ni subía su cola, ni bajaba el día. Comprobar la diferencia es una ayuda;
    // subir y bajar es la razón de ser, y una ayuda no puede tumbar la razón de ser.
    final virgen = baseDePrueba();
    addTearDown(virgen.close);
    final sinTablero = Huerfanos(virgen);

    expect((await sinTablero.mirar()).hayAlguno, isFalse);
    expect(await sinTablero.volverAEncolar(ColaDeSalida(virgen)), 0);
  });

  group('volver a encolar', () {
    test('rehace la zona Y sus pedidos, en su orden', () async {
      await zonaLocal('local-abc', pedidos: ['p1', 'p2', 'p3']);

      final puestos = await huerfanos.volverAEncolar(cola);
      expect(puestos, 4, reason: '1 zona + 3 pedidos');

      final apuntes = await base.select(base.apuntes).get();
      expect(apuntes.first.metodo, 'POST');
      expect(apuntes.first.ruta, '/board/columns?branchId=hab-1');
      expect(
        apuntes.first.provisional,
        'local-abc',
        reason:
            'sin el provisional, las colocaciones de detrás acaban en una columna '
            'que no existe en ningún sitio',
      );
      expect(
        apuntes.skip(1).map((a) => a.ruta).toList(),
        ['/board/placements/p1', '/board/placements/p2', '/board/placements/p3'],
        reason: 'y en el orden en que se colocaron, que es el orden de visita',
      );
    });

    test('una zona vacía sube sola, sin inventarse pedidos', () async {
      await zonaLocal('local-vacia');
      expect(await huerfanos.volverAEncolar(cola), 1);
    });

    test('NO la vuelve a encolar en la vuelta siguiente', () async {
      // Ésta es la guarda contra el bucle. El ciclo corre cada pocos minutos: si cada
      // vuelta volviera a encolar lo mismo, la cola crecería sola hasta reventar.
      await zonaLocal('local-abc', pedidos: ['p1']);

      expect(await huerfanos.volverAEncolar(cola), 2);
      expect(
        await huerfanos.volverAEncolar(cola),
        0,
        reason: 'ya tiene apunte vivo: dejó de estar huérfana',
      );
      expect((await base.select(base.apuntes).get()).length, 2);
    });

    test('no toca lo que ya tiene apunte', () async {
      await zonaLocal('local-con-apunte');
      await cola.encolar(
        metodo: 'POST',
        ruta: '/board/columns?branchId=hab-1',
        cuerpo: const {'nombre': 'Vista'},
        provisional: 'local-con-apunte',
      );
      await zonaLocal('local-huerfana', nombre: 'Otra');

      expect(await huerfanos.volverAEncolar(cola), 1);
      final nuevos = (await base.select(base.apuntes).get())
          .where((a) => a.provisional == 'local-huerfana');
      expect(nuevos.length, 1);
    });
  });
}
