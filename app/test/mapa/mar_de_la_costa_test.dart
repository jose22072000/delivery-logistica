// EL MAR, sacado de la línea de costa.
//
// Jose, 22/09/2026, alejando el mapa en el teléfono: el océano salía del mismo
// crema que la tierra, y en un punto intermedio aparecía una banda azul cortada
// en línea recta que no seguía la costa.
//
// Lo que se comprueba aquí es **la decisión**, no los píxeles: de qué lado de la
// costa cae el agua, que un anillo se cierre por el borde de la tesela y nunca
// en diagonal por dentro, y que cuando la costa no cuadra se devuelva nada en
// vez de un mar inventado. Una prueba de píxeles no explica nada cuando falla;
// un anillo sí se puede mirar punto a punto.
//
// Las teselas se arman a mano —cuatro puntos y una clase— porque así se puede
// escribir el caso exacto: la costa recta, el cayo, la laguna y el lazo
// degenerado que rompió el relevo en la z8/72/113 de Cuba. La muestra de verdad
// (`muestra/cuba-muestra.pmtiles`, z0..z6, sólo costa y carreteras) se usa
// al final para que esto no sea sólo consistente consigo mismo.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/colores.dart';
import 'package:reparto/mapa/fondo_del_paquete.dart';
import 'package:reparto/mapa/mvt.dart';
import 'package:reparto/mapa/pmtiles.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';

/// El lado en píxeles con el que se piden todas las pruebas de aquí.
const lado = 256.0;

/// La resolución de una tesela vectorial. Se escriben las pruebas en unidades de
/// tesela y se multiplica por esto: así los números son los mismos que los del
/// fichero y se pueden comparar con una sonda.
const extension = 4096;

/// Un punto en unidades de tesela, a partir de píxeles.
Offset u(double xPixeles, double yPixeles) =>
    Offset(xPixeles * extension / lado, yPixeles * extension / lado);

CapaVectorial _capaDeCosta(List<List<Offset>> lineas) => CapaVectorial(
  nombre: 'costa',
  extension: extension,
  rasgos: [
    for (final linea in lineas)
      RasgoVectorial(
        forma: FormaVectorial.linea,
        partes: [linea],
        clase: 'costa',
      ),
  ],
);

/// ¿Cae este punto (en píxeles) dentro del mar?
bool esMar(List<List<Offset>>? anillos, Offset punto) =>
    anillos != null && caminoDelMar(anillos).contains(punto);

