/// El POST-despacho: lo que tiene que quedar en el camion.
///
/// El camion vuelve y alguien tiene que cuadrar lo que baja. Hasta ahora eso se
/// hacia de memoria y con la hoja del pre-despacho en la mano, restando a ojo:
/// se cargaron cuarenta cajas, se entregaron treinta y una, quedan nueve?
/// Nadie lo comprobaba, y lo que faltaba aparecia dias despues sin poder decir
/// de que reparto salio.
///
/// Esta hoja es la cuenta hecha: por producto, cuanto salio, cuanto se entrego
/// y cuanto tiene que estar todavia arriba. Con su columna para marcar lo que
/// de verdad bajo, que es lo que convierte la hoja en un control y no en un
/// informe. Debajo va el detalle por cliente de lo que NO se entrego, porque
/// «faltan nueve cajas» no sirve para reclamar: hace falta saber de quien eran.
///
/// Estructura literal: `../docs/pantallas.md` §10.2.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'estilo.dart';
import 'hoja.dart';
import 'piezas.dart';

/// Los literales de la hoja, en espanol y fuera de `lib/textos/`: este papel es
/// el punto de paridad con el de Next (P7) y se compara palabra a palabra.
abstract final class TextoPostDespacho {
  static const String titulo = 'Post-despacho';
  static const String salio = 'Salió ';
  static const String volvio = ' · volvió ';

  /// El `(s)` va DENTRO del literal, como en el pliego. Nada de ICU.
  static const String entregadas = ' entregada(s)';
  static const String devueltas = ' devuelta(s)';
  static const String canceladas = ' cancelada(s)';
  static const String sinMarcar = ' sin marcar';

  static const String seccionQueda = 'Tiene que quedar en el camión';
  static const String seccionDeQuien = 'De quién es lo que vuelve';

  static const String colProducto = 'Producto';
  static const String colSalio = 'Salió';
  static const String colEntregado = 'Entregado';
  static const String colQueda = 'Queda';
  static const String colBajo = 'Bajó';
  static const String total = 'Total';

  static const String nadaQueda = 'Nada: se entregó todo lo que salió.';
  static const String todoEntregado = 'Todas las paradas se entregaron.';

  static const String etiquetaDevuelto = 'Devuelto';
  static const String etiquetaCancelado = 'Cancelado';
  static const String etiquetaSinMarcar = 'Sin marcar';

  static const String sinProductos = '—';
  static const String separadorProductos = ' · ';
  static const String por = ' × ';

  static const String firmaEntrego = 'Entregó (chofer)';
  static const String firmaRecibio = 'Recibió en almacén';
}

/// Los 78 px del HTML en papel (78/96 de pulgada = 20.6 mm). Va fija por lo
/// mismo que la del pre-despacho: dentro no se imprime nada y sin ancho propio
/// la columna se cerraria.
final pw.FixedColumnWidth anchoBajo = pw.FixedColumnWidth(
  20.6 * PdfPageFormat.mm,
);

