// Armar una ruta SIN conexion: orden de visita, km, peso, precio, el codigo de
// ruta del aparato y los seis rechazos con su texto literal.
//
// **Los mensajes se comparan caracter a caracter contra el pliego a proposito.**
// Un rechazo local y uno remoto tienen que leerse igual: si aqui dice «no se
// pudo» y el servidor dice «3 de los 8 pedidos ya están en otra ruta», la persona
// aprende que la aplicacion miente a veces.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/rutas/datos/acciones_rutas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../pedidos/sembrar.dart';

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late AccionesDeRuta acciones;
  late RelojFalso reloj;

  setUp(() async {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime.utc(2026, 9, 14, 16, 5));
    cola = ColaDeSalida(base, reloj: reloj.leer);
    acciones = AccionesDeRuta(base, cola, reloj: reloj.leer, sufijoAparato: 'MSI');
    await sembrarCatalogo(base);

    // Tres paradas en el ecuador, a 0.1 / 0.3 / 0.2 grados de longitud del
    // origen (0,0): asi los km se pueden comprobar a mano.
    await sembrarPedido(
      base,
      id: 'q1',
      cliente: 'Ana',
      folio: 'F-001',
      peso: 100,
      endLat: 0,
      endLng: 0.1,
    );
    await sembrarPedido(
      base,
      id: 'q2',
      cliente: 'Beto',
      folio: 'F-002',
      peso: 200,
      endLat: 0,
      endLng: 0.3,
    );
    await sembrarPedido(
      base,
      id: 'q3',
      cliente: 'Carla',
      folio: 'F-003',
      peso: 300,
      endLat: 0,
      endLng: 0.2,
    );
  });

  tearDown(() => base.close());

  Future<String> armarLasTres() => acciones.armar(
    vehiculoId: 'V1',
    pedidoIds: ['q1', 'q2', 'q3'],
    origenLat: 0,
    origenLng: 0,
    origenDireccion: 'Almacén central',
    sucursalId: 'B1',
    nombre: 'Reparto de la mañana',
  );

  test('la ruta se arma entera en el aparato y sale con id local', () async {
    final rutaId = await armarLasTres();
    expect(rutaId, startsWith('local-'));

    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals(rutaId))).getSingle();

    // El codigo lleva el sufijo del aparato: sin el, dos sucursales sin red el
    // mismo dia generarian los dos `RT-20260914-001`.
    expect(ruta.routeCode, 'RT-20260914-001-MSI');
    expect(ruta.totalWeight, 600);
    // 10 + 60 + 30 (los `pedidoCosto` sembrados son 10 por defecto) — aqui los
    // tres valen 10, asi que el total es 30.
    expect(ruta.totalPrice, 30);
    // 0.1 + 0.1 + 0.1 (ida por 0.1 → 0.2 → 0.3) + 0.3 de regreso = 0.6 grados.
    expect(ruta.totalDistance, closeTo(11.1195 * 6, 0.05));
    expect(ruta.optimized, isTrue);
    expect(ruta.status, EstadoRuta.planificada);
  });

  test('el orden de visita es el del vecino mas proximo', () async {
    final rutaId = await armarLasTres();
    final paradas =
        await (base.select(base.orders)
              ..where((o) => o.ultimaRutaId.equals(rutaId)))
            .get();
    final porOrden = {for (final p in paradas) p.stopOrder: p.id};
    expect(porOrden[1], 'q1'); // 0.1
    expect(porOrden[2], 'q3'); // 0.2
    expect(porOrden[3], 'q2'); // 0.3

    // `segmentKm` es la distancia RADIAL desde el origen, no la del tramo.
    final q2 = paradas.firstWhere((p) => p.id == 'q2');
    expect(q2.segmentKm, closeTo(11.1195 * 3, 0.05));

    // Y los tres quedan ocupados por la ruta, en las DOS columnas.
    for (final parada in paradas) {
      expect(parada.routeId, rutaId);
      expect(parada.ultimaRutaId, rutaId);
    }
  });

  test('el apunte queda en la cola con el id provisional como bisagra', () async {
    final rutaId = await armarLasTres();
    final pendientes = await cola.pendientes().first;
    expect(pendientes.length, 1);

    final apunte = pendientes.single;
    expect(apunte.metodo, 'POST');
    expect(apunte.ruta, '/routes');
    expect(apunte.provisional, rutaId);
    // La hora del APARATO, escrita al encolar.
    expect(apunte.hechoAt, reloj.ahora);

    final cuerpo = ColaDeSalida.cuerpoDe(apunte)! as Map<String, Object?>;
    expect(cuerpo['orderIds'], ['q1', 'q3', 'q2']);
    expect(cuerpo['vehicleId'], 'V1');
    expect(cuerpo['branchId'], 'B1');
  });

  group('los rechazos, con el texto literal del servidor', () {
    test('sin coordenadas de partida', () async {
      expect(
        () => acciones.armar(
          vehiculoId: 'V1',
          pedidoIds: ['q1'],
          origenLat: null,
          origenLng: null,
        ),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            'Las coordenadas del punto de partida son requeridas',
          ),
        ),
      );
    });

    test('sin vehiculo', () async {
      expect(
        () => acciones.armar(
          vehiculoId: null,
          pedidoIds: ['q1'],
          origenLat: 0,
          origenLng: 0,
        ),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            'Se requiere un vehículo para crear la ruta',
          ),
        ),
      );
    });

    test('sin pedidos, con las comillas invertidas del literal', () async {
      expect(
        () => acciones.armar(
          vehiculoId: 'V1',
          pedidoIds: const [],
          origenLat: 0,
          origenLng: 0,
        ),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            'Una ruta se arma eligiendo pedidos ya existentes. Manda `orderIds`.',
          ),
        ),
      );
    });

    test('ninguno disponible', () async {
      expect(
        () => acciones.armar(
          vehiculoId: 'V1',
          pedidoIds: const ['no-existe'],
          origenLat: 0,
          origenLng: 0,
        ),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            'Los pedidos seleccionados ya no están disponibles',
          ),
        ),
      );
    });

    test('alguno ya esta en otra ruta: se dice CUANTOS', () async {
      await sembrarRuta(base, id: 'R9');
      await (base.update(base.orders)..where((o) => o.id.equals('q2'))).write(
        const OrdersCompanion(routeId: Value('R9')),
      );

      expect(
        () => acciones.armar(
          vehiculoId: 'V1',
          pedidoIds: ['q1', 'q2', 'q3'],
          origenLat: 0,
          origenLng: 0,
        ),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            '1 de los 3 pedidos ya están en otra ruta. Vuelve a elegirlos.',
          ),
        ),
      );
    });

    test('en una ruta sólo entra lo facturado y que cuadre', () async {
      await (base.update(base.orders)..where((o) => o.id.equals('q2'))).write(
        const OrdersCompanion(facturaEstado: Value(EstadoFactura.cambiado)),
      );
      await (base.update(base.orders)..where((o) => o.id.equals('q3'))).write(
        const OrdersCompanion(facturaEstado: Value(null)),
      );

      expect(
        () => acciones.armar(
          vehiculoId: 'V1',
          pedidoIds: ['q1', 'q2', 'q3'],
          origenLat: 0,
          origenLng: 0,
        ),
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            'En una ruta sólo entra lo facturado y que cuadre. 2 no cumplen: '
                'F-002 (cambió en la factura), F-003 (sin cotejar).',
          ),
        ),
      );
    });

    test('sobrepeso: el peso a un decimal y la capacidad sin formatear', () async {
      await (base.update(base.vehicles)..where((v) => v.id.equals('V1'))).write(
        const VehiclesCompanion(capacity: Value(500)),
      );

      expect(
        armarLasTres,
        throwsA(
          isA<RechazoLocal>().having(
            (r) => r.mensaje,
            'mensaje',
            'Peso total (600.0 kg) supera la capacidad del vehículo (500 kg)',
          ),
        ),
      );
    });

    test('igualar la capacidad exacta SI pasa', () async {
      await (base.update(base.vehicles)..where((v) => v.id.equals('V1'))).write(
        const VehiclesCompanion(capacity: Value(600)),
      );
      // La comparacion es `>` estricta, como en el servidor.
      await expectLater(armarLasTres(), completes);
    });

    test('un rechazo NO deja nada a medias', () async {
      await (base.update(base.vehicles)..where((v) => v.id.equals('V1'))).write(
        const VehiclesCompanion(capacity: Value(500)),
      );
      await expectLater(armarLasTres(), throwsA(isA<RechazoLocal>()));

      expect(await base.select(base.routes).get(), isEmpty);
      expect(await cola.pendientes().first, isEmpty);
    });
  });

  test('los numeros de ruta se van sucediendo en el aparato', () async {
    await armarLasTres();
    await sembrarPedido(
      base,
      id: 'q4',
      cliente: 'Dani',
      peso: 10,
      endLat: 0,
      endLng: 0.4,
    );
    final segunda = await acciones.armar(
      vehiculoId: 'V1',
      pedidoIds: ['q4'],
      origenLat: 0,
      origenLng: 0,
    );
    final ruta = await (base.select(
      base.routes,
    )..where((r) => r.id.equals(segunda))).getSingle();
    expect(ruta.routeCode, 'RT-20260914-002-MSI');
  });
}
