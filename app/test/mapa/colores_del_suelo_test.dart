// DE QUÉ COLOR SALE CADA CLASE DE SUELO.
//
// Esto nace de un fallo que no dio ni un error: la tarde del 21/09/2026 el
// generador estrenó la clase `humedal` al coser los multipolígonos —363, y el
// más grande es la **Ciénaga de Zapata**— y el pintor no la conocía. La clase
// cayó en el `_ =>` de su tabla y la ciénaga salió pintada **del color de un
// prado**. Ni excepción, ni hueco, ni pantalla roja: una mancha creíble y
// equivocada, que es el fallo que más caro sale aquí porque no se ve.
//
// Por un prado se mete un camión y por una ciénaga no. Un mapa de reparto está
// para decir eso.
//
// Las pruebas van en dos alturas, y las dos hacen falta:
//
//  1. **Sobre la tabla del pintor**: que `humedal` tenga color propio, que no
//     sea el de por defecto ni el de `hierba`, y que se distinga de sus dos
//     vecinos de verdad —la hierba y el agua—.
//  2. **Atando la tabla al generador**: que TODA clase de suelo que escribe
//     `herramientas/mapa-cuba/niveles.go` tenga su línea aquí. Ésta es la que
//     habría cazado el humedal el mismo día, y la que cazará la siguiente. Un
//     comentario que diga «acuérdate de añadirla» no falla nunca; esta prueba
//     sí. (`CLAUDE.md` §3-bis: lo que tiene que contestar lo mismo se ata con
//     una prueba, no con un comentario.)

import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/colores.dart';
import 'package:reparto/mapa/fondo_del_paquete.dart';

/// El color al que cae una clase que el pintor no conoce. Se calcula
/// preguntando por una clase que no existe ni existirá, no copiando el valor:
/// si mañana el `_ =>` pasa a ser otro tono, esta prueba sigue midiendo lo que
/// dice medir.
final _porDefecto = colorDelSuelo('esta-clase-no-existe');

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Cuánto se parecen dos colores, en tono y en luz. Es la misma vara que usa
/// `test/diseno/paleta_test.dart` con las cuatro señales.
({double tono, double luz}) _distancia(Color a, Color b) {
  final x = HSLColor.fromColor(a);
  final y = HSLColor.fromColor(b);
  final bruta = (x.hue - y.hue).abs();
  return (
    tono: bruta > 180 ? 360 - bruta : bruta,
    luz: (x.lightness - y.lightness).abs(),
  );
}

/// Las clases de suelo que escribe el generador, leídas de su propio fichero.
///
/// Se leen de ahí y no de una lista copiada aquí **a propósito**: una lista
/// copiada se queda igual el día que el generador estrena una clase, que es
/// exactamente el día en que esta prueba tiene que ponerse roja.
Set<String> _clasesQueEscribeElGenerador() {
  final fuente = File('../herramientas/mapa-cuba/niveles.go');
  if (!fuente.existsSync()) return const {};
  final texto = fuente.readAsStringSync();
  final desde = texto.indexOf('var clasesDeSuelo = map[string]string{');
  expect(
    desde,
    isNot(-1),
    reason:
        'no está `clasesDeSuelo` en niveles.go: o se renombró, y entonces hay '
        'que arreglar esta prueba, o se borró y el suelo dejó de viajar',
  );
  final hasta = texto.indexOf('\n}', desde);
  final cuerpo = texto.substring(desde, hasta);
  return {
    for (final m in RegExp(r'"[^"]+":\s*"([^"]+)"').allMatches(cuerpo))
      m.group(1)!,
  };
}

