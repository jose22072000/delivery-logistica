/// El pre-despacho, en papel.
///
/// El almacen no mira una pantalla: alguien baja con una hoja y va sacando. Por
/// eso se imprime, y por eso lleva los totales grandes al final — es lo que se
/// comprueba cuando el camion ya esta cargado.
///
/// En Next esto era una ventana de 900x700 con HTML escrito a mano. Aqui no hay
/// ventana nueva ni impresora del navegador en Android, asi que se genera el
/// PDF y se ensena en un cajon con `VistaPreviaPdf`.
///
/// Estructura literal: `../docs/pantallas.md` §10.1.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'estilo.dart';
import 'hoja.dart';
import 'piezas.dart';

/// Los literales de la hoja. Van en espanol y NO pasan por los textos de
/// `lib/textos/`: este papel es el punto de paridad con la hoja de Next y se
/// compara palabra a palabra con ella, asi que no puede cambiar con el idioma
/// que tenga puesta la barra superior.
abstract final class TextoPreDespacho {
  static const String titulo = 'Pre-despacho';
  static const String pedidosDel = 'Pedidos del ';

  /// El `(s)` va DENTRO del literal, tal cual lo escribe el pliego. Nada de
  /// pluralizar con ICU: en cuanto se hace, el texto deja de ser identico.
  static const String pedidos = ' pedido(s)';
  static const String kg = ' kg';

  static const String colProducto = 'Producto';
  static const String colEmpaques = 'Empaques';
  static const String colUnidades = 'Unidades';
  static const String colKg = 'kg';
  static const String colSacado = 'Sacado';
  static const String total = 'Total';

  static const String firmaSaco = 'Sacó del almacén';
  static const String firmaRecibio = 'Recibió (chofer)';
}

/// El ancho de la columna que se marca a mano: los 70 px del HTML pasados a
/// papel (70/96 de pulgada = 18.5 mm). Se fija y no se deja al contenido porque
/// el contenido es NADA: sin un ancho de verdad la columna se cierra y no cabe
/// el numero que hay que escribir dentro.
final pw.FixedColumnWidth anchoSacado = pw.FixedColumnWidth(
  18.5 * PdfPageFormat.mm,
);

/// Arma el PDF del pre-despacho.
///
/// [impresoEn] entra por parametro y no se lee del reloj aqui dentro para que
/// la hoja sea reproducible: la misma entrada da los mismos bytes, que es lo
/// que permite compararla con la de Next y probarla.
///
/// [paqueteDeAssets] solo lo usan los tests; en la aplicacion las fuentes salen
/// del `rootBundle`, es decir del propio APK, sin tocar la red.
Future<Uint8List> pdfPreDespacho(
  HojaPreDespacho h, {
  required DateTime impresoEn,
  AssetBundle? paqueteDeAssets,
}) async {
  await prepararFechas();
  final fuentes = await cargarFuentes(desde: paqueteDeAssets);
  final totales = TotalesPreDespacho.de(h);

  final doc = pw.Document(theme: fuentes.tema, title: TextoPreDespacho.titulo);

  doc.addPage(
    pw.MultiPage(
      pageFormat: hojaA4,
      theme: fuentes.tema,
      build: (pw.Context ctx) => <pw.Widget>[
        cabecera(
          izquierda: <pw.Widget>[
            titulo(TextoPreDespacho.titulo),
            lineaDeCabecera(
              h.vehiculo.isNotEmpty
                  ? '${h.sucursal} · ${h.vehiculo}'
                  : h.sucursal,
            ),
            if (h.dia != null && h.dia!.isNotEmpty)
              lineaDeCabecera('${TextoPreDespacho.pedidosDel}${h.dia}'),
          ],
          derecha: <pw.Widget>[
            lineaDeCabecera('${h.pedidos}${TextoPreDespacho.pedidos}'),
            lineaDeCabecera('${pesoTotal(h.pesoKg)}${TextoPreDespacho.kg}'),
            lineaDeCabecera(fechaDeImpresion(impresoEn)),
          ],
        ),
        _tabla(h, totales),
        firmas(TextoPreDespacho.firmaSaco, TextoPreDespacho.firmaRecibio),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _tabla(HojaPreDespacho h, TotalesPreDespacho t) => pw.Table(
  columnWidths: <int, pw.TableColumnWidth>{
    0: const pw.FlexColumnWidth(),
    1: const pw.IntrinsicColumnWidth(),
    2: const pw.IntrinsicColumnWidth(),
    3: const pw.IntrinsicColumnWidth(),
    4: anchoSacado,
  },
  children: <pw.TableRow>[
    pw.TableRow(
      decoration: decoracionCabecera,
      repeat: true, // si la hoja pasa de pagina, la cabecera va otra vez
      children: <pw.Widget>[
        celdaCabecera(TextoPreDespacho.colProducto),
        celdaCabecera(TextoPreDespacho.colEmpaques, derecha: true),
        celdaCabecera(TextoPreDespacho.colUnidades, derecha: true),
        celdaCabecera(TextoPreDespacho.colKg, derecha: true),
        celdaCabecera(TextoPreDespacho.colSacado),
      ],
    ),
    // Las lineas vienen YA ordenadas de mas a menos empaques; esta hoja no
    // las toca. Si aqui se reordenaran, dejaria de cuadrar con la de Next.
    for (final l in h.lineas)
      pw.TableRow(
        decoration: decoracionFila,
        children: <pw.Widget>[
          celda(l.producto),
          celda(numero(l.formatos), derecha: true),
          celda(numero(l.unidades), derecha: true),
          celda(pesoDeFila(l.pesoKg), derecha: true),
          celdaParaMarcar(),
        ],
      ),
    pw.TableRow(
      decoration: decoracionPie,
      children: <pw.Widget>[
        celda(TextoPreDespacho.total, negrita: true),
        celda(numero(t.formatos), derecha: true, negrita: true),
        celda(numero(t.unidades), derecha: true, negrita: true),
        celda(pesoTotal(t.pesoKg), derecha: true, negrita: true),
        celdaParaMarcar(),
      ],
    ),
  ],
);
