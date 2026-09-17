import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// NINGUNA PANTALLA ESCRIBE UN IMPORTE A MANO.
///
/// El dinero se pinta SIEMPRE por `TasaDeLaMirada.importe(usd, moneda)`, que es
/// lo único que sabe dos cosas: la tasa es POR SUCURSAL, y sin la de esa
/// sucursal no se convierte nada —ni se cae a la de otra, ni a un número por
/// defecto—.
///
/// El Tablero se lo saltaba entero. Su ayudante era
/// `'${Numeros.importe(usd)} \$'` escrito a pelo, así que con CUP puesto en la
/// barra las tarjetas y las cabeceras de columna seguían diciendo «0,04 $»: la
/// única pantalla donde el selector de moneda no hacía nada, y la que más se
/// mira para decidir qué se carga en el camión. Visto en el teléfono de Jose el
/// 16/09/2026, con La Habana y su tasa de 715 ya bajadas.
///
/// Se comprueba sobre el CÓDIGO y no pintando un widget a propósito: lo que hay
/// que impedir es que alguien vuelva a escribir el símbolo al lado de un número,
/// y eso se ve leyendo, no montando un árbol con providers de mentira.
void main() {
  test(
    'el dinero del tablero pasa por la tasa, no por un símbolo escrito a mano',
    () {
      final sospechosas = <String>[];
      final dir = Directory('lib/pantallas/tablero');
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final lineas = f.readAsLinesSync();
        for (var i = 0; i < lineas.length; i++) {
          final l = lineas[i];
          if (l.trimLeft().startsWith('//') || l.trimLeft().startsWith('///')) {
            continue;
          }
          // Un `$` escapado dentro de una cadena: `' \$'`, `"\$"`, `'\$ '`…
          // Es como se escribe el símbolo de moneda en Dart, y no hay ninguna
          // otra razón para escaparlo dentro de un literal de texto.
          if (l.contains(r"\$'") || l.contains(r'\$"') || l.contains(r"\$ ")) {
            sospechosas.add('${f.path}:${i + 1}: ${l.trim()}');
          }
        }
      }
      expect(
        sospechosas,
        isEmpty,
        reason:
            'estas líneas escriben el símbolo de la moneda a mano en vez de pasar '
            'por TasaDeLaMirada.importe, así que enseñan USD aunque la barra diga '
            'CUP:\n${sospechosas.join('\n')}',
      );
    },
  );

  /// La otra mitad: que el ayudante del tablero SÍ pida la tasa. Sin esto, un
  /// `dineroBonito` que devolviera la cadena vacía pasaría la prueba de arriba.
  test('dineroBonito recibe el ref para poder mirar la tasa', () {
    final kit = File('lib/pantallas/tablero/vista/kit.dart').readAsStringSync();
    expect(
      kit.contains('String dineroBonito(WidgetRef ref, double usd)'),
      isTrue,
      reason:
          'dineroBonito tiene que recibir el ref: es lo que le deja leer '
          'tasaDeLaMiradaProvider y monedaEfectivaProvider',
    );
    expect(
      kit.contains('tasaDeLaMiradaProvider') &&
          kit.contains('monedaEfectivaProvider'),
      isTrue,
      reason: 'y tiene que usar los dos, no sólo pedirlos',
    );
  });
}
