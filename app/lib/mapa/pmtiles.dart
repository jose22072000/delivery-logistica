// EL LECTOR DEL PAQUETE: PMTiles v3.
//
// Un paquete de mapa es **un solo fichero**. Dentro lleva una cabecera de 127
// bytes, unos directorios y las teselas pegadas unas detras de otras. Sacar la
// tesela `z/x/y` es: mirar el directorio, saltar al sitio que diga, leer tantos
// bytes.
//
// ## Por que PMTiles y no MBTiles, que es SQLite y ya lo tenemos
//
// Se miraron los dos y el argumento de MBTiles es de peso: la aplicacion ya
// lleva SQLite dentro para la base local, asi que leer una tesela seria una
// consulta y no este fichero. Se eligio PMTiles por tres cosas concretas:
//
//  1. **Un fichero y nada mas.** SQLite se trae sus companeros (`-wal`, `-shm`)
//     y quiere permiso de escritura en la carpeta hasta para leer. Aqui lo que
//     hay es un fichero que se baja una vez, se comprueba por `sha256` y no se
//     vuelve a tocar: cuanto menos se parezca a una base de datos viva, mejor.
//  2. **Se lee por rangos.** Hoy se baja entero, que es lo que pidio Jose
//     —«que se descargue el mapa... cuando cargue sólo una vez»—, pero el dia
//     que haga falta ensenar una provincia sin bajarse Cuba, el formato ya lo
//     permite y el codigo de aqui no cambia.
//  3. **Lo escriben las herramientas de siempre.** `tippecanoe --output=x.pmtiles`
//     y `planetiler` sacan esto mismo. Si un dia nuestro generador se queda
//     corto, se cambia el generador y no la aplicacion.
//
// Lo que se perdio al elegirlo: hay que escribir este lector. Son doscientas
// lineas y el escritor esta en el mismo repositorio
// (`herramientas/mapa-cuba/pmtiles.go`), con una muestra generada por el uno y
// leida por el otro en `test/mapa/muestra/`. Esa pareja es lo unico que
// comprueba de verdad un formato binario: un lector que solo se prueba contra
// ficheros que el mismo escribe no comprueba nada.

import 'dart:convert';
import 'dart:typed_data';

import 'descomprimir.dart';

/// De donde salen los bytes. Una interfaz y no un `File` para poder probar el
/// lector con un fichero en memoria y **sin tocar el disco**.
abstract interface class LeerPorRangos {
  /// [largo] bytes a partir de [desde]. Lanza si no los hay: pedir mas alla del
  /// final es un fichero corrupto, no un caso normal.
  Future<Uint8List> leer(int desde, int largo);

  Future<void> cerrar();
}

/// Bytes que ya estan en memoria. Es lo que usan las pruebas.
class RangosEnMemoria implements LeerPorRangos {
  RangosEnMemoria(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List> leer(int desde, int largo) async {
    if (desde < 0 || largo < 0 || desde + largo > bytes.length) {
      throw RangeError('se pidieron $largo bytes en $desde de ${bytes.length}');
    }
    return Uint8List.sublistView(bytes, desde, desde + largo);
  }

  @override
  Future<void> cerrar() async {}
}

/// Lo que el paquete dice de si mismo.
class CabeceraDelPaquete {
  const CabeceraDelPaquete({
    required this.raizDesde,
    required this.raizLargo,
    required this.metaDesde,
    required this.metaLargo,
    required this.hojasDesde,
    required this.datosDesde,
    required this.entradas,
    required this.zMin,
    required this.zMax,
    required this.minLon,
    required this.minLat,
    required this.maxLon,
    required this.maxLat,
  });

  final int raizDesde;
  final int raizLargo;
  final int metaDesde;
  final int metaLargo;
  final int hojasDesde;
  final int datosDesde;

  /// Cuantas teselas hay. Sirve para una cosa muy concreta: decirlo en la
  /// pantalla, para que «tienes el mapa» sea un numero y no una promesa.
  final int entradas;

  final int zMin;
  final int zMax;
  final double minLon;
  final double minLat;
  final double maxLon;
  final double maxLat;
}

/// Lo que puede salir mal al abrir un paquete. Con nombre y con motivo: «no se
/// pudo abrir el mapa» no le dice a nadie que hacer.
class PaqueteIlegible implements Exception {
  const PaqueteIlegible(this.motivo);

  final String motivo;

  @override
  String toString() => motivo;
}

/// EL PAQUETE ABIERTO.
class PaqueteDeTeselas {
  PaqueteDeTeselas._(this._fuente, this.cabecera);

  final LeerPorRangos _fuente;
  final CabeceraDelPaquete cabecera;

  /// Los directorios ya leidos. Un directorio hoja cubre miles de teselas, asi
  /// que recordarlo ahorra una lectura por cada tesela de la misma zona — que en
  /// un telefono, con el fichero en la tarjeta, se nota.
  final _directorios = <int, List<_Entrada>>{};

  static const _tamanoDeCabecera = 127;

