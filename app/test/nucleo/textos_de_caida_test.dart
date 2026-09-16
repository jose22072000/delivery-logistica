import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/plataforma.dart';

/// LA PAREJA: en aparato se habla de señal, en web no.
///
/// Va en pareja como manda `CLAUDE.md` §1. Una mitad sola no comprueba nada:
///
///  * sólo «en web no dice señal» se cumpliría igual si alguien borrara el
///    texto del aparato, y el logístico del patio se quedaría sin saber que lo
///    que bajó sigue dentro;
///  * sólo «en aparato dice señal» se cumpliría igual si alguien quitara el
///    `if`, y la web volvería a mandar a la oficina a mirar la antena.
void main() {
  group('cuando el servidor no contesta', () {
    test('en el APARATO se habla de señal y de lo que ya está bajado', () {
      expect(
        TextosDeCaida.titular(sinConexion: true),
        contains('cuando haya señal'),
      );
      expect(
        TextosDeCaida.queHacer(sinConexion: true),
        allOf(contains('señal'), contains('sigue en el aparato')),
      );
    });

    test('en la WEB no se nombra ni la señal ni el aparato', () {
      final titular = TextosDeCaida.titular(sinConexion: false);
      final queHacer = TextosDeCaida.queHacer(sinConexion: false);

      for (final texto in [titular, queHacer]) {
        expect(
          texto.toLowerCase(),
          isNot(contains('señal')),
          reason:
              'la página cargó, así que conexión hay: mandar a mirar la señal '
              'es mandar a mirar donde no es',
        );
        expect(texto.toLowerCase(), isNot(contains('aparato')));
        expect(texto.toLowerCase(), isNot(contains('descargado')));
      }
      // Y se dice lo que SÍ pasa, que es otra cosa.
      expect(titular, contains('no contesta'));
      expect(queHacer, contains('oficina'));
    });
  });
}
