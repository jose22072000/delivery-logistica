/// Las piezas que las dos hojas dibujan igual: la cabecera a dos lados, las
/// celdas de la tabla y los huecos de firma.
///
/// Estan aqui y no copiadas en cada hoja porque en el HTML de Next son
/// literalmente la misma regla CSS en los dos ficheros: si un dia se separan,
/// que sea a proposito y en un solo sitio.
library;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'estilo.dart';

/// El `<h1>` de las dos hojas: 20 px, negrita, 2 px por debajo.
pw.Widget titulo(String texto) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 2 * px),
  child: pw.Text(
    texto,
    style: pw.TextStyle(fontSize: 20 * px, fontWeight: pw.FontWeight.bold),
  ),
);

/// Un `<p>` de la cabecera: gris, 2 px arriba y abajo.
pw.Widget lineaDeCabecera(String texto) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 2 * px),
  child: pw.Text(texto, style: const pw.TextStyle(color: Tinta.apagado)),
);

/// `.cab`: dos bloques, uno pegado a cada margen, 14 px por debajo.
///
/// El de la derecha lleva su texto alineado a la izquierda DENTRO del bloque,
/// que es lo que hace el navegador con un `<div>` dentro de un `flex`: el
/// bloque se va a la derecha, el texto no se centra ni se justifica.
pw.Widget cabecera({
  required List<pw.Widget> izquierda,
  required List<pw.Widget> derecha,
}) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 14 * px),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: izquierda,
      ),
      pw.SizedBox(width: 16 * px),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: derecha,
      ),
    ],
  ),
);

/// Un `<h2>` de seccion: 14 px, MAYUSCULAS, gris, con su aire.
///
/// El HTML pone `text-transform: uppercase` y escribe el titulo en minuscula;
/// el PDF no transforma nada, asi que la mayuscula se hace aqui y no se confia
/// a que quien escriba el literal se acuerde.
pw.Widget tituloDeSeccion(String texto) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 22 * px, bottom: 8 * px),
  child: pw.Text(
    texto.toUpperCase(),
    style: pw.TextStyle(
      fontSize: 14 * px,
      fontWeight: pw.FontWeight.bold,
      color: Tinta.apagado,
      letterSpacing: 14 * px * 0.04,
    ),
  ),
);

/// `th, td { padding: 6px 8px }`.
const pw.EdgeInsets rellenoCelda = pw.EdgeInsets.symmetric(
  vertical: 6 * px,
  horizontal: 8 * px,
);

/// Una celda de cabecera de tabla: 11 px, MAYUSCULAS, con su separacion.
pw.Widget celdaCabecera(String texto, {bool derecha = false}) => pw.Padding(
  padding: rellenoCelda,
  child: pw.Text(
    texto.toUpperCase(),
    textAlign: derecha ? pw.TextAlign.right : pw.TextAlign.left,
    style: pw.TextStyle(fontSize: 11 * px, letterSpacing: 11 * px * 0.04),
  ),
);

/// Una celda de datos. `derecha` es la clase `.n` del HTML: los numeros se leen
/// por la coma, no por la primera cifra.
pw.Widget celda(
  String texto, {
  bool derecha = false,
  bool negrita = false,
  PdfColor color = Tinta.texto,
}) => pw.Padding(
  padding: rellenoCelda,
  child: pw.Text(
    texto,
    textAlign: derecha ? pw.TextAlign.right : pw.TextAlign.left,
    style: pw.TextStyle(
      fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color,
    ),
  ),
);

/// La celda de la columna que se marca a mano: va VACIA a proposito.
///
/// No lleva ni un guion ni un cuadrito: quien saca la mercancia escribe ahi el
/// numero que de verdad conto, y cualquier cosa impresa se lo come.
pw.Widget celdaParaMarcar() =>
    pw.Padding(padding: rellenoCelda, child: pw.Text(' '));

/// `th { background: #f4f4f4 }` mas la linea fina de debajo.
pw.BoxDecoration get decoracionCabecera => const pw.BoxDecoration(
  color: Tinta.cabeceraFondo,
  border: pw.Border(
    bottom: pw.BorderSide(color: Tinta.linea, width: px),
  ),
);

/// `td { border-bottom: 1px solid #ddd }`.
pw.BoxDecoration get decoracionFila => const pw.BoxDecoration(
  border: pw.Border(
    bottom: pw.BorderSide(color: Tinta.linea, width: px),
  ),
);

/// `tfoot td { border-top: 2px solid #333 }`, y la fina de abajo que hereda.
pw.BoxDecoration get decoracionPie => const pw.BoxDecoration(
  border: pw.Border(
    top: pw.BorderSide(color: Tinta.lineaGruesa, width: 2 * px),
    bottom: pw.BorderSide(color: Tinta.linea, width: px),
  ),
);

/// Los dos huecos de firma del pie de la hoja.
///
/// Son dos rayas con una etiqueta debajo, no dos recuadros: la hoja vuelve
/// firmada a mano y una raya larga es lo unico que aguanta una firma de verdad.
pw.Widget firmas(String izquierda, String derecha, {double desde = 34 * px}) =>
    pw.Padding(
      padding: pw.EdgeInsets.only(top: desde),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Expanded(child: _hueco(izquierda)),
          pw.SizedBox(width: 40 * px),
          pw.Expanded(child: _hueco(derecha)),
        ],
      ),
    );

pw.Widget _hueco(String etiqueta) => pw.Container(
  decoration: const pw.BoxDecoration(
    border: pw.Border(
      top: pw.BorderSide(color: Tinta.lineaFirma, width: px),
    ),
  ),
  padding: const pw.EdgeInsets.only(top: 4 * px),
  child: pw.Text(
    etiqueta,
    style: const pw.TextStyle(fontSize: 11 * px, color: Tinta.apagado),
  ),
);

/// Un texto de «aqui no hay nada»: gris y en cursiva, como `.vacio`.
pw.Widget vacio(String texto) => pw.Text(
  texto,
  style: const pw.TextStyle(color: Tinta.gris, fontStyle: pw.FontStyle.italic),
);