void main() {
  test('la Ciénaga de Zapata NO se pinta del color de un prado', () {
    // ÉSTA es la prueba. Lo que se rompió el 21/09/2026 y lo que no puede
    // volver a romperse: `humedal` con color propio, ni el de por defecto ni el
    // de `hierba`.
    final humedal = colorDelSuelo('humedal');

    expect(
      humedal,
      isNot(_porDefecto),
      reason:
          'la clase `humedal` cae en el `_ =>` de la tabla de `suelo`: la '
          'Ciénaga de Zapata sale del color de por defecto (${_hex(_porDefecto)}) '
          'y nadie se entera. Le falta su línea en `colorDelSuelo`',
    );
    expect(
      humedal,
      isNot(ColoresDelMapa.hierba),
      reason:
          'un humedal pintado de hierba dice que por ahí se puede meter un '
          'camión, y por una ciénaga no se puede',
    );
    expect(humedal, ColoresDelMapa.humedal);
  });

  test('el humedal se distingue de la hierba y del agua', () {
    // Sus dos vecinos de verdad: la hierba es la otra mancha verde clara, y el
    // agua es lo que un humedal medio es. Si se confunde con cualquiera de las
    // dos, tener la clase aparte no sirve de nada.
    //
    // La vara es la de `paleta_test.dart`: más de 30 grados de tono, o una
    // diferencia de luz clara. Aquí se pide el tono porque las tres son claras
    // a propósito —el mapa es el fondo sobre el que se lee la ruta— y subir o
    // bajar la luz sería empezar a gritar.
    for (final vecino in {
      'hierba': ColoresDelMapa.hierba,
      'agua': ColoresDelMapa.agua,
      'bosque': ColoresDelMapa.bosque,
      'parque': ColoresDelMapa.parque,
    }.entries) {
      final d = _distancia(ColoresDelMapa.humedal, vecino.value);
      expect(
        d.tono > 30 || d.luz > 0.08,
        isTrue,
        reason:
            'el humedal (${_hex(ColoresDelMapa.humedal)}) y «${vecino.key}» '
            '(${_hex(vecino.value)}) se parecen demasiado: '
            '${d.tono.toStringAsFixed(0)} grados de tono y '
            '${d.luz.toStringAsFixed(2)} de luz',
      );
    }
  });

  test('el humedal no grita: sigue siendo fondo', () {
    // La otra mitad de la regla. Un color que se distingue porque es fuerte se
    // come la línea de la ruta, y lo que se mira en un mapa es el camino.
    final hsl = HSLColor.fromColor(ColoresDelMapa.humedal);
    expect(
      hsl.lightness,
      greaterThan(0.78),
      reason:
          'el humedal ${_hex(ColoresDelMapa.humedal)} es una mancha oscura: '
          'tapa el recorrido en vez de quedarse debajo',
    );
    expect(
      hsl.saturation,
      lessThan(0.45),
      reason:
          'el humedal ${_hex(ColoresDelMapa.humedal)} tiene demasiado color '
          'para ser fondo de mapa',
    );
  });

  test('ninguna clase de suelo repite el color de otra', () {
    // Dos clases del mismo color son una clase, y entonces sobra la de menos.
    final porClase = {
      for (final clase in const [
        'bosque',
        'parque',
        'hierba',
        'humedal',
        'urbano',
        'industrial',
        'portuario',
      ])
        clase: colorDelSuelo(clase),
    };
    for (final a in porClase.entries) {
      for (final b in porClase.entries) {
        if (a.key.compareTo(b.key) >= 0) continue;
        expect(
          a.value,
          isNot(b.value),
          reason:
              '«${a.key}» y «${b.key}» salen las dos de ${_hex(a.value)}: en el '
              'mapa son la misma mancha',
        );
      }
    }
  });

  test('toda clase que escribe el generador tiene color propio aquí', () {
    // LA QUE HABRÍA CAZADO EL HUMEDAL EL MISMO DÍA. El contrato entre el
    // generador y el pintor son cadenas exactas (§3 de
    // `docs/mapa-sin-conexion.md`): una clase nueva allí y ninguna línea aquí
    // es una mancha del color de otra cosa, sin un solo error.
    final clases = _clasesQueEscribeElGenerador();
    expect(
      clases,
      isNotEmpty,
      reason: 'no se pudo leer `clasesDeSuelo` de niveles.go',
    );
    expect(
      clases,
      contains('humedal'),
      reason:
          'el generador dejó de escribir `humedal`: o se quitó la Ciénaga de '
          'Zapata del mapa, o se le cambió el nombre y aquí se pinta otra cosa',
    );
    for (final clase in clases) {
      // `hierba` es legítimamente el color de por defecto: es la única que
      // puede coincidir con él.
      if (clase == 'hierba') continue;
      expect(
        colorDelSuelo(clase),
        isNot(_porDefecto),
        reason:
            'el generador escribe la clase «$clase» y el pintor no la conoce: '
            'cae en el `_ =>` y sale del color de por defecto '
            '(${_hex(_porDefecto)}), que es el de `hierba`. Es lo que le pasó a '
            '`humedal` el 21/09/2026: se pinta algo creíble y equivocado',
      );
    }
  });

  test('una clase que NO conocemos se pinta igual, no se deja en blanco', () {
    // La regla 4 de la casa aplicada al dibujo, y es la otra mitad de la
    // anterior: la tabla se cierra con un `_ =>` **con color**, no con `null`.
    // Un hueco blanco nadie sabe si es un descampado o un fallo; una mancha del
    // color raro se ve y se arregla.
    expect(colorDelSuelo('manglar'), isNotNull);
    expect(colorDelSuelo(null), isNotNull);
    expect(colorDelSuelo('manglar').a, 1.0, reason: 'y opaca, no transparente');
  });
}
