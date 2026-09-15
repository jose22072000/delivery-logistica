import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/actualizacion/comprobador.dart';
import 'package:reparto/nucleo/actualizacion/version_publicada.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

/// Las tres reglas de `docs/actualizaciones.md`, una por una.
void main() {
  const sesion = Sesion(
    token: 'tok',
    refresh: 'r0',
    sub: 'u1',
    sucursalId: 'STG',
  );

  late BaseLocal base;

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// El cuerpo de `GET /api/version` con una versión publicada.
  Map<String, Object?> anuncio({
    String version = '1.5.0',
    int? compilacion = 12,
    Map<String, String> descargas = const {
      'android': 'https://descargas.procovar.cloud/reparto-1.5.0.apk',
    },
  }) => <String, Object?>{
    'version': 'api-abc123',
    'ultima': <String, Object?>{
      'version': version,
      'compilacion': compilacion,
      'notas': 'El cierre de ruta ya no pierde las fotos.',
      'publicadaAt': '2026-09-15T00:00:00Z',
      'descargas': descargas,
    },
  };

  ({ComprobadorDeActualizacion comprobador, ServidorFalso servidor}) montar({
    required Future<RespuestaFalsa?> Function(PeticionVista) responder,
    Plataforma plataforma = Plataforma.android,
    VersionInstalada instalada = const VersionInstalada(
      version: '1.4.0',
      compilacion: 9,
    ),
  }) {
    final servidor = ServidorFalso(responder);
    final almacen = AlmacenEnMemoria(sesion);
    final auth = Dio(BaseOptions(baseUrl: 'https://auth.test'))
      ..httpClientAdapter = servidor;
    final cliente = ClienteApi.montar(
      baseUrl: 'https://api.test/api',
      almacen: almacen,
      renovador: Renovador(auth, almacen),
      esperas: ComprobadorDeActualizacion.sinEsperas,
    );
    cliente.dio.httpClientAdapter = servidor;
    return (
      comprobador: ComprobadorDeActualizacion(
        cliente: cliente,
        base: base,
        plataforma: plataforma,
        instalada: () async => instalada,
      ),
      servidor: servidor,
    );
  }

  Future<void> encolarAlgo() => ColaDeSalida(base).encolar(
    metodo: 'POST',
    ruta: '/api/routes/r1/close',
    cuerpo: const {'entregados': 12},
  );

  // --------------------------------------------------------------- regla 1

  test('REGLA 1: con cola pendiente no se actualiza, y dice cuántas', () async {
    await encolarAlgo();
    await encolarAlgo();

    final m = montar(responder: (p) async => RespuestaFalsa(200, anuncio()));
    final estado = await m.comprobador.comprobar();

    expect(estado, isA<PrimeroSube>());
    expect((estado as PrimeroSube).pendientes, 2);
    // Y sabe cuál es, para poder decir «cuando subas, te espera la 1.5.0».
    expect(estado.publicada.version, '1.5.0');
  });

  test('sin nada pendiente sí se puede, con su enlace', () async {
    final m = montar(responder: (p) async => RespuestaFalsa(200, anuncio()));
    final estado = await m.comprobador.comprobar();

    expect(estado, isA<SePuedeActualizar>());
    expect(
      (estado as SePuedeActualizar).enlace,
      'https://descargas.procovar.cloud/reparto-1.5.0.apk',
    );
  });

  // --------------------------------------------------------------- regla 2

  test('REGLA 2: comprobar no baja ni instala nada; sólo pregunta', () async {
    final m = montar(responder: (p) async => RespuestaFalsa(200, anuncio()));
    await m.comprobador.comprobar();

    // Una sola petición, un GET, y a `/version`. Nada de bajarse el APK.
    expect(m.servidor.vistas.length, 1);
    expect(m.servidor.vistas.single.metodo, 'GET');
    expect(m.servidor.vistas.single.ruta, '/version');
  });

  // --------------------------------------------------------------- regla 3

  test('REGLA 3: en web no se comprueba, y ni se llama al servidor', () async {
    await encolarAlgo(); // aunque haya cola: da igual, aquí no se instala nada
    final m = montar(
      responder: (p) async => RespuestaFalsa(200, anuncio()),
      plataforma: Plataforma.ninguna,
    );

    expect(await m.comprobador.comprobar(), isA<NoAplica>());
    expect(m.servidor.vistas, isEmpty);
  });

  // --------------------------------------------------------------- lo demás

  test('sin red no se dice nada: se mira mañana', () async {
    final m = montar(responder: (p) async => null);
    expect(await m.comprobador.comprobar(), isA<NoSeSupo>());
  });

  test('si el servidor no anuncia ninguna, está al día', () async {
    final m = montar(
      responder: (p) async =>
          RespuestaFalsa(200, {'version': 'api-abc123', 'ultima': null}),
    );
    expect(await m.comprobador.comprobar(), isA<AlDia>());
  });

  test('la misma versión instalada no avisa', () async {
    final m = montar(
      responder: (p) async => RespuestaFalsa(200, anuncio()),
      instalada: const VersionInstalada(version: '1.5.0', compilacion: 12),
    );
    expect(await m.comprobador.comprobar(), isA<AlDia>());
  });

  test('una versión MÁS NUEVA que la publicada tampoco avisa', () async {
    final m = montar(
      responder: (p) async => RespuestaFalsa(200, anuncio()),
      instalada: const VersionInstalada(version: '1.6.0', compilacion: 20),
    );
    expect(await m.comprobador.comprobar(), isA<AlDia>());
  });

  test('sin fichero para esta plataforma no se avisa', () async {
    final m = montar(
      responder: (p) async => RespuestaFalsa(200, anuncio()),
      plataforma: Plataforma.windows,
    );
    expect(await m.comprobador.comprobar(), isA<NoAplica>());
  });

  // --------------------------------------------------- comparar versiones

  group('qué cuenta como más nueva', () {
    test('manda la compilación cuando se saben las dos', () {
      // El número de versión dice lo mismo, pero la compilación subió: es otra.
      expect(
        hayQueActualizar(
          const VersionInstalada(version: '1.5.0', compilacion: 12),
          const VersionPublicada(version: '1.5.0', compilacion: 13),
        ),
        isTrue,
      );
    });

    test('sin compilación se comparan los números, NO el texto', () {
      // "1.10.0" es POSTERIOR a "1.9.0" aunque alfabéticamente vaya antes.
      expect(
        hayQueActualizar(
          const VersionInstalada(version: '1.9.0', compilacion: 0),
          const VersionPublicada(version: '1.10.0'),
        ),
        isTrue,
      );
      expect(
        hayQueActualizar(
          const VersionInstalada(version: '1.10.0', compilacion: 0),
          const VersionPublicada(version: '1.9.0'),
        ),
        isFalse,
      );
    });

    test('un sufijo no la hace más nueva', () {
      expect(
        hayQueActualizar(
          const VersionInstalada(version: '1.5.0', compilacion: 0),
          const VersionPublicada(version: '1.5.0-rc.2'),
        ),
        isFalse,
      );
    });
  });

  group('leer el anuncio', () {
    test('un cuerpo que no es el esperado no revienta el arranque', () {
      expect(VersionPublicada.deJson(null), isNull);
      expect(VersionPublicada.deJson('<html>vaya proxy</html>'), isNull);
      expect(VersionPublicada.deJson(const {'version': ''}), isNull);
    });

    test('una descarga vacía no cuenta como enlace', () {
      final p = VersionPublicada.deJson(const {
        'version': '1.5.0',
        'descargas': {'android': '', 'linux': 'https://x/y.tar.gz'},
      });
      expect(p!.descargaPara(Plataforma.android), isNull);
      expect(p.descargaPara(Plataforma.linux), 'https://x/y.tar.gz');
    });
  });
}
