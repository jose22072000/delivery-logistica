// ABRIR EL FICHERO GENERADO Y MIRAR DENTRO.
//
// Una prueba que sólo comprueba que exportar «no lanzó» no vale: un `.xlsx` mal
// armado no lanza nada, pesa sus 3 kB y revienta cuando alguien lo abre. Y una
// que leyera el libro con el mismo código que lo escribe tampoco: diría que sí
// a cualquier cosa mientras las dos mitades se equivoquen igual.
//
// Así que esto no llama a nada de `hoja_de_calculo.dart`. Descomprime el zip
// con `archive`, lee las partes del OOXML con `xml` y saca **las celdas que
// vería Excel**: el nombre de cada hoja sale de `xl/workbook.xml`, la hoja a la
// que apunta sale de sus relaciones, y el valor de cada celda de su `<v>` o de
// su `<is><t>`. Si el escritor deja de escribir una relación, el lector no
// encuentra la hoja y la prueba cae.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Un libro leído: las hojas por su nombre, **en el orden en que están en el
/// fichero** (`Map` de Dart conserva el orden de inserción).
typedef LibroLeido = Map<String, List<List<Object?>>>;

LibroLeido leerXlsx(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);

  String parte(String ruta) {
    final fichero = zip.findFile(ruta);
    if (fichero == null) {
      throw StateError('al libro le falta la parte «$ruta»');
    }
    return utf8.decode(fichero.readBytes()!);
  }

  final relaciones = <String, String>{
    for (final r in XmlDocument.parse(
      parte('xl/_rels/workbook.xml.rels'),
    ).findAllElements('Relationship'))
      r.getAttribute('Id')!: r.getAttribute('Target')!,
  };

  final libro = <String, List<List<Object?>>>{};
  for (final hoja in XmlDocument.parse(
    parte('xl/workbook.xml'),
  ).findAllElements('sheet')) {
    final nombre = hoja.getAttribute('name')!;
    final destino = relaciones[hoja.getAttribute('r:id')];
    if (destino == null) {
      throw StateError('la hoja «$nombre» apunta a una relación que no está');
    }
    libro[nombre] = _filas(XmlDocument.parse(parte('xl/$destino')));
  }
  return libro;
}

List<List<Object?>> _filas(XmlDocument hoja) {
  final filas = <List<Object?>>[];
  for (final fila in hoja.findAllElements('row')) {
    final celdas = <Object?>[];
    for (final celda in fila.findAllElements('c')) {
      // La columna sale de la referencia (`C7`), no del orden: las celdas
      // vacías no se escriben, así que contar `<c>` correría las columnas.
      final x = _columna(celda.getAttribute('r')!);
      while (celdas.length < x) {
        celdas.add(null);
      }
      celdas.add(_valor(celda));
    }
    filas.add(celdas);
  }
  return filas;
}

Object? _valor(XmlElement celda) {
  if (celda.getAttribute('t') == 'inlineStr') {
    return celda.findAllElements('t').map((t) => t.innerText).join();
  }
  final v = celda.findAllElements('v').firstOrNull;
  if (v == null) return null;
  final crudo = v.innerText;
  final numero = num.tryParse(crudo);
  if (numero == null) {
    throw StateError(
      'la celda ${celda.getAttribute('r')} dice «$crudo», que '
      'no es un número — Excel la enseñaría como error',
    );
  }
  return numero;
}

/// De `AB12` al índice de columna (0 = A).
int _columna(String referencia) {
  var n = 0;
  for (final letra in referencia.split('')) {
    final codigo = letra.codeUnitAt(0);
    if (codigo < 65 || codigo > 90) break;
    n = n * 26 + (codigo - 64);
  }
  return n - 1;
}