/// El área que ocupan los anillos, en píxeles cuadrados y con signo.
double _areaDe(List<List<Offset>> anillos) {
  var total = 0.0;
  for (final anillo in anillos) {
    for (var i = 0; i + 1 < anillo.length; i++) {
      total +=
          anillo[i].dx * anillo[i + 1].dy - anillo[i + 1].dx * anillo[i].dy;
    }
  }
  return total / 2;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('coser la costa', () {
    test('los trozos que comparten un extremo salen en UNA cadena', () {
      // La costa llega partida en una vía de OSM por trozo. Sin coserlos, un
      // trozo que empieza y acaba en mitad del cuadro no se puede cerrar contra
      // ningún borde y el mar de esa tesela se daría por perdido.
      final capas = [
        _capaDeCosta([
          [u(128, 0), u(128, 80)],
          [u(128, 80), u(128, 170)],
          [u(128, 170), u(128, 256)],
        ]),
      ];

      final cadenas = coserLaCosta(capas);

      expect(cadenas, hasLength(1));
      expect(cadenas.single.first, u(128, 0));
      expect(cadenas.single.last, u(128, 256));
    });

    test('un anillo cerrado sale entero aunque llegue en trozos', () {
      final capas = [
        _capaDeCosta([
          [u(60, 60), u(180, 60)],
          [u(180, 60), u(180, 180)],
          [u(180, 180), u(60, 180)],
          [u(60, 180), u(60, 60)],
        ]),
      ];

      final cadenas = coserLaCosta(capas);

      expect(cadenas, hasLength(1));
      expect(cadenas.single.first, cadenas.single.last);
    });
  });

  group('de qué lado está el agua', () {
    // En OSM la costa se dibuja SIEMPRE con la tierra a la izquierda según se
    // camina. La tesela le da la vuelta al eje vertical, así que aquí dentro la
    // tierra queda a la derecha y el agua a la izquierda. Estas dos pruebas son
    // esa regla, y son las que se rompen si alguien "arregla" un signo.

    test('bajando por el medio, el mar es la mitad de la IZQUIERDA', () {
      final mar = marDeLaCosta([
        _capaDeCosta([
          [u(128, 0), u(128, 256)],
        ]),
      ], lado: lado);

      expect(mar, isNotNull);
      expect(
        esMar(mar, const Offset(40, 128)),
        isTrue,
        reason: 'el agua va a la izquierda del sentido de la costa',
      );
      expect(esMar(mar, const Offset(200, 128)), isFalse);
      expect(
        _areaDe(mar!),
        closeTo(lado * lado / 2, 1),
        reason: 'media tesela, ni más ni menos',
      );
    });

    test('subiendo por el medio, el mar es la mitad de la DERECHA', () {
      final mar = marDeLaCosta([
        _capaDeCosta([
          [u(128, 256), u(128, 0)],
        ]),
      ], lado: lado);

      expect(esMar(mar, const Offset(200, 128)), isTrue);
      expect(esMar(mar, const Offset(40, 128)), isFalse);
    });
  });

  group('el anillo se cierra por el BORDE', () {
    test('una costa en diagonal no deja ni un tramo por dentro', () {
      // ÉSTA ES LA PRUEBA DE LA RAYA INVENTADA. Un anillo que se cierre uniendo
      // su final con su principio dibuja una recta a través de la tesela; el
      // mismo trozo de mar en la tesela de al lado se cerraría por otro sitio y
      // se vería el corte. Cerrando por el borde, la raya cae donde las dos
      // teselas la comparten.
      final mar = marDeLaCosta([
        _capaDeCosta([
          [u(0, 60), u(90, 100), u(256, 200)],
        ]),
      ], lado: lado);

      expect(mar, isNotNull);
      for (final anillo in mar!) {
        for (var i = 0; i + 1 < anillo.length; i++) {
          final a = anillo[i];
          final b = anillo[i + 1];
          final deLaCosta = _enLaCosta(a) && _enLaCosta(b);
          if (deLaCosta) continue;
          expect(
            _enElBorde(a) && _enElBorde(b),
            isTrue,
            reason:
                'el tramo $a → $b no es costa y tampoco va por el borde: es una '
                'raya recta cruzando la tesela',
          );
        }
      }
    });

    test('la esquina del cuadro entra en el anillo', () {
      // Sin las esquinas el mar se cerraría en diagonal de un borde a otro y se
      // comería el pico de tierra que hay entre los dos.
      final mar = marDeLaCosta([
        _capaDeCosta([
          [u(200, 0), u(230, 120), u(256, 130)],
        ]),
      ], lado: lado);

      expect(
        mar!.single,
        contains(const Offset(0, 0)),
        reason: 'de la costa al borde de arriba se pasa por la esquina',
      );
    });
  });

  group('cuando NO se puede decir, se dice que no', () {
    test('sin capa de costa no hay mar', () {
      // Una tesela de tierra adentro —La Habana a z14— no lleva costa. Ahí el
      // papel es la respuesta buena, no un azul por si acaso.
      expect(
        marDeLaCosta([
          CapaVectorial(
            nombre: 'carretera',
            extension: extension,
            rasgos: const [],
          ),
        ], lado: lado),
        isNull,
      );
    });

    test('una costa con un cabo suelto NO se cierra a ojo', () {
      // Si el generador deja una costa que muere en mitad del cuadro, cerrarla
      // contra el borde más cercano pintaría de agua media ciudad. Antes
      // ninguno que uno inventado.
      final mar = marDeLaCosta([
        _capaDeCosta([
          [u(0, 60), u(128, 128)],
        ]),
      ], lado: lado);

      expect(mar, isNull);
    });
  });

  group('cayos y lagunas', () {
    test('un cayo deja un agujero en el mar', () {
      // El anillo de un cayo tiene la TIERRA dentro: recorrido con el agua a la
      // izquierda sale con el área negativa, y así se lee como agujero.
      final mar = marDeLaCosta([
        _capaDeCosta([
          [u(100, 100), u(100, 160), u(160, 160), u(160, 100), u(100, 100)],
        ]),
      ], lado: lado);

      expect(mar, isNotNull);
      expect(
        esMar(mar, const Offset(130, 130)),
        isFalse,
        reason: 'dentro del cayo hay tierra',
      );
      expect(
        esMar(mar, const Offset(20, 20)),
        isTrue,
        reason: 'un cayo está rodeado de mar por definición',
      );
    });

    test('una laguna es agua, y lo de fuera es tierra', () {
      // El mismo anillo al revés: el agua queda dentro. Es una laguna abierta al
      // mar, y entonces lo que la rodea es tierra.
      final mar = marDeLaCosta([
        _capaDeCosta([
          [u(100, 100), u(160, 100), u(160, 160), u(100, 160), u(100, 100)],
        ]),
      ], lado: lado);

      expect(esMar(mar, const Offset(130, 130)), isTrue);
      expect(esMar(mar, const Offset(20, 20)), isFalse);
    });
  });

  test('cuando el relevo se rompe, el anillo se cierra por el BORDE', () {
    // LA REGRESIÓN DE LA z8/72/113, en el Golfo de Guacanayabo. El generador
    // deja lazos como el primero de aquí abajo: cuatro puntos que se cruzan
    // consigo mismos y cruzan cuatro veces el borde de arriba —es lo que queda
    // al simplificar una punta de costa de dos metros—. Recortado, sale en dos
    // trozos cuyos extremos ya no se alternan en el borde, así que cuando le
    // toca el turno a la costa de verdad su relevo ya está gastado.
    //
    // Se vio de las dos formas antes de llegar aquí, y las dos están en el
    // código como lo que NO se hace: cerrar contra el arranque en línea recta
    // dibujó un pico de tierra atravesando el golfo en diagonal, y cerrar dando
    // la vuelta entera al borde dejó la tesela azul con sus dos pueblos dentro.
    //
    // El orden importa y por eso se escribe así: el lazo va PRIMERO, como en el
    // fichero, y la costa acaba en el borde de arriba ANTES de donde el lazo
    // empieza.
    final mar = marDeLaCosta([
      _capaDeCosta([
        [
          u(237.50, 0.44),
          u(238.19, -0.38),
          u(238.69, 1.06),
          u(237.38, -1.19),
          u(237.50, 0.44),
        ],
        [u(256, 80), u(200, 30), u(150, 0)],
      ]),
    ], lado: lado);

    expect(mar, isNotNull);
    expect(
      esMar(mar, const Offset(240, 20)),
      isTrue,
      reason:
          'el mar que queda entre la costa y las dos esquinas de arriba: si el '
          'anillo se cerró en recta contra su arranque, esto se queda fuera',
    );
    expect(
      esMar(mar, const Offset(100, 200)),
      isFalse,
      reason:
          'y la tierra sigue siendo tierra: si el anillo dio la vuelta entera '
          'al borde, el mar se la come',
    );
  });

  group('de qué lado cae un punto', () {
    test('esAgua mira el trozo de costa más cercano', () {
      final costa = [
        [const Offset(128, 0), const Offset(128, 256)],
      ];
      expect(esAgua(const Offset(40, 128), costa), isTrue);
      expect(esAgua(const Offset(200, 128), costa), isFalse);
    });

    test('sin costa no contesta', () {
      expect(esAgua(const Offset(40, 128), const []), isNull);
    });
  });

  group('contra el paquete de verdad', () {
    Future<PaqueteDeTeselas> muestra() async => PaqueteDeTeselas.abrir(
      RangosEnMemoria(
        await File('test/mapa/muestra/cuba-muestra.pmtiles').readAsBytes(),
      ),
    );

    test(
      'a z6 La Habana es tierra y el Atlántico de enfrente es mar',
      () async {
        final capas = leerTeselaVectorial(
          (await (await muestra()).tesela(6, 17, 27))!,
        );
        final mar = marDeLaCosta(capas, lado: lado);

        expect(
          esMar(mar, _enLaTesela(-82.38, 23.13, 6, 17, 27)),
          isFalse,
          reason: 'el Malecón es tierra',
        );
        expect(
          esMar(mar, _enLaTesela(-82.38, 24.60, 6, 17, 27)),
          isTrue,
          reason: 'y 160 km al norte es el estrecho de la Florida',
        );
      },
    );

    test('y el dibujo lleva los dos colores', () async {
      final imagen = await FondoDelPaquete(await muestra()).tesela(6, 17, 27);
      final datos = await imagen!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final bytes = datos!.buffer.asUint8List();
      var deMar = 0;
      var dePapel = 0;
      for (var i = 0; i + 3 < bytes.length; i += 4) {
        if (_esEsteColor(bytes, i, ColoresDelMapa.agua)) deMar++;
        if (_esEsteColor(bytes, i, ColoresDelMapa.fondo)) dePapel++;
      }
      expect(deMar, greaterThan(5000), reason: 'el mar no se está pintando');
      expect(
        dePapel,
        greaterThan(1000),
        reason: 'la tierra dejó de ser tierra: el mar se lo comió todo',
      );
    });

    test('la costa de la muestra cierra en TODAS sus teselas', () async {
      // La guarda de `marDeLaCosta` devuelve nada cuando la costa no cuadra. Si
      // un día el generador empieza a partirla de otra forma, esto se pone rojo
      // antes de que nadie vea una tesela crema en mitad del mar.
      final paquete = await muestra();
      for (var z = paquete.cabecera.zMin; z <= paquete.cabecera.zMax; z++) {
        for (var x = 0; x < 1 << z; x++) {
          for (var y = 0; y < 1 << z; y++) {
            final crudo = await paquete.tesela(z, x, y);
            if (crudo == null) continue;
            final capas = leerTeselaVectorial(crudo);
            if (!capas.any((c) => c.nombre == 'costa')) continue;
            expect(
              marDeLaCosta(capas, lado: lado),
              isNotNull,
              reason: 'la z$z/$x/$y trae costa y no se le pudo sacar el mar',
            );
          }
        }
      }
    });

    test('el mar abierto que el paquete no guarda sale del antepasado', () async {
      // El paquete sólo guarda las teselas que llevan algo dentro, y a cien
      // kilómetros de la costa no hay nada que guardar. Antes eso era una tesela
      // que no llegaba, o sea papel, o sea tierra.
      final fondo = FondoDelPaquete(await muestra());

      // z6/16/26: el Golfo de México, al norte de Cuba. No está en la muestra.
      final imagen = await fondo.tesela(6, 16, 26);
      expect(
        imagen,
        isNotNull,
        reason: 'el antepasado z5/8/13 sí está y sabe decir que eso es mar',
      );

      final datos = await imagen!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final bytes = datos!.buffer.asUint8List();
      var deMar = 0;
      for (var i = 0; i + 3 < bytes.length; i += 4) {
        if (_esEsteColor(bytes, i, ColoresDelMapa.agua)) deMar++;
      }
      expect(deMar, greaterThan(60000), reason: 'ahí fuera es todo mar');
    });

    test('la RED manda sobre el antepasado', () async {
      // El antepasado sólo sabe decir si algo es mar. Si hay red, lo suyo es
      // pedirle la tesela de verdad, con sus calles.
      final red = _RedQueCuenta();
      final fondo = FondoDelPaquete(await muestra(), respaldo: red);

      await fondo.tesela(6, 16, 26);

      expect(
        red.llamadas,
        1,
        reason:
            'si el paquete no la tiene se pregunta fuera ANTES de conformarse '
            'con pintar agua',
      );
    });

    test('más allá del tope no se inventa nada', () async {
      // El antepasado se busca hasta [saltosParaElMar] niveles arriba. Sin ese
      // tope se acaba llegando al z0, donde «lo que no es Cuba es mar» quiere
      // decir que Florida es mar.
      final fondo = FondoDelPaquete(await muestra());
      expect(await fondo.tesela(6, 0, 0), isNull);
      expect(saltosParaElMar, 4);
    });
  });

  // ── EL MAR NO SE PUEDE PINTAR TIERRA ADENTRO ──────────────────────────────
  //
  // Éste es el agujero que faltaba, y es el que se ve: todas las pruebas de
  // arriba le dan a `marDeLaCosta` una tesela con la costa DENTRO del cuadro.
  // La que se pinta mal de verdad es la otra — la que no tiene ni un metro de
  // costa dentro y hay que decidirla ENTERA por el sentido de la costa que pasa
  // fuera (la rama de `cadenas.isEmpty`, que resuelve `esAgua`).
  //
  // Si ese sentido se invierte, o si se contesta «mar» cuando no se sabe,
  // **Camagüey se pinta de azul** y no lo desmiente nadie: el repartidor ve agua
  // donde hay carretera, y este mapa es el que se usa SIN CONEXIÓN, que es justo
  // cuando no hay con qué contrastarlo.
  //
  // Las dos teselas de abajo son la MISMA geometría con el sentido al revés, a
  // propósito: así ninguna de las dos puede salir verde por casualidad.
  group('sin costa dentro, la tesela se decide por el sentido de la de fuera', () {
    // LA COSTA NORTE DE CUBA, escrita como la escribe OpenStreetMap: la tierra a
    // la izquierda según se camina. Mirando al OESTE, el sur —la isla— queda a
    // mano izquierda, así que la costa norte se camina de este a oeste. Cruza el
    // cuadro entero a lo ancho y se queda fuera por arriba o por abajo, según
    // [y].
    List<Offset> costaNorte(double y) => [u(400, y), u(-140, y)];

    // Y LA COSTA SUR, la misma regla y por eso al revés: mirando al ESTE, el
    // norte —la isla— queda a mano izquierda.
    List<Offset> costaSur(double y) => [u(-140, y), u(400, y)];

    test('CAMAGÜEY (21,3808 N · 77,9169 O) NO puede salir como mar', () {
      // Camagüey ciudad está a unos 60 km de la costa norte y a unos 80 de la
      // del sur: su tesela no lleva ni un metro de costa dentro. Las dos costas
      // quedan fuera del cuadro —la del norte por encima, la del sur por
      // debajo— y las dos contestan lo mismo: aquí es TIERRA.
      final mar = marDeLaCosta([
        _capaDeCosta([costaNorte(-30), costaSur(316)]),
      ], lado: lado);

      expect(
        mar,
        isNull,
        reason:
            'Camagüey (21,3808 N · 77,9169 O) va entre las dos costas, a 60 km '
            'de la de arriba y a 80 de la de abajo, y salió con mar: '
            '${_comoSalio(mar)}. Tierra adentro el papel es la respuesta buena; '
            'el azul aquí es el mapa mintiendo, y sin conexión no hay con qué '
            'desmentirlo',
      );
    });

    test('y con UNA sola costa fuera, tampoco', () {
      // La misma tesela vista sólo con la costa del norte. Va aparte porque el
      // desempate de `esAgua` coge el trozo de costa MÁS CERCANO: con dos, una
      // de las dos podría estar tapando a la otra.
      for (final (nombre, capa) in <(String, List<Offset>)>[
        ('sólo la costa norte, por encima', costaNorte(-30)),
        ('sólo la costa sur, por debajo', costaSur(316)),
      ]) {
        expect(
          marDeLaCosta([
            _capaDeCosta([capa]),
          ], lado: lado),
          isNull,
          reason:
              'con $nombre, Camagüey salió como mar: '
              '${_comoSalio(marDeLaCosta([
                _capaDeCosta([capa]),
              ], lado: lado))}',
        );
      }
    });

    test('EL CARIBE al sur de Cuba (19,50 N · 77,50 O) SÍ es mar', () {
      // Mar abierto entre Cuba y Jamaica, a unos 200 km de la costa sur. Lo
      // único que se ve de costa es esa, muy por encima del cuadro: **la misma
      // línea y el mismo sitio que en la prueba de Camagüey**, y lo único que
      // cambia es hacia dónde se camina. De ahí sale de qué lado está la tierra,
      // y es toda la decisión.
      final mar = marDeLaCosta([
        _capaDeCosta([costaSur(-30)]),
      ], lado: lado);

      expect(
        mar,
        isNotNull,
        reason:
            'el Caribe (19,50 N · 77,50 O) se quedó sin mar: la costa sur pasa '
            'por encima con la tierra a su izquierda, así que todo lo de debajo '
            'es agua. En papel, eso es el Caribe pintado de tierra',
      );
      expect(
        esMar(mar, const Offset(128, 128)),
        isTrue,
        reason:
            'salió ${_comoSalio(mar)} y el centro de la tesela no cae dentro',
      );
      expect(
        _areaDe(mar!).abs(),
        closeTo(lado * lado, 1),
        reason: 'mar abierto: la tesela entera, ni más ni menos',
      );
    });

    test('contra el paquete de verdad: Camagüey es tierra a z6', () async {
      // Y lo mismo con datos de OSM, no dibujados a mano. La z6/18/28 es la que
      // contiene Camagüey (21,3808 N · 77,9169 O) y también el Caribe de
      // enfrente (19,50 N · 77,50 O), así que la pareja entera cabe en una
      // tesela de la muestra.
      final paquete = await PaqueteDeTeselas.abrir(
        RangosEnMemoria(
          await File('test/mapa/muestra/cuba-muestra.pmtiles').readAsBytes(),
        ),
      );
      final crudo = await paquete.tesela(6, 18, 28);
      expect(crudo, isNotNull, reason: 'la muestra tiene que traer la z6/18/28');
      final mar = marDeLaCosta(leerTeselaVectorial(crudo!), lado: lado);

      expect(
        esMar(mar, _enLaTesela(-77.9169, 21.3808, 6, 18, 28)),
        isFalse,
        reason:
            'Camagüey ciudad (21,3808 N · 77,9169 O) salió pintada de agua '
            'sobre el paquete de verdad; salió ${_comoSalio(mar)}',
      );
      expect(
        esMar(mar, _enLaTesela(-77.50, 19.50, 6, 18, 28)),
        isTrue,
        reason:
            'y el Caribe de enfrente (19,50 N · 77,50 O) salió de papel; salió '
            '${_comoSalio(mar)}',
      );
    });
  });
}

