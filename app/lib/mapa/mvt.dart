// EL DECODIFICADOR DE TESELAS VECTORIALES (Mapbox Vector Tile).
//
// ## Por que se escribe a mano en vez de meter una biblioteca de mapas
//
// La decision de esta casa ya estaba tomada y esta razonada en
// `pantallas/rutas/vista/croquis_de_ruta.dart`: **el mapa se dibuja con un
// `CustomPainter` y proyeccion Mercator web, sin ninguna biblioteca de mapas**.
// Meter ahora `vector_map_tiles` o `maplibre` para poder leer esto seria tirar
// esa decision por un decodificador que cabe en este fichero.
//
// Y hay tres razones mas, en orden de peso:
//
//  1. **Lo que hay que dibujar son cuatro capas**: carreteras, costa, agua y
//     nucleos. No hay etiquetas curvadas, ni rotacion, ni inclinacion, ni
//     estilos de Mapbox. Una biblioteca de mapas trae todo eso y su peso en el
//     APK, y en el patio de un almacen no se usa ni una linea.
//  2. **No puede romper la web ni el escritorio.** `maplibre` es un plugin con
//     codigo nativo por destino; esto es Dart puro y compila en los cuatro.
//  3. Este formato es **publico y esta congelado** (MVT 2.1). No hay una version
//     nueva que perseguir: lo que se escriba aqui vale igual dentro de cinco
//     anos.
//
// ## Lo unico que hay que entender del formato
//
// Una tesela es un protobuf con capas; cada capa trae sus rasgos; cada rasgo
// trae su geometria como una **tira de ordenes** —«muevete aqui», «traza hasta
// alla», «cierra»— con las coordenadas en *unidades de tesela* (4096 por lado,
// no pixeles) y **en incrementos** respecto al punto anterior.
//
// Eso ultimo es lo que hace que ocupe tan poco: una calle de cien puntos son
// cien parejas de numeros pequenos, no cien parejas de coordenadas de siete
// cifras.
//
// ## Lo que este decodificador NO hace, y es a proposito
//
// No valida que el fichero venga de nadie. Lo que lo hace fiable es el `sha256`
// que se comprueba al terminar la descarga (`descarga_de_mapa.dart`): sin esa
// comprobacion, ningun cuidado aqui serviria de nada. Lo que si hace es **no
// reventar** con bytes que no entiende —salta el campo y sigue—, porque esto
// corre dentro del repintado del mapa y una excepcion ahi deja la pantalla en
// negro en vez de dejar el croquis debajo.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

/// Las tres formas que trae una tesela.
enum FormaVectorial { punto, linea, area }

/// Un rasgo ya decodificado. Las coordenadas van en **unidades de tesela**.
class RasgoVectorial {
  const RasgoVectorial({
    required this.forma,
    required this.partes,
    this.clase,
    this.nombre,
  });

  final FormaVectorial forma;

  /// Las partes: una linea suelta tiene una; un area con isla tiene varias.
  final List<List<Offset>> partes;

  /// `clase` y `nombre` son las dos unicas propiedades que escribe nuestro
  /// generador (`herramientas/mapa-cuba/teselar.go`). Cualquier otra se lee y
  /// se tira: un fichero de `tippecanoe` trae docenas y no se usa ninguna.
  final String? clase;
  final String? nombre;
}

/// Una capa: su nombre, su resolucion y sus rasgos.
class CapaVectorial {
  const CapaVectorial({
    required this.nombre,
    required this.extension,
    required this.rasgos,
  });

  final String nombre;

  /// Cuantas unidades mide la tesela por lado. **Casi siempre 4096, pero se lee
  /// del fichero y no se supone**: dar por hecho 4096 sobre una tesela de 512
  /// dibuja todo apelotonado en una esquina, y se ve raro sin saltar.
  final int extension;

  final List<RasgoVectorial> rasgos;
}

