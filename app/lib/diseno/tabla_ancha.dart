import 'package:flutter/material.dart';

import 'colores.dart';
import 'tema.dart';

/// Una tabla con **su propio** desplazamiento horizontal.
///
/// El pliego (§11) lo pide literalmente para Clientes y para las tablas del
/// pre-despacho: *«se desplaza la tabla, no la pagina»*. Sin esto, una tabla de
/// 736 px en una pantalla de 390 px empuja la pagina entera de lado y el menu,
/// la barra y el reloj de datos se van con ella.
class TablaAncha extends StatefulWidget {
  const TablaAncha({required this.child, this.anchoMinimo = 736, super.key});

  final Widget child;
  final double anchoMinimo;

  @override
  State<TablaAncha> createState() => _TablaAnchaState();
}

class _TablaAnchaState extends State<TablaAncha> {
  /// LA BARRA NECESITA SU PROPIO MANDO, y por eso esto tiene estado.
  ///
  /// `Scrollbar(thumbVisibility: true)` sin controlador se busca el
  /// `PrimaryScrollController`, y donde no lo hay **revienta**: «A
  /// ScrollController is required when Scrollbar.thumbVisibility is true».
  /// Pasaba en Reportes con la pestaña `Detalle de Órdenes` abierta en un
  /// teléfono —la tabla pide 860 px, la pantalla tiene 420—, dentro de un
  /// `TabBarView`, que no deja pasar el controlador primario. La pestaña se caía
  /// entera y nadie lo había visto porque hasta ahora no había forma cómoda de
  /// llegar a ella desde un móvil.
  final _mando = ScrollController();

  @override
  void dispose() {
    _mando.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, medidas) {
      final ancho = medidas.maxWidth;
      // Si cabe entera no se envuelve en un scroll: un `Scrollable` de mas se
      // come los gestos de las filas que se pueden pulsar.
      if (ancho >= widget.anchoMinimo) return widget.child;
      return Scrollbar(
        controller: _mando,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _mando,
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: widget.anchoMinimo, child: widget.child),
        ),
      );
    },
  );
}

/// LA CAJA DE UNA TABLA: blanca, borde fino de `--line`, `rounded-2xl` y
/// recortada, para que la primera fila y el pie de paginacion sigan la curva de
/// las esquinas.
///
/// En delivery ninguna tabla va suelta sobre el papel: van todas dentro de esta
/// caja, con la paginacion pegada abajo separada por una linea
/// (`border-t bg-white` de `Pagination.tsx`). Es lo que hace que una lista larga
/// se lea como **una** cosa y no como filas flotando.
class TarjetaDeTabla extends StatelessWidget {
  const TarjetaDeTabla({required this.child, this.pie, super.key});

  final Widget child;

  /// La paginacion, o lo que vaya pegado abajo. Se separa con la linea fina.
  final Widget? pie;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colores.blanco,
      borderRadius: BorderRadius.circular(Radios.xl),
      border: Border.all(color: Colores.linea),
      boxShadow: Sombras.md,
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(Radios.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: child),
          if (pie != null) ...[
            Divider(height: 1, thickness: 1, color: Colores.linea),
            pie!,
          ],
        ],
      ),
    ),
  );
}

/// El estilo de una CABECERA de tabla: 11 px, semibold, versalitas y bien
/// espaciada, sobre el papel. Es el `text-[11px] uppercase tracking-…` que
/// delivery usa en todas las cabeceras.
///
/// Es una funcion y no un widget porque `DataTable` quiere `Text` en su
/// `DataColumn.label` y envolverlo en otra cosa le rompe la alineacion.
TextStyle estiloDeCabecera() => Tipos.texto(
  tamano: 11,
  peso: FontWeight.w600,
  color: Colores.tintaSuave,
  interletra: 0.4,
);

/// La cabecera lista para poner en un `DataColumn`.
///
/// **Se queda con su literal**: en la de Next las versalitas las pone el CSS y
/// el texto sigue siendo «Cliente». Pasarlo a mayusculas aqui cambiaria el dato
/// que comparan las pruebas contra el pliego. El trabajo de rotulo lo hace el
/// estilo.
Widget cabecera(String texto) => Text(texto, style: estiloDeCabecera());

/// El `DataTableThemeData` que usa una tabla de delivery: cabecera sobre papel,
/// filas altas y la linea fina entre ellas.
DataTableThemeData temaDeTabla(BuildContext context) {
  final tema = Theme.of(context);
  return tema.dataTableTheme.copyWith(
    headingRowColor: const WidgetStatePropertyAll(Colores.papel),
    headingTextStyle: estiloDeCabecera(),
    headingRowHeight: 44,
    dataRowMinHeight: 52,
    dataRowMaxHeight: 76,
    dataTextStyle: tema.textTheme.bodyMedium,
    dividerThickness: 1,
    columnSpacing: 24,
    horizontalMargin: Aire.lg,
  );
}
