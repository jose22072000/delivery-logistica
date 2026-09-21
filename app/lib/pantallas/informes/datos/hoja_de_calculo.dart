// UN `.xlsx` ES UN ZIP DE XML, Y ESTO ES ESE ZIP.
//
// ## Por que a mano y no con el paquete `excel`
//
// El comentario que habia en `pantalla_informes.dart` decia que para exportar
// hacian falta `excel` y `file_saver`. Lo de `excel` no sale: su version de hoy
// (4.0.6) pide `archive ^3.6.1` y `xml >=5 <7`, y este arbol resuelve
// `archive 4.0.9` y `xml 7.0.1` porque se los pide `printing`. Meterlo obliga a
// BAJAR las dos por debajo de lo que necesita lo impreso —lo que sale por la
// impresora del almacen todos los dias— a cambio de un escritor de hojas.
//
// Asi que se escribe el OOXML minimo con lo que ya estaba en el arbol. Son tres
// partes fijas y una por hoja, todo en Dart puro, y por lo mismo vale igual en
// Android, en el escritorio y en el navegador.
//
// ## Lo que se escribe, y lo que NO
//
// Se escribe lo minimo que abre en Excel, en LibreOffice y en Google Sheets:
// libro, relaciones, tipos de contenido, un `styles.xml` de una sola celda y una
// hoja por pestaña. Las cadenas van **en linea** (`t="inlineStr"`) y no en una
// tabla de cadenas compartidas: una hoja de 300 filas no gana nada con la tabla
// y si gana una parte mas que puede quedar descuadrada.
//
// NO se escribe nada de formato —ni negritas, ni anchos, ni colores—. Esto no
// es la pantalla: es el fichero que alguien abre para sumar en su hoja. Lo que
// si se cuida es que **los numeros salgan como numeros**, porque un importe
// guardado como texto no se suma y la columna da cero sin decir por que.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// El tipo de contenido del fichero, para quien lo tenga que entregar.
const tipoMimeXlsx =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Una celda es un texto, un numero o un hueco. **Nada mas**: ver
/// [_revisarCelda].
typedef Celda = Object?;

/// Una hoja del libro, con su nombre —el que sale en la pestaña de abajo— y sus
/// filas.
class Hoja {
  const Hoja({required this.nombre, required this.filas});

  /// El nombre de la pestaña. Excel no acepta cualquier cosa; ver
  /// [_revisarNombre].
  final String nombre;

  final List<List<Celda>> filas;
}

/// Lo que Excel no acepta en el nombre de una hoja, mas el limite de 31 letras.
/// Un libro con un nombre invalido **no abre**: da «formato no valido» y punto,
/// sin decir cual de las tres hojas es.
const _prohibidoEnNombre = r'[]:*?/\';

/// El libro entero, listo para escribir en disco o mandar al navegador.
///
/// Lanza [ArgumentError] antes de escribir un solo byte si algo no cuadra. Es a
/// proposito: un `.xlsx` roto no se nota al generarlo, se nota cuando alguien lo
/// abre delante de su jefe.
Uint8List armarXlsx(List<Hoja> hojas) {
  if (hojas.isEmpty) {
    throw ArgumentError.value(hojas, 'hojas', 'un libro sin hojas no abre');
  }
  final vistos = <String>{};
  for (final hoja in hojas) {
    _revisarNombre(hoja.nombre);
    if (!vistos.add(hoja.nombre)) {
      throw ArgumentError.value(
        hoja.nombre,
        'hojas',
        'hay dos hojas con el mismo nombre',
      );
    }
  }

  final zip = Archive()
    ..addFile(
      ArchiveFile.string('[Content_Types].xml', _tiposDeContenido(hojas)),
    )
    ..addFile(ArchiveFile.string('_rels/.rels', _relacionesRaiz))
    ..addFile(ArchiveFile.string('xl/workbook.xml', _libro(hojas)))
    ..addFile(
      ArchiveFile.string(
        'xl/_rels/workbook.xml.rels',
        _relacionesDelLibro(hojas),
      ),
    )
    ..addFile(ArchiveFile.string('xl/styles.xml', _estilos));
  for (var i = 0; i < hojas.length; i++) {
    zip.addFile(
      ArchiveFile.string('xl/worksheets/sheet${i + 1}.xml', _hoja(hojas[i])),
    );
  }

  return ZipEncoder().encodeBytes(zip);
}

void _revisarNombre(String nombre) {
  if (nombre.isEmpty) {
    throw ArgumentError.value(nombre, 'nombre', 'una hoja sin nombre no abre');
  }
  if (nombre.length > 31) {
    throw ArgumentError.value(
      nombre,
      'nombre',
      'el nombre de una hoja no pasa de 31 letras',
    );
  }
  for (final letra in _prohibidoEnNombre.split('')) {
    if (nombre.contains(letra)) {
      throw ArgumentError.value(
        nombre,
        'nombre',
        'el nombre de una hoja no puede llevar «$letra»',
      );
    }
  }
}

/// `A`, `B`, … `Z`, `AA`, `AB`… La columna [indice] contando desde 0.
String columnaDeExcel(int indice) {
  if (indice < 0) {
    throw ArgumentError.value(indice, 'indice', 'no hay columnas negativas');
  }
  final letras = StringBuffer();
  var n = indice;
  while (true) {
    letras.write(String.fromCharCode(65 + n % 26));
    n = n ~/ 26 - 1;
    if (n < 0) break;
  }
  return letras.toString().split('').reversed.join();
}