/// Lee una tesela MVT ya descomprimida. Devuelve las capas, o una lista vacia si
/// los bytes no son una tesela. **Nunca lanza.**
List<CapaVectorial> leerTeselaVectorial(Uint8List crudo) {
  try {
    final capas = <CapaVectorial>[];
    final lector = _Lector(crudo);
    while (!lector.seAcabo) {
      final (campo, tipo) = lector.etiqueta();
      if (campo == 3 && tipo == 2) {
        final capa = _leerCapa(lector.trozo());
        if (capa != null) capas.add(capa);
      } else {
        lector.saltar(tipo);
      }
    }
    return capas;
  } on Object {
    // Bytes que no son una tesela. Devolver vacio deja el croquis debajo, que
    // es el cimiento y no necesita a nadie; lanzar tumbaria el repintado.
    return const [];
  }
}

CapaVectorial? _leerCapa(Uint8List crudo) {
  var nombre = '';
  var extension = 4096;
  final claves = <String>[];
  final valores = <String?>[];
  final rasgosCrudos = <Uint8List>[];

  final lector = _Lector(crudo);
  while (!lector.seAcabo) {
    final (campo, tipo) = lector.etiqueta();
    switch (campo) {
      case 1 when tipo == 2:
        nombre = lector.texto();
      case 2 when tipo == 2:
        rasgosCrudos.add(lector.trozo());
      case 3 when tipo == 2:
        claves.add(lector.texto());
      case 4 when tipo == 2:
        valores.add(_leerValor(lector.trozo()));
      case 5 when tipo == 0:
        extension = lector.varint();
      default:
        lector.saltar(tipo);
    }
  }
  if (nombre.isEmpty || extension <= 0) return null;

  final rasgos = <RasgoVectorial>[];
  for (final crudo in rasgosCrudos) {
    final r = _leerRasgo(crudo, claves, valores);
    if (r != null) rasgos.add(r);
  }
  return CapaVectorial(nombre: nombre, extension: extension, rasgos: rasgos);
}

/// Un valor de propiedad. Se devuelve siempre como texto: lo unico que hace este
/// mapa con ellos es comparar la clase y rotular el nombre.
String? _leerValor(Uint8List crudo) {
  final lector = _Lector(crudo);
  while (!lector.seAcabo) {
    final (campo, tipo) = lector.etiqueta();
    switch (campo) {
      case 1 when tipo == 2:
        return lector.texto();
      case 4 when tipo == 0:
        return lector.varint().toString();
      case 5 when tipo == 0:
        return lector.varint().toString();
      case 6 when tipo == 0:
        return _zigzag(lector.varint()).toString();
      case 7 when tipo == 0:
        return lector.varint() != 0 ? 'true' : 'false';
      default:
        lector.saltar(tipo);
    }
  }
  return null;
}

RasgoVectorial? _leerRasgo(
  Uint8List crudo,
  List<String> claves,
  List<String?> valores,
) {
  var tipoGeo = 0;
  List<int> etiquetas = const [];
  List<int> geometria = const [];

  final lector = _Lector(crudo);
  while (!lector.seAcabo) {
    final (campo, tipo) = lector.etiqueta();
    switch (campo) {
      case 2 when tipo == 2:
        etiquetas = _Lector(lector.trozo()).varintsSeguidos();
      case 3 when tipo == 0:
        tipoGeo = lector.varint();
      case 4 when tipo == 2:
        geometria = _Lector(lector.trozo()).varintsSeguidos();
      default:
        lector.saltar(tipo);
    }
  }

  final forma = switch (tipoGeo) {
    1 => FormaVectorial.punto,
    2 => FormaVectorial.linea,
    3 => FormaVectorial.area,
    // `0` es UNKNOWN en el formato. No se dibuja: no hay forma de saber si es
    // una linea o un area, y adivinar pinta manchas donde habia calles.
    _ => null,
  };
  if (forma == null) return null;

  final partes = _leerGeometria(geometria, forma);
  if (partes.isEmpty) return null;

  String? clase;
  String? nombre;
  for (var i = 0; i + 1 < etiquetas.length; i += 2) {
    final c = etiquetas[i];
    final v = etiquetas[i + 1];
    if (c >= claves.length || v >= valores.length) continue;
    switch (claves[c]) {
      case 'clase':
        clase = valores[v];
      case 'nombre':
        nombre = valores[v];
    }
  }
  return RasgoVectorial(
    forma: forma,
    partes: partes,
    clase: clase,
    nombre: nombre,
  );
}

