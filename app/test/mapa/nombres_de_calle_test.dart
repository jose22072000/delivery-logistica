// LOS NOMBRES DE LAS CALLES sobre la tesela del paquete.
//
// El dato ya venía dentro del paquete —el generador escribe `nombre` en la capa
// `carretera` desde el z9— y el pintor sólo rotulaba `poblacion`: estaba en el
// teléfono y no se enseñaba. Lo que se comprueba aquí no es que «salga texto»,
// que eso lo dice cualquier captura, sino **las cuatro decisiones** que separan
// un mapa legible de una mancha: a qué zoom entra cada clase, que un nombre no
// se repita, que ninguno salga boca abajo y que dos no se pisen.
//
// Se mira `rotulosDeCalleDeLaTesela` y no los píxeles de la imagen a propósito:
// una prueba que compara píxeles, cuando falla, no dice **qué** se rompió.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/mapa/fondo_del_paquete.dart';
import 'package:reparto/mapa/mvt.dart';

/// De píxeles de la tesela a unidades de tesela. La capa mide 4096 y la imagen
/// 256, así que uno por dieciséis: escribir las pruebas en píxeles es lo que
/// hace que se puedan leer.
double _u(double pixeles) => pixeles * 16;

Offset _p(double x, double y) => Offset(_u(x), _u(y));

RasgoVectorial _via(String nombre, List<Offset> puntos, {String clase = 'calle'}) =>
    RasgoVectorial(
      forma: FormaVectorial.linea,
      partes: [puntos],
      clase: clase,
      nombre: nombre,
    );

CapaVectorial _carreteras(List<RasgoVectorial> rasgos) =>
    CapaVectorial(nombre: 'carretera', extension: 4096, rasgos: rasgos);

CapaVectorial _poblaciones(List<RasgoVectorial> rasgos) =>
    CapaVectorial(nombre: 'poblacion', extension: 4096, rasgos: rasgos);

