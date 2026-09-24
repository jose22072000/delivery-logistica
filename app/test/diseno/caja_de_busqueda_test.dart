// LA CAJA DE BUSCAR, QUE FILTRA SEGÚN SE ESCRIBE.
//
// Dos quejas del 22/09/2026, y son la misma:
//
//   «tengo q dar enter para q el filtro funcione»
//
// y, medido en el asistente de rutas: se teclea `CHAPLIN` y el campo se queda
// en `CH` y filtra por eso. Letra a letra con 400 ms entre teclas sí entra
// entera.
//
// Las pruebas de aquí son de TIEMPO: se escribe sin Intro, se avanza el reloj
// del `tester` y se mira si filtró. El reloj de un `testWidgets` no corre solo,
// así que un temporizador que no se avance es un temporizador que no existe.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/caja_de_busqueda.dart';

/// Un anfitrión como los de verdad: guarda el filtro, y cuando la caja le dice
/// que busque **se lo cree y se lo devuelve por `valor`**. Ese viaje de ida y
/// vuelta es justo donde se perdían las letras.
class _Anfitrion extends StatefulWidget {
  const _Anfitrion({
    required this.filtro,
    required this.busquedas,
    this.aplicaSolo = true,
  });

  final ValueNotifier<String> filtro;

  /// Todo lo que ha salido de la caja, en orden. Es lo que se cuenta.
  final List<String> busquedas;

  /// `false` = el filtro NO adopta lo que le mandan; lo hace la prueba a mano,
  /// para poder soltar el eco tarde y a propósito.
  final bool aplicaSolo;

  @override
  State<_Anfitrion> createState() => _AnfitrionState();
}

class _AnfitrionState extends State<_Anfitrion> {
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder<String>(
        valueListenable: widget.filtro,
        builder: (contexto, q, hijo) => Column(
          children: [
            CajaDeBusqueda(
              valor: q,
              alBuscar: (t) {
                widget.busquedas.add(t);
                if (widget.aplicaSolo) widget.filtro.value = t;
              },
            ),
            // La lista de debajo, que es lo que la persona mira.
            Text('filtrando por «$q»'),
          ],
        ),
      ),
    ),
  );
}

