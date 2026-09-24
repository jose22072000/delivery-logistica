/// Que los calendarios de Material sigan hablando español.
///
/// **De dónde sale esto.** Es lo único que se salvó de
/// `test/textos/en_pantalla_test.dart`, que se fue el 24/09/2026 con la
/// traducción al inglés. Aquel fichero era la forma 3 de prueba verde que no
/// prueba nada —montaba un `_Pantalla` sintético suyo que leía
/// `context.textos.navPedidos`, nunca una pantalla de verdad—, pero su último
/// caso sí valía: comprobaba que las delegaciones de MATERIAL estuvieran
/// puestas, y ése es el que se queda.
///
/// Por qué es la guarda que hace falta: al quitar la traducción es muy fácil
/// llevarse por delante `flutter_localizations` entera, que parece que sólo
/// servía para eso. No. Sin ella Flutter cae en `DefaultMaterialLocalizations`,
/// que sólo sabe inglés, y esta aplicación abre calendarios en cinco sitios
/// (`showDatePicker` en Informes, en el Tablero y dos veces en el asistente de
/// rutas, más el `CalendarDatePicker` de `diseno/rango_de_fechas.dart`). El
/// resultado sería `January` y `Cancel` dentro de una pantalla en español: no
/// quitar el inglés, sino ponerlo donde no estaba.
///
/// Esto falla en cuanto alguien toque `lib/idioma.dart` o el `pubspec`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/idioma.dart';

void main() {
  testWidgets('el español es el único idioma y es el primero', (
    WidgetTester t,
  ) async {
    expect(idiomas.map((l) => l.languageCode), <String>['es']);
  });

  testWidgets('las delegaciones de Material están puestas y en español', (
    WidgetTester t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: delegacionesDeIdioma,
        supportedLocales: idiomas,
        home: const Text('hola'),
      ),
    );
    final BuildContext ctx = t.element(find.byType(Text));

    // `Cancelar`, no `Cancel`: es lo que sale en un selector de fecha.
    final l10n = MaterialLocalizations.of(ctx);
    expect(l10n.cancelButtonLabel, 'Cancelar');
    // Y los meses, que es lo que se lee en el propio calendario.
    expect(l10n.formatMonthYear(DateTime(2026, 1, 15)), contains('enero'));
  });

  testWidgets('un aparato en otro idioma cae igualmente en español', (
    WidgetTester t,
  ) async {
    // El almacén habla español pase lo que pase en el teléfono.
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('pt'),
        localizationsDelegates: delegacionesDeIdioma,
        supportedLocales: idiomas,
        home: const Text('hola'),
      ),
    );
    final BuildContext ctx = t.element(find.byType(Text));
    expect(MaterialLocalizations.of(ctx).cancelButtonLabel, 'Cancelar');
  });
}
