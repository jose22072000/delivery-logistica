import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/sincro/bajada.dart';
import 'package:reparto/nucleo/sincro/ciclo.dart';
import 'package:reparto/pantallas/informes/vista/pantalla_informes.dart';

import '../../apoyo/base_de_prueba.dart';

/// UN INFORME CUADRADO CON MEDIO PADRÓN ES UN NÚMERO QUE ALGUIEN VA A COBRAR.
///
/// Reportes avisaba de dos cosas: que no se bajó nunca, y que lo bajado tiene
/// más de un día. **No avisaba de la tercera**, que es justamente la del §3 del
/// `CLAUDE.md`: que la última bajada volvió **a medias**.
///
/// Y ahí la marca de frescura SÍ se movió y las tablas SÍ tienen filas, así que
/// las dos guardas de antes contestan que todo está bien. Lo que sale es un
/// total de dinero cuadrado sobre 2.000 clientes de 8.103, en verde, con su
/// botón de exportar a Excel al lado. Es, palabra por palabra, «un número
/// creíble y equivocado, que es lo peor que puede pasarle a un número que
/// alguien va a cobrar».
///
/// El aviso existía desde el 24/09/2026 —`bajadaAMediasProvider`, con el motivo
/// literal de `bajada.dart`— y lo leía un solo sitio: la franja de estado. Una
/// línea de doce puntos arriba del todo, encima de una pantalla de importes.
///
/// **Se siembra DESPUÉS de montar** (§3-ter): el aviso de la bajada a medias
/// llega cuando el ciclo termina, con la pantalla ya abierta. Sembrarlo antes
/// es justo la forma que el §4-bis prohíbe.
void main() {
  setUpAll(() => initializeDateFormatting('es'));

  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  final ahora = DateTime(2026, 9, 24, 11);

  late ProviderContainer contenedor;

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final scope = ProviderScope(
      overrides: [
        baseProvider.overrideWithValue(base),
        relojProvider.overrideWithValue(() => ahora),
      ],
      child: const MaterialApp(home: Scaffold(body: PantallaInformes())),
    );
    await tester.pumpWidget(scope);
    contenedor = ProviderScope.containerOf(
      tester.element(find.byType(PantallaInformes)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  /// Las nueve colecciones con marca de hace un minuto: para las dos guardas de
  /// antes, esto es un aparato perfectamente al día.
  Future<void> bajadaDeHaceUnMinuto() async {
    for (final coleccion in Colecciones.todas) {
      await base
          .into(base.frescura)
          .insertOnConflictUpdate(
            FrescuraCompanion.insert(
              coleccion: coleccion,
              hasta: const Value('2026-09-24T10:59:00.000Z'),
              bajadaAt: Value(DateTime(2026, 9, 24, 10, 59)),
              completa: const Value(true),
            ),
          );
    }
  }

  testWidgets('la última bajada volvió a medias: el informe lo dice, con el '
      'motivo literal del servidor', (tester) async {
    await montar(tester);
    await bajadaDeHaceUnMinuto();
    await tester.pumpAndSettle();

    // Punto de partida: nada que avisar. Las dos guardas viejas están contentas
    // y la pantalla dice, en gris, con qué está cuadrando.
    expect(find.textContaining('no cuadra con el servidor'), findsNothing);
    expect(
      find.textContaining('Cuadrado con'),
      findsOneWidget,
      reason: 'si esto falla, la pantalla ni siquiera cree tener datos',
    );

    // Y AHORA acaba el ciclo, con la pantalla ya delante, y vuelve a medias.
    // El motivo va TAL CUAL lo escribe `bajada.dart`.
    // Por `anotar`, que es como lo pone la aplicación de verdad
    // (`alAcabarElCicloProvider`), y no escribiéndole el estado por detrás.
    contenedor.read(bajadaAMediasProvider.notifier).anotar(
      const ResumenDelCiclo(
        bajada: ResumenDeBajada(
          puestos: 2000,
          quitados: 0,
          completa: false,
          tandas: 50,
          quedoPor:
              'se llegó al tope de 50 tandas y el servidor seguía diciendo '
              'que queda más',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(contenedor.read(bajadaAMediasProvider), isNotNull);

    expect(
      find.textContaining('no está entera'),
      findsOneWidget,
      reason:
          'el informe se cuadró con lo que hay, y lo que hay no es todo: con '
          'medio padrón sale un total creíble y equivocado',
    );
    expect(
      find.textContaining('se llegó al tope de 50 tandas'),
      findsOneWidget,
      reason:
          'el motivo del servidor, literal. «No se pudo traer todo» no le dice '
          'a nadie qué pasó ni qué hacer',
    );

    await desmontar(tester);
  });

  testWidgets('con la bajada entera NO sale ningún aviso', (tester) async {
    // La pareja del §3-quinquies. Sin esto, «arreglarlo» sacando el aviso
    // siempre pasaría la prueba de arriba y dejaría un cartel que nadie lee.
    await montar(tester);
    await bajadaDeHaceUnMinuto();
    await tester.pumpAndSettle();

    expect(contenedor.read(bajadaAMediasProvider), isNull);
    expect(find.textContaining('no está entera'), findsNothing);

    await desmontar(tester);
  });
}
