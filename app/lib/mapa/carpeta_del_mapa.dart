// DONDE VIVE EL PAQUETE, y cómo se toca.
//
// Es un puerto, no un `File`, por la razón de siempre en esta casa: para poder
// probarlo. **Las pruebas inyectan el fichero, nunca lo bajan** — ni de
// Procovar, ni de OpenStreetMap, ni de Geofabrik.
//
// Y hay una segunda razón que no es de pruebas: `dart:io` no existe en el
// navegador y esta aplicación compila también para web. El paquete de mapa no se
// usa allí (`CLAUDE.md` §1), pero el código tiene que compilar igual en los
// cuatro destinos.
//
// ## Los tres nombres que hay dentro de la carpeta
//
//	cuba-<nivel>.pmtiles           el paquete bueno, comprobado por sha256
//	cuba-<nivel>.pmtiles.parcial   lo que se lleva bajado y todavía no vale
//	cuba-<nivel>.json              qué es lo que hay: versión, bytes y huella
//
// **El parcial se llama distinto a propósito.** Si lo que se está bajando y lo
// que ya vale compartieran nombre, una descarga cortada dejaría el mapa bueno
// pisado a medias: el chofer perdería el mapa que ya tenía por intentar
// actualizarlo, en la conexión de allá, que es donde más se corta. Así, hasta
// que el `sha256` no cuadra, el bueno no se toca.

import 'dart:typed_data';

import 'pmtiles.dart';

/// Lo que hace falta saber hacer con los ficheros del mapa.
abstract interface class CarpetaDelMapa {
  /// Cuántos bytes tiene [nombre], o `0` si no está. **`0` y «no está» son lo
  /// mismo aquí a propósito**: los dos significan «hay que empezar por el
  /// principio».
  Future<int> bytes(String nombre);

  /// Añade al final. Es lo que hace posible reanudar.
  Future<void> anadir(String nombre, List<int> trozo);

  Future<void> borrar(String nombre);

  Future<void> renombrar(String de, String a);

  /// El contenido en trozos, para calcular el `sha256` sin cargarse 26 MB en la
  /// memoria de un teléfono.
  Stream<List<int>> porTrozos(String nombre);

  /// Para leer teselas sueltas sin cargar el fichero entero.
  Future<LeerPorRangos> porRangos(String nombre);

  Future<void> escribirTexto(String nombre, String texto);

  Future<String?> leerTexto(String nombre);
}

/// UNA CARPETA EN MEMORIA. Es lo que usan las pruebas, y lo que permite
/// ejercitar la reanudación y el `sha256` **sin una sola petición de red y sin
/// tocar el disco**.
class CarpetaEnMemoria implements CarpetaDelMapa {
  final Map<String, List<int>> _ficheros = {};

  /// Para que una prueba pueda dejar un fichero puesto de entrada.
  void sembrar(String nombre, List<int> contenido) {
    _ficheros[nombre] = [...contenido];
  }

  bool tiene(String nombre) => _ficheros.containsKey(nombre);

  @override
  Future<int> bytes(String nombre) async => _ficheros[nombre]?.length ?? 0;

  @override
  Future<void> anadir(String nombre, List<int> trozo) async {
    (_ficheros[nombre] ??= <int>[]).addAll(trozo);
  }

  @override
  Future<void> borrar(String nombre) async => _ficheros.remove(nombre);

  @override
  Future<void> renombrar(String de, String a) async {
    final contenido = _ficheros.remove(de);
    if (contenido != null) _ficheros[a] = contenido;
  }

  @override
  Stream<List<int>> porTrozos(String nombre) async* {
    final contenido = _ficheros[nombre];
    if (contenido == null) return;
    // En trozos de verdad, no de una vez: es lo que ejercita el cálculo por
    // partes del sha256, que es como corre en el aparato.
    for (var i = 0; i < contenido.length; i += 8192) {
      yield contenido.sublist(i, i + 8192 > contenido.length ? contenido.length : i + 8192);
    }
  }

  @override
  Future<LeerPorRangos> porRangos(String nombre) async =>
      RangosEnMemoria(Uint8List.fromList(_ficheros[nombre] ?? const []));

  @override
  Future<void> escribirTexto(String nombre, String texto) async {
    _ficheros[nombre] = texto.codeUnits;
  }

  @override
  Future<String?> leerTexto(String nombre) async {
    final c = _ficheros[nombre];
    return c == null ? null : String.fromCharCodes(c);
  }
}