void main() {
  late ValueNotifier<String> filtro;
  late List<String> busquedas;

  setUp(() {
    filtro = ValueNotifier<String>('');
    busquedas = <String>[];
  });

  tearDown(() => filtro.dispose());

  Future<void> pintar(WidgetTester tester, {bool aplicaSolo = true}) =>
      tester.pumpWidget(
        _Anfitrion(
          filtro: filtro,
          busquedas: busquedas,
          aplicaSolo: aplicaSolo,
        ),
      );

  String loQueDiceLaCaja() =>
      (find.byType(TextField).evaluate().single.widget as TextField)
          .controller!
          .text;

  group('filtra según se escribe, sin Intro', () {
    testWidgets('se escribe, pasa el respiro y la lista filtró', (
      tester,
    ) async {
      await pintar(tester);

      await tester.enterText(find.byType(TextField), 'DAYLIS');
      await tester.pump();

      // Nadie ha pulsado Intro. Antes, aquí no pasaba NADA — nunca.
      expect(
        busquedas,
        isEmpty,
        reason: 'todavía no: el respiro es lo que evita seis repintados por palabra',
      );

      await tester.pump(CajaDeBusqueda.esperaPorDefecto);

      expect(
        busquedas,
        ['DAYLIS'],
        reason: 'nadie pulsa Intro en un buscador: se escribe y se espera que filtre',
      );
      expect(find.text('filtrando por «DAYLIS»'), findsOneWidget);
    });

    testWidgets('escribir RÁPIDO filtra UNA vez y con la palabra entera', (
      tester,
    ) async {
      await pintar(tester);

      // Siete pulsaciones seguidas, 40 ms entre ellas: escribir normal.
      for (final trozo in [
        'C',
        'CH',
        'CHA',
        'CHAP',
        'CHAPL',
        'CHAPLI',
        'CHAPLIN',
      ]) {
        await tester.enterText(find.byType(TextField), trozo);
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pump(CajaDeBusqueda.esperaPorDefecto);

      expect(
        busquedas,
        ['CHAPLIN'],
        reason:
            'seis consultas sobre 8.348 clientes son seis repintados de la '
            'lista por palabra, y en el teléfono de allá eso se nota',
      );
      expect(loQueDiceLaCaja(), 'CHAPLIN');
    });
  });

  group('Intro', () {
    testWidgets('busca YA, sin esperar el respiro', (tester) async {
      await pintar(tester);

      await tester.enterText(find.byType(TextField), 'DAYLIS');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(
        busquedas,
        ['DAYLIS'],
        reason: 'quien ya tiene el hábito de pulsar Intro no puede salir perdiendo',
      );
    });

    testWidgets('DESPUÉS del respiro no dispara una segunda búsqueda', (
      tester,
    ) async {
      await pintar(tester);

      await tester.enterText(find.byType(TextField), 'DAYLIS');
      await tester.pump(CajaDeBusqueda.esperaPorDefecto);
      expect(busquedas, ['DAYLIS']);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump(CajaDeBusqueda.esperaPorDefecto);

      expect(
        busquedas,
        ['DAYLIS'],
        reason: 'sería una segunda consulta encima de la que ya está pintada',
      );
    });
  });

  group('lo que se escribe no se pierde NUNCA', () {
    testWidgets('el eco del filtro no borra lo que se sigue tecleando', (
      tester,
    ) async {
      // EL CASO `CHAPLIN` → `CH`, tal y como se midió.
      await pintar(tester, aplicaSolo: false);

      await tester.enterText(find.byType(TextField), 'CH');
      await tester.pump(CajaDeBusqueda.esperaPorDefecto);
      expect(busquedas, ['CH'], reason: 'el respiro busca «CH»');

      // Y mientras el filtro se aplica se sigue escribiendo.
      await tester.enterText(find.byType(TextField), 'CHAPLIN');
      await tester.pump(const Duration(milliseconds: 10));

      // AHORA llega el eco de la búsqueda anterior: el filtro dice «CH».
      filtro.value = 'CH';
      await tester.pump();

      expect(
        loQueDiceLaCaja(),
        'CHAPLIN',
        reason:
            'aquí es donde se perdían cinco letras: el estado del filtro '
            'reescribía el campo por detrás',
      );

      await tester.pump(CajaDeBusqueda.esperaPorDefecto);

      expect(
        busquedas,
        ['CH', 'CHAPLIN'],
        reason: 'y al pisarlo se cancelaba también la búsqueda que venía',
      );
    });

    testWidgets('un repintado por otra cosa tampoco se lleva las letras', (
      tester,
    ) async {
      // El caso de verdad: llegan las facetas, baja la lista, cambia cualquier
      // otra cosa de la pantalla. El filtro no ha dicho nada.
      await pintar(tester, aplicaSolo: false);

      await tester.enterText(find.byType(TextField), 'CHAPLIN');
      await tester.pump(const Duration(milliseconds: 10));

      filtro.notifyListeners();
      await tester.pump();

      expect(loQueDiceLaCaja(), 'CHAPLIN');
      await tester.pump(CajaDeBusqueda.esperaPorDefecto);
      expect(busquedas, ['CHAPLIN']);
    });
  });

  group('lo que sí manda desde fuera', () {
    testWidgets('`Quitar filtros` vacía la caja y cancela lo pendiente', (
      tester,
    ) async {
      await pintar(tester, aplicaSolo: false);

      await tester.enterText(find.byType(TextField), 'ARROZ');
      await tester.pump(CajaDeBusqueda.esperaPorDefecto);
      filtro.value = 'ARROZ';
      await tester.pump();

      // Se sigue escribiendo y, antes de que salte el respiro, se limpia.
      await tester.enterText(find.byType(TextField), 'ARROZB');
      await tester.pump(const Duration(milliseconds: 100));
      filtro.value = '';
      await tester.pump();

      expect(
        loQueDiceLaCaja(),
        '',
        reason:
            'una caja con texto encima de una lista SIN filtrar se lee como '
            '«esto es todo lo que hay de arroz»',
      );

      await tester.pump(CajaDeBusqueda.esperaPorDefecto);
      expect(
        busquedas,
        ['ARROZ'],
        reason: 'una limpieza le gana a una letra que aún no ha llegado a buscarse',
      );
    });

    testWidgets('la caja arranca con lo que traiga el enlace', (tester) async {
      filtro.value = 'MALTA';
      await pintar(tester);
      expect(loQueDiceLaCaja(), 'MALTA');
    });
  });
}
