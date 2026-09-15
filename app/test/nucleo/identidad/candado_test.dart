import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/fallos.dart';

import '../../apoyo/servidor_falso.dart';

/// EL TEST MAS IMPORTANTE DEL PROYECTO.
///
/// El refresh es de un solo uso. Dos renovaciones a la vez presentan el mismo,
/// el servidor lo lee como robo y **revoca todas las sesiones de la cuenta**. En
/// reparto pasa de verdad: el telefono recupera senal y dispara la cola entera
/// de golpe.
///
/// Lo que se cuenta aqui es lo mismo que hay que mirar en el registro del
/// servidor despues de quitar el modo avion: **cuantas veces se pidio
/// `/refresh`**. Si no es una, el caso falla aunque todo lo demas salga.
void main() {
  Sesion sesionCon(String refresh) => Sesion(
    token: 'tok-$refresh',
    refresh: refresh,
    sub: 'u1',
    sucursalId: 'PAL',
    roles: const ['OPERADOR'],
  );

  group('el candado del renovador', () {
    test('20 renovaciones a la vez producen UNA sola llamada a /refresh', () async {
      var emitidos = 0;
      final servidor = ServidorFalso((p) async {
        // El servidor se demora: sin demora las 20 llamadas se serializarian
        // solas y el test no probaria nada.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (p.ruta == '/refresh') {
          final cuerpo = p.cuerpo! as Map<String, Object?>;
          if (cuerpo['refresh'] != 'r0') {
            // Un refresh ya gastado. Es exactamente lo que el servidor de verdad
            // lee como robo.
            return RespuestaFalsa(401, {
              'mensaje':
                  'El refresh ya se usó. Todas las sesiones quedan revocadas.',
            });
          }
          emitidos++;
          return RespuestaFalsa(200, {
            'token': 'tok-r$emitidos',
            'refresh': 'r$emitidos',
          });
        }
        return RespuestaFalsa(404);
      });

      final dio = Dio(BaseOptions(baseUrl: 'https://auth.test'))
        ..httpClientAdapter = servidor;
      final almacen = AlmacenEnMemoria(sesionCon('r0'));
      final renovador = Renovador(dio, almacen);

      // Las veinte salen con LA MISMA sesion en la mano, que es lo que pasa
      // cuando la cola entera se dispara a la vez.
      final vista = sesionCon('r0');
      final resultados = await Future.wait([
        for (var i = 0; i < 20; i++) renovador.renovar(vista),
      ]);

      expect(
        servidor.cuantas('POST', '/refresh'),
        1,
        reason: 'el servidor sólo puede haber visto UNA renovacion',
      );
      expect(renovador.renovacionesPedidas, 1);

      // Y las veinte se llevan el MISMO par nuevo: las 19 que llegaron tarde
      // reutilizaron el resultado en vez de lanzar la suya.
      expect(resultados.map((s) => s.refresh).toSet(), {'r1'});
      expect((await almacen.leer())!.refresh, 'r1');
    });

    test(
      'sin la comparacion del refresh serian 20 renovaciones EN FILA',
      () async {
        // Este test documenta POR QUE hacen falta las dos mitades. Aqui cada
        // llamada trae la sesion que el almacen tiene en ese momento —es decir,
        // se salta la comparacion— y el resultado es que el servidor ve veinte
        // renovaciones seguidas. Con `Lock` y todo.
        var emitidos = 0;
        final servidor = ServidorFalso((p) async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          emitidos++;
          return RespuestaFalsa(200, {
            'token': 'tok$emitidos',
            'refresh': 'r$emitidos',
          });
        });
        final dio = Dio(BaseOptions(baseUrl: 'https://auth.test'))
          ..httpClientAdapter = servidor;
        final almacen = AlmacenEnMemoria(sesionCon('r0'));
        final renovador = Renovador(dio, almacen);

        for (var i = 0; i < 20; i++) {
          final actual = await almacen.leer();
          await renovador.renovar(actual!);
        }

        expect(
          servidor.cuantas('POST', '/refresh'),
          20,
          reason: 'el Lock solo no evita esto: por eso se compara el refresh',
        );
      },
    );

    test('401 en el refresh: sesion muerta y almacen vacio', () async {
      final servidor = ServidorFalso(
        (p) async => RespuestaFalsa(401, {'mensaje': 'El refresh ya se usó.'}),
      );
      final dio = Dio(BaseOptions(baseUrl: 'https://auth.test'))
        ..httpClientAdapter = servidor;
      final almacen = AlmacenEnMemoria(sesionCon('r0'));
      final renovador = Renovador(dio, almacen);

      await expectLater(
        renovador.renovar(sesionCon('r0')),
        throwsA(isA<SesionMuerta>()),
      );
      expect(await almacen.leer(), isNull);
    });

    test('500 en el refresh: los tokens SE QUEDAN (caso I6)', () async {
      final servidor = ServidorFalso((p) async => RespuestaFalsa(500));
      final dio = Dio(BaseOptions(baseUrl: 'https://auth.test'))
        ..httpClientAdapter = servidor;
      final almacen = AlmacenEnMemoria(sesionCon('r0'));
      final renovador = Renovador(dio, almacen);

      await expectLater(
        renovador.renovar(sesionCon('r0')),
        throwsA(isA<FalloDeRed>()),
      );
      expect(
        (await almacen.leer())?.refresh,
        'r0',
        reason: 'una caida pasajera no puede dejar a alguien fuera en la calle',
      );
    });

    test('sin red en el refresh: los tokens SE QUEDAN', () async {
      final servidor = ServidorFalso((p) async => null);
      final dio = Dio(BaseOptions(baseUrl: 'https://auth.test'))
        ..httpClientAdapter = servidor;
      final almacen = AlmacenEnMemoria(sesionCon('r0'));
      final renovador = Renovador(dio, almacen);

      await expectLater(
        renovador.renovar(sesionCon('r0')),
        throwsA(isA<FalloDeRed>()),
      );
      expect((await almacen.leer())?.refresh, 'r0');
    });

    test('un fallo NO deja el candado puesto', () async {
      // Una renovacion fallida que dejara el candado echado impediria cualquier
      // intento posterior: el aparato muerto hasta reinstalar.
      var caidas = 0;
      final servidor = ServidorFalso((p) async {
        if (caidas++ < 1) return null; // la primera, sin red
        return RespuestaFalsa(200, {'token': 't2', 'refresh': 'r2'});
      });
      final dio = Dio(BaseOptions(baseUrl: 'https://auth.test'))
        ..httpClientAdapter = servidor;
      final almacen = AlmacenEnMemoria(sesionCon('r0'));
      final renovador = Renovador(dio, almacen);

      await expectLater(
        renovador.renovar(sesionCon('r0')),
        throwsA(isA<FalloDeRed>()),
      );
      final segunda = await renovador.renovar(sesionCon('r0'));
      expect(segunda.refresh, 'r2');
    });

    test('el mensaje literal del servidor llega a la pantalla', () async {
      final servidor = ServidorFalso(
        (p) async => RespuestaFalsa(401, {
          'mensaje':
              'El refresh ya se usó. Todas las sesiones quedan revocadas.',
        }),
      );
      final dio = Dio(BaseOptions(baseUrl: 'https://auth.test'))
        ..httpClientAdapter = servidor;
      final renovador = Renovador(dio, AlmacenEnMemoria(sesionCon('r0')));

      try {
        await renovador.renovar(sesionCon('r0'));
        fail('tenia que lanzar');
      } on SesionMuerta catch (e) {
        expect(
          e.detalle,
          'El refresh ya se usó. Todas las sesiones quedan revocadas.',
        );
      }
    });
  });

  group('el candado, desde la cola entera (caso I1)', () {
    test('20 peticiones que reciben 401 a la vez: UNA renovacion y todas pasan', () async {
      var renovado = false;
      final servidor = ServidorFalso((p) async {
        if (p.ruta == '/refresh') {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          renovado = true;
          return RespuestaFalsa(200, {'token': 'nuevo', 'refresh': 'r1'});
        }
        // El token de acceso caduco en las ocho horas sin conexion. Hasta que
        // no se renueve, todo es 401.
        if (!renovado) return RespuestaFalsa(401, {'mensaje': 'caducado'});
        if (p.cabeceras['Authorization'] != 'Bearer nuevo') {
          return RespuestaFalsa(401, {'mensaje': 'token viejo'});
        }
        return RespuestaFalsa(200, {'ok': true});
      });

      final almacen = AlmacenEnMemoria(sesionCon('r0'));
      final auth = Dio(BaseOptions(baseUrl: 'https://auth.test'))
        ..httpClientAdapter = servidor;
      final renovador = Renovador(auth, almacen);
      final cliente = ClienteApi.montar(
        baseUrl: 'https://api.test',
        almacen: almacen,
        renovador: renovador,
      );
      cliente.dio.httpClientAdapter = servidor;

      final respuestas = await Future.wait([
        for (var i = 0; i < 20; i++)
          cliente.pedir<Map<String, Object?>>('/api/orders/$i'),
      ]);

      expect(
        servidor.cuantas('POST', '/refresh'),
        1,
        reason:
            'el telefono pilla senal y dispara la cola entera: UNA renovacion',
      );
      expect(respuestas, hasLength(20));
      expect(respuestas.every((r) => r['ok'] == true), isTrue);
    });
  });
}
