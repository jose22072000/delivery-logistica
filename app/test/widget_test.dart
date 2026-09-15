import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/navegacion/franja_de_estado.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/acceso/vista/pantalla_acceso.dart';
import 'package:reparto/pantallas/configuracion_inicial/vista/pantalla_configurando.dart';

import 'apoyo/apoyo_sesion.dart';
import 'apoyo/base_de_prueba.dart';
import 'apoyo/servidor_falso.dart';

/// El humo: la aplicacion de verdad, con el REGISTRO de verdad y con el PORTERO
/// puesto.
///
/// Son tres pruebas y no una porque la aplicacion ya no arranca en un solo
/// sitio:
///
///  * sin sesion se entra por la puerta;
///  * con sesion y **con los datos ya bajados** se entra al Panel directo, sin
///    pantalla de espera y sin esperar a la red;
///  * con sesion y el **aparato vacio** se ve «Configurando Reparto», porque
///    entrar la primera vez ES configurarse el aparato.
///
/// **Esto es el humo de la APK y del escritorio.** Aqui no se sustituye
/// `trabajaSinConexionProvider`, asi que corre en el destino que se prepara para
/// quedarse sin senal. El mismo humo visto desde un navegador —sin «Configurando
/// Reparto», sin franja y sin la promesa del dia entero— esta en
/// `test/la_web_no_se_prepara_test.dart`, y va en pareja con este fichero: cada
/// pieza se comprueba en los dos destinos o no se comprueba en ninguno.
void main() {
  setUpAll(() => initializeDateFormatting('es'));

  /// [demora] es lo que tarda el servidor falso en contestar. Por defecto cero
  /// —las pruebas que no miran el camino no quieren esperar— pero la de la
  /// configuracion inicial SI la necesita: sin demora la bajada termina antes
  /// del primer fotograma y la pantalla que se quiere comprobar no llega a
  /// pintarse nunca. Una bajada instantanea no existe fuera de un test.
  Future<void> montarSinAsentar(
    WidgetTester tester, {
    required AlmacenDeSesion almacen,
    bool yaConfigurado = false,
    Duration demora = Duration.zero,
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final base = baseDePrueba();
    addTearDown(base.close);
    if (yaConfigurado) await aparatoYaConfigurado(base);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 14, 8, 30)),
          almacenSesionProvider.overrideWithValue(almacen),
          // Auth falso: la renovacion del arranque contesta un par nuevo.
          dioAuthProvider.overrideWithValue(
            dioFalso((p) async => RespuestaFalsa(200, parDeTokens())),
          ),
          // Y la bajada del dia, contra el servidor falso y sin esperas.
          clienteApiProvider.overrideWithValue(
            clienteFalso((p) async {
              if (demora > Duration.zero) await Future<void>.delayed(demora);
              return RespuestaFalsa(200, <String, Object?>{
                'hasta': '2026-09-14T08:00:00Z',
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

  /// Igual que [montarSinAsentar] pero esperando a que todo se asiente, que es
  /// lo que quieren las dos primeras pruebas.
  Future<void> montar(
    WidgetTester tester, {
    required AlmacenDeSesion almacen,
    bool yaConfigurado = false,
  }) async {
    await montarSinAsentar(
      tester,
      almacen: almacen,
      yaConfigurado: yaConfigurado,
    );
    await tester.pumpAndSettle();
  }

  Future<void> desmontar(WidgetTester tester) async {
    // Desmontar aqui y no en un `tearDown`: las consultas de Drift sueltan un
    // temporizador al cancelarse y flutter_test lo comprueba antes.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  testWidgets('sin sesion guardada: la puerta, no el Panel', (tester) async {
    await montar(tester, almacen: AlmacenEnMemoria());

    expect(find.byType(PantallaAcceso), findsOneWidget);
    expect(find.text('Entrar'), findsWidgets);
    // Y nada del armazon: ni menu al que no se puede ir, ni franja que diria
    // «sin descargar» antes de haber entrado.
    expect(find.byType(FranjaDeEstado), findsNothing);

    await desmontar(tester);
  });

  testWidgets('con sesion Y con datos: al Panel, sin pantalla de espera', (
    tester,
  ) async {
    // EL CASO DE TODOS LOS DIAS MENOS EL PRIMERO. Palabras de Jose: «en caso de
    // q lo tenga arranca normal la apk». Ni «Configurando Reparto», ni esperar a
    // la red: el aparato ya tiene su dia dentro.
    await montar(
      tester,
      almacen: AlmacenEnMemoria(sesionDePrueba()),
      yaConfigurado: true,
    );

    expect(find.text('Panel'), findsWidgets);
    expect(find.byType(FranjaDeEstado), findsOneWidget);
    expect(find.byType(PantallaAcceso), findsNothing);
    expect(
      find.byType(PantallaConfigurando),
      findsNothing,
      reason: 'con datos dentro no se ensena nunca',
    );

    await desmontar(tester);
  });

  testWidgets('con sesion y el aparato VACIO: «Configurando Reparto»', (
    tester,
  ) async {
    // LA PRIMERA VEZ, y son DOS mitades: se ve mientras configura, y se quita
    // cuando acaba. Lo que habia antes era el Panel en ceros mientras las cosas
    // aparecian por detras, y un Panel a cero es indistinguible de una sucursal
    // sin nada que repartir.
    //
    // Se mira SIN dejar que todo se asiente, a proposito: `pumpAndSettle` espera
    // a que el ciclo termine, y entonces la pantalla que se quiere comprobar ya
    // se ha ido. Esta prueba se escribio cuando el ciclo NO ARRANCABA —se
    // quedaba en el 0 % para siempre— y por eso `pumpAndSettle` la dejaba a la
    // vista: pasaba por el fallo, no a pesar de el.
    await montarSinAsentar(
      tester,
      almacen: AlmacenEnMemoria(sesionDePrueba()),
      demora: const Duration(seconds: 1),
    );
    // Con duracion, no un `pump()` a secas: la cadena de antes de la bajada
    // —leer la sesion, abrir la copia de esa persona, contar lo que hay— son
    // varias vueltas de base, y sin dejar correr el reloj el arbol todavia esta
    // vacio y la comprobacion mira una pantalla que aun no se ha pintado.
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(PantallaConfigurando), findsOneWidget);
    expect(find.text('Configurando Reparto'), findsOneWidget);
    // Y NO el Panel por detras: nada de entrar mientras se configura.
    expect(find.byType(FranjaDeEstado), findsNothing);

    // Y LA SEGUNDA MITAD: cuando la bajada termina, se entra. El servidor falso
    // contesta «no hay nada que traer», que para un aparato virgen es una
    // respuesta legitima —una sucursal recien abierta— y cuenta como
    // configurado. Quedarse aqui seria encerrar a esa persona en una barra que
    // ya no se mueve.
    // El reloj tiene que pasar de la demora del servidor falso: `pumpAndSettle`
    // solo pinta mientras haya fotogramas pedidos, y la barra de avance los
    // pide, asi que se asienta con la bajada todavia en vuelo.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
      find.byType(PantallaConfigurando),
      findsNothing,
      reason: 'la configuracion acabo: no se puede quedar la pantalla puesta',
    );
    expect(find.text('Panel'), findsWidgets);

    await desmontar(tester);
  });
}