bool _enElBorde(Offset p) =>
    p.dx.abs() < 0.01 ||
    p.dy.abs() < 0.01 ||
    (p.dx - lado).abs() < 0.01 ||
    (p.dy - lado).abs() < 0.01;

/// La costa de `una costa en diagonal no deja ni un tramo por dentro`: los tres
/// puntos que se le dieron, y los cortes contra el borde.
bool _enLaCosta(Offset p) {
  const puntos = [Offset(0, 60), Offset(90, 100), Offset(256, 200)];
  return puntos.any((q) => (p - q).distance < 0.01);
}

class _RedQueCuenta implements FondoDeCalles {
  int llamadas = 0;

  @override
  Future<ui.Image?> tesela(int z, int x, int y) async {
    llamadas++;
    return null;
  }
}

/// Dónde cae un punto del mundo dentro de una tesela, en píxeles. Mercator web,
/// la misma proyección que usa el croquis: con otra, la prueba miraría otro
/// sitio y saldría verde sin serlo.
Offset _enLaTesela(double lon, double lat, int z, int x, int y) {
  final n = (1 << z).toDouble();
  final seno = math.sin(lat * math.pi / 180);
  final aLoAncho = (lon + 180) / 360 * n;
  final aLoAlto = (0.5 - math.log((1 + seno) / (1 - seno)) / (4 * math.pi)) * n;
  return Offset((aLoAncho - x) * lado, (aLoAlto - y) * lado);
}

/// El píxel que empieza en [i] (RGBA sin premultiplicar), ¿es [color]?
///
/// Se compara canal a canal y no con `Color.value`, que está deprecado y además
/// arrastra el alfa: lo que se quiere saber aquí es de qué color se pintó, no
/// con qué opacidad se compuso.
bool _esEsteColor(Uint8List bytes, int i, ui.Color color) =>
    bytes[i] == (color.r * 255).round() &&
    bytes[i + 1] == (color.g * 255).round() &&
    bytes[i + 2] == (color.b * 255).round();

/// Cómo se cuenta en un mensaje de fallo lo que salió de `marDeLaCosta`.
///
/// Un `null` a secas no dice nada cuando la prueba se pone roja: hace falta
/// saber **cuánta tesela** se pintó de agua, que es lo que se ve en el teléfono.
String _comoSalio(List<List<Offset>>? mar) {
  if (mar == null) return 'nada (null), o sea «aquí no se pinta agua»';
  final tapado = _areaDe(mar).abs() / (lado * lado) * 100;
  return '${mar.length} anillo(s) de agua que tapan el '
      '${tapado.toStringAsFixed(1)} % de la tesela';
}