/// Arma el PDF del post-despacho.
///
/// [impresoEn] entra por parametro: la misma entrada tiene que dar los mismos
/// bytes para poder compararla con la de Next y para poder probarla.
Future<Uint8List> pdfPostDespacho(
  HojaPostDespacho h, {
  required DateTime impresoEn,
  AssetBundle? paqueteDeAssets,
}) async {
  await prepararFechas();
  final fuentes = await cargarFuentes(desde: paqueteDeAssets);

  // Solo se listan los productos que QUEDAN, y el pie suma ESAS filas: si
  // sumara todas, el total no cuadraria con lo que se ve encima.
  final filas = h.lineasConResto;
  final totales = TotalesPostDespacho.de(h);

  final doc = pw.Document(theme: fuentes.tema, title: TextoPostDespacho.titulo);

  doc.addPage(
    pw.MultiPage(
      pageFormat: hojaA4,
      theme: fuentes.tema,
      build: (pw.Context ctx) => <pw.Widget>[
        cabecera(
          izquierda: <pw.Widget>[
            titulo(TextoPostDespacho.titulo),
            lineaDeCabecera(_lineaRuta(h)),
            if (h.salida != null && h.salida!.isNotEmpty)
              lineaDeCabecera(_lineaHorario(h)),
          ],
          derecha: <pw.Widget>[lineaDeCabecera(fechaDeImpresion(impresoEn))],
        ),
        _pildoras(h),
        tituloDeSeccion(TextoPostDespacho.seccionQueda),
        if (filas.isEmpty)
          vacio(TextoPostDespacho.nadaQueda)
        else
          _tabla(filas, totales),
        tituloDeSeccion(TextoPostDespacho.seccionDeQuien),
        if (h.pendientes.isEmpty)
          vacio(TextoPostDespacho.todoEntregado)
        else
          for (final p in h.pendientes) _parada(p),
        firmas(
          TextoPostDespacho.firmaEntrego,
          TextoPostDespacho.firmaRecibio,
          desde: 30 * px,
        ),
      ],
    ),
  );

  return doc.save();
}

String _lineaRuta(HojaPostDespacho h) {
  final base = '${h.ruta} · ${h.sucursal}';
  return h.vehiculo.isNotEmpty ? '$base · ${h.vehiculo}' : base;
}

/// `Salió <cuando>` y, si tambien se sabe, ` · volvió <cuando>`. El regreso no
/// se escribe solo: sin salida no hay linea, igual que en la de Next.
String _lineaHorario(HojaPostDespacho h) {
  final salida = '${TextoPostDespacho.salio}${h.salida}';
  final r = h.regreso;
  return (r != null && r.isNotEmpty)
      ? '$salida${TextoPostDespacho.volvio}$r'
      : salida;
}

/// La fila de pildoras del resumen. `sin marcar` **solo aparece si hay alguna**:
/// un «0 sin marcar» impreso se lee como que ya se reviso, que es justo lo
/// contrario de lo que esta hoja quiere decir.
pw.Widget _pildoras(HojaPostDespacho h) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 10 * px, bottom: 4 * px),
  child: pw.Wrap(
    spacing: 10 * px,
    runSpacing: 10 * px,
    children: <pw.Widget>[
      _pildora('${h.entregadas}${TextoPostDespacho.entregadas}'),
      _pildora('${h.devueltas}${TextoPostDespacho.devueltas}'),
      _pildora('${h.canceladas}${TextoPostDespacho.canceladas}'),
      if (h.sinMarcar > 0)
        _pildora('${h.sinMarcar}${TextoPostDespacho.sinMarcar}'),
    ],
  ),
);

pw.Widget _pildora(String texto) => pw.Container(
  decoration: pw.BoxDecoration(
    border: pw.Border.all(color: Tinta.bordePildora, width: px),
    borderRadius: pw.BorderRadius.circular(999 * px),
  ),
  padding: const pw.EdgeInsets.symmetric(vertical: 3 * px, horizontal: 10 * px),
  child: pw.Text(texto, style: const pw.TextStyle(fontSize: 12 * px)),
);

