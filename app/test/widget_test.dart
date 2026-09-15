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
void main() {
  setUpAll(() => initializeDateFormatting('es'));

  Future<void> montar(
    WidgetTester tester, {
    required AlmacenDeSesion almacen,
    bool yaConfigurado = false,
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
            clienteFalso(
              (p) async => RespuestaFalsa(200, <String, Object?>{
                'hasta': '2026-09-14T08:00:00Z',
                'completa': true,
                'truncado': false,
                'cambios': <String, Object?>{},
                'sucursales': <Object?>[],
              }),
            ),
          ),
        ],
        child: const RepartoApp(),
      ),
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
    // LA PRIMERA VEZ. Lo que habia antes era el Panel en ceros mientras las
    // cosas aparecian por detras, y un Panel a cero es indistinguible de una
    // sucursal sin nada que repartir.
    await montar(tester, almacen: AlmacenEnMemoria(sesionDePrueba()));

    expect(find.byType(PantallaConfigurando), findsOneWidget);
    expect(find.text('Configurando Reparto'), findsOneWidget);
    // Y NO el Panel por detras: nada de entrar mientras se configura.
    expect(find.byType(FranjaDeEstado), findsNothing);

    await desmontar(tester);
  });
}
