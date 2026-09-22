// EN LA WEB, SINCRONIZACIÓN NO PIDE NADA Y NO HABLA DE APARATOS.
//
// Lo medido en producción el 22/09/2026, con la pantalla abierta por su URL en
// un navegador:
//
//   GET /sync/estado?sucursal=… → 401     treinta veces en poco más de un minuto
//
// El sincronizador habla con aparatos dados de alta y un navegador no lo es, así
// que el `401` no se arregla esperando: el cliente daba la sesión por muerta, el
// portero rebotaba a `/acceso?volverA=/sincronizacion`, se entraba otra vez y se
// volvía a pedir. **Un rechazo permanente contra un reintentador es un bucle, no
// una defensa** — y por debajo, la pantalla se quedaba para siempre en «Cargando
// el estado de los aparatos…», que es además lo que la regla 1 de `CLAUDE.md` no
// deja enseñar en un navegador: ahí no hay ni aparato ni cola.
//
// Las pruebas van EN PAREJA (§3-quinquies): una que en la web no sale ni una
// petición, y su gemela de que en el aparato sí sale. Sin la segunda, la primera
// la deja verde cualquiera que rompa la pantalla entera.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/diseno/insignia.dart';
import 'package:reparto/navegacion/pantallas.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/sincronizacion/datos/panel_sincronizacion.dart';
import 'package:reparto/pantallas/sincronizacion/registro.dart';
import 'package:reparto/pantallas/sincronizacion/vista/pantalla_sincronizacion.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo_sincronizacion.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  final ahora = DateTime(2026, 9, 14, 10, 42);

  late BaseLocal base;
  late SincroFalso servidor;

  setUp(() {
    base = baseDePrueba();
    servidor = SincroFalso(
      estadoJson(
        aparatos: [
          aparatoJson(
            aparato: 'ap-palma',
            persona: 'María',
            sucursal: 'b-palma',
            nombre: 'Teléfono de Palma',
            pendientes: 12,
          ),
        ],
        bandeja: [
          rechazoJson(rechazo: 'r1', motivo: 'Ese pedido ya va en otra ruta.'),
        ],
      ),
    );
  });
  tearDown(() => base.close());

  /// Monta la pantalla por su ruta, en el destino que se le diga.
  ///
  /// `trabajaSinConexionProvider` sobrescrito es **exactamente lo que ve quien
  /// abre un navegador** — lo dice el propio provider en
  /// `nucleo/plataforma.dart`—, y es la única forma de ejercitar las reglas de
  /// la web sin compilar para web.
  Future<void> montar(WidgetTester tester, {required bool comoAparato}) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
          clienteSyncProvider.overrideWithValue(clienteDePrueba(servidor)),
          trabajaSinConexionProvider.overrideWithValue(comoAparato),
        ],
        child: RepartoApp(
          enrutador: crearEnrutador(
            pantallas: [registrarSincronizacion()],
            // La constante, no el literal: una prueba que copia la dirección
            // del código que prueba no comprueba la dirección (§5).
            inicial: PantallaSincronizacion.ruta,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  testWidgets('EN LA WEB no sale ni una petición al sincronizador', (
    tester,
  ) async {
    await montar(tester, comoAparato: false);

    // ESTO ES LA CORRECCIÓN ENTERA. Cero, no «pocas»: una sola basta para que
    // el 401 eche la sesión y el portero rebote, y entonces vuelve a pedir.
    expect(
      servidor.cuantas,
      0,
      reason:
          'LA WEB ESTÁ PIDIENDO /sync/estado. Ese camino contesta 401 a un '
          'navegador —no es un aparato dado de alta— y el rechazo no mejora '
          'reintentando: echa la sesión, el portero rebota a /acceso, se '
          'vuelve a entrar y se vuelve a pedir. Treinta veces en un minuto, '
          'medido en producción el 22/09/2026.',
    );

    // Y se queda así: aunque pase el tiempo, nadie reintenta.
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    expect(servidor.cuantas, 0, reason: 'alguien reintenta con el tiempo');

    await desmontar(tester);
  });

  testWidgets('EN LA WEB no se habla de aparatos ni de cola', (tester) async {
    await montar(tester, comoAparato: false);

    // Lo que sí se ve: de quién es esta pantalla y qué pasa aquí en su lugar.
    expect(find.text(TextosDeSincronizacion.enLaWeb), findsOneWidget);

    // Y lo que no. El subtítulo de la pantalla («qué aparato lleva sin subir,
    // qué le queda pendiente y qué se le rechazó») describe una copia y una
    // cola que en un navegador no existen — regla 1.
    expect(find.text(TextosDeSincronizacion.explicacion), findsNothing);
    // El cartel eterno que se veía en producción.
    expect(find.text(TextosDeSincronizacion.cargando), findsNothing);
    // Ni la tabla, ni sus insignias, ni la bandeja, ni el botón de recargar
    // algo que no se lee.
    expect(find.byType(Insignia), findsNothing);
    expect(find.text('Teléfono de Palma'), findsNothing);
    expect(find.text('Ese pedido ya va en otra ruta.'), findsNothing);
    expect(find.text(TextosDeSincronizacion.bandejaTitulo), findsNothing);
    expect(find.text('Actualizar'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('LA GEMELA: en el aparato sí pide y sí enseña el panel', (
    tester,
  ) async {
    await montar(tester, comoAparato: true);

    expect(
      servidor.cuantas,
      greaterThan(0),
      reason:
          'en la APK y en el escritorio esta pantalla es la razón de ser del '
          'sincronizador: si aquí tampoco pide, lo de arriba está verde por '
          'una pantalla rota, no por la guarda',
    );
    expect(find.text('Teléfono de Palma'), findsOneWidget);
    expect(find.text(TextosDeSincronizacion.explicacion), findsOneWidget);
    expect(find.text(TextosDeSincronizacion.enLaWeb), findsNothing);

    await desmontar(tester);
  });

  test('en la web, Sincronización NO está en el menú', () async {
    // El registro de verdad, no el de la prueba: `enElMenu` sale de
    // `Destino.trabajaSinConexion` y hay que verlo caer.
    expect(
      pantallasDeLaAplicacion()
          .where((p) => p.enElMenu)
          .map((p) => p.ruta)
          .contains(PantallaSincronizacion.ruta),
      isTrue,
      reason: 'en el aparato SÍ va en el menú: es donde se mira quién no sube',
    );

    final enLaWeb = await Destino.comoSiFueraWeb(
      () async => pantallasDeLaAplicacion()
          .where((p) => p.enElMenu)
          .map((p) => p.ruta)
          .toSet(),
    );
    expect(
      enLaWeb.contains(PantallaSincronizacion.ruta),
      isFalse,
      reason:
          'SINCRONIZACIÓN SALE EN EL MENÚ DE LA WEB. Lo que enseña son '
          'aparatos y su cola, que es el aparato de prepararse para quedarse '
          'sin señal: de la APK y del escritorio. Va con '
          '`enElMenu: Destino.trabajaSinConexion`.',
    );
  });

  test('la ruta SIGUE registrada, también en la web', () async {
    // A propósito, igual que el mapa sin conexión: quitar la ruta dejaría a
    // quien tenga el enlace guardado delante de «No hay ninguna pantalla en
    // /sincronizacion», que no explica nada. Llega, y lee por qué.
    final enLaWeb = await Destino.comoSiFueraWeb(
      () async => pantallasDeLaAplicacion().map((p) => p.ruta).toSet(),
    );
    expect(enLaWeb, contains(PantallaSincronizacion.ruta));
  });
}
