import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/fallos.dart';

import '../../apoyo/servidor_falso.dart';

/// La tabla de la regla 5, comprobada renglon a renglon.
void main() {
  const sesion = Sesion(
    token: 'tok',
    refresh: 'r0',
    sub: 'u1',
    sucursalId: 'PAL',
  );

  ({ClienteApi cliente, AlmacenEnMemoria almacen, ServidorFalso servidor})
  montar(Future<RespuestaFalsa?> Function(PeticionVista) responder) {
    final servidor = ServidorFalso(responder);
    final almacen = AlmacenEnMemoria(sesion);
    final auth = Dio(BaseOptions(baseUrl: 'https://auth.test'))
      ..httpClientAdapter = servidor;
    final cliente = ClienteApi.montar(
      baseUrl: 'https://api.test',
      almacen: almacen,
      renovador: Renovador(auth, almacen),
      // Sin esperas de verdad: lo que se prueba es la POLITICA, no el reloj.
      esperar: (_) async {},
    );
    cliente.dio.httpClientAdapter = servidor;
    return (cliente: cliente, almacen: almacen, servidor: servidor);
  }

  test('200: dentro', () async {
    final m = montar((p) async => RespuestaFalsa(200, {'total': 12}));
    expect(
      await m.cliente.pedir<Map<String, Object?>>('/api/orders'),
      {'total': 12},
    );
  });

  test('la sesion va en la cabecera', () async {
    final m = montar((p) async => RespuestaFalsa(200, const {}));
    await m.cliente.pedir<Map<String, Object?>>('/api/orders');
    expect(m.servidor.vistas.single.cabeceras['Authorization'], 'Bearer tok');
  });

  test('4xx que no es 401: Rechazo con el mensaje LITERAL', () async {
    const literal =
        '3 de los 8 pedidos ya están en otra ruta. Vuelve a elegirlos.';
    final m = montar(
      (p) async => RespuestaFalsa(409, {'mensaje': literal}),
    );

    try {
      await m.cliente.mandar<Map<String, Object?>>(
        'POST',
        '/api/routes',
        const {},
      );
      fail('tenia que lanzar');
    } on Rechazo catch (e) {
      expect(e.codigo, 409);
      expect(
        e.mensaje,
        literal,
        reason: 'se pinta tal cual, sin envolver en «Ha ocurrido un error»',
      );
    }

    // Un Rechazo NO se reintenta jamas.
    expect(m.servidor.vistas, hasLength(1));
  });

  test('500: FalloDeRed, se reintenta y los tokens NO se tocan', () async {
    var vueltas = 0;
    final m = montar((p) async {
      vueltas++;
      return RespuestaFalsa(500, {'mensaje': 'la base no responde'});
    });

    await expectLater(
      m.cliente.pedir<Map<String, Object?>>('/api/orders'),
      throwsA(isA<FalloDeRed>()),
    );
    expect(
      vueltas,
      esperasPorDefecto.length + 1,
      reason: 'el primer intento mas los cuatro reintentos',
    );
    expect(
      (await m.almacen.leer())?.refresh,
      'r0',
      reason: 'un 500 no mata la sesion (regla 5)',
    );
  });

  test('sin red: FalloDeRed y los tokens siguen ahi', () async {
    final m = montar((p) async => null);
    await expectLater(
      m.cliente.pedir<Map<String, Object?>>('/api/orders'),
      throwsA(isA<FalloDeRed>()),
    );
    expect((await m.almacen.leer())?.refresh, 'r0');
  });

  test('un 500 que se arregla solo acaba entrando', () async {
    var vueltas = 0;
    final m = montar((p) async {
      vueltas++;
      if (vueltas < 3) return RespuestaFalsa(503);
      return RespuestaFalsa(200, {'ok': true});
    });
    expect(
      await m.cliente.pedir<Map<String, Object?>>('/api/orders'),
      {'ok': true},
    );
  });

  test('401: renueva UNA vez y reintenta UNA vez', () async {
    var renovado = false;
    final m = montar((p) async {
      if (p.ruta == '/refresh') {
        renovado = true;
        return RespuestaFalsa(200, {'token': 'nuevo', 'refresh': 'r1'});
      }
      if (!renovado) return RespuestaFalsa(401, const {});
      return RespuestaFalsa(200, {'ok': true});
    });

    expect(
      await m.cliente.pedir<Map<String, Object?>>('/api/orders'),
      {'ok': true},
    );
    expect(m.servidor.cuantas('POST', '/refresh'), 1);
    expect(
      m.servidor.cuantas('GET', '/api/orders'),
      2,
      reason: 'el original y UN reenvio',
    );
    expect((await m.almacen.leer())?.token, 'nuevo');
  });

  test('401 que sigue siendo 401 despues de renovar: SesionMuerta', () async {
    final m = montar((p) async {
      if (p.ruta == '/refresh') {
        return RespuestaFalsa(200, {'token': 'nuevo', 'refresh': 'r1'});
      }
      return RespuestaFalsa(401, const {});
    });

    await expectLater(
      m.cliente.pedir<Map<String, Object?>>('/api/orders'),
      throwsA(isA<SesionMuerta>()),
    );
    expect(
      m.servidor.cuantas('GET', '/api/orders'),
      2,
      reason: 'no se entra en un bucle de renovar y reintentar',
    );
  });

  test('401 con la red caida al renovar: NO mata la sesion', () async {
    final m = montar((p) async {
      if (p.ruta == '/refresh') return null; // sin red justo al renovar
      return RespuestaFalsa(401, const {});
    });

    await expectLater(
      m.cliente.pedir<Map<String, Object?>>('/api/orders'),
      throwsA(isA<FalloDeRed>()),
    );
    expect(
      (await m.almacen.leer())?.refresh,
      'r0',
      reason: 'no se pudo comprobar: se conserva y se reintenta luego',
    );
  });

  test('la sucursal mirada viaja en su cabecera', () async {
    final servidor = ServidorFalso(
      (p) async => RespuestaFalsa(200, const {}),
    );
    final almacen = AlmacenEnMemoria(sesion);
    final auth = Dio()..httpClientAdapter = servidor;
    final cliente = ClienteApi.montar(
      baseUrl: 'https://api.test',
      almacen: almacen,
      renovador: Renovador(auth, almacen),
      sucursalMirada: () => 'HOL',
      esperar: (_) async {},
    );
    cliente.dio.httpClientAdapter = servidor;

    await cliente.pedir<Map<String, Object?>>('/api/orders');
    expect(servidor.vistas.single.cabeceras['x-sucursal-id'], 'HOL');
  });
}
