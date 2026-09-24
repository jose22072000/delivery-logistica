/// La aplicación habla ESPAÑOL, y sólo español.
///
/// Aquí no hay traducción ni selector de idioma: **es una decisión de Jose del
/// 24/09/2026**, no un hueco pendiente. Lo que había —305 claves en `app_es.arb`
/// y otras 305 en `app_en.arb`, la clase `Textos` generada por `gen_l10n` y sus
/// delegaciones— estaba enchufado a **una sola** pantalla de las cuarenta y
/// pico, y todo el texto de la interfaz eran literales en español a pelo. Ni
/// `locale:`, ni provider, ni forma de cambiar de idioma. Las ocho sucursales
/// son de Cuba y nadie ha pedido inglés. Se quitó entero.
///
/// **Lo que NO se quitó, y por qué:** `flutter_localizations`. Las que van aquí
/// son las delegaciones de MATERIAL, no las nuestras, y sin ellas Flutter cae en
/// `DefaultMaterialLocalizations`, que sólo sabe inglés. Esta aplicación abre
/// calendarios en cinco sitios —`showDatePicker` en Informes, en el Tablero y
/// dos veces en el asistente de rutas, más el `CalendarDatePicker` de
/// `diseno/rango_de_fechas.dart`—, así que quitarlas dejaría `January`,
/// `Cancel` y `OK` dentro de una pantalla en español. Eso no es quitar el
/// inglés: es ponerlo donde antes no estaba.
///
/// Las pruebas que montan pantallas usan ESTO MISMO, para que lo que ven sea lo
/// que ve quien abre la aplicación.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// El único idioma. Una lista porque es lo que pide `supportedLocales`.
const List<Locale> idiomas = <Locale>[Locale('es')];

/// Las delegaciones que van en el `MaterialApp`: Material, Cupertino y Widgets,
/// las tres juntas. Se dan por el atajo del SDK para que nadie se deje una.
List<LocalizationsDelegate<dynamic>> get delegacionesDeIdioma =>
    GlobalMaterialLocalizations.delegates;
