import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/nucleo/sincro/bajada.dart';
import 'package:reparto/nucleo/sincro/ciclo.dart';
import 'package:reparto/nucleo/sincro/identidad_del_aparato.dart';
import 'package:reparto/nucleo/sincro/huerfanos.dart';
import 'package:reparto/nucleo/sincro/subida.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';

/// EL CICLO al recuperar la senal: renovar → subir → bajar.
///
/// Todo con reloj y red inyectados. Ni un `sleep`, ni un `Future.delayed`, ni un
/// `pumpAndSettle`: lo que se comprueba es el ORDEN de lo que sale a la red y
/// cuantas veces sale, y eso se mira en la lista del servidor falso.
void main() {
  late BaseLocal base;
  late RelojFalso reloj;
  late ColaDeSalida cola;
  late AlmacenEnMemoria almacen;

  setUp(() {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime(2026, 9, 15, 16, 4));
    cola = ColaDeSalida(base, reloj: reloj.leer);
    almacen = AlmacenEnMemoria(
      const Sesion(token: 't-viejo', refresh: 'r0', sub: 'u1'),
    );
  });

  // El alta del aparato tiene su propio fichero; aqui se da por hecha.
  setUp(() => aparatoYaDeAlta(base));

  tearDown(() => base.close());

  /// Lo que contesta un servidor que va bien: refresh, subida y bajada.
  Future<RespuestaFalsa?> servidorQueVaBien(PeticionVista p) async {
    if (p.ruta.endsWith('/refresh')) {
      return RespuestaFalsa(200, <String, Object?>{
        'token': 't-nuevo',
        'refresh_token': 'r1',
        'sub': 'u1',
      });
    }
    if (p.ruta.endsWith('/subida')) {
      final cuerpo = p.cuerpo! as Map<String, Object?>;
      final apuntes = cuerpo['apuntes']! as List<Object?>;
      return RespuestaFalsa(200, <String, Object?>{
        'resultados': [
          for (final a in apuntes)
            {
              'clave': (a! as Map<String, Object?>)['clave'],
              'estado': 'aplicado',
            },
        ],
      });
    }
    if (p.ruta.endsWith('/almacenes')) {
      return RespuestaFalsa(200, <String, Object?>{'sucursales': <Object?>[]});
    }
    // La bajada por diferencias.
    return RespuestaFalsa(200, <String, Object?>{
      'hasta': '2026-09-15T16:05:00Z',
      'completa': true,
      'truncado': false,
      'cambios': <String, Object?>{
        'customers': <String, Object?>{
          'puestos': <Object?>[
            <String, Object?>{
              'id': 'c-1',
              'name': 'Yasmani',
              'lat': 20.02,
              'lng': -75.82,
            },
          ],
          'quitados': <Object?>[],
        },
      },
    });
  }

  ({
    CicloDeSincronizacion ciclo,
    ServidorFalso servidor,
    Renovador renovador,
    List<String> muertes,
  })
  montar(
    Future<RespuestaFalsa?> Function(PeticionVista) responder, {
    bool haySesion = true,
  }) {
    final servidor = ServidorFalso(responder);
    final auth = Dio(BaseOptions(baseUrl: 'https://auth.test/api/auth'))
      ..httpClientAdapter = servidor;
    final renovador = Renovador(auth, almacen);

    ClienteApi contra(String baseUrl) {
      final cliente = ClienteApi.montar(
        baseUrl: baseUrl,
        almacen: almacen,
        renovador: renovador,
        // Sin esperas: los reintentos de 1 s, 4 s, 15 s y 60 s en una prueba son
        // un temporizador colgado que hace fallar por lo que no es.
        esperas: const <Duration>[],
      );
      cliente.dio.httpClientAdapter = servidor;
      return cliente;
    }

    final muertes = <String>[];
    return (
      ciclo: CicloDeSincronizacion(
        almacen: almacen,
        renovador: renovador,
        subida: Subida(
          cliente: contra('https://sync.test'),
          cola: cola,
          aparato: IdentidadDelAparato(base),
          base: base,
          quienEsta: () async => (await almacen.leer())?.sub,
        ),
        bajada: Bajada(
          cliente: contra('https://api.test'),
          base: base,
          frescura: RegistroDeFrescura(base, reloj: reloj.leer),
          reloj: reloj.leer,
        ),
        huerfanos: Huerfanos(base),
        cola: cola,
        haySesion: () => haySesion,
        alMorirLaSesion: () => muertes.add('murio'),
      ),
      servidor: servidor,
      renovador: renovador,
      muertes: muertes,
    );
  }

  /// Sólo las rutas que importan, en el orden en que salieron.
  List<String> ordenDe(ServidorFalso servidor) => [
    for (final p in servidor.vistas)
      if (p.ruta.endsWith('/refresh'))
        'renovar'
      else if (p.ruta.endsWith('/subida'))
        'subir'
      else if (p.ruta.endsWith('/sync/cambios'))
        'bajar',
  ];

  group('vuelve la red', () {
    test('sube lo pendiente y baja lo nuevo, EN ESE ORDEN', () async {
      await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes/local-9f3a/results',
        cuerpo: <String, Object?>{'resultado': 'entregado'},
      );

      final m = montar(servidorQueVaBien);
      final resumen = await m.ciclo.ahora(motivo: 'volvio la red');

      expect(resumen.bien, isTrue, reason: '$resumen');
      expect(resumen.pasos, [
        PasoDelCiclo.renovar,
        PasoDelCiclo.subir,
        PasoDelCiclo.bajar,
      ]);

      // LO QUE DE VERDAD IMPORTA: el orden en el que salio a la red.
      //
      // Renovar antes de subir, porque ocho horas sin cobertura dejan el token
      // caducado y la cola saldria con el viejo: 401 y el dia dentro del
      // telefono. Y subir antes de bajar, porque bajar primero pisa con la foto
      // del servidor lo que el aparato tiene sin subir.
      expect(ordenDe(m.servidor), ['renovar', 'subir', 'bajar']);

      // Y el efecto, no sólo la peticion: el apunte quedo aplicado y el cliente
      // que trajo la bajada esta en la base.
      expect(await base.cuantosPendientes(), 0);
      expect(await base.select(base.customers).get(), hasLength(1));
    });

    test('con la cola vacia no se manda una subida en balde', () async {
      final m = montar(servidorQueVaBien);
      final resumen = await m.ciclo.ahora(motivo: 'volvio la red');

      expect(resumen.bien, isTrue);
      expect(resumen.subidos, 0);
      expect(ordenDe(m.servidor), [
        'renovar',
        'bajar',
      ], reason: 'una subida sin nada dentro es una peticion regalada');
    });

    test('dos avisos seguidos son UN SOLO ciclo, no dos', () async {
      await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes/r-1/results',
        cuerpo: <String, Object?>{'resultado': 'entregado'},
      );

      // El segundo aviso llega mientras el primero todavia corre: es lo que pasa
      // de verdad cuando el telefono coge y suelta la antena dos veces seguidas.
      final m = montar(servidorQueVaBien);
      final primero = m.ciclo.ahora(motivo: 'volvio la red');
      final segundo = m.ciclo.ahora(motivo: 'volvio la red otra vez');

      expect(
        identical(primero, segundo),
        isTrue,
        reason: 'el segundo aviso se engancha al ciclo que ya va',
      );

      await Future.wait(<Future<ResumenDelCiclo>>[primero, segundo]);

      expect(
        ordenDe(m.servidor),
        ['renovar', 'subir', 'bajar'],
        reason:
            'una vez cada cosa: dos ciclos serian dos subidas del mismo lote',
      );
      expect(
        m.renovador.renovacionesPedidas,
        1,
        reason:
            'y UNA sola renovacion: dos con el mismo refresh se leen como '
            'robo y revocan todas las sesiones de la cuenta (identidad.md)',
      );
      expect(m.ciclo.enVuelo, isFalse, reason: 'y el candado queda suelto');
    });

    test(
      'un gesto que llega DESPUÉS de subir no espera al temporizador: se da '
      'otra vuelta',
      () async {
        // EL FALLO DE LOS 50 SEGUNDOS, 17/09/2026.
        //
        // El ciclo es renovar → subir → bajar. Un gesto que llega cuando la
        // vuelta ya pasó por «subir» no viaja en ella: se engancha, se entera de
        // su resultado, y su apunte se queda en la cola hasta el temporizador —
        // dos minutos en la web, cinco en la APK. Medido en producción con un
        // arrastre en el tablero: **50 segundos** en llegar al servidor.
        //
        // Jose: «¿por qué se demora en traer esas cosas tanto tiempo si debe ser
        // en tiempo real todo esto cuando tenga internet?».
        // El gesto entra JUSTO DESPUÉS del paso de subir, que es el momento
        // exacto del fallo. Se encola desde el propio servidor falso, cuando
        // llega la petición de bajar: encolarlo antes no reproduce nada, porque
        // entonces sí viaja en esa vuelta (y así estaba escrita la primera
        // versión de esta prueba, que pasaba sin probar nada).
        var yaSeEncolo = false;
        final m = montar((p) async {
          if (p.ruta.endsWith('/sync/cambios') && !yaSeEncolo) {
            yaSeEncolo = true;
            await cola.encolar(
              metodo: 'PUT',
              ruta: '/api/board/placements/p-1',
              cuerpo: <String, Object?>{'columnaId': 'c-1', 'posicion': 1},
            );
          }
          return servidorQueVaBien(p);
        });

        await m.ciclo.ahora(motivo: 'toco el reloj');
        // La segunda vuelta la lanza el ciclo solo, sin temporizador y sin que
        // nadie vuelva a pedirla.
        for (var i = 0; i < 40 && await base.cuantosPendientes() > 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }

        expect(
          await base.cuantosPendientes(),
          0,
          reason:
              'el gesto tiene que estar arriba YA, no dentro de dos minutos: '
              'es lo que distingue «en vivo» de «a golpe de reloj»',
        );
        expect(
          ordenDe(m.servidor).where((p) => p == 'subir').length,
          1,
          reason:
              'UNA subida, la de la segunda vuelta. La primera no manda ninguna '
              'porque su cola estaba vacía, y una subida sin nada dentro es una '
              'petición regalada',
        );
        expect(
          ordenDe(m.servidor).where((p) => p == 'bajar').length,
          2,
          reason: 'dos vueltas enteras, la segunda lanzada por el propio ciclo',
        );
        expect(
          m.renovador.renovacionesPedidas,
          1,
          reason:
              'y UNA sola renovación en las dos vueltas: dos con el mismo '
              'refresh se leen como robo y revocan todas las sesiones',
        );
      },
    );

    test('acabando de entrar no se renueva dos veces seguidas', () async {
      // El arranque y la pantalla de acceso traen el par recien hecho. Renovar
      // otra vez dos dedos despues es una ida y vuelta regalada por la conexion
      // de alla, y una rotacion del refresh que no hacia falta.
      final m = montar(servidorQueVaBien);
      final resumen = await m.ciclo.ahora(
        motivo: 'al entrar',
        yaSeRenovo: true,
      );

      expect(resumen.bien, isTrue, reason: '$resumen');
      expect(resumen.pasos, [PasoDelCiclo.subir, PasoDelCiclo.bajar]);
      expect(m.renovador.renovacionesPedidas, 0);
      expect(ordenDe(m.servidor), ['bajar']);
    });

    test('cuando termina uno se puede correr otro', () async {
      // El candado no puede quedarse puesto: si se quedara, el aparato no
      // volveria a sincronizar hasta reinstalar.
      final m = montar(servidorQueVaBien);
      await m.ciclo.ahora();
      await m.ciclo.ahora();
      expect(m.renovador.renovacionesPedidas, 2);
    });
  });

  group('sin sesion', () {
    test('no se intenta NADA: ni renovar, ni subir, ni bajar', () async {
      await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes/r-1/results',
        cuerpo: <String, Object?>{'resultado': 'entregado'},
      );

      final m = montar(servidorQueVaBien, haySesion: false);
      final resumen = await m.ciclo.ahora(motivo: 'volvio la red');

      expect(resumen.sinSesion, isTrue);
      expect(resumen.bien, isFalse);
      expect(resumen.pasos, isEmpty);
      expect(
        m.servidor.vistas,
        isEmpty,
        reason:
            'entrar exige conexion y ahi manda el portero; sin sesion el '
            'ciclo se calla y no toca la red',
      );
      expect(
        await base.cuantosPendientes(),
        1,
        reason: 'y la cola se queda entera',
      );
    });
  });

  group('cuando falla', () {
    test('se cae la red al subir: la cola sigue COMPLETA', () async {
      for (var i = 1; i <= 3; i++) {
        await cola.encolar(
          metodo: 'POST',
          ruta: '/api/routes/r-$i/results',
          cuerpo: <String, Object?>{'resultado': 'entregado'},
        );
      }

      final m = montar((p) async {
        if (p.ruta.endsWith('/refresh')) {
          return RespuestaFalsa(200, <String, Object?>{
            'token': 't-nuevo',
            'refresh_token': 'r1',
            'sub': 'u1',
          });
        }
        // La subida se corta: el aparato dijo que habia wifi y no salio un
        // paquete. Es el caso de Cuba, no un caso raro.
        return null;
      });

      final resumen = await m.ciclo.ahora(motivo: 'volvio la red');

      expect(resumen.bien, isFalse);
      expect(resumen.fallo, isA<FalloDeRed>());
      expect(resumen.pasos, [
        PasoDelCiclo.renovar,
      ], reason: 'se renovo, se intento subir y ahi se paro');
      expect(
        await base.cuantosPendientes(),
        3,
        reason: 'NADA se da por subido: los tres apuntes siguen pendientes',
      );
      expect(
        ordenDe(m.servidor),
        isNot(contains('bajar')),
        reason:
            'y NO se baja detras: bajar sin haber subido pisa el trabajo '
            'del dia con la foto del servidor',
      );
    });

    test('se cae la red al bajar: lo ya subido queda, y nada mas', () async {
      await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes/r-1/results',
        cuerpo: <String, Object?>{'resultado': 'entregado'},
      );

      final m = montar((p) async {
        if (p.ruta.endsWith('/sync/cambios')) return null;
        return servidorQueVaBien(p);
      });

      final resumen = await m.ciclo.ahora();

      expect(resumen.fallo, isA<FalloDeRed>());
      expect(resumen.subidos, 1);
      expect(resumen.pasos, [PasoDelCiclo.renovar, PasoDelCiclo.subir]);
      expect(
        await base.select(base.customers).get(),
        isEmpty,
        reason: 'una bajada que falla no deja la base peor que antes',
      );
    });

    test('un refresh que el servidor ya no acepta saca a la persona', () async {
      final m = montar((p) async {
        if (p.ruta.endsWith('/refresh')) {
          return RespuestaFalsa(401, <String, Object?>{
            'mensaje': 'Ese refresh ya se usó.',
          });
        }
        return servidorQueVaBien(p);
      });

      final resumen = await m.ciclo.ahora();

      expect(resumen.fallo, isA<SesionMuerta>());
      expect(resumen.pasos, isEmpty);
      expect(
        m.muertes,
        ['murio'],
        reason:
            'si no se avisa al portero, el reloj seguiria disparando '
            'ciclos contra una sesion que ya no existe',
      );
      expect(ordenDe(m.servidor), ['renovar']);
    });
  });

  group('en web, donde el almacen no guarda nada', () {
    test('sin par guardado se sigue igual: manda la cookie', () async {
      // `AlmacenDeSesion` en web devuelve `null` SIEMPRE. Si eso parara el
      // ciclo, la web no subiria nunca.
      almacen = AlmacenEnMemoria();
      final m = montar(servidorQueVaBien);
      final resumen = await m.ciclo.ahora();

      expect(resumen.bien, isTrue, reason: '$resumen');
      expect(m.renovador.renovacionesPedidas, 0);
      expect(ordenDe(m.servidor), ['bajar']);
    });
  });
}
