/// Los textos de la aplicación — la puerta de entrada.
///
/// Todo lo demás importa ESTE fichero y nunca `generado/textos.dart`: lo de
/// `generado/` lo reescribe `flutter gen-l10n` de cabo a rabo cada vez que se
/// toca un `.arb`, así que cualquier cosa añadida allí se pierde sin avisar.
///
/// Cómo está montado, en tres líneas (PLAN.md §4.3):
///
/// - `arb/app_es.arb` es **la verdad**: cada cadena copiada literal del pliego,
///   con sus tildes y sus comillas angulares. `arb/app_en.arb` la sigue.
/// - Las claves son planas y llevan el nombre de la pantalla delante:
///   `orders.filters.title` de next-intl es aquí `pedidosFiltrosTitulo`.
/// - Los `pedido(s)` del pliego **no se pluralizan con ICU**. El `(s)` va dentro
///   del texto tal cual: en cuanto se mete un `plural{}` la cadena deja de ser
///   idéntica a la de Next y se rompe el criterio de terminado.
library;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'generado/textos.dart';

export 'generado/textos.dart' show Textos;

/// Los dos idiomas de la casa. El orden manda: si el aparato viene en algo que
/// no es ninguno de los dos, Flutter se queda con el primero, y aquí eso tiene
/// que ser español porque es el idioma del almacén.
const List<Locale> idiomas = <Locale>[Locale('es'), Locale('en')];

/// Las delegaciones que van en el `MaterialApp`. Se dan juntas para que nadie
/// se deje fuera las de Material y acabe con los botones de un `DatePicker` en
/// inglés dentro de una pantalla en español.
List<LocalizationsDelegate<Object?>> get delegacionesDeIdioma =>
    <LocalizationsDelegate<Object?>>[...Textos.localizationsDelegates];

/// Atajo para leer los textos desde un `BuildContext`.
///
/// Se llama así de corto a propósito: aparece en cada línea de cada pantalla, y
/// `Textos.of(context).pedidosTitulo` repetido trescientas veces no lo lee
/// nadie.
extension TextosDelContexto on BuildContext {
  Textos get textos => Textos.of(this);
}
