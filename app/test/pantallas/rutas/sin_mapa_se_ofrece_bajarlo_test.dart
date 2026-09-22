// SIN EL MAPA DESCARGADO, SE DICE Y SE OFRECE BAJARLO.
//
// Jose, 21/09/2026, con el avión puesto y el croquis a secas delante: «y por qué
// sin conexión no tenía el mapa, pon un mensaje que salga ahí la opción de que
// se descargue el mapa».
//
// El croquis funciona sin el paquete —las paradas, su orden y el recorrido se
// dibujan igual—, así que esto no bloquea nada: es un aviso CON SALIDA. Lo que
// no puede pasar es que la pantalla prometa «se ve igual sin señal» y no diga lo
// único que hay que hacer para que eso sea verdad.
//
// Las dos mitades van en pareja, como manda §3-quinquies: sale cuando no hay
// mapa, y NO sale cuando ya está bajado ni en la web (regla 1: allí no existe el
// aparato de sin-conexión).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/mapa/anuncio_de_mapa.dart';
import 'package:reparto/mapa/proveedores_de_mapa.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';
import 'package:reparto/pantallas/rutas/vista/mapa_de_la_ruta.dart';

import 'rutas_a_mano.dart';

void main() {
  Future<void> pintar(
    WidgetTester tester, {
    required bool enElAparato,
    PaqueteGuardado? guardado,
  }) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trabajaSinConexionProvider.overrideWithValue(enElAparato),
          fondoDeCallesProvider.overrideWithValue(const SinCalles()),
          recorridoPorCallesProvider.overrideWithValue(
            const SinCallesQueSeguir(),
          ),
          paqueteGuardadoProvider.overrideWith((ref) async => guardado),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MapaDeLaRuta(
                ruta: rutaAMano(
                  vehiculo: camionAMano(),
                  paradas: [
                    paradaAMano(
                      id: 'p1',
                      cliente: 'Uno',
                      lat: 23.11,
                      lng: -82.37,
                    ),
                    paradaAMano(
                      id: 'p2',
                      cliente: 'Dos',
                      lat: 23.13,
                      lng: -82.35,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('en el APARATO y sin mapa: se dice y se ofrece bajarlo', (
    tester,
  ) async {
    await pintar(tester, enElAparato: true);

    expect(
      find.textContaining('Sin el mapa de Cuba descargado'),
      findsOneWidget,
      reason:
          'NO SE DICE QUE FALTA EL MAPA: el croquis sale a secas y quien lo mira '
          'no tiene forma de saber que las calles se bajan una vez.',
    );
    expect(
      find.widgetWithText(FilledButton, 'Descargar'),
      findsOneWidget,
      reason: 'el aviso tiene que llevar a bajarlo, no sólo contarlo',
    );
  });

  testWidgets('con el mapa YA bajado no se dice nada', (tester) async {
    await pintar(
      tester,
      enElAparato: true,
      guardado: PaqueteGuardado(
        nivel: 'detallado',
        version: '2026-09-21',
        bytes: 95074203,
        sha256: 'da',
        guardadoAt: DateTime(2026, 9, 21, 17),
      ),
    );

    expect(
      find.textContaining('Sin el mapa de Cuba descargado'),
      findsNothing,
      reason:
          'UN AVISO QUE SALE SIEMPRE DEJA DE LEERSE: con el mapa bajado no hay '
          'nada que ofrecer.',
    );
  });

  testWidgets('en la WEB no se habla de descargar nada', (tester) async {
    await pintar(tester, enElAparato: false);

    expect(
      find.textContaining('Sin el mapa de Cuba descargado'),
      findsNothing,
      reason:
          'REGLA 1: en un navegador no existe el aparato de sin-conexión, así '
          'que ofrecer un mapa para bajar es explicar algo que ahí no pasa.',
    );
  });
}