void main() {
  // `TextPainter` necesita el motor. Pruebas normales y no `testWidgets`: aquí
  // no se monta pantalla ninguna y dentro de un `testWidgets` el reloj no
  // avanza solo (`CLAUDE.md` §5).
  TestWidgetsFlutterBinding.ensureInitialized();

  test('el nombre de la calle sale, y sigue el trazo', () {
    final rotulos = rotulosDeCalleDeLaTesela(
      [
        _carreteras([
          _via('Calle 23', [_p(20, 128), _p(230, 128)]),
        ]),
      ],
      14,
    );

    expect(
      rotulos.map((r) => r.texto),
      ['Calle 23'],
      reason:
          'el nombre viene dentro del paquete y una calle de 210 píxeles tiene '
          'sitio de sobra: si no sale, se está tirando un dato que ya está en '
          'el teléfono',
    );
    expect(rotulos.single.angulo, closeTo(0, 0.01));
    expect(
      rotulos.single.centro.dy,
      closeTo(128, 1),
      reason: 'el rótulo va SOBRE la calle, no flotando encima del papel',
    );
  });

  test('el rótulo se inclina con el tramo donde cae', () {
    final rotulos = rotulosDeCalleDeLaTesela(
      [
        _carreteras([
          _via('Avenida 26', [_p(20, 20), _p(230, 230)]),
        ]),
      ],
      14,
    );

    expect(rotulos, hasLength(1));
    expect(
      rotulos.single.angulo,
      closeTo(math.pi / 4, 0.02),
      reason: 'una calle en diagonal con el nombre en horizontal encima no es '
          'un mapa: es un cartel puesto al lado',
    );
  });

  test('NUNCA boca abajo: el tramo de derecha a izquierda se voltea', () {
    // Las calles vienen del fichero en el orden en que las dibujó quien las
    // dibujó. La mitad van de derecha a izquierda, y escritas tal cual salen a
    // 180°: no se leen, se descifran.
    final rotulos = rotulosDeCalleDeLaTesela(
      [
        _carreteras([
          _via('Calle Obispo', [_p(230, 60), _p(20, 60)]),
          _via('Calle Cuba', [_p(230, 200), _p(20, 130)]),
        ]),
      ],
      14,
    );

    expect(rotulos, hasLength(2));
    for (final r in rotulos) {
      expect(
        r.angulo.abs() <= math.pi / 2 + 1e-9,
        isTrue,
        reason:
            '«${r.texto}» sale a ${(r.angulo * 180 / math.pi).round()}°: fuera '
            'de ±90° el texto está boca abajo. El tramo que va de derecha a '
            'izquierda hay que recorrerlo al revés antes de medir el ángulo',
      );
    }
    expect(rotulos.firstWhere((r) => r.texto == 'Calle Obispo').angulo,
        closeTo(0, 0.01));
  });

  test('el mismo nombre no se repite en la misma tesela', () {
    // Una avenida llega partida en un rasgo por manzana. Sin la guarda, «Avenida
    // 26» sale cuatro veces en 256 píxeles y no se lee ninguna.
    final rotulos = rotulosDeCalleDeLaTesela(
      [
        _carreteras([
          _via('Avenida 26', [_p(10, 40), _p(240, 40)]),
          _via('Avenida 26', [_p(10, 120), _p(240, 120)]),
          _via('Avenida 26', [_p(10, 200), _p(240, 200)]),
        ]),
      ],
      14,
    );

    expect(
      rotulos,
      hasLength(1),
      reason: 'son tres trozos de la misma avenida, no tres avenidas',
    );
  });

  test('dos rótulos no se pisan: el segundo se cae', () {
    // Dos calles paralelas a tres píxeles. Los dos nombres superpuestos no son
    // dos nombres: son una mancha, y se pierden los dos.
    final rotulos = rotulosDeCalleDeLaTesela(
      [
        _carreteras([
          _via('Calle Mercaderes', [_p(10, 128), _p(245, 128)]),
          _via('Calle Oficios', [_p(10, 131), _p(245, 131)]),
        ]),
      ],
      14,
    );

    expect(
      rotulos,
      hasLength(1),
      reason:
          'los dos caben en el trazo pero se solapan: hay que descartar el '
          'segundo, no pintar los dos encima',
    );
  });

  test('ningún par de rótulos colocados se solapa', () {
    // La misma guarda mirada desde el otro lado, sobre una parrilla entera: lo
    // que se coloca, se coloca sin tocarse.
    final rasgos = <RasgoVectorial>[];
    for (var i = 0; i < 14; i++) {
      rasgos.add(_via('Calle ${i + 1}', [_p(5, 8.0 + i * 8), _p(250, 8.0 + i * 8)]));
      rasgos.add(_via('Avenida ${i + 1}', [_p(8.0 + i * 8, 5), _p(8.0 + i * 8, 250)]));
    }
    final rotulos = rotulosDeCalleDeLaTesela([_carreteras(rasgos)], 14);

    expect(rotulos.length, greaterThan(1), reason: 'algo tiene que salir');
    for (var i = 0; i < rotulos.length; i++) {
      for (var j = i + 1; j < rotulos.length; j++) {
        expect(
          rotulos[i].caja.overlaps(rotulos[j].caja),
          isFalse,
          reason:
              '«${rotulos[i].texto}» y «${rotulos[j].texto}» se pisan: '
              '${rotulos[i].caja} contra ${rotulos[j].caja}',
        );
      }
    }
  });

  test('los nombres de población mandan sobre los de calle', () {
    // El nombre del barrio es lo que convierte la telaraña en un sitio
    // reconocible. Perderlo para poder leer «Calle 3ra» es mal cambio.
    final conBarrio = rotulosDeCalleDeLaTesela(
      [
        _poblaciones([
          RasgoVectorial(
            forma: FormaVectorial.punto,
            partes: [
              [_p(128, 120)],
            ],
            clase: 'barrio',
            nombre: 'Alamar',
          ),
        ]),
        _carreteras([
          _via('Calle 3ra', [_p(10, 128), _p(245, 128)]),
        ]),
      ],
      14,
    );

    expect(
      conBarrio,
      isEmpty,
      reason:
          'el nombre del barrio ya ocupa ese hueco y se pintó antes: la calle '
          'tiene que ceder',
    );

    // Y sin el barrio delante, la misma calle sí se rotula: así se sabe que lo
    // que la tiró fue el barrio y no otra cosa.
    final sinBarrio = rotulosDeCalleDeLaTesela(
      [
        _carreteras([
          _via('Calle 3ra', [_p(10, 128), _p(245, 128)]),
        ]),
      ],
      14,
    );
    expect(sinBarrio.map((r) => r.texto), ['Calle 3ra']);
  });

  test('a zoom bajo no se rotula ninguna calle', () {
    final capas = [
      _carreteras([
        _via('Calle 23', [_p(10, 60), _p(245, 60)]),
        _via('Callejón del Chorro', [_p(10, 120), _p(245, 120)], clase: 'servicio'),
        _via('Camino de la finca', [_p(10, 180), _p(245, 180)], clase: 'camino'),
      ]),
    ];

    for (final z in [9, 10, 11, 12, 13]) {
      expect(
        rotulosDeCalleDeLaTesela(capas, z),
        isEmpty,
        reason:
            'a z$z la calle entera mide dos manzanas en pantalla: rotularla '
            'tapa el mapa que se está mirando',
      );
    }

    // A z14 entra la calle; el servicio y el camino siguen fuera hasta el z16.
    expect(rotulosDeCalleDeLaTesela(capas, 14).map((r) => r.texto), ['Calle 23']);
    expect(
      rotulosDeCalleDeLaTesela(capas, 16).map((r) => r.texto),
      containsAll(['Calle 23', 'Callejón del Chorro', 'Camino de la finca']),
    );
  });

  test('una vía grande se rotula antes que una calle', () {
    // El orden importa cuando las dos se pisan: la carretera que cruza el pueblo
    // se lee; la calle de al lado, si sobra sitio.
    final rotulos = rotulosDeCalleDeLaTesela(
      [
        _carreteras([
          _via('Calle Aguacate', [_p(10, 128), _p(245, 128)]),
          _via('Carretera Central', [_p(10, 130), _p(245, 130)], clase: 'carretera'),
        ]),
      ],
      14,
    );

    expect(rotulos.map((r) => r.texto), ['Carretera Central']);
  });

  test('una calle sin sitio para el nombre NO se rotula', () {
    final rotulos = rotulosDeCalleDeLaTesela(
      [
        _carreteras([
          _via('Avenida de los Presidentes', [_p(120, 128), _p(140, 128)]),
        ]),
      ],
      14,
    );

    expect(
      rotulos,
      isEmpty,
      reason: 'veinte píxeles de calle: media palabra estorba más que el hueco',
    );
  });

  test('una calle que da la vuelta no se rotula atravesándola', () {
    // Una rotonda mide de sobra recorriéndola y nada en línea recta. Sin la
    // comprobación de la cuerda, el nombre se pinta cruzándola por el medio.
    final vuelta = <Offset>[
      for (var i = 0; i <= 24; i++)
        _p(128 + 30 * math.cos(i * math.pi / 12), 128 + 30 * math.sin(i * math.pi / 12)),
    ];
    final rotulos = rotulosDeCalleDeLaTesela(
      [
        _carreteras([_via('Rotonda de Paseo', vuelta)]),
      ],
      14,
    );

    expect(rotulos, isEmpty);
  });

  test('un rasgo sin nombre no inventa rótulo', () {
    final rotulos = rotulosDeCalleDeLaTesela(
      [
        _carreteras([
          RasgoVectorial(
            forma: FormaVectorial.linea,
            partes: [
              [_p(10, 128), _p(245, 128)],
            ],
            clase: 'calle',
          ),
        ]),
      ],
      14,
    );
    expect(rotulos, isEmpty);
  });

  test('al ampliar, sólo se rotula lo que cae en el trozo que se ve', () {
    // Por encima del zoom del paquete se amplía el antepasado y se dibuja un
    // cuarto de él. Un rótulo del cuarto de al lado se pintaría fuera del
    // recorte: trabajo tirado y, peor, un hueco donde tocaba un nombre.
    final capas = [
      _carreteras([
        _via('Calle del cuadrante', [_p(10, 30), _p(120, 30)]),
      ]),
    ];

    // Con aumento 2 la calle se va al cuadrante (0,0): ahí sale…
    expect(
      rotulosDeCalleDeLaTesela(capas, 15, aumento: 2, dentroX: 0, dentroY: 0),
      hasLength(1),
    );
    // …y en el de al lado, no.
    expect(
      rotulosDeCalleDeLaTesela(capas, 15, aumento: 2, dentroX: 1, dentroY: 1),
      isEmpty,
    );
  });
}
