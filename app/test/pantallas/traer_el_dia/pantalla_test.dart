import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/diseno/cajon.dart';
import 'package:reparto/navegacion/franja_de_estado.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/panel/registro.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo_traer_el_dia.dart';

/// EL BOTON EN LA PANTALLA: que se vea, que se pueda dar, y que lo que diga al
/// acabar sea lo que hay.
///
/// Las dos anchuras en las que se mira esto todos los dias: 1440 (el monitor de
/// la oficina) y 390 (el telefono del almacen). **El gesto tiene que estar igual
/// en las dos** — ese era el encargo.
void main() {
  setUpAll(() => initializeDateFormatting('es'));

  late BaseLocal base;
  late RelojFalso reloj;

  setUp(() {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime(2026, 9, 15, 8, 14));
  });

  tearDown(() => base.close());

  Future<ProviderContainer> montar(
    WidgetTester tester, {
    required Future<RespuestaFalsa?> Function(PeticionVista) responder,
    double ancho = 1440,
    double alto = 1000,
    bool hayPista = true,
  }) async {
    tester.view.physicalSize = Size(ancho, alto);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final caja = montarTraerElDia(
      base: base,
      reloj: reloj.leer,
      responder: responder,
      hayPista: hayPista,
    );
    addTearDown(caja.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: caja,
        child: RepartoApp(
          enrutador: crearEnrutador(
            pantallas: [registrarPanel()],
            inicial: '/dashboard',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return caja;
  }

  /// Deja correr el gesto sin `pumpAndSettle`: mientras corre hay una rueda
  /// girando y un cronometro por segundos, y `pumpAndSettle` con eso delante no
  /// vuelve nunca. Se avanza a mano, que es lo que hay que hacer aqui.
  Future<void> dejarCorrer(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  group('donde se ve', () {
    testWidgets('en ESCRITORIO esta arriba del Panel, con su boton', (
      tester,
    ) async {
      await montar(tester, responder: servidorQueTraeElDia);

      expect(
        find.widgetWithText(FilledButton, 'Traer el día'),
        findsOneWidget,
        reason: 'es la accion principal de la pantalla de la manana',
      );
      // Y por encima de las cuatro cifras: lo que no esta arriba no se hace.
      final boton = tester.getTopLeft(find.byType(FilledButton).first).dy;
      final primeraCifra = tester.getTopLeft(find.text('Pedidos sin ruta')).dy;
      expect(boton, lessThan(primeraCifra));

      await desmontar(tester);
    });

    testWidgets('en MOVIL esta igual: mismo sitio y mismo texto', (
      tester,
    ) async {
      await montar(
        tester,
        responder: servidorQueTraeElDia,
        ancho: 390,
        alto: 800,
      );

      expect(find.widgetWithText(FilledButton, 'Traer el día'), findsOneWidget);
      final boton = tester.getTopLeft(find.byType(FilledButton).first).dy;
      final primeraCifra = tester.getTopLeft(find.text('Pedidos sin ruta')).dy;
      expect(boton, lessThan(primeraCifra));

      await desmontar(tester);
    });

    testWidgets('la franja de estado lleva al mismo sitio, sin bajar nada', (
      tester,
    ) async {
      final rutas = <String>[];
      await montar(
        tester,
        responder: (p) async {
          rutas.add(p.ruta);
          return servidorQueTraeElDia(p);
        },
      );

      // Es la segunda puerta, y la que hace que el gesto exista en las otras
      // seis pantallas: donde se lee que los datos estan viejos es donde se
      // arregla.
      await tester.tap(find.byType(FranjaDeEstado));
      await tester.pumpAndSettle();

      expect(find.byType(Cajon), findsOneWidget);
      expect(
        rutas,
        isEmpty,
        reason:
            'mirar lo que se tiene no dispara una bajada; para eso esta el '
            'boton, que se ve',
      );

      await desmontar(tester);
    });
  });

  group('se le da al boton', () {
    testWidgets('abre el cajon, ensena por donde va y acaba con los numeros', (
      tester,
    ) async {
      await montar(tester, responder: servidorQueTraeElDia);

      await tester.tap(find.widgetWithText(FilledButton, 'Traer el día'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // CAJON, tambien en escritorio: es la regla de la casa de delivery.
      expect(find.byType(Cajon), findsOneWidget);

      await dejarCorrer(tester);

      expect(
        find.text('Ya lo tienes'),
        findsNWidgets(2),
        reason:
            'lo dicen el cajon y el banner de debajo: al cerrar el cajon el '
            'Panel tiene que seguir diciendo como quedo',
      );
      expect(
        find.text('1 pedido · 2 clientes · 1 producto'),
        findsWidgets,
        reason: 'los numeros, que es lo que convierte el gesto en confianza',
      );
      expect(find.text('de las 8:14'), findsWidgets);

      await desmontar(tester);
    });

    testWidgets('en MOVIL el cajon ocupa la pantalla entera', (tester) async {
      await montar(
        tester,
        responder: servidorQueTraeElDia,
        ancho: 390,
        alto: 800,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Traer el día'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await dejarCorrer(tester);

      expect(find.byType(Cajon), findsOneWidget);
      expect(
        tester.getSize(find.byType(Cajon)).width,
        390,
        reason: 'un panel de 448 px sobre una pantalla de 390 sale cortado',
      );
      expect(find.text('Ya lo tienes'), findsWidgets);

      await desmontar(tester);
    });

    testWidgets(
      'falta el catalogo: NO dice «ya lo tienes» y dice que se rompe',
      (tester) async {
        await montar(
          tester,
          responder: (p) async {
            if (p.ruta.endsWith('/sync/cambios')) {
              return RespuestaFalsa(
                200,
                cambiosCompletos(sin: <String>[Colecciones.productos]),
              );
            }
            return servidorQueTraeElDia(p);
          },
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Traer el día'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await dejarCorrer(tester);

        expect(
          find.text('Ya lo tienes'),
          findsNothing,
          reason:
              'un aparato que dice «listo» y se va al almacen sin catalogo es '
              'el fallo que este boton existe para evitar',
        );
        expect(find.text('Falta el catálogo de productos'), findsWidgets);
        expect(
          find.textContaining('los pesos van incompletos'),
          findsOneWidget,
          reason: 'y se dice QUE se rompe sin el',
        );
        expect(
          find.textContaining('vuelve a darle al botón'),
          findsOneWidget,
          reason: 'y QUE hacer: un aviso sin eso es una queja',
        );
        // Lo que si bajo se sigue diciendo.
        expect(find.textContaining('2 clientes'), findsWidgets);

        await desmontar(tester);
      },
    );

    testWidgets('sin senal lo dice y no se queda girando', (tester) async {
      final rutas = <String>[];
      await montar(
        tester,
        responder: (p) async {
          rutas.add(p.ruta);
          return servidorQueTraeElDia(p);
        },
        hayPista: false,
      );

      // La pista de `connectivity_plus` **ya no pinta el estado** —eso lo decide
      // si las peticiones llegan (`red/salud.dart`)—, asi que el boton sigue
      // ahi: la pista sirve para no salir en balde cuando se le da.
      await tester.tap(find.widgetWithText(FilledButton, 'Traer el día'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await dejarCorrer(tester);

      expect(rutas, isEmpty);
      expect(find.text('No hay señal'), findsWidgets);
      expect(
        find.textContaining('el aparato dice que no hay red'),
        findsOneWidget,
      );

      await desmontar(tester);
    });
  });
}
