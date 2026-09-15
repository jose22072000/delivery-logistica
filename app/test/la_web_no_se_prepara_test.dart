import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/navegacion/franja_de_estado.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/acceso/vista/pantalla_acceso.dart';
import 'package:reparto/pantallas/configuracion_inicial/vista/pantalla_configurando.dart';
import 'package:reparto/pantallas/panel/vista/estado_del_dia.dart';

import 'apoyo/apoyo_sesion.dart';
import 'apoyo/base_de_prueba.dart';
import 'apoyo/servidor_falso.dart';

/// EL APARATO DE TRABAJAR SIN CONEXION **NO SE ENSENA EN WEB**.
///
/// Palabras de Jose, 15/09/2026:
///
/// > «el trabajo sin conexion es solo para las aplicaciones cojone la web
/// > siempre va a estar en internet»
/// > «la web siempre va a tener el internet por q esta en la nube eso es para la
/// > apk y la desktop quitame eso de la web»
///
/// ## Por que TODAS las pruebas de aqui van en pareja
///
/// Cada pieza se comprueba dos veces: **en web no sale** y **en aparato si
/// sale**. Una sola mitad no sirve de nada y es peor que nada:
///
///  * sólo «en web no sale» se cumple igual si alguien borra la pieza entera, y
///    entonces la APK se queda sin lo unico que la hace util en el patio de un
///    almacen;
///  * sólo «en aparato si sale» se cumple igual si alguien quita el `if` de la
///    plataforma, y la web vuelve a ensenar lo de siempre sin que nadie se
///    entere.
///
/// Son las dos mitades juntas las que fijan la linea por donde va. Y por eso la
/// prueba de mutacion es la que de verdad las valida: con
/// `Destino.trabajaSinConexion` clavado a `true` tienen que caerse las de web, y
/// clavado a `false` las de aparato. Si al clavarlo no se cae ninguna, estas
/// pruebas no estan comprobando nada.
///
/// No se compila para web para probar esto: la capacidad se lee por provider
/// (`trabajaSinConexionProvider`), asi que ponerse en el otro destino es
/// sustituirlo. Es exactamente el mismo interruptor que mira el codigo.
void main() {
  setUpAll(() => initializeDateFormatting('es'));

  /// Monta la aplicacion de verdad, con el portero puesto, en el destino que se
  /// pida.
  ///
  /// [enWeb] es lo unico que cambia entre las dos mitades de cada pareja. Todo
  /// lo demas —la base, la sesion, el servidor falso— es identico a proposito:
  /// si cambiara algo mas, la prueba no estaria midiendo la plataforma.
  Future<void> montarSinAsentar(
    WidgetTester tester, {
    required bool enWeb,
    required AlmacenDeSesion almacen,
    bool yaConfigurado = false,
    Duration demora = Duration.zero,
    Size tamano = const Size(1440, 1000),
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final base = baseDePrueba();
    addTearDown(base.close);
    if (yaConfigurado) await aparatoYaConfigurado(base);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // LA UNICA DIFERENCIA ENTRE LAS DOS MITADES.
          trabajaSinConexionProvider.overrideWithValue(!enWeb),
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 15, 8, 30)),
          almacenSesionProvider.overrideWithValue(almacen),
          dioAuthProvider.overrideWithValue(
            dioFalso((p) async => RespuestaFalsa(200, parDeTokens())),
          ),
          clienteApiProvider.overrideWithValue(
            clienteFalso((p) async {
              if (demora > Duration.zero) await Future<void>.delayed(demora);
              return RespuestaFalsa(200, <String, Object?>{
                'hasta': '2026-09-15T08:00:00Z',
                'completa': true,
                'truncado': false,
                'cambios': <String, Object?>{},
                'sucursales': <Object?>[],
              });
            }),
          ),
        ],
        child: const RepartoApp(),
      ),
    );
  }

  Future<void> montar(
    WidgetTester tester, {
    required bool enWeb,
    required AlmacenDeSesion almacen,
    bool yaConfigurado = false,
    Size tamano = const Size(1440, 1000),
  }) async {
    await montarSinAsentar(
      tester,
      enWeb: enWeb,
      almacen: almacen,
      yaConfigurado: yaConfigurado,
      tamano: tamano,
    );
    await tester.pumpAndSettle();
  }

  /// Desmontar aqui y no en un `tearDown`: las consultas de Drift sueltan un
  /// temporizador al cancelarse y flutter_test lo comprueba ANTES de los
  /// `tearDown`. Sin esto, la primera prueba se lleva por delante a las demas.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  // ---------------------------------------------------------------------------
  // 1 · «CONFIGURANDO REPARTO»
  // ---------------------------------------------------------------------------

  group('1 · «Configurando Reparto», la primera vez', () {
    testWidgets('en APARATO SI sale: entrar la primera vez ES configurarse', (
      tester,
    ) async {
      // Sin asentar a proposito: `pumpAndSettle` espera a que la bajada termine
      // y entonces la pantalla que se mira ya se fue.
      await montarSinAsentar(
        tester,
        enWeb: false,
        almacen: AlmacenEnMemoria(sesionDePrueba()),
        demora: const Duration(seconds: 1),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(PantallaConfigurando), findsOneWidget);
      expect(find.text('Configurando Reparto'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await desmontar(tester);
    });

    testWidgets('en WEB no sale: se entra directo y la carga va por detras', (
      tester,
    ) async {
      // Mismo aparato vacio, misma demora del servidor. Lo unico que cambia es
      // el destino.
      await montarSinAsentar(
        tester,
        enWeb: true,
        almacen: AlmacenEnMemoria(sesionDePrueba()),
        demora: const Duration(seconds: 1),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byType(PantallaConfigurando),
        findsNothing,
        reason:
            'quien abre un navegador no se va al patio de ningun almacen: no '
            'hay nada que dejar listo antes de dejarle entrar',
      );
      // Y NO es que se quede en blanco: se entra al Panel mientras la primera
      // bajada sigue en vuelo por detras.
      expect(find.text('Panel'), findsWidgets);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // 2 · «TRAER EL DIA / ENTREGAR EL DIA», la pieza del Panel
  // ---------------------------------------------------------------------------

  group('2 · la pieza de traer y entregar el dia, en el Panel', () {
    testWidgets('en APARATO SI sale', (tester) async {
      await montar(
        tester,
        enWeb: false,
        almacen: AlmacenEnMemoria(sesionDePrueba()),
        yaConfigurado: true,
      );

      expect(find.text('Panel'), findsWidgets);
      expect(find.byType(EstadoDelDia), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('en WEB no sale: no hay dia que traer a mano', (tester) async {
      await montar(
        tester,
        enWeb: true,
        almacen: AlmacenEnMemoria(sesionDePrueba()),
        yaConfigurado: true,
      );

      expect(find.text('Panel'), findsWidgets);
      expect(
        find.byType(EstadoDelDia),
        findsNothing,
        reason: 'en la web se sincroniza solo: no hay dia que traer a mano',
      );
      // Y con ella se va la frase que en un navegador no pasa nunca.
      expect(find.text('Trabajando sin conexión'), findsNothing);
      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // 3 · LA FRANJA DE ESTADO, en las siete pantallas
  // ---------------------------------------------------------------------------

  group('3 · la franja de estado', () {
    testWidgets('en APARATO SI sale, y en las DOS anchuras (caso S8)', (
      tester,
    ) async {
      await montar(
        tester,
        enWeb: false,
        almacen: AlmacenEnMemoria(sesionDePrueba()),
        yaConfigurado: true,
      );
      expect(find.byType(FranjaDeEstado), findsOneWidget);

      await montar(
        tester,
        enWeb: false,
        almacen: AlmacenEnMemoria(sesionDePrueba()),
        yaConfigurado: true,
        tamano: const Size(390, 800),
      );
      expect(find.byType(FranjaDeEstado), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('en WEB no sale, en ninguna de las dos anchuras', (
      tester,
    ) async {
      await montar(
        tester,
        enWeb: true,
        almacen: AlmacenEnMemoria(sesionDePrueba()),
        yaConfigurado: true,
      );
      expect(
        find.byType(FranjaDeEstado),
        findsNothing,
        reason:
            'la franja contesta «¿de que hora son estos datos?», y en un '
            'navegador con internet la respuesta no cambia nunca',
      );

      await montar(
        tester,
        enWeb: true,
        almacen: AlmacenEnMemoria(sesionDePrueba()),
        yaConfigurado: true,
        tamano: const Size(390, 800),
      );
      expect(find.byType(FranjaDeEstado), findsNothing);
      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // 4 · LA PROMESA DEL DIA SIN SENAL, en la pantalla de acceso
  // ---------------------------------------------------------------------------

  group('4 · la promesa del dia entero sin senal, en el acceso', () {
    final laPromesa = find.textContaining(
      'puedes seguir trabajando el día entero sin señal',
    );

    testWidgets('en APARATO SI se promete', (tester) async {
      await montar(tester, enWeb: false, almacen: AlmacenEnMemoria());

      expect(find.byType(PantallaAcceso), findsOneWidget);
      expect(laPromesa, findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('en WEB no se promete: alli seria mentira', (tester) async {
      await montar(tester, enWeb: true, almacen: AlmacenEnMemoria());

      expect(find.byType(PantallaAcceso), findsOneWidget);
      expect(
        laPromesa,
        findsNothing,
        reason:
            'la web se abre desde internet y nadie le prometio a esa persona '
            'un dia entero de nada',
      );
      // Y NO se cambia por otra frase: un hueco vacio es mejor que una linea '
      // puesta para llenarlo.
      expect(
        find.textContaining('Para entrar hace falta conexión'),
        findsNothing,
      );
      await desmontar(tester);
    });

    testWidgets(
      'en APARATO, si el almacen no guarda se dice ANTES de la contrasena',
      (tester) async {
        await montar(
          tester,
          enWeb: false,
          almacen: AlmacenEnMemoria.queNoGuarda(
            'Este aparato no guarda la '
            'sesión.',
          ),
        );

        expect(find.text('Este aparato no guarda la sesión.'), findsOneWidget);
        expect(
          find.textContaining('Avisa a la oficina antes de irte al almacén'),
          findsOneWidget,
        );
        // Y la promesa NO se escribe: o se cumple, o no se promete.
        expect(laPromesa, findsNothing);
        await desmontar(tester);
      },
    );

    testWidgets('en WEB no se sondea el almacen ni se avisa por adelantado', (
      tester,
    ) async {
      // MISMO almacen roto. En la APK eso pinta el recuadro ambar; aqui no,
      // porque lo que ese recuadro viene a desdecir —la promesa— no existe.
      // El fallo de verdad se sigue diciendo, pero cuando PASA: al intentar
      // entrar (`pantalla_acceso.dart`, `_noSeGuardo`).
      await montar(
        tester,
        enWeb: true,
        almacen: AlmacenEnMemoria.queNoGuarda(
          'Este aparato no guarda la '
          'sesión.',
        ),
      );

      expect(find.byType(PantallaAcceso), findsOneWidget);
      expect(
        find.text('Este aparato no guarda la sesión.'),
        findsNothing,
        reason:
            'es un aviso de PREPARARSE para no tener conexion, y eso es lo '
            'que en web no pinta nada',
      );
      expect(
        find.textContaining('Avisa a la oficina antes de irte al almacén'),
        findsNothing,
      );
      await desmontar(tester);
    });
  });
}
