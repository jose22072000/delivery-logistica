/// Que `es` y `en` no se separen nunca.
///
/// Una clave que está en español y no en inglés no revienta: sale el texto en
/// español dentro de la pantalla en inglés y nadie se entera hasta que lo ve un
/// cliente. Por eso esto falla si falta una sola.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _dirArb = 'lib/textos/arb';
const String _fuenteNext = '../../delivery/src/lib/i18n.ts';

Map<String, Object?> _leer(String locale) {
  final crudo = File('$_dirArb/app_$locale.arb').readAsStringSync();
  return jsonDecode(crudo) as Map<String, Object?>;
}

/// Las claves de verdad: sin `@@locale` ni los `@clave` de metadatos.
Set<String> _claves(Map<String, Object?> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

Set<String> _marcadores(String texto) =>
    RegExp(r'\{(\w+)\}').allMatches(texto).map((m) => m.group(1)!).toSet();

void main() {
  final es = _leer('es');
  final en = _leer('en');

  group('los dos idiomas van a la par', () {
    test('tienen EXACTAMENTE las mismas claves', () {
      final soloEs = _claves(es).difference(_claves(en));
      final soloEn = _claves(en).difference(_claves(es));

      expect(soloEs, isEmpty, reason: 'faltan en app_en.arb: $soloEs');
      expect(soloEn, isEmpty, reason: 'sobran en app_en.arb: $soloEn');
    });

    test('ninguna traducción se quedó vacía', () {
      for (final k in _claves(en)) {
        expect(
          (en[k]! as String).trim(),
          isNotEmpty,
          reason: 'la clave $k está vacía en inglés',
        );
      }
    });

    test('cada clave lleva los MISMOS marcadores en los dos idiomas', () {
      // Un `{n}` que se pierde al traducir deja el número fuera de la frase, y
      // la frase sigue saliendo: no hay forma de verlo sin esto.
      for (final k in _claves(es)) {
        expect(
          _marcadores(en[k]! as String),
          _marcadores(es[k]! as String),
          reason: 'los marcadores de $k no coinciden',
        );
      }
    });

    test('la plantilla declara todos los marcadores que usa', () {
      for (final k in _claves(es)) {
        final usados = _marcadores(es[k]! as String);
        if (usados.isEmpty) continue;

        final meta = es['@$k'] as Map<String, Object?>?;
        final declarados =
            (meta?['placeholders'] as Map<String, Object?>?)?.keys.toSet() ??
                <String>{};
        expect(
          declarados,
          usados,
          reason: 'a $k le faltan marcadores declarados en @$k',
        );
      }
    });

    test('la traducción NO lleva metadatos: los lleva solo la plantilla', () {
      // gen_l10n solo mira los `@clave` del fichero plantilla. Duplicarlos en
      // `en` es garantía de que un día digan cosas distintas.
      expect(en.keys.where((k) => k.startsWith('@') && k != '@@locale'), isEmpty);
    });

    test('cada texto de la plantilla dice de dónde salió', () {
      for (final k in _claves(es)) {
        final meta = es['@$k'] as Map<String, Object?>?;
        expect(meta, isNotNull, reason: '$k no tiene su bloque @$k');
        expect(
          (meta!['description']! as String).trim(),
          isNotEmpty,
          reason: '$k no dice de dónde salió',
        );
      }
    });
  });

  group('las claves están bien formadas', () {
    test('todas son identificadores de Dart en minúscula inicial', () {
      // gen_l10n las convierte en getters de la clase `Textos`: una clave con
      // un punto o un guion no compila, y el fallo sale lejos de aquí.
      final bien = RegExp(r'^[a-z][a-zA-Z0-9]*$');
      for (final k in _claves(es)) {
        expect(bien.hasMatch(k), isTrue, reason: '$k no es un identificador');
      }
    });

    test('ninguna choca con un miembro que la clase ya tiene', () {
      const reservadas = <String>{
        'localeName', 'toString', 'hashCode', 'runtimeType', 'noSuchMethod',
        'delegate', 'localizationsDelegates', 'supportedLocales', 'of',
      };
      expect(_claves(es).intersection(reservadas), isEmpty);
    });
  });

  group('el traslado desde la de Next está completo', () {
    // Las claves originales, leídas del propio fichero de Next. Es la única
    // forma de que esto siga siendo verdad cuando alguien añada una allí.
    final crudo = File(_fuenteNext).readAsStringSync();
    final original = RegExp(r"^\s*'([a-zA-Z]+\.[a-zA-Z0-9_.]+)':\s*'")
        .allMatches(
          RegExp(r'const es: Dict = \{\n(.*?)\n\}\n', dotAll: true)
              .firstMatch(crudo)!
              .group(1)!,
        )
        .map((m) => m.group(1)!)
        .toSet();

    test('está trasladado TODO lo que tiene la de Next', () {
      // Cada clave de Next deja su rastro en el `@description` del ARB.
      final trasladadas = <String>{
        for (final k in _claves(es))
          ...RegExp(r'De `([^`]+)` en delivery')
              .allMatches((es['@$k']! as Map<String, Object?>)['description']! as String)
              .map((m) => m.group(1)!),
      };
      final sinTrasladar = original.difference(trasladadas);
      expect(sinTrasladar, isEmpty, reason: 'se quedaron sin pasar: $sinTrasladar');
    });

    test('lo que NO viene de Next lleva el prefijo `nuevo`', () {
      // Regla 5 de PLAN.md §4.3: así se sabe siempre qué se comparó con la de
      // Next y qué es invención de esta aplicación.
      for (final k in _claves(es)) {
        final desc = (es['@$k']! as Map<String, Object?>)['description']! as String;
        if (desc.contains('en delivery/src/lib/i18n.ts')) continue;
        expect(
          k.startsWith('nuevo'),
          isTrue,
          reason: '$k no viene de Next y no lleva el prefijo `nuevo`',
        );
        expect(
          desc.toUpperCase(),
          contains('NUEVO'),
          reason: '$k no explica por qué existe',
        );
      }
    });

    test('ninguna clave `nuevo` se cuela como traslado', () {
      for (final k in _claves(es).where((k) => k.startsWith('nuevo'))) {
        final desc = (es['@$k']! as Map<String, Object?>)['description']! as String;
        expect(desc, isNot(contains('en delivery/src/lib/i18n.ts')));
      }
    });
  });
}