/// Una celda solo puede ser texto, numero o hueco.
///
/// Lo comprueba y lanza en vez de escribir `Instance of 'FilaDeInforme'` en
/// medio de una columna de precios, que es lo que hace un `'$valor'` alegre.
void _revisarCelda(Celda valor, String referencia) {
  if (valor == null || valor is String || valor is num) return;
  throw ArgumentError.value(
    valor,
    referencia,
    'una celda solo puede ser texto, numero o hueco',
  );
}

String _hoja(Hoja hoja) {
  final b = XmlBuilder()..processing('xml', 'version="1.0" encoding="UTF-8"');
  b.element(
    'worksheet',
    attributes: {'xmlns': _ns},
    nest: () => b.element(
      'sheetData',
      nest: () {
        for (var y = 0; y < hoja.filas.length; y++) {
          final fila = hoja.filas[y];
          b.element(
            'row',
            attributes: {'r': '${y + 1}'},
            nest: () {
              for (var x = 0; x < fila.length; x++) {
                final referencia = '${columnaDeExcel(x)}${y + 1}';
                final valor = fila[x];
                _revisarCelda(valor, '${hoja.nombre}!$referencia');
                // Un hueco no se escribe: una celda vacia y una celda que no
                // esta son lo mismo para Excel, y asi el fichero es mas corto.
                if (valor == null) continue;
                if (valor is num) {
                  b.element(
                    'c',
                    attributes: {'r': referencia},
                    nest: () =>
                        b.element('v', nest: () => b.text(_numero(valor))),
                  );
                } else {
                  b.element(
                    'c',
                    attributes: {'r': referencia, 't': 'inlineStr'},
                    nest: () => b.element(
                      'is',
                      // `xml:space="preserve"` o Excel se come los espacios de
                      // los extremos; un destino que empieza por espacio deja
                      // de cuadrar con la pantalla.
                      nest: () => b.element(
                        't',
                        attributes: {'xml:space': 'preserve'},
                        nest: () => b.text(valor as String),
                      ),
                    ),
                  );
                }
              }
            },
          );
        }
      },
    ),
  );
  return b.buildDocument().toXmlString();
}

/// El numero, con punto decimal y **sin notacion cientifica**.
///
/// `1e-7.toString()` en Dart da `1e-7`, que en una celda `<v>` es un numero que
/// Excel no lee. Y un entero se escribe sin `.0` para que no salga `12,0` en la
/// columna de ordenes.
///
/// Los ceros de sobra se quitan **solo de la parte decimal**. Recortar el final
/// de la cadena entera convertiria `100000000000000000000,0` en un `1`: un
/// numero creible y equivocado, que es justo lo que no puede pasar aqui.
String _numero(num valor) {
  if (valor is int) return '$valor';
  final d = valor as double;
  if (!d.isFinite) {
    throw ArgumentError.value(valor, 'valor', 'un importe no puede ser $d');
  }
  if (d == d.roundToDouble() && d.abs() < 1e15) return '${d.toInt()}';
  final partes = d.toStringAsFixed(10).split('.');
  final decimales = partes[1].replaceFirst(RegExp(r'0+$'), '');
  return decimales.isEmpty ? partes[0] : '${partes[0]}.$decimales';
}

const _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _nsRel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

String _tiposDeContenido(List<Hoja> hojas) {
  final hojasXml = [
    for (var i = 0; i < hojas.length; i++)
      '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
  ].join();
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="$tipoMimeXlsx.main+xml"/>'
      '<Override PartName="/xl/styles.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '$hojasXml'
      '</Types>';
}

const _relacionesRaiz =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="$_nsRel/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

String _libro(List<Hoja> hojas) {
  final b = XmlBuilder()..processing('xml', 'version="1.0" encoding="UTF-8"');
  b.element(
    'workbook',
    attributes: {'xmlns': _ns, 'xmlns:r': _nsRel},
    nest: () => b.element(
      'sheets',
      nest: () {
        for (var i = 0; i < hojas.length; i++) {
          b.element(
            'sheet',
            attributes: {
              'name': hojas[i].nombre,
              'sheetId': '${i + 1}',
              'r:id': 'rId${i + 1}',
            },
          );
        }
      },
    ),
  );
  return b.buildDocument().toXmlString();
}

String _relacionesDelLibro(List<Hoja> hojas) {
  final hojasXml = [
    for (var i = 0; i < hojas.length; i++)
      '<Relationship Id="rId${i + 1}" Type="$_nsRel/worksheet" '
          'Target="worksheets/sheet${i + 1}.xml"/>',
  ].join();
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '$hojasXml'
      '<Relationship Id="rId${hojas.length + 1}" Type="$_nsRel/styles" Target="styles.xml"/>'
      '</Relationships>';
}

/// El minimo que exige el formato: una fuente, dos rellenos —Excel da por hecho
/// que el 1 es el rayado—, un borde y un estilo de celda.
const _estilos =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<styleSheet xmlns="$_ns">'
    '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
    '<fills count="2">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '</fills>'
    '<borders count="1"><border/></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
    // El estilo `Normal`. Sin el, un libro se abre igual pero los lectores
    // avisan de que no trae estilo por defecto y se lo inventan; mejor que lo
    // traiga, que es una linea.
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';
