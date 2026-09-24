import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/aviso_de_version_nueva.dart'
    show abridorDeLaDescargaProvider;
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/entrada_por_accesos.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/acceso/vista/pantalla_acceso.dart';

import '../../apoyo/apoyo_accesos.dart';
import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

/// LAS DOS SALIDAS DE LA PUERTA: bajarse el APK e irse al portal.
///
/// Jose, 24/09/2026:
///
/// > «recuerda q tienes q poner en el login q puedan descargar la aplicacion y
/// > entrar a procovar.cloud […] recuerda q se pueden hacer las dos, para q
/// > puedan descargar la apk y instalarla»
///
/// ## Las dos parejas, y por que van en pareja (`CLAUDE.md` §1 y §4)
///
/// Cada decision se comprueba **dos veces**, porque una sola mitad es peor que
/// nada. El molde es `test/la_web_no_se_prepara_test.dart`:
///
///  1. **El destino.** «Sale en la web» y «NO sale en el aparato». Sin la
///     segunda mitad, un boton de «descarga la APK» dentro de la propia APK
///     pasaria todas las pruebas — y eso es exactamente lo que prohibe la §1.
///     Sin la primera, borrar el bloque entero tambien pasaria.
///  2. **El anuncio.** «Con anuncio sale, y con su tamano» y «sin anuncio NO
///     sale un enlace muerto». Sin la segunda, un dia sin nada colgado deja en
///     la puerta un boton que lleva a un 404.
///
/// La linea que separa los destinos se lee por provider
/// (`trabajaSinConexionProvider`), asi que ponerse en el otro lado es
/// sustituirlo: no hace falta compilar para web.
void main() {
  late AlmacenEnMemoria almacen;

  setUp(() => almacen = AlmacenEnMemoria());

  /// El cuerpo de `GET /api/version` tal y como lo manda la api
  /// (`docs/actualizaciones.md` §2). Los 77.646.816 bytes son los del APK de
  /// verdad del 24/09/2026.
  Map<String, Object?> anuncio({
    String version = '1.0.1',
    Map<String, Object?>? descargas = const <String, Object?>{
      'android':
          'https://archivos.procovar.cloud/reparto/apk/reparto-1.0.1.apk',
    },
    Map<String, Object?>? ficheros = const <String, Object?>{
      'android': <String, Object?>{
        'bytes': 77646816,
        'sha256':
            '5656565656565656565656565656565656565656565656565656565656565656',
      },
    },
  }) => <String, Object?>{
    'version': 'api-abc123',
    'ultima': <String, Object?>{
      'version': version,
      'compilacion': 2,
      'descargas': ?descargas,
      'ficheros': ?ficheros,
    },
  };

  /// Lo que se pidio abrir fuera de la aplicacion, en orden.
  late List<String> abiertos;

  /// Cuantas veces se le pregunto al servidor por lo que hay colgado.
  late int preguntas;

  /// Monta la pantalla de acceso suelta, en el destino que se pida.
  ///
  /// [enWeb] es lo UNICO que cambia entre las dos mitades de cada pareja. Todo
  /// lo demas es identico a proposito: si cambiara algo mas, la prueba no
  /// estaria midiendo el destino.
  Future<void> montar(
    WidgetTester tester, {
    required bool enWeb,
    Future<RespuestaFalsa?> Function(PeticionVista)? version,
  }) async {
    abiertos = <String>[];
    preguntas = 0;

    // Alta a proposito: la tarjeta de la puerta con las dos salidas no cabe en
    // los 800x600 de por defecto, y lo que queda debajo del pliegue no se puede
    // pulsar — `tap` avisa de que no acerto y la prueba falla por el sitio
    // equivocado.
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final base = baseDePrueba();
    addTearDown(base.close);
    // Sembrado DENTRO del cuerpo y no en el `setUp`: lo que Drift deja empezado
    // fuera del reloj falso no avanza dentro, y la prueba se cuelga en vez de
    // fallar (`CLAUDE.md` §5).
    await aparatoYaConfigurado(base);

    // La puerta de la web, con Accesos caido a proposito: desde que la web entra
    // sola por el login unico, el formulario SOLO se ve cuando el login unico
    // falla. Sin esto la mitad de web se pasaria mirando una rueda de
    // «entrando», o sea sin comprobar nada.
    final navegador = NavegadorFalso(
      direccion: 'https://ejemplo.test/acceso?sso=error',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // LA UNICA DIFERENCIA ENTRE LAS DOS MITADES.
          trabajaSinConexionProvider.overrideWithValue(!enWeb),
          baseProvider.overrideWithValue(base),
          almacenSesionProvider.overrideWithValue(almacen),
          navegadorProvider.overrideWithValue(navegador),
          entradaPorAccesosProvider.overrideWithValue(
            entradaFalsa(
              navegador,
              (p) async => RespuestaFalsa(401, <String, Object?>{'user': null}),
            ),
          ),
          dioAuthProvider.overrideWithValue(
            dioFalso((p) async => RespuestaFalsa(200, parDeTokens())),
          ),
          clienteApiProvider.overrideWithValue(
            clienteFalso(
              (p) async => RespuestaFalsa(200, <String, Object?>{
                'hasta': '2026-09-24T08:00:00Z',
                'completa': true,
                'truncado': false,
                'cambios': <String, Object?>{},
                'sucursales': <Object?>[],
              }),
            ),
          ),
          // EL ANUNCIO. Se cuenta cuantas veces se pregunta: en el aparato tiene
          // que ser cero, y eso no se ve mirando la pantalla.
          clienteVersionProvider.overrideWithValue(
            clienteFalso((p) async {
              preguntas++;
              return version == null
                  ? RespuestaFalsa(200, anuncio())
                  : await version(p);
            }),
          ),
          // Abrir un enlace, sin sistema operativo al otro lado: lo que hay que
          // poder comprobar es QUE SE PIDIO ABRIR ESE enlace.
          abridorDeLaDescargaProvider.overrideWithValue(
            (enlace) async => abiertos.add(enlace),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: PantallaAcceso())),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Desmontar aqui y no en un `tearDown`: las consultas de Drift sueltan un
  /// temporizador al cancelarse y flutter_test lo comprueba ANTES de los
  /// `tearDown`.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  final elBotonDeDescarga = find.textContaining('Descargar la aplicación');
  final elBotonDelPortal = find.text('Ir a procovar.cloud');

  // ---------------------------------------------------------------------------
  // 1 · QUIEN VE LAS DOS SALIDAS
  // ---------------------------------------------------------------------------

  group('1 · el destino', () {
    testWidgets('en WEB salen las dos: la aplicacion no esta instalada', (
      tester,
    ) async {
      await montar(tester, enWeb: true);

      expect(find.byType(PantallaAcceso), findsOneWidget);
      expect(elBotonDeDescarga, findsOneWidget);
      expect(elBotonDelPortal, findsOneWidget);
      await desmontar(tester);
    });

    testWidgets(
      'en el APARATO no sale NINGUNA, y ni siquiera se pregunta al servidor',
      (tester) async {
        // Mismo anuncio, mismo servidor. Lo unico que cambia es el destino.
        await montar(tester, enWeb: false);

        expect(find.byType(PantallaAcceso), findsOneWidget);
        expect(
          elBotonDeDescarga,
          findsNothing,
          reason:
              'ofrecerle bajarse el APK a quien ya lo tiene abierto es lo que '
              'prohibe la §1; de la version nueva se encarga el aviso del '
              'armazon, que ademas sabe que no se actualiza con cola pendiente',
        );
        expect(
          elBotonDelPortal,
          findsNothing,
          reason:
              'el portal son las demas aplicaciones WEB: mandar a un navegador '
              'externo desde la puerta de la unica que trabaja sin senal es '
              'sacar a alguien de lo unico que le va a funcionar en el patio '
              'de un almacen. Y en escritorio, ademas, el APK no se instala',
        );
        expect(
          preguntas,
          0,
          reason:
              'el `if` del destino va DELANTE de mirar el provider: en la APK y '
              'en el escritorio no sale ni una peticion desde la puerta',
        );
        await desmontar(tester);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 2 · EL ANUNCIO: con el, con su tamano; sin el, nada de enlaces muertos
  // ---------------------------------------------------------------------------

  group('2 · el anuncio', () {
    testWidgets('CON anuncio: dice cuanto pesa y lleva a la url del anuncio', (
      tester,
    ) async {
      await montar(tester, enWeb: true);

      // 77.646.816 bytes son «77,6 MB». El tamano va EN el boton: pulsar sin
      // saber que son 77 MB es la tarde de datos de alguien.
      expect(
        find.text('Descargar la aplicación para Android (77,6 MB)'),
        findsOneWidget,
      );
      expect(preguntas, 1);

      await tester.tap(elBotonDeDescarga);
      await tester.pumpAndSettle();

      expect(
        abiertos,
        <String>[
          'https://archivos.procovar.cloud/reparto/apk/reparto-1.0.1.apk',
        ],
        reason:
            'la url sale del anuncio y no escrita a mano: escribirla aqui seria '
            'una direccion que caduca con la siguiente version publicada',
      );
      // Y se dice que version es, para que quien ya tenga una sepa si le aporta.
      expect(find.textContaining('Versión 1.0.1'), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('SIN anuncio no hay boton de descarga, pero el portal sigue', (
      tester,
    ) async {
      // `ultima: null` es lo normal mientras no haya nada colgado.
      await montar(
        tester,
        enWeb: true,
        version: (p) async =>
            RespuestaFalsa(200, <String, Object?>{'version': 'api-abc123'}),
      );

      expect(
        elBotonDeDescarga,
        findsNothing,
        reason: 'un boton que lleva a un 404 es peor que no ofrecer nada',
      );
      expect(
        elBotonDelPortal,
        findsOneWidget,
        reason: 'el portal no depende de la api: sale igual',
      );
      await desmontar(tester);
    });

    testWidgets('con anuncio pero SIN fichero de Android, tampoco', (
      tester,
    ) async {
      // Hay version colgada, pero para Android no hay nada: la clave no viene.
      await montar(
        tester,
        enWeb: true,
        version: (p) async => RespuestaFalsa(
          200,
          anuncio(
            descargas: const <String, Object?>{
              'windows': 'https://archivos.procovar.cloud/reparto.zip',
            },
            ficheros: null,
          ),
        ),
      );

      expect(elBotonDeDescarga, findsNothing);
      expect(elBotonDelPortal, findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('SIN RED tampoco se pinta un enlace: no saber no se cuenta', (
      tester,
    ) async {
      await montar(tester, enWeb: true, version: (p) async => null);

      expect(elBotonDeDescarga, findsNothing);
      expect(elBotonDelPortal, findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('si el servidor contesta un 404, igual: nada de boton', (
      tester,
    ) async {
      await montar(
        tester,
        enWeb: true,
        version: (p) async => RespuestaFalsa(404, <String, Object?>{}),
      );

      expect(elBotonDeDescarga, findsNothing);
      expect(elBotonDelPortal, findsOneWidget);
      await desmontar(tester);
    });

    testWidgets(
      'anuncio SIN «ficheros»: sale el boton, sin numero inventado, y se dice '
      'que no se sabe cuanto pesa',
      (tester) async {
        // Una api anterior al 22/09/2026 no manda `ficheros`. El enlace es bueno,
        // asi que el boton sale; lo que no se hace es inventarse un tamano.
        await montar(
          tester,
          enWeb: true,
          version: (p) async => RespuestaFalsa(200, anuncio(ficheros: null)),
        );

        expect(
          find.text('Descargar la aplicación para Android'),
          findsOneWidget,
        );
        expect(find.textContaining('MB'), findsNothing);
        expect(
          find.textContaining('El servidor no dice cuánto pesa'),
          findsOneWidget,
          reason:
              'con la conexion de alla, un enlace sin tamano se avisa; lo que '
              'no se hace es escribir «? MB» ni un numero creible y equivocado',
        );
        await desmontar(tester);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 3 · EL PORTAL
  // ---------------------------------------------------------------------------

  testWidgets('3 · el portal lleva a procovar.cloud, la entrada comun', (
    tester,
  ) async {
    await montar(tester, enWeb: true);

    await tester.tap(elBotonDelPortal);
    await tester.pumpAndSettle();

    expect(abiertos, <String>['https://procovar.cloud']);
    await desmontar(tester);
  });
}