  /// Abre el paquete. Lanza [PaqueteIlegible] con el motivo si no lo es.
  static Future<PaqueteDeTeselas> abrir(LeerPorRangos fuente) async {
    Uint8List crudo;
    try {
      crudo = await fuente.leer(0, _tamanoDeCabecera);
    } on Object {
      throw const PaqueteIlegible(
        'el fichero del mapa tiene menos de 127 bytes: se quedó a medio bajar',
      );
    }
    final b = ByteData.sublistView(crudo);
    if (String.fromCharCodes(crudo.sublist(0, 7)) != 'PMTiles') {
      throw const PaqueteIlegible(
        'el fichero del mapa no empieza por «PMTiles»: no es un paquete de mapa',
      );
    }
    if (crudo[7] != 3) {
      throw PaqueteIlegible(
        'el paquete es de la versión ${crudo[7]} de PMTiles y esta aplicación '
        'lee la 3',
      );
    }
    // Las dos compresiones tienen que ser gzip y las teselas MVT. Si no lo son
    // se dice: leerlo igual da un mapa de garabatos, que es peor que no tenerlo.
    if (crudo[97] != 2 || crudo[98] != 2) {
      throw const PaqueteIlegible(
        'el paquete viene comprimido de otra forma; esta aplicación lee gzip',
      );
    }
    if (crudo[99] != 1) {
      throw const PaqueteIlegible(
        'el paquete trae teselas de imagen y no vectoriales: es el formato que '
        'ocupa 6,5 GB en vez de 26 MB',
      );
    }

    double grados(int pos) => b.getInt32(pos, Endian.little) / 1e7;
    final cabecera = CabeceraDelPaquete(
      raizDesde: b.getUint64(8, Endian.little),
      raizLargo: b.getUint64(16, Endian.little),
      metaDesde: b.getUint64(24, Endian.little),
      metaLargo: b.getUint64(32, Endian.little),
      hojasDesde: b.getUint64(40, Endian.little),
      datosDesde: b.getUint64(56, Endian.little),
      entradas: b.getUint64(80, Endian.little),
      zMin: crudo[100],
      zMax: crudo[101],
      minLon: grados(102),
      minLat: grados(106),
      maxLon: grados(110),
      maxLat: grados(114),
    );
    if (cabecera.entradas == 0) {
      // UNA RESPUESTA VACÍA NO ES UNA RESPUESTA BUENA (`CLAUDE.md` §3). Un
      // paquete sin una sola tesela se abre sin un error y deja el mapa en
      // blanco para siempre.
      throw const PaqueteIlegible(
        'el paquete no trae ni una tesela: el fichero está vacío o se generó mal',
      );
    }
    return PaqueteDeTeselas._(fuente, cabecera);
  }

  Future<void> cerrar() => _fuente.cerrar();

  /// Los metadatos del paquete, incluida **la atribución de OpenStreetMap**.
  /// Viaja dentro del fichero a propósito: la licencia la exige también sin
  /// conexión, y metida aquí no se pierde aunque cambie la pantalla.
  Future<Map<String, Object?>> metadatos() async {
    if (cabecera.metaLargo == 0) return const {};
    try {
      final crudo = await _fuente.leer(cabecera.metaDesde, cabecera.metaLargo);
      final texto = utf8.decode(descomprimirGzip(crudo), allowMalformed: true);
      final leido = jsonDecode(texto);
      return leido is Map<String, Object?> ? leido : const {};
    } on Object {
      return const {};
    }
  }

  /// LA TESELA `z/x/y`, **ya descomprimida**, o `null` si el paquete no la trae.
  ///
  /// `null` es lo normal, no una avería: el paquete sólo lleva las teselas que
  /// tienen algo, y en Cuba casi toda la caja es mar.
  Future<Uint8List?> tesela(int z, int x, int y) async {
    if (z < cabecera.zMin || z > cabecera.zMax) return null;
    final buscado = idDeTesela(z, x, y);
    if (buscado == null) return null;

    var desde = cabecera.raizDesde;
    var largo = cabecera.raizLargo;
    // Tres saltos son de sobra: la especificación no encadena más de dos niveles
    // de hoja. El tope está para que un fichero corrupto que se apunte a sí
    // mismo no deje la aplicación dando vueltas para siempre.
    for (var salto = 0; salto < 3; salto++) {
      final entradas = await _directorio(desde, largo);
      final e = _buscar(entradas, buscado);
      if (e == null) return null;
      if (e.repetida != 0) {
        try {
          final crudo = await _fuente.leer(cabecera.datosDesde + e.desde, e.largo);
          return descomprimirGzip(crudo);
        } on Object {
          // Una tesela ilegible es UNA tesela, no el paquete. Se devuelve null
          // y el mapa se dibuja sin ese trozo, con el croquis debajo.
          return null;
        }
      }
      desde = cabecera.hojasDesde + e.desde;
      largo = e.largo;
    }
    return null;
  }

