import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/datos/repositorio.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo.dart';

void main() {
  late BaseLocal base;
  late ConsultasTablero consultas;
  late RepositorioTablero repo;
  late AlmacenOrigen origen;

  setUp(() async {
    base = baseDePrueba();
    consultas = ConsultasTablero(base);
    repo = RepositorioTablero(base, ColaDeSalida(base));
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    origen = await consultas.almacenDe(sucursalStg);
  });

  tearDown(() => base.close());

  group('el almacén desde el que se mide', () {
    test('gana el principal con coordenadas', () async {
      await sembrarAlmacen(
        base,
        id: 'alm-2',
        nombre: 'Patio',
        principal: false,
        lat: 21,
      );
      final elegido = await consultas.almacenDe(sucursalStg);
      expect(elegido.nombre, 'Almacén principal');
    });

    test('si ninguno es principal, vale el primero con coordenadas', () async {
      await base.delete(base.warehouses).go();
      await sembrarAlmacen(
        base,
        id: 'alm-2',
        nombre: 'Patio',
        principal: false,
      );
      final elegido = await consultas.almacenDe(sucursalStg);
      expect(elegido.nombre, 'Patio');
    });

    test(
      'sin ninguno con coordenadas NO HAY TABLERO, y se dice cuál',
      () async {
        await base.delete(base.warehouses).go();
        await sembrarAlmacen(base, id: 'alm-3', lat: null, lng: null);
        expect(
          () => consultas.almacenDe(sucursalStg),
          throwsA(
            isA<SinAlmacenConCoordenadas>().having(
              (e) => e.mensaje,
              'mensaje',
              'Santiago no tiene ningún almacén con coordenadas',
            ),
          ),
        );
      },
    );

    test('(0,0) no son coordenadas: es el golfo de Guinea', () async {
      await base.delete(base.warehouses).go();
      await sembrarAlmacen(base, id: 'alm-4', lat: 0, lng: 0);
      expect(
        () => consultas.almacenDe(sucursalStg),
        throwsA(isA<SinAlmacenConCoordenadas>()),
      );
    });
  });

  group('el orden: el más cerca del almacén primero', () {
    test('es por cercanía, no por fecha', () async {
      // El lejano es el MAS NUEVO: por fecha saldria el primero.
      await sembrarPedido(
        base,
        id: 'lejos',
        aGrados: 0.30,
        fecha: DateTime(2026, 9, 14, 18),
      );
      await sembrarPedido(
        base,
        id: 'medio',
        aGrados: 0.10,
        fecha: DateTime(2026, 9, 14, 12),
      );
      await sembrarPedido(
        base,
        id: 'cerca',
        aGrados: 0.01,
        fecha: DateTime(2026, 9, 14, 6),
      );

      final izquierda = await consultas.sinColocar(sucursalStg, origen);
      expect(izquierda.pedidos.map((p) => p.pedidoId).toList(), [
        'cerca',
        'medio',
        'lejos',
      ]);
      expect(izquierda.pedidos.first.kmAlAlmacen, closeTo(gradoKm * 0.01, 0.2));
    });

    test('a igual distancia el desempate es estable: fecha y luego id', () async {
      // Dos clientes del mismo edificio dan exactamente los mismos kilometros.
      // Sin un segundo criterio las tarjetas bailan entre dos lecturas delante
      // de quien las esta arrastrando.
      await sembrarPedido(
        base,
        id: 'b',
        aGrados: 0.05,
        fecha: DateTime(2026, 9, 14, 9),
      );
      await sembrarPedido(
        base,
        id: 'a',
        aGrados: 0.05,
        fecha: DateTime(2026, 9, 14, 11),
      );

      final una = await consultas.sinColocar(sucursalStg, origen);
      final otra = await consultas.sinColocar(sucursalStg, origen);
      expect(una.pedidos.map((p) => p.pedidoId).toList(), ['a', 'b']);
      expect(
        otra.pedidos.map((p) => p.pedidoId).toList(),
        una.pedidos.map((p) => p.pedidoId).toList(),
      );
    });
  });

  group('qué entra y qué no en la mitad izquierda', () {
    test(
      'las cinco condiciones del armador, ni una más ni una menos',
      () async {
        await sembrarPedido(base, id: 'bueno');
        await sembrarPedido(base, id: 'con-ruta', rutaId: 'r1');
        await sembrarPedido(base, id: 'sin-coords', conCoordenadas: false);
        await sembrarPedido(base, id: 'sin-cotejar', facturaEstado: null);
        await sembrarPedido(
          base,
          id: 'sin-factura',
          facturaEstado: EstadoFactura.sinFactura,
        );
        await sembrarPedido(base, id: 'a-mano', fuente: null);
        await sembrarPedido(base, id: 'de-otra', sucursal: 'suc-hol');
        // `cambiado` SI se puede repartir: lo que sube al camion son las lineas
        // de la factura.
        await sembrarPedido(
          base,
          id: 'cambiado',
          facturaEstado: EstadoFactura.cambiado,
        );

        final izquierda = await consultas.sinColocar(sucursalStg, origen);
        expect(izquierda.pedidos.map((p) => p.pedidoId).toSet(), {
          'bueno',
          'cambiado',
        });
      },
    );

    test('lo que ya está colocado sale de la lista', () async {
      await sembrarPedido(base, id: 'p1');
      await sembrarPedido(base, id: 'p2');
      final columna = await repo.crearColumna(
        sucursalId: sucursalStg,
        nombre: 'Centro',
      );
      await repo.colocar(pedidoId: 'p1', columnaId: columna);

      final izquierda = await consultas.sinColocar(sucursalStg, origen);
      expect(izquierda.pedidos.map((p) => p.pedidoId).toList(), ['p2']);
      expect(izquierda.total, 1);
    });
  });

  group('los filtros', () {
    setUp(() async {
      await sembrarPedido(
        base,
        id: 'p1',
        cliente: 'Bodega La Palma',
        municipio: 'Songo',
        vendedor: 'Ana',
        aGrados: 0.02,
      );
      await sembrarPedido(
        base,
        id: 'p2',
        cliente: 'Cafetería Central',
        municipio: 'Santiago de Cuba',
        vendedor: 'Luis',
        aGrados: 0.40,
        fecha: DateTime(2026, 9, 13, 10),
      );
      await sembrarRenglon(
        base,
        id: 'r1',
        pedidoId: 'p2',
        descripcion: 'Malta Bucanero 24u',
      );
    });

    test('la búsqueda mira también el contenido de los renglones', () async {
      final izquierda = await consultas.sinColocar(
        sucursalStg,
        origen,
        filtros: const FiltrosSinColocar(q: 'malta'),
      );
      expect(izquierda.pedidos.single.pedidoId, 'p2');
    });

    test('la búsqueda mira el cliente', () async {
      final izquierda = await consultas.sinColocar(
        sucursalStg,
        origen,
        filtros: const FiltrosSinColocar(q: 'palma'),
      );
      expect(izquierda.pedidos.single.pedidoId, 'p1');
    });

    test('municipio, vendedor y corte por kilómetros', () async {
      expect(
        (await consultas.sinColocar(
          sucursalStg,
          origen,
          filtros: const FiltrosSinColocar(municipio: 'Songo'),
        )).pedidos.single.pedidoId,
        'p1',
      );
      expect(
        (await consultas.sinColocar(
          sucursalStg,
          origen,
          filtros: const FiltrosSinColocar(vendedor: 'Luis'),
        )).pedidos.single.pedidoId,
        'p2',
      );
      expect(
        (await consultas.sinColocar(
          sucursalStg,
          origen,
          filtros: const FiltrosSinColocar(kmMax: 10),
        )).pedidos.single.pedidoId,
        'p1',
      );
    });

    test('el día del pedido', () async {
      final izquierda = await consultas.sinColocar(
        sucursalStg,
        origen,
        filtros: FiltrosSinColocar(dia: DateTime(2026, 9, 13)),
      );
      expect(izquierda.pedidos.single.pedidoId, 'p2');
    });

    test('el total es el de los mismos filtros, no el de la página', () async {
      final izquierda = await consultas.sinColocar(
        sucursalStg,
        origen,
        filtros: const FiltrosSinColocar(limite: 1),
      );
      expect(izquierda.pedidos.length, 1);
      expect(izquierda.total, 2);
      expect(izquierda.truncada, isTrue);
    });
  });

  test('dos pedidos del mismo cliente son DOS tarjetas, y se dice', () async {
    // El sufijo del folio es nuestro: X-2992 y X-2992-2 son dos pedidos, con su
    // peso y su domicilio cada uno.
    await sembrarPedido(
      base,
      id: 'x1',
      cliente: 'Bodega La Palma',
      operacion: 'X-2992',
    );
    await sembrarPedido(
      base,
      id: 'x2',
      cliente: 'Bodega La Palma',
      operacion: 'X-2992-2',
    );

    final izquierda = await consultas.sinColocar(sucursalStg, origen);
    expect(izquierda.pedidos.length, 2, reason: 'no se funden');
    expect(izquierda.pedidos.every((p) => p.mismoCliente == 2), isTrue);
    // Y caen seguidas, que es lo que hace que se vean juntas.
    expect(
      izquierda.pedidos.map((p) => p.operationNumber).toList(),
      containsAll(<String>['X-2992', 'X-2992-2']),
    );
  });

  // EL TABLERO SOLO OFRECE LO QUE VA A DOMICILIO.
  //
  // El tablero es la preparacion de las rutas, y una ruta reparte a casa del
  // cliente. Sin este filtro, con los datos reales de Santiago del 25/09/2026,
  // se ofrecian 246 pedidos sin colocar de los que **183 no eran de domicilio**:
  // tres de cada cuatro. Se armo una zona entera con ellos probandolo, y despues
  // el asistente de rutas no la aceptaba, porque alli el filtro si estaba.
  // Preparar el dia para que luego no sirva es peor que no poder prepararlo.
  //
  // Jose, 25/09/2026: «sin domicilio no los pongas, por que eso no lleva
  // domicilio».
  //
  // LA PRUEBA VA EN PAREJA, y hace falta: con solo la mitad de «no sale el que
  // no lleva domicilio» se cumpliria igual devolviendo SIEMPRE cero.
  group('sin domicilio no se coloca', () {
    test('el que va a domicilio sale, y el que no, no', () async {
      await sembrarPedido(base, id: 'con-domicilio');
      await sembrarPedido(base, id: 'sin-domicilio', domicilio: false);

      final mitad = await consultas.sinColocar(sucursalStg, origen);
      final ids = mitad.pedidos.map((p) => p.pedidoId).toSet();

      expect(
        ids,
        contains('con-domicilio'),
        reason:
            'el pedido que SI va a domicilio no sale: el tablero se queda sin '
            'nada que preparar',
      );
      expect(
        ids,
        isNot(contains('sin-domicilio')),
        reason:
            'sale un pedido que no lleva domicilio. Se puede colocar en una '
            'zona y despues el asistente de rutas no lo acepta: el dia se '
            'prepara para nada',
      );
    });

    // `null` no es `false`: es «nadie lo ha marcado todavia». Tampoco se
    // reparte, y por eso tampoco se ofrece — pero se comprueba aparte, porque en
    // SQL un `= true` y un `IS TRUE` tratan el nulo distinto y es justo el borde
    // donde se cuela.
    test('el que nadie ha marcado tampoco sale', () async {
      await sembrarPedido(base, id: 'con-domicilio');
      await sembrarPedido(base, id: 'sin-marcar', domicilio: null);

      final mitad = await consultas.sinColocar(sucursalStg, origen);
      final ids = mitad.pedidos.map((p) => p.pedidoId).toSet();

      expect(ids, contains('con-domicilio'));
      expect(
        ids,
        isNot(contains('sin-marcar')),
        reason:
            'un pedido sin marcar salio como si fuera de domicilio: `null` no '
            'es `true`',
      );
    });
  });
}
