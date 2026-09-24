import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/panel/registro.dart';

import '../../apoyo/base_de_prueba.dart';

/// EL PANEL NO PUEDE DECIR «TODO AL DÍA» CON TRABAJO COLGADO DEBAJO.
///
/// El 24/09/2026 la franja de estado aprendió a nombrar dos cosas que hasta
/// entonces no salían en ninguna pantalla: el **trabajo huérfano**
/// (`trabajoHuerfanoProvider`) y la **bajada que volvió a medias**
/// (`bajadaAMediasProvider`). Bien.
///
/// Pero la franja es una línea de 12 puntos arriba del todo, y **justo debajo,
/// en el Panel, sigue la pieza grande**: `EstadoDelDia`. Ésa se arma sólo con
/// la cola (`sinSubirProvider`) y con la frescura, así que con una ruta armada
/// sin señal cuyo apunte se perdió decía, en verde y a tamaño titular:
///
///     Todo al día
///     Los datos son de ahora mismo y no queda nada sin enviar.
///
/// Es la MISMA pantalla diciendo dos cosas contrarias, y la que se lee es la
/// grande. Palabras de Jose el 16/09/2026, enumerando las tres pantallas que
/// mentían a la vez: «el Panel: Todo al día. No queda nada sin enviar». La
/// franja tapó la primera; ésta seguía abierta.
///
/// **Se siembra DESPUÉS de montar** (`CLAUDE.md` §3-ter): lo que hay que
/// comprobar es que la pieza se entera de lo que aparece con la pantalla
/// delante, no de lo que ya estaba cuando se pintó.
void main() {
  setUpAll(() => initializeDateFormatting('es'));

  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  final ahora = DateTime(2026, 9, 24, 10, 30);

  Future<void> montar(WidgetTester tester, {DateTime? reloj}) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => reloj ?? ahora),
        ],
        child: RepartoApp(
          enrutador: crearEnrutador(
            pantallas: [registrarPanel()],
            inicial: '/dashboard',
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

  /// El aparato al día de verdad: las nueve colecciones bajadas hace un minuto.
  /// Sin esto no se llega nunca a «Todo al día», que es justo el estado que hay
  /// que poner a prueba.
  Future<void> alDia() async {
    for (final coleccion in Colecciones.todas) {
      await base
          .into(base.frescura)
          .insertOnConflictUpdate(
            FrescuraCompanion.insert(
              coleccion: coleccion,
              hasta: const Value('2026-09-24T10:29:00.000Z'),
              bajadaAt: Value(DateTime(2026, 9, 24, 10, 29)),
              completa: const Value(true),
            ),
          );
    }
  }

  testWidgets('una ruta armada sin señal y sin apunte: el Panel NO puede decir '
      '«Todo al día»', (tester) async {
    await montar(tester);
    await alDia();
    await tester.pumpAndSettle();

    // Punto de partida: sin nada colgado, «Todo al día» es verdad y se dice.
    expect(find.text('Todo al día'), findsOneWidget);

    // Y AHORA aparece el trabajo colgado, con la pantalla ya montada. Es el
    // caso del 16/09/2026 trasladado a una ruta: se armó sin señal —lleva
    // `local-…`—, su apunte se descartó, y `Huerfanos.volverAEncolar` sólo sabe
    // rehacer zonas del tablero, así que **nada la va a subir nunca**.
    // POR LA API DE DRIFT Y NO CON `customStatement`, que es como la escribe el
    // armador de rutas. No es un detalle de estilo: un `customStatement` **no
    // avisa a los streams de Drift**, así que el aviso no se encendería y la
    // prueba pasaría por el motivo equivocado.
    await base
        .into(base.routes)
        .insert(RoutesCompanion.insert(id: 'local-9f3a2b7c'));
    await tester.pumpAndSettle();

    expect(
      find.text('Todo al día'),
      findsNothing,
      reason:
          'hay una ruta que sólo existe en este teléfono y no la va a subir '
          'nadie: decir «Todo al día» es exactamente la pantalla que Jose '
          'enumeró el 16/09/2026',
    );
    expect(
      find.text(
        'Los datos son de ahora mismo y no queda nada sin enviar. Se mantiene '
        'solo mientras haya señal.',
      ),
      findsNothing,
      reason: 'ni la explicación, que es la frase que de verdad se lee',
    );

    // Y SE NOMBRA QUÉ ES. «Hay trabajo sin enviar» no le dice a nadie dónde
    // mirar; «1 ruta» sí.
    expect(find.textContaining('1 ruta'), findsWidgets);

    await desmontar(tester);
  });

  testWidgets('sin nada colgado el aviso NO sale: un aviso que sale siempre '
      'deja de leerse', (tester) async {
    await montar(tester);
    await alDia();
    await tester.pumpAndSettle();

    // La pareja obligatoria del §3-quinquies. Una ruta con id de verdad —la
    // que bajó del servidor— no es trabajo colgado y no puede encender nada.
    await base
        .into(base.routes)
        .insert(RoutesCompanion.insert(id: 'r-de-verdad'));
    await tester.pumpAndSettle();

    expect(find.text('Todo al día'), findsOneWidget);
    expect(find.textContaining('no va a subir'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('el reloj del teléfono se fue hacia atrás: ni «Todo al día» ni '
      'quitarle el botón de traer el día', (tester) async {
    // El teléfono se apagó en la calle y volvió con el reloj cuatro días atrás.
    // La marca de la bajada la puso el servidor y es POSTERIOR a «ahora», así
    // que `ahora.difference(bajadaAt)` sale negativo, `EstadoFrescura` lo lee
    // como «reciente» y esta pieza se plantaba en «Todo al día» — verde y sin
    // botón, con los pedidos de anteayer dentro.
    await montar(tester, reloj: DateTime(2026, 9, 20, 9));
    await alDia();
    await tester.pumpAndSettle();

    expect(
      find.text('Todo al día'),
      findsNothing,
      reason:
          'con el reloj detrás no se sabe de cuándo son los datos: darlos por '
          '«de ahora mismo» es el número creíble y equivocado',
    );
    expect(
      find.text('Traer el día'),
      findsWidgets,
      reason:
          'y sobre todo el botón sigue ahí: `todoAlDia` no ofrece ninguno, así '
          'que el reloj movido le quitaba al repartidor el único gesto con el '
          'que se arreglaba',
    );

    await desmontar(tester);
  });
}
