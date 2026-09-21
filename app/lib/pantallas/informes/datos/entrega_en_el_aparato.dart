// LA APK Y EL ESCRITORIO: el fichero se escribe en disco y, si el aparato sabe,
// se saca el cajon de compartir.
//
// El orden importa y no es el que parece. Primero **escribir**, despues
// compartir:
//
//  * En Linux compartir un fichero no existe —`share_plus` lanza
//    `UnimplementedError('Sharing files not supported on Linux')`—, asi que si
//    se compartiera primero no quedaria nada. Escrito primero, el Excel esta en
//    la carpeta de descargas aunque el cajon no salga, y eso es lo que se dice.
//  * En Android la carpeta de la aplicacion no la ve nadie desde el telefono,
//    asi que enseñar la ruta ahi no sirve de nada: lo util es el cajon.
//
// De ahi que el mensaje sea distinto segun lo que se consiguio, y no una frase
// hecha que valga para los dos y no sirva para ninguno.

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../nucleo/registro/registro.dart';
import 'entrega_del_excel.dart';

EntregaDeFichero crearEntrega() => const EntregaEnElAparato();

class EntregaEnElAparato implements EntregaDeFichero {
  const EntregaEnElAparato();

  @override
  Future<Entregado> entregar({
    required Uint8List bytes,
    required String nombre,
    required String tipoMime,
  }) async {
    final File fichero;
    try {
      final carpeta = await _dondeEscribir();
      fichero = File('${carpeta.path}${Platform.pathSeparator}$nombre');
      await fichero.writeAsBytes(bytes, flush: true);
    } on Object catch (e) {
      Registro.fallo('no se pudo escribir $nombre: $e');
      // EL MOTIVO LITERAL. Un «no se pudo guardar» no le dice a nadie si es el
      // disco lleno, un permiso o una carpeta que no existe.
      return Entregado.noSePudo('No se pudo guardar el Excel: $e');
    }

    if (await _compartir(fichero.path, nombre, tipoMime)) {
      return Entregado.hecho('Excel listo: elegí dónde mandarlo o guardarlo.');
    }
    // Sin cajon, pero el fichero ESTA. Se dice donde, que es lo unico que le
    // sirve a quien lo va a abrir.
    return Entregado.hecho('Excel guardado en ${fichero.path}');
  }

  /// La carpeta de descargas si el destino la tiene; si no, la de la
  /// aplicacion; y de ultimo la temporal.
  ///
  /// En Android `getDownloadsDirectory` no existe y lanza, que es justo el
  /// destino donde la ruta no le importa a nadie porque lo que entrega es el
  /// cajon de compartir.
  Future<Directory> _dondeEscribir() async {
    try {
      final descargas = await getDownloadsDirectory();
      if (descargas != null) return descargas;
    } on Object catch (e) {
      Registro.info('este destino no tiene carpeta de descargas: $e');
    }
    try {
      return await getApplicationDocumentsDirectory();
    } on Object catch (e) {
      Registro.info('sin carpeta de documentos, va a la temporal: $e');
      return getTemporaryDirectory();
    }
  }

  /// `false` = este aparato no sabe compartir ficheros. **No es un fallo**: el
  /// Excel ya esta escrito.
  Future<bool> _compartir(String ruta, String nombre, String tipoMime) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(ruta, mimeType: tipoMime, name: nombre)],
          fileNameOverrides: [nombre],
          subject: nombre,
        ),
      );
      return true;
    } on Object catch (e) {
      Registro.info('este aparato no comparte ficheros: $e');
      return false;
    }
  }
}
