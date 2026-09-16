import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/sincro/que_se_puede.dart';

/// LAS TRES REGLAS DE LOS BOTONES DEL DÍA.
///
/// Jose, 16/09/2026: «si no hay conexion pues no puedes ni traer ni enviar datos
/// al servidor por q para eso es y en caso de q no alla q traer nada del dia
/// pues ese boton se desabilita y solo se deja enviar en caso de q si alla q
/// traer se desabilida el de enviar para no subir nada sin tener todo lo actual
/// y despues si se podra una ves todo actualizado».
void main() {
  test('sin conexión no se puede ninguna de las dos', () {
    final q = quePuedeHacerse(hayConexion: false, hayQueTraer: true);

    expect(q.traer.sePuede, isFalse);
    expect(q.enviar.sePuede, isFalse);
    expect(
      q.traer.motivo,
      contains('Sin conexión'),
      reason:
          'los dos gestos son contra el servidor: decirlo en ambos evita '
          'pulsar dos veces cada uno buscando cuál falla',
    );
  });

  test('si hay que traer, ENVIAR se apaga: no se sube sin lo de ahora', () {
    final q = quePuedeHacerse(hayConexion: true, hayQueTraer: true);

    expect(q.traer.sePuede, isTrue);
    expect(q.enviar.sePuede, isFalse);
    expect(q.enviar.motivo, contains('Trae el día primero'));
  });

  test('con los datos al día, TRAER se apaga y enviar queda libre', () {
    final q = quePuedeHacerse(hayConexion: true, hayQueTraer: false);

    expect(q.traer.sePuede, isFalse);
    expect(q.traer.motivo, contains('ya son de ahora'));
    expect(q.enviar.sePuede, isTrue);
  });

  test('enviar sigue permitido con cero pendientes', () {
    // Es el gesto de «asegúrate», y quien acaba de cerrar una ruta lo busca.
    // Apagarlo ahí fue justo el hueco que se encontró el 16/09.
    final q = quePuedeHacerse(hayConexion: true, hayQueTraer: false);
    expect(q.enviar.sePuede, isTrue);
  });

  test('un motivo nunca viene vacío cuando el gesto está apagado', () {
    // Un botón apagado sin motivo enseña a desconfiar de todos los botones.
    for (final q in [
      quePuedeHacerse(hayConexion: false, hayQueTraer: false),
      quePuedeHacerse(hayConexion: true, hayQueTraer: true),
      quePuedeHacerse(hayConexion: true, hayQueTraer: false),
    ]) {
      for (final g in [q.traer, q.enviar]) {
        if (!g.sePuede) {
          expect(g.motivo, isNotNull);
          expect(g.motivo!.trim(), isNotEmpty);
        }
      }
    }
  });
}
