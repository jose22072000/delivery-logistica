import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/configuracion_inicial/vista/pantalla_configurando.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

/// EL MOTIVO DE QUE LA BAJADA SE CORTARA LLEGA A LA PANTALLA, LITERAL.
///
/// `bajada.dart` sabe decir POR QUÉ se quedó a medias —«se llegó al tope de N
/// tandas», «no avanzó ni la marca ni el cursor», «dijo que quedaba más y no
/// mandó la marca»— y lo escribe en `ResumenDeBajada.quedoPor`. El portero lo
/// miraba para no dejar entrar, **y ahí lo tiraba**: la pantalla pintaba «El
/// servidor no terminó de mandar los datos», que no nombra nada y con lo que no
/// se puede hacer nada.
///
/// Es el §3 del `CLAUDE.md` a medio cumplir: se comprueba el tope, sí, pero lo
/// que se dice después no sirve para decidir si vale la pena volver a darle o
/// hay que llamar a alguien.
///
/// Las dos pruebas van en pareja: con corte se dice el motivo, y **sin corte no
/// se dice que hubo uno** — inventar un corte que no hubo manda a mirar al
/// servidor cuando el problema es otro.
///
/// El tercer texto de `_elMotivo` —«La bajada terminó y el aparato sigue
/// vacío»— no tiene prueba aquí y se dice por qué: el portero llega a él cuando
/// la bajada vino entera y `_elAparatoEstaVacio()` sigue diciendo que sí, y con
/// un servidor falso que contesta 200 la marca de frescura se escribe igual, así
/// que el aparato deja de estar vacío. Lo que sí se prueba es que **no se dice
/// un corte que no hubo**, que es la mitad que engañaba.
void main() {
  setUpAll(() => initializeDateFormatting('es'));

  Future<void> montar(
    WidgetTester tester, {
    required Map<String, Object?> loQueContesta,
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final base = baseDePrueba();
    addTearDown(base.close);
    // SIN `aparatoYaConfigurado`: el aparato nace vacío, que es lo que manda al
    // portero a «Configurando Reparto».

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 24, 8, 30)),
          almacenSesionProvider.overrideWithValue(
            AlmacenEnMemoria(sesionDePrueba()),
          ),
          dioAuthProvider.overrideWithValue(
            dioFalso((p) async => RespuestaFalsa(200, parDeTokens())),
          ),
          clienteApiProvider.overrideWithValue(
            clienteFalso((p) async => RespuestaFalsa(200, loQueContesta)),
          ),
        ],
        child: const RepartoApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  testWidgets('el servidor corta la bajada: se dice POR QUÉ, con sus palabras', (
    tester,
  ) async {
    // `truncado` sin `hasta`: el servidor dice que queda más y no manda por
    // dónde seguir. `bajada.dart` para ahí y lo escribe en `quedoPor`.
    await montar(
      tester,
      loQueContesta: const <String, Object?>{
        'completa': true,
        'truncado': true,
        'cambios': <String, Object?>{},
        'sucursales': <Object?>[],
      },
    );

    expect(find.byType(PantallaConfigurando), findsOneWidget);
    expect(find.text('La configuración se quedó a medias.'), findsOneWidget);

    expect(
      find.textContaining('el servidor dijo que quedaba mas y no mando la marca'),
      findsOneWidget,
      reason:
          'EL MOTIVO LITERAL, el que escribe `bajada.dart`. Aquí se tiraba y '
          'se pintaba «El servidor no terminó de mandar los datos», que no '
          'nombra lo que se quedó fuera y no sirve para decidir nada '
          '(`CLAUDE.md` §3)',
    );
    expect(find.text('Reintentar'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('sin corte NO se avisa de ninguno: la bajada entera entra y ya', (
    tester,
  ) async {
    // El caso de todos los días. Si esto enseñara un corte, el aviso saldría
    // siempre y dejaría de leerse — §3-quinquies, y ya pasó una vez.
    await montar(
      tester,
      loQueContesta: const <String, Object?>{
        'hasta': '2026-09-24T08:00:00Z',
        'completa': true,
        'truncado': false,
        'cambios': <String, Object?>{},
        'sucursales': <Object?>[],
      },
    );

    expect(find.byType(PantallaConfigurando), findsNothing);
    expect(find.textContaining('La bajada se cortó'), findsNothing);

    await desmontar(tester);
  });

}
