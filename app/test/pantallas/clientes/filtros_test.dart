import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/clientes/datos/repositorio_clientes.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo_clientes.dart';

/// Los 6 filtros del pliego (§4), uno a uno y juntos, contra una base sembrada.
/// El criterio de terminado de esta pantalla es dar el MISMO numero que la de
/// Next, asi que lo que se comprueba son numeros, no widgets.
void main() {
  late BaseLocal base;
  late RepositorioClientes repositorio;

  setUp(() async {
    base = baseDePrueba();
    repositorio = RepositorioClientes(base);
    await sembrarSucursal(base);
    await marcarBajada(base, DateTime(2026, 9, 14, 7, 42));

    await sembrarCliente(
      base,
      id: 'c1',
      nombre: 'Ana Pérez',
      lat: 20.03,
      lng: -75.82,
      municipio: 'Santiago',
      zona: 'Norte',
      vendedor: 'Luis',
      telefono: '53000001',
      direccion: 'Calle 1',
      codigo: 'CL-001',
    );
    await sembrarCliente(
      base,
      id: 'c2',
      nombre: 'Beto Gómez',
      lat: 20.04,
      lng: -75.83,
      municipio: 'Palma',
      zona: 'Norte',
      vendedor: 'Luis',
      direccion: 'Carretera central',
    );
    await sembrarCliente(
      base,
      id: 'c3',
      nombre: 'Carla Ruiz',
      lat: 20.02,
      lng: -75.81,
      municipio: 'Santiago',
      zona: 'Sur',
      vendedor: 'Marta',
      telefono: '53000003',
    );
    // Manual: sin `source` y **sin codigo de sucursal**.
    await sembrarCliente(
      base,
      id: 'c4',
      nombre: 'Delia Manual',
      lat: 20.01,
      lng: -75.80,
      municipio: 'Santiago',
      source: null,
      sucursalCodigo: null,
    );
    // De otra sucursal: no tiene que salir nunca con el alcance de STG.
    await sembrarCliente(
      base,
      id: 'c5',
      nombre: 'Elio Habana',
      lat: 23.13,
      lng: -82.38,
      municipio: 'Habana Vieja',
      sucursalCodigo: 'HAB',
    );
  });

  tearDown(() => base.close());

  Future<List<String>> ids(FiltrosClientes f) async {
    final pagina = await repositorio.consultar(f, sucursalId: 'b-stg');
    return [for (final c in pagina.clientes) c.cliente.id];
  }

  test(
    'el alcance deja fuera otra sucursal y deja dentro los manuales',
    () async {
      // Los manuales no llevan codigo: si se filtraran por sucursal
      // desaparecerian de TODAS, y son los unicos que nadie puede recuperar.
      expect(await ids(const FiltrosClientes()), ['c1', 'c2', 'c3', 'c4']);
    },
  );

  test('municipio', () async {
    expect(await ids(const FiltrosClientes(municipio: 'Santiago')), [
      'c1',
      'c3',
      'c4',
    ]);
  });

  test('zona', () async {
    expect(await ids(const FiltrosClientes(zona: 'Norte')), ['c1', 'c2']);
  });

  test('vendedor', () async {
    expect(await ids(const FiltrosClientes(vendedor: 'Luis')), ['c1', 'c2']);
  });

  test('teléfono: con y sin', () async {
    expect(await ids(const FiltrosClientes(telefono: true)), ['c1', 'c3']);
    expect(await ids(const FiltrosClientes(telefono: false)), ['c2', 'c4']);
  });

  test('origen: de PEDIDO y manuales', () async {
    expect(await ids(const FiltrosClientes(origen: OrigenCliente.pedido)), [
      'c1',
      'c2',
      'c3',
    ]);
    expect(await ids(const FiltrosClientes(origen: OrigenCliente.manual)), [
      'c4',
    ]);
  });

  test('la búsqueda mira nombre, dirección, municipio, zona, teléfono, código y vendedor', () async {
    expect(await ids(const FiltrosClientes(q: 'pérez')), ['c1']);
    expect(await ids(const FiltrosClientes(q: 'carretera')), ['c2']);
    expect(await ids(const FiltrosClientes(q: 'CL-001')), ['c1']);
    expect(await ids(const FiltrosClientes(q: 'marta')), ['c3']);
    // Sin distinguir mayusculas, como el `contains insensitive` del servidor.
    expect(await ids(const FiltrosClientes(q: 'SANTIAGO')), ['c1', 'c3', 'c4']);
  });

  test('los seis a la vez', () async {
    expect(
      await ids(
        const FiltrosClientes(
          q: 'ana',
          municipio: 'Santiago',
          zona: 'Norte',
          vendedor: 'Luis',
          telefono: true,
          kmMax: 50,
          origen: OrigenCliente.pedido,
        ),
      ),
      ['c1'],
    );
  });

  test('las facetas se cuentan sobre el alcance, no sobre la página', () async {
    // Con un filtro puesto, los desplegables siguen ofreciendo TODO lo que hay:
    // si se recortaran con el filtro, elegir un municipio haria desaparecer los
    // demas y ya no se podria cambiar de idea.
    final pagina = await repositorio.consultar(
      const FiltrosClientes(municipio: 'Palma'),
      sucursalId: 'b-stg',
    );
    expect(
      {for (final f in pagina.municipios) f.valor: f.clientes},
      {'Palma': 1, 'Santiago': 3},
    );
    expect(
      {for (final f in pagina.zonas) f.valor: f.clientes},
      {'Norte': 2, 'Sur': 1},
    );
    expect(
      {for (final f in pagina.vendedores) f.valor: f.clientes},
      {'Luis': 2, 'Marta': 1},
    );
    expect(pagina.sinTelefono, 2);
  });

  test('quitar filtros aparece con municipio, zona, origen o búsqueda', () {
    expect(const FiltrosClientes().hayQueQuitar, isFalse);
    expect(const FiltrosClientes(kmMax: 5).hayQueQuitar, isFalse);
    expect(const FiltrosClientes(zona: 'Norte').hayQueQuitar, isTrue);
    expect(const FiltrosClientes(q: 'ana').hayQueQuitar, isTrue);
  });

  test('cambiar un filtro vuelve a la página 1', () {
    const f = FiltrosClientes(pagina: 7);
    expect(f.copiar(municipio: 'Santiago').pagina, 1);
    // Sólo pasar de pagina conserva la pagina.
    expect(f.copiar(pagina: 8).pagina, 8);
  });
}