  Future<List<_Entrada>> _directorio(int desde, int largo) async {
    final ya = _directorios[desde];
    if (ya != null) return ya;
    final crudo = await _fuente.leer(desde, largo);
    final entradas = _leerDirectorio(descomprimirGzip(crudo));
    _directorios[desde] = entradas;
    return entradas;
  }
}

/// Una fila de directorio.
class _Entrada {
  _Entrada(this.id, this.desde, this.largo, this.repetida);

  final int id;
  final int desde;
  final int largo;

  /// `0` significa **«esto apunta a un directorio hoja»**, no «una tesela que se
  /// repite cero veces». Tratarlo como tesela devuelve el directorio comprimido
  /// donde tenía que ir un dibujo, y eso se ve como un mapa en blanco.
  final int repetida;
}

List<_Entrada> _leerDirectorio(Uint8List datos) {
  final lector = _LectorDeVarints(datos);
  final cuantas = lector.varint();
  if (cuantas <= 0 || cuantas > 1 << 24) {
    // Un número absurdo aquí es un fichero corrupto, no un fichero grande. Sin
    // este tope, reservar esa lista tumba la aplicación.
    throw PaqueteIlegible('el directorio dice tener $cuantas entradas');
  }
  final ids = List<int>.filled(cuantas, 0);
  var ultimo = 0;
  for (var i = 0; i < cuantas; i++) {
    ultimo += lector.varint();
    ids[i] = ultimo;
  }
  final repetidas = [for (var i = 0; i < cuantas; i++) lector.varint()];
  final largos = [for (var i = 0; i < cuantas; i++) lector.varint()];
  final desdes = List<int>.filled(cuantas, 0);
  for (var i = 0; i < cuantas; i++) {
    final v = lector.varint();
    // `0` no es un desplazamiento: significa «va pegada a la anterior». Es lo
    // que permite que una tira de teselas seguidas no gaste ni un byte en decir
    // dónde está cada una.
    desdes[i] = (v == 0 && i > 0)
        ? desdes[i - 1] + largos[i - 1]
        : v - 1;
  }
  return [
    for (var i = 0; i < cuantas; i++)
      _Entrada(ids[i], desdes[i], largos[i], repetidas[i]),
  ];
}

/// La búsqueda del formato: **la última entrada con `id <= buscado`**, no la que
/// tenga ese id exacto. Esa diferencia es la que permite que una entrada de hoja
/// cubra un rango entero de teselas.
_Entrada? _buscar(List<_Entrada> entradas, int buscado) {
  var bajo = 0;
  var alto = entradas.length - 1;
  while (bajo <= alto) {
    final medio = (bajo + alto) ~/ 2;
    final id = entradas[medio].id;
    if (id > buscado) {
      alto = medio - 1;
    } else if (id < buscado) {
      bajo = medio + 1;
    } else {
      return entradas[medio];
    }
  }
  if (alto < 0) return null;
  final e = entradas[alto];
  if (e.repetida == 0) return e; // una hoja: cubre lo que venga detrás
  if (buscado - e.id < e.repetida) return e;
  return null;
}

/// EL IDENTIFICADOR DE UNA TESELA: el desplazamiento de su nivel más su posición
/// en la **curva de Hilbert**.
///
/// La curva es lo que mantiene juntos en el fichero los vecinos en el mapa.
/// Escrita al revés, el fichero se abre igual, pesa igual y devuelve la tesela
/// de otro sitio — que se ve como un mapa raro, no como un error. Por eso el
/// generador de Go y esto se prueban contra los mismos números
/// (`herramientas/mapa-cuba/mapa_cuba_test.go`).
int? idDeTesela(int z, int x, int y) {
  if (z < 0 || z > 26) return null;
  final cuantas = 1 << z;
  if (x < 0 || y < 0 || x >= cuantas || y >= cuantas) return null;

  var id = ((1 << (2 * z)) - 1) ~/ 3;
  var xi = x;
  var yi = y;
  for (var s = cuantas ~/ 2; s > 0; s ~/= 2) {
    final rx = (xi & s) > 0 ? 1 : 0;
    final ry = (yi & s) > 0 ? 1 : 0;
    id += s * s * ((3 * rx) ^ ry);
    if (ry == 0) {
      if (rx == 1) {
        xi = s - 1 - xi;
        yi = s - 1 - yi;
      }
      final t = xi;
      xi = yi;
      yi = t;
    }
  }
  return id;
}

class _LectorDeVarints {
  _LectorDeVarints(this.b);

  final Uint8List b;
  int i = 0;

  int varint() {
    var valor = 0;
    var desplazamiento = 0;
    while (i < b.length) {
      final byte = b[i++];
      valor |= (byte & 0x7F) << desplazamiento;
      if (byte & 0x80 == 0) return valor;
      desplazamiento += 7;
      if (desplazamiento > 63) {
        throw const PaqueteIlegible('el directorio del paquete está corrupto');
      }
    }
    throw const PaqueteIlegible('el directorio del paquete se acaba a medias');
  }
}
