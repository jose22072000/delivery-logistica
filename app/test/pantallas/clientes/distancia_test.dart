import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/clientes/datos/geo.dart';
import 'package:reparto/pantallas/clientes/datos/repositorio_clientes.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo_clientes.dart';

/// Los km que ve el logistico salen del APARATO, no del servidor: sin conexion
/// tienen que ser los mismos. Los valores de abajo estan calculados aparte, con
/// la formula de `reglas-negocio.md` §1.1 (R = 6371), y se comparan a los dos
/// decimales con que se pintan.
void main() {
  // Dos bases en memoria dentro del mismo test: el aviso de drift es para el
  // aparato, donde dos `BaseLocal` sobre el mismo fichero si se pisan.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late BaseLocal base;
  late RepositorioClientes repositorio;

  /// Cinco puntos con su distancia conocida al almacen de Santiago.
  const puntos = <(String, double, double, double)>[
    ('c1', 20.0247, -75.8219, 0.0),
    ('c2', 20.0500, -75.8219, 2.81),
    ('c3', 20.0247, -75.7500, 7.51),
    ('c4', 19.9000, -75.9000, 16.09),
    ('c5', 20.3000, -76.2000, 49.95),
  ];

  setUp(() async {
    base = baseDePrueba();
    repositorio = RepositorioClientes(base);
    await sembrarSucursal(base);
    await marcarBajada(base, DateTime(2026, 9, 14, 7, 42));
    for (final (id, lat, lng, _) in puntos) {
      await sembrarCliente(
        base,
        id: id,
        nombre: 'Cliente $id',
        lat: lat,
        lng: lng,
      );
    }
  });

  tearDown(() => base.close());

  test(
    'la distancia es haversine desde el almacén principal, a 2 decimales',
    () async {
      final pagina = await repositorio.consultar(
        const FiltrosClientes(),
        sucursalId: 'b-stg',
      );
      final porId = {for (final c in pagina.clientes) c.cliente.id: c.km};
      for (final (id, _, _, km) in puntos) {
        expect(porId[id], km, reason: 'los km de $id');
      }
    },
  );

  test('`Hasta 10 km` deja fuera lo que está a 16,09 y a 49,95', () async {
    final pagina = await repositorio.consultar(
      const FiltrosClientes(kmMax: 10),
      sucursalId: 'b-stg',
    );
    expect(pagina.clientes.map((c) => c.cliente.id), ['c1', 'c2', 'c3']);
  });

  test(
    '`Hasta 50 km` deja dentro el de 49,95 — el límite no se pasa de largo',
    () async {
      final pagina = await repositorio.consultar(
        const FiltrosClientes(kmMax: 50),
        sucursalId: 'b-stg',
      );
      expect(pagina.clientes.length, 5);
    },
  );

  test('sin almacén con coordenadas la distancia es null, NO cero', () async {
    final otra = baseDePrueba();
    await sembrarSucursal(otra, conAlmacen: false);
    await marcarBajada(otra, DateTime(2026, 9, 14, 7, 42));
    await sembrarCliente(
      otra,
      id: 'c9',
      nombre: 'Sin referencia',
      lat: 20.1,
      lng: -75.8,
    );

    final pagina = await RepositorioClientes(otra)
        .consultar(const FiltrosClientes(), sucursalId: 'b-stg');

    expect(pagina.almacenDeReferencia, isNull);
    // Cero km significaria «esta en la puerta del almacen». Un cliente sin
    // referencia no esta en la puerta: es que no se sabe.
    expect(pagina.clientes.single.km, isNull);
    await otra.close();
  });

  test('la cuenta de Geo redondea una sola vez', () {
    // 2,813232 km: a dos decimales es 2,81. Redondear antes y despues mueve el
    // limite de `Hasta 5 km` en los casos justos.
    final crudo = Geo.haversineKm(almacenLat, almacenLng, 20.05, almacenLng);
    expect(crudo, closeTo(2.813232, 0.0001));
    expect(Geo.km2(crudo), 2.81);
  });
}
