import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'carpeta_del_mapa.dart';
import 'pmtiles.dart';

/// Android, Windows y Linux: una carpeta `mapa/` dentro de los datos de la
/// aplicacion.
///
/// POR QUE AHI Y NO EN LA TARJETA O EN DESCARGAS: es la carpeta que el sistema
/// borra al desinstalar y que ninguna otra aplicacion toca. Un `.pmtiles` de 26
/// MB suelto en Descargas se lo lleva por delante cualquier limpiador de los que
/// vienen instalados en los telefonos de alla, y el mapa desaparece sin que
/// nadie sepa por que.
class CarpetaEnDisco implements CarpetaDelMapa {
  CarpetaEnDisco(this.raiz);

  final Directory raiz;

  File _f(String nombre) => File('${raiz.path}${Platform.pathSeparator}$nombre');

  @override
  Future<int> bytes(String nombre) async {
    final f = _f(nombre);
    return await f.exists() ? f.length() : 0;
  }

  @override
  Future<void> anadir(String nombre, List<int> trozo) =>
      _f(nombre).writeAsBytes(trozo, mode: FileMode.append, flush: false);

  @override
  Future<void> borrar(String nombre) async {
    final f = _f(nombre);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> renombrar(String de, String a) async {
    await borrar(a);
    await _f(de).rename(_f(a).path);
  }

  @override
  Stream<List<int>> porTrozos(String nombre) => _f(nombre).openRead();

  @override
  Future<LeerPorRangos> porRangos(String nombre) async =>
      _RangosDeFichero(await _f(nombre).open());

  @override
  Future<void> escribirTexto(String nombre, String texto) =>
      _f(nombre).writeAsString(texto, flush: true);

  @override
  Future<String?> leerTexto(String nombre) async {
    final f = _f(nombre);
    return await f.exists() ? f.readAsString() : null;
  }
}

class _RangosDeFichero implements LeerPorRangos {
  _RangosDeFichero(this._f);

  final RandomAccessFile _f;

  @override
  Future<Uint8List> leer(int desde, int largo) async {
    await _f.setPosition(desde);
    final salida = await _f.read(largo);
    if (salida.length != largo) {
      // Pedir mas alla del final es un fichero corrupto, no un caso normal: se
      // dice, no se devuelve medio trozo.
      throw const PaqueteIlegible(
        'el fichero del mapa se acaba antes de lo que dice su cabecera',
      );
    }
    return salida;
  }

  @override
  Future<void> cerrar() => _f.close();
}

/// Abre —y crea si hace falta— la carpeta del mapa.
Future<CarpetaDelMapa> abrirLaCarpetaDelMapa() async {
  final datos = await getApplicationSupportDirectory();
  final carpeta = Directory('${datos.path}${Platform.pathSeparator}mapa');
  if (!await carpeta.exists()) await carpeta.create(recursive: true);
  return CarpetaEnDisco(carpeta);
}