pw.Widget _tabla(List<LineaPostDespacho> filas, TotalesPostDespacho t) =>
    pw.Table(
      columnWidths: <int, pw.TableColumnWidth>{
        0: const pw.FlexColumnWidth(),
        1: const pw.IntrinsicColumnWidth(),
        2: const pw.IntrinsicColumnWidth(),
        3: const pw.IntrinsicColumnWidth(),
        4: anchoBajo,
      },
      children: <pw.TableRow>[
        pw.TableRow(
          decoration: decoracionCabecera,
          repeat: true,
          children: <pw.Widget>[
            celdaCabecera(TextoPostDespacho.colProducto),
            celdaCabecera(TextoPostDespacho.colSalio, derecha: true),
            celdaCabecera(TextoPostDespacho.colEntregado, derecha: true),
            celdaCabecera(TextoPostDespacho.colQueda, derecha: true),
            celdaCabecera(TextoPostDespacho.colBajo),
          ],
        ),
        for (final l in filas)
          pw.TableRow(
            decoration: decoracionFila,
            children: <pw.Widget>[
              celda(l.producto),
              celda(numero(l.salio), derecha: true),
              celda(numero(l.entregado), derecha: true),
              // `Queda` va en negrita: es la columna por la que se lee esta
              // hoja, y se tiene que ver desde lejos con el camion abierto.
              celda(numero(l.queda), derecha: true, negrita: true),
              celdaParaMarcar(),
            ],
          ),
        pw.TableRow(
          decoration: decoracionPie,
          children: <pw.Widget>[
            celda(TextoPostDespacho.total, negrita: true),
            celda(numero(t.salio), derecha: true, negrita: true),
            celda(numero(t.entregado), derecha: true, negrita: true),
            celda(numero(t.queda), derecha: true, negrita: true),
            celdaParaMarcar(),
          ],
        ),
      ],
    );

/// Una parada que no se entrego: quien es, que paso, por que, y que trae.
pw.Widget _parada(ParadaPendiente p) => pw.Container(
  decoration: const pw.BoxDecoration(
    border: pw.Border(
      bottom: pw.BorderSide(color: Tinta.lineaParada, width: px),
    ),
  ),
  padding: const pw.EdgeInsets.symmetric(vertical: 6 * px),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          pw.Flexible(
            child: pw.Text(
              p.cliente,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(width: 6 * px),
          _etiqueta(p.resultado),
        ],
      ),
      if (p.nota != null && p.nota!.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2 * px),
          child: pw.Text(
            p.nota!,
            style: const pw.TextStyle(
              fontSize: 12 * px,
              color: Tinta.gris,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 2 * px),
        child: pw.Text(
          productosDeParada(p),
          style: const pw.TextStyle(fontSize: 12 * px, color: Tinta.prods),
        ),
      ),
    ],
  ),
);

/// `producto × n` separados por ` · `, o una raya si la parada no traia nada.
///
/// Se saca a funcion suelta porque es lo que se compara con la hoja de Next
/// linea a linea, y desde el dibujo del PDF no se puede leer.
String productosDeParada(ParadaPendiente p) {
  if (p.productos.isEmpty) return TextoPostDespacho.sinProductos;
  return p.productos
      .map((x) => '${x.producto}${TextoPostDespacho.por}${numero(x.formatos)}')
      .join(TextoPostDespacho.separadorProductos);
}

/// La etiqueta de que paso con la parada. `null` es «Sin marcar», en ambar:
/// no es lo mismo que cancelada, y en la hoja tiene que verse que nadie la toco.
pw.Widget _etiqueta(String? resultado) {
  final (String texto, PdfColor fondo, PdfColor tinta) = switch (resultado) {
    'devuelto' => (
      TextoPostDespacho.etiquetaDevuelto,
      Tinta.devueltoFondo,
      Tinta.devueltoTexto,
    ),
    'cancelado' => (
      TextoPostDespacho.etiquetaCancelado,
      Tinta.canceladoFondo,
      Tinta.canceladoTexto,
    ),
    _ => (
      TextoPostDespacho.etiquetaSinMarcar,
      Tinta.sinMarcarFondo,
      Tinta.sinMarcarTexto,
    ),
  };

  return pw.Container(
    decoration: pw.BoxDecoration(
      color: fondo,
      borderRadius: pw.BorderRadius.circular(999 * px),
    ),
    padding: const pw.EdgeInsets.symmetric(
      vertical: 2 * px,
      horizontal: 7 * px,
    ),
    child: pw.Text(
      texto.toUpperCase(),
      style: pw.TextStyle(
        fontSize: 10 * px,
        color: tinta,
        letterSpacing: 10 * px * 0.04,
      ),
    ),
  );
}
