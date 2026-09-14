import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/reloj_de_datos.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/clientes/datos/repositorio_clientes.dart';
import 'package:reparto/pantallas/clientes/estado/estado_clientes.dart';
import 'package:reparto/pantallas/clientes/vista/pantalla_clientes.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo_clientes.dart';

/// Lo que esta pantalla tiene que hacer sin conexion: ensenar la foto de la
/// ultima bajada **y decir de que hora es**. Y sus tres vacios, que son tres
/// textos distintos y se confunden con facilidad.
void main() {
  late BaseLocal base;

  /// Las 7:42 de la manana del dia de la prueba. El reloj va aparte para poder
  /// mirar la pantalla «mas tarde» sin esperar.
  final bajada = DateTime(2026, 9, 14, 7, 42);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> pintar(WidgetTester tester, {DateTime? ahora}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora ?? bajada),
        ],
        child: const MaterialApp(home: PantallaClientes()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin bajar nada: no dice «no hay clientes», dice que no se ha descargado', (
    tester,
  ) async {
    await sembrarSucursal(base);
    await pintar(tester);

    // Una lista vacia aqui es un FALLO, no un dato (caso S7).
    expect(find.text(SinDescargar.textoDeLaPantallaVacia), findsOneWidget);
    expect(find.text('Sin descargar todavía'), findsOneWidget);
  });

  testWidgets('bajado y vacío: el texto es otro', (tester) async {
    await sembrarSucursal(base);
    await marcarBajada(
      base,
      bajada,
      colecciones: const [Colecciones.clientes, Colecciones.almacenes],
    );
    await pintar(tester);

    expect(
      find.text(
        'Sin clientes todavía. Los de PEDIDO aparecen solos cuando tengan '
        'geolocalización.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('con datos: dice de qué hora es la foto', (tester) async {
    await sembrarSucursal(base);
    await marcarBajada(
      base,
      bajada,
      colecciones: const [Colecciones.clientes, Colecciones.almacenes],
    );
    await sembrarCliente(
      base,
      id: 'c1',
      nombre: 'Ana Pérez',
      lat: 20.03,
      lng: -75.82,
      municipio: 'Santiago',
    );
    await pintar(tester, ahora: bajada.add(const Duration(minutes: 3)));

    expect(find.text('Datos de las 7:42'), findsOneWidget);
    expect(find.text('Ana Pérez'), findsOneWidget);
  });

  testWidgets('el reloj se pone en ámbar cuando la foto es de ayer', (
    tester,
  ) async {
    await sembrarSucursal(base);
    await marcarBajada(
      base,
      bajada,
      colecciones: const [Colecciones.clientes, Colecciones.almacenes],
    );
    // Cinco horas despues sigue en gris; es al pasar del dia cuando enganna.
    await pintar(tester, ahora: bajada.add(const Duration(hours: 5)));
    expect(find.text('Datos de hace 5 h'), findsOneWidget);
  });

  testWidgets('con filtros que no cuadran: «Sin resultados.»', (tester) async {
    await sembrarSucursal(base);
    await marcarBajada(
      base,
      bajada,
      colecciones: const [Colecciones.clientes, Colecciones.almacenes],
    );
    await sembrarCliente(
      base,
      id: 'c1',
      nombre: 'Ana Pérez',
      lat: 20.03,
      lng: -75.82,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => bajada),
          filtrosClientesProviderParaLaPrueba,
        ],
        child: const MaterialApp(home: PantallaClientes()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sin resultados.'), findsOneWidget);
  });

  test('50 por página, y la cuenta de arriba es la del filtro, no la de la página', () async {
    await sembrarSucursal(base);
    await marcarBajada(base, bajada);
    for (var i = 0; i < 60; i++) {
      await sembrarCliente(
        base,
        id: 'c${i.toString().padLeft(2, '0')}',
        nombre: 'Cliente ${i.toString().padLeft(2, '0')}',
        lat: 20.03,
        lng: -75.82,
      );
    }

    final repositorio = RepositorioClientes(base);
    final primera = await repositorio.consultar(
      const FiltrosClientes(),
      sucursalId: 'b-stg',
    );
    expect(primera.clientes.length, 50);
    expect(primera.total, 60);
    expect(primera.paginas, 2);
    expect(primera.desde, 1);
    expect(primera.hasta, 50);

    final segunda = await repositorio.consultar(
      const FiltrosClientes(pagina: 2),
      sucursalId: 'b-stg',
    );
    expect(segunda.clientes.length, 10);
    expect(segunda.desde, 51);
    expect(segunda.hasta, 60);
  });
}

/// Un filtro que no cuadra con nada, puesto desde fuera.
final filtrosClientesProviderParaLaPrueba = filtrosClientesProvider
    .overrideWith(_FiltroQueNoCuadra.new);

class _FiltroQueNoCuadra extends FiltrosDeClientes {
  @override
  FiltrosClientes build() => const FiltrosClientes(municipio: 'Marte');
}
