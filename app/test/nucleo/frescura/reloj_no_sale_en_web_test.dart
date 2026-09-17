import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/frescura/reloj_de_datos.dart';
import 'package:reparto/nucleo/plataforma.dart';

/// EL RELOJ DE DATOS NO SALE EN LA WEB.
///
/// Dice dos cosas —de qué hora es tu copia y cuánto te queda sin subir— y las
/// dos son del mundo de no tener señal. En un navegador no hay copia que pueda
/// envejecer ni cola que pueda atascarse.
///
/// Jose, 17/09/2026, por quinta vez: «en la web sigo viendo cosas de
/// sincronización, de cosas sin conexión, y no sé cuántas veces tengo que
/// decirte que la web siempre está en línea, nunca se desconecta. Quita todo lo
/// que tenga que ver con eso: ella está directa al servidor».
///
/// Se prueba aquí, en el widget, y no en las siete pantallas que lo llaman: en
/// siete sitios se olvida uno, y el que se olvide es el que él verá.
void main() {
  Future<void> pintar(WidgetTester tester, EstadoFrescura estado, int sinSubir) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RelojDeDatos(estado: estado, sinSubir: sinSubir),
          ),
        ),
      );

  testWidgets('en la web no pinta NADA, ni la hora ni lo que falta por subir', (
    tester,
  ) async {
    await Destino.comoSiFueraWeb(() async {
      await pintar(tester, DatosRecientes(DateTime(2026, 9, 17, 10, 36)), 3);

      expect(
        find.textContaining('Datos de las'),
        findsNothing,
        reason:
            'la web lee del servidor: esa hora no avisa de nada, y el día que '
            'la marca se quede atrás avisa de algo falso',
      );
      expect(
        find.textContaining('sin subir'),
        findsNothing,
        reason: 'en un navegador no hay cola que pueda quedarse sin subir',
      );
      // Y no deja un hueco donde estaba.
      expect(find.byType(Row), findsNothing);
    });
  });

  testWidgets('en la web tampoco sale el ámbar de «sin descargar»', (
    tester,
  ) async {
    await Destino.comoSiFueraWeb(() async {
      await pintar(tester, const SinDescargar(), 0);
      expect(find.text('Sin descargar todavía'), findsNothing);
    });
  });

  testWidgets('en la APK sigue saliendo entero: ahí sí hay copia y sí hay cola', (
    tester,
  ) async {
    // El otro mundo, que es su razón de ser y no se toca.
    await pintar(tester, DatosRecientes(DateTime(2026, 9, 17, 10, 36)), 3);

    expect(find.text('Datos de las 10:36'), findsOneWidget);
    expect(find.text('3 sin subir'), findsOneWidget);
  });

  testWidgets('en la APK, «sin descargar» sigue avisando', (tester) async {
    await pintar(tester, const SinDescargar(), 0);
    expect(find.text('Sin descargar todavía'), findsOneWidget);
  });
}
