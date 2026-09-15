import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

/// LA PRUEBA QUE NO PUEDE FALTAR.
///
/// Arrastrar una tarjeta sin conexión tiene que hacer tres cosas y ninguna más:
/// escribir en la base del aparato, dejar el apunte en la cola y **no llamar a
/// nadie**. Y lo que quede escrito tiene que seguir ahí después de cerrar la
/// aplicación y volver a abrirla, que es lo que distingue «guarda en memoria»
/// de «vive en el aparato» (PLAN.md §5.1, pasos 2 y 6).
///
/// Por eso la base va a un FICHERO y no a memoria: una base en memoria pasaría
/// esta prueba sin decir nada de lo que de verdad se quiere comprobar.
void main() {
  late Directory carpeta;
  late File fichero;
  late ServidorFalso servidor;

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('tablero_sin_red');
    fichero = File('${carpeta.path}/reparto.sqlite');
    servidor = ServidorFalso(
      // Sin red: cualquier petición que se escape falla como en la calle. Y
      // además se apunta, que es lo que se comprueba.
      (peticion) async => null,
    );
  });

  tearDown(() async {
    if (carpeta.existsSync()) await carpeta.delete(recursive: true);
  });

  BaseLocal abrirBase() => BaseLocal.con(NativeDatabase(fichero));

  ProviderContainer montar(BaseLocal base) {
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.invalido'))
      ..httpClientAdapter = servidor;
    return ProviderContainer.test(
      overrides: [
        // Sin `onDispose`: la base la cierra la prueba, que es justo lo que
        // quiere simular.
        baseProvider.overrideWith((ref) => base),
        clienteApiProvider.overrideWithValue(ClienteApi(dio: dio)),
        almacenSesionProvider.overrideWithValue(
          AlmacenEnMemoria(
            const Sesion(
              token: 't',
              refresh: 'r',
              sub: 'logistico',
              sucursalId: sucursalStg,
            ),
          ),
        ),
      ],
    );
  }

  test(
    'arrastrar sin conexión: se escribe aquí, va a la cola, no llama a nadie '
    'y sobrevive a cerrar y reabrir la aplicación',
    () async {
      // ---- Por la mañana, con red: bajó el día. -------------------------
      var base = abrirBase();
      await sembrarSucursal(base);
      await sembrarAlmacen(base);
      await sembrarPedido(base, id: 'p-cerca', aGrados: 0.01, peso: 120);
      await sembrarPedido(base, id: 'p-medio', aGrados: 0.05, peso: 80);
      await sembrarPedido(base, id: 'p-lejos', aGrados: 0.40, peso: 60);

      var contenedor = montar(base);
      var tablero = await contenedor.read(tableroProvider.future);
      expect(tablero.sinColocar.total, 3);
      expect(tablero.sinColocar.pedidos.map((p) => p.pedidoId).toList(), [
        'p-cerca',
        'p-medio',
        'p-lejos',
      ], reason: 'el más cerca del almacén primero');

      // ---- Por la tarde, en el patio y sin señal. -----------------------
      final mando = contenedor.read(tableroProvider.notifier);
      final columnaId = await mando.crearColumna('Centro');
      expect(columnaId, startsWith('local-'));

      await mando.colocar(pedidoId: 'p-cerca', columnaId: columnaId);
      await mando.colocar(pedidoId: 'p-medio', columnaId: columnaId);

      // 1. NO SE LLAMÓ A NADIE. Arrastrar no habla con el servidor.
      expect(
        servidor.vistas,
        isEmpty,
        reason: 'arrastrar escribe aquí; la subida va por detrás',
      );

      // 2. Se ve movido, ya.
      tablero = await contenedor.read(tableroProvider.future);
      expect(tablero.columnas.single.pedidos, 2);
      expect(tablero.columnas.single.pesoKg, 200);
      expect(tablero.sinColocar.total, 1);
      expect(
        tablero.deColumna(columnaId).map((t) => t.pedido.pedidoId).toList(),
        ['p-cerca', 'p-medio'],
      );

      // 3. Y está en la cola, en orden, con el cuerpo del contrato.
      final cola = ColaDeSalida(base);
      var lote = await cola.lote();
      expect(lote.map((a) => a.ruta).toList(), [
        '/board/columns?branchId=$sucursalStg',
        '/board/placements/p-cerca',
        '/board/placements/p-medio',
      ]);
      expect(lote.first.provisional, columnaId);
      expect(jsonDecode(lote[1].cuerpo), {
        'columnaId': columnaId,
        'posicion': 1,
      });
      final claves = lote.map((a) => a.clave).toList();

      // ---- Se cierra la aplicación del todo y se vuelve a abrir. --------
      contenedor.dispose();
      await base.close();

      base = abrirBase();
      contenedor = montar(base);
      tablero = await contenedor.read(tableroProvider.future);

      // Las tarjetas siguen donde se dejaron…
      expect(tablero.columnas.single.nombre, 'Centro');
      expect(tablero.columnas.single.pedidos, 2);
      expect(
        tablero.deColumna(columnaId).map((t) => t.pedido.pedidoId).toList(),
        ['p-cerca', 'p-medio'],
      );
      expect(tablero.sinColocar.pedidos.single.pedidoId, 'p-lejos');

      // …y la cola también, con las mismas claves: nada se subió dos veces ni
      // se perdió por el camino.
      lote = await ColaDeSalida(base).lote();
      expect(lote.map((a) => a.clave).toList(), claves);
      expect(lote.every((a) => a.estado == EstadoApunte.pendiente), isTrue);
      expect(servidor.vistas, isEmpty);

      await base.close();
    },
  );

  test('cuando la columna sube, su «local-…» se sustituye en la cola y en el '
      'tablero', () async {
    final base = abrirBase();
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarPedido(base, id: 'p1');
    final contenedor = montar(base);
    await contenedor.read(tableroProvider.future);

    final mando = contenedor.read(tableroProvider.notifier);
    final provisional = await mando.crearColumna('Vista Alegre');
    await mando.colocar(pedidoId: 'p1', columnaId: provisional);

    // Sube la creación de la columna y el servidor devuelve el id de verdad.
    final cola = ColaDeSalida(base);
    final creacion = (await cola.lote()).first;
    await cola.resolver(
      creacion.clave,
      const ResultadoApunte(
        estado: EstadoResultado.aplicado,
        id: 'col-de-verdad',
      ),
    );

    // Sin esto, las colocaciones que van detrás irían a una columna que no
    // existe en ningún sitio y se perderían justo después de subirse.
    final pendientes = await cola.lote();
    expect(pendientes.single.ruta, '/board/placements/p1');
    expect(jsonDecode(pendientes.single.cuerpo), {
      'columnaId': 'col-de-verdad',
      'posicion': 1,
    });

    // Y la pantalla deja de enseñar el provisional.
    await contenedor.read(tableroProvider.notifier).refrescar();
    final tablero = contenedor.read(tableroProvider).value!;
    expect(tablero.columnas.single.id, 'col-de-verdad');
    expect(tablero.columnas.single.esProvisional, isFalse);
    expect(tablero.deColumna('col-de-verdad').single.pedido.pedidoId, 'p1');

    await base.close();
  });

  test('sin sucursal elegida no se enseña «todo»', () async {
    final base = abrirBase();
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    final dio = Dio()..httpClientAdapter = servidor;
    final contenedor = ProviderContainer.test(
      overrides: [
        baseProvider.overrideWith((ref) => base),
        clienteApiProvider.overrideWithValue(ClienteApi(dio: dio)),
        almacenSesionProvider.overrideWithValue(AlmacenEnMemoria()),
      ],
    );

    final tablero = await contenedor.read(tableroProvider.future);
    // No se enseña «todo», que es lo que parecería razonable y sería lo peor:
    // un tablero con las diez sucursales mezcladas ordenaría los pedidos de
    // Holguín por su distancia al almacén de Santiago.
    expect(tablero.problema, 'Elige una sucursal para ver su tablero');
    expect(tablero.columnas, isEmpty);
    expect(tablero.sinColocar.pedidos, isEmpty);
    await base.close();
  });
}