/// LA TIRA DE ORDENES. Es lo unico del formato que no es obvio.
///
/// Cada orden es un numero que lleva dentro **que hacer** (los tres bits de
/// abajo) y **cuantas veces** (el resto). Las coordenadas van en incrementos y
/// con signo en zigzag.
List<List<Offset>> _leerGeometria(List<int> g, FormaVectorial forma) {
  final partes = <List<Offset>>[];
  List<Offset>? actual;
  var x = 0;
  var y = 0;
  var i = 0;

  while (i < g.length) {
    final orden = g[i++];
    final cual = orden & 0x7;
    final cuantas = orden >> 3;

    switch (cual) {
      case 1: // muévete aquí: empieza una parte nueva
        for (var n = 0; n < cuantas && i + 1 < g.length; n++) {
          x += _zigzag(g[i++]);
          y += _zigzag(g[i++]);
          actual = [Offset(x.toDouble(), y.toDouble())];
          partes.add(actual);
        }
      case 2: // traza hasta allá
        for (var n = 0; n < cuantas && i + 1 < g.length; n++) {
          x += _zigzag(g[i++]);
          y += _zigzag(g[i++]);
          actual?.add(Offset(x.toDouble(), y.toDouble()));
        }
      case 7: // cierra el anillo
        if (actual != null && actual.length > 2) actual.add(actual.first);
      default:
        // Una orden que no existe. Se para aqui: seguir leyendo desplazado
        // dibuja una maranha de lineas por toda la tesela.
        i = g.length;
    }
  }

  // Un punto es un punto; una linea necesita dos; un area necesita tres.
  final minimo = switch (forma) {
    FormaVectorial.punto => 1,
    FormaVectorial.linea => 2,
    FormaVectorial.area => 3,
  };
  return [
    for (final parte in partes)
      if (parte.length >= minimo) parte,
  ];
}

int _zigzag(int v) => (v >> 1) ^ (-(v & 1));

/// Un lector de protobuf del tamaño justo. Nada de generar codigo: el esquema de
/// MVT son cuatro mensajes y esta congelado desde 2016.
class _Lector {
  _Lector(this.b);

  final Uint8List b;
  int i = 0;

  bool get seAcabo => i >= b.length;

  int varint() {
    var valor = 0;
    var desplazamiento = 0;
    while (i < b.length) {
      final byte = b[i++];
      valor |= (byte & 0x7F) << desplazamiento;
      if (byte & 0x80 == 0) return valor;
      desplazamiento += 7;
      if (desplazamiento > 63) throw const FormatException('varint sin fin');
    }
    throw const FormatException('varint cortado');
  }

  (int, int) etiqueta() {
    final v = varint();
    return (v >> 3, v & 0x7);
  }

  Uint8List trozo() {
    final largo = varint();
    if (largo < 0 || i + largo > b.length) {
      throw const FormatException('trozo más largo que el mensaje');
    }
    final salida = Uint8List.sublistView(b, i, i + largo);
    i += largo;
    return salida;
  }

  /// UTF-8 DE VERDAD, no `String.fromCharCodes`. Los nombres de aqui llevan
  /// tildes y enes —«Camagüey», «Ciego de Ávila», «La Peña»— y leidos byte a
  /// byte salen partidos en dos caracteres raros. `allowMalformed` para que un
  /// nombre mal codificado en OSM salga feo en vez de tumbar el repintado.
  String texto() => utf8.decode(trozo(), allowMalformed: true);

  List<int> varintsSeguidos() {
    final salida = <int>[];
    while (!seAcabo) {
      salida.add(varint());
    }
    return salida;
  }

  /// Saltar un campo que no interesa. **Hace falta de verdad**: sin esto, un
  /// fichero de `tippecanoe` —que trae campos que nosotros no escribimos— se
  /// leería desplazado a partir del primero, y eso no se ve como un error: se
  /// ve como un mapa de garabatos.
  void saltar(int tipo) {
    switch (tipo) {
      case 0:
        varint();
      case 1:
        i += 8;
      case 2:
        trozo();
      case 5:
        i += 4;
      default:
        throw FormatException('tipo de campo $tipo desconocido');
    }
  }
}
