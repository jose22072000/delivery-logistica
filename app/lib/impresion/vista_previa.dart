/// La vista previa de una hoja impresa.
///
/// En Next la hoja se abría en una ventana de 900x700 y **no lanzaba el diálogo
/// de impresión**: se revisa primero —que estén todos los productos, que las
/// cantidades cuadren— y se imprime desde el botón de la propia vista. Aquí se
/// conserva ese orden: primero se mira, después se imprime.
///
/// Lo que se añade es `Compartir`, que no existía: en el patio de un almacén la
/// hoja se manda por WhatsApp mucho antes de que alguien la imprima.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../textos/textos.dart';
import 'estilo.dart';

/// Quién arma los bytes de la hoja. Se recibe la función y no los bytes ya
/// hechos para que el PDF se construya cuando la vista lo pide y con el formato
/// de papel que el aparato tenga puesto.
typedef ArmarHoja = Future<Uint8List> Function(PdfPageFormat formato);

/// El cuerpo de la vista previa: el PDF y sus tres acciones.
///
/// No monta ningún cajón por su cuenta. La casa manda que esto vaya dentro de
/// un `Cajon` `xl` (pantallas.md §9.2), y el cajón lo pone quien abre la hoja:
/// así la misma vista sirve para el cierre de ruta, para pedidos y para el paso
/// 4 del asistente sin que cada uno herede un cajón que no quería.
class VistaPreviaPdf extends StatelessWidget {
  const VistaPreviaPdf({
    required this.armar,
    required this.nombreDeFichero,
    this.alCerrar,
    super.key,
  });

  final ArmarHoja armar;

  /// Con qué nombre se guarda o se comparte. Va con `.pdf` incluido.
  final String nombreDeFichero;

  /// Qué hacer con `Cerrar`. Si no se da, se cierra la ruta de encima, que es
  /// lo que hace el cajón.
  final VoidCallback? alCerrar;

  @override
  Widget build(BuildContext context) {
    final t = context.textos;

    return PdfPreview(
      build: armar,
      // El papel ya viene decidido por la hoja (A4 con 12 mm); el selector de
      // formato solo serviría para que alguien imprima el pre-despacho en A5 y
      // no pueda escribir en la columna de marcar.
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      initialPageFormat: hojaA4,
      pdfFileName: nombreDeFichero,
      allowPrinting: true,
      allowSharing: true,
      useActions: true,
      actionBarTheme: const PdfActionBarTheme(alignment: WrapAlignment.end),
      actions: <PdfPreviewAction>[
        // `Cerrar` es de la vista, no del PDF: en el HTML de Next era un botón
        // flotante con `display:none` al imprimir, y aquí sencillamente no
        // entra en el papel.
        PdfPreviewAction(
          icon: const Icon(Icons.close),
          onPressed: (BuildContext _, LayoutCallback _, PdfPageFormat _) =>
              alCerrar != null ? alCerrar!() : Navigator.of(context).maybePop(),
        ),
      ],
      previewPageMargin: const EdgeInsets.all(12),
      scrollViewDecoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
      ),
      onError: (BuildContext ctx, Object error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t.nuevoPdfNoSePudo, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// Manda la hoja a la impresora sin pasar por la vista previa.
///
/// Existe para el caso en que alguien ya miró la hoja y quiere sacar otra copia
/// igual. **No es el camino por defecto**: el pliego dice que la hoja se revisa
/// antes de imprimirla.
Future<bool> imprimirHoja(Uint8List bytes, String nombre) => Printing.layoutPdf(
  onLayout: (PdfPageFormat _) async => bytes,
  name: nombre,
  format: hojaA4,
);

/// Manda la hoja por donde el aparato sepa compartir: WhatsApp, correo, lo que
/// haya. Es lo que de verdad va a pasar en el patio de un almacén.
Future<void> compartirHoja(Uint8List bytes, String nombre) async {
  await Printing.sharePdf(bytes: bytes, filename: nombre);
}
