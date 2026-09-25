// LA BARRA DE FILTROS DE TODAS LAS LISTAS. Una sola, y por eso está aquí.
//
// Las piezas de filtrar ya eran comunes —`CajaDeBusqueda`, `Selector`,
// `RangoDeFechas`—, pero cada pantalla las COLOCABA a su manera, y en un
// teléfono de 390 px eso se veía como cuatro aplicaciones distintas. Palabras
// de Jose, 25/09/2026:
//
//     «en movil sigues teniendo los filtros en todas las vistas q tengan
//      filtros lo tienes mal ubicados regados sin uniformidad sin nada lo
//      tienes super mal organizado»
//
// Lo que había, mirado a 390 px en el navegador:
//
//   - **Tablero**: la caja de buscar a todo el ancho y, encima de ella, un
//     embudo suelto pegado al borde derecho, sin nada al lado.
//   - **Pedidos**: la caja de buscar de 220 px con un hueco muerto a su
//     derecha, y debajo siete pastillas partidas en escalones desiguales
//     —dos, dos, una y una— con el borde derecho hecho sierra.
//   - **Clientes**: la caja de buscar de 220 px y los filtros en columna, cada
//     uno con su etiqueta encima («Municipio del cliente»...). Otro diseño.
//   - **Rutas**: la caja de buscar de 220 px y tres pastillas en una fila que
//     acaba antes que la caja de arriba.
//
// Cuatro maneras de resolver lo mismo. En escritorio las cuatro se ven bien
// porque sobra ancho; el desorden nace justo donde se trabaja de verdad.
//
// LA REGLA QUE IMPONE ESTA BARRA, y son tres cosas:
//
// 1. **La caja de buscar manda sola y a todo el ancho.** Siempre arriba,
//    siempre la primera, siempre pegada a los dos márgenes. Es lo que más se
//    usa y lo que antes se encogía a 220 px dejando el hueco.
// 2. **Los filtros van en rejilla de dos columnas iguales.** No en `Wrap`: el
//    `Wrap` reparte según lo que mide cada etiqueta y por eso salían los
//    escalones. Dos columnas de la MISMA anchura dejan el borde derecho recto
//    aunque las etiquetas midan distinto. Si el número de filtros es impar, el
//    último ocupa la fila entera en vez de quedarse cojo al lado de un hueco.
// 3. **En escritorio vuelve a ser una fila que fluye.** A partir de
//    [Anchos.idioma] hay ancho de sobra y la rejilla forzada desperdiciaría
//    sitio; ahí el `Wrap` es lo correcto y además es como está hoy, que
//    funciona.
//
// Lo que esta barra NO hace: NO decide qué filtros hay ni cómo se pintan. Eso
// sigue siendo de cada pantalla y de las piezas de siempre. Aquí sólo se decide
// DÓNDE van, que es lo que estaba mal.

import 'package:flutter/material.dart';

import 'anchos.dart';
import 'tema.dart';

class BarraDeFiltros extends StatelessWidget {
  const BarraDeFiltros({
    required this.busqueda,
    this.filtros = const [],
    this.anchoCompleto = const [],
    this.acciones = const [],
    this.accionFinal,
    this.margen,
    super.key,
  });

  /// La caja de buscar. Va sola en su fila y a todo el ancho: no se le pone
  /// `ancho` —o se le pone `null`—, porque aquí quien manda es esta barra.
  final Widget busqueda;

  /// Los desplegables y pastillas, en el orden en que se leen. Van a la
  /// rejilla de dos columnas.
  final List<Widget> filtros;

  /// Los que NO caben en media columna y ocupan la fila entera: un rango de
  /// fechas —que ya son dos botones y una ✕—, un grupo de segmentos, una
  /// pastilla con un texto largo. Van debajo de la rejilla.
  ///
  /// Meterlos en la rejilla es lo que partía el rango de fechas de Pedidos en
  /// dos escalones con la ✕ colgando sola.
  final List<Widget> anchoCompleto;

  /// Los botones que hacen algo en vez de filtrar: «Agregar vehículo», «Tipos
  /// de vehículo», «Nuevo almacén». Se colocan con la MISMA regla que los
  /// filtros —rejilla de dos columnas en el teléfono— para que la pantalla no
  /// se vea distinta, pero van en su propia lista porque no son filtros y
  /// llamarlos así engañaría a quien lea esto dentro de seis meses.
  final List<Widget> acciones;

  /// Lo que va al final del todo y no es un filtro: «Limpiar», «Quitar
  /// filtros», un embudo de avanzados. Ocupa la fila entera para que no se
  /// confunda con un filtro más.
  final Widget? accionFinal;

  /// El margen lateral. Por defecto el del teléfono ([Aire.md]) y el de las
  /// pantallas grandes ([Aire.xl]), que es la regla de `Aire`.
  final EdgeInsetsGeometry? margen;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final estrecho = ancho < Anchos.idioma;

    final porDefecto = EdgeInsets.symmetric(
      horizontal: estrecho ? Aire.md : Aire.xl,
      vertical: Aire.md,
    );

    return Padding(
      padding: margen ?? porDefecto,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          busqueda,
          if (filtros.isNotEmpty) ...[
            SizedBox(height: estrecho ? Aire.sm : Aire.md),
            if (estrecho) _Rejilla(filtros: filtros) else _Fila(filtros: filtros),
          ],
          for (final ancho in anchoCompleto) ...[
            SizedBox(height: estrecho ? Aire.sm : Aire.md),
            ancho,
          ],
          if (acciones.isNotEmpty) ...[
            SizedBox(height: estrecho ? Aire.sm : Aire.md),
            if (estrecho) _Rejilla(filtros: acciones) else _Fila(filtros: acciones),
          ],
          if (accionFinal != null) ...[
            SizedBox(height: estrecho ? Aire.sm : Aire.md),
            Align(
              alignment: estrecho ? Alignment.centerLeft : Alignment.centerRight,
              child: accionFinal,
            ),
          ],
        ],
      ),
    );
  }
}

/// Dos columnas iguales, y el impar de abajo a todo lo ancho.
///
/// Se hace con `Row`+`Expanded` y no con `GridView` a propósito: el `GridView`
/// quiere un alto fijo por celda y aquí las pastillas miden lo que miden. Con
/// `Expanded` las dos columnas salen exactamente iguales —que es lo que endereza
/// el borde derecho— sin imponer alto.
class _Rejilla extends StatelessWidget {
  const _Rejilla({required this.filtros});

  final List<Widget> filtros;

  @override
  Widget build(BuildContext context) {
    final filas = <Widget>[];

    for (var i = 0; i < filtros.length; i += 2) {
      final ultimoSuelto = i == filtros.length - 1;

      if (filas.isNotEmpty) filas.add(const SizedBox(height: Aire.sm));

      // Un filtro solo en la última fila NO se queda a media anchura con un
      // hueco al lado: eso es justo el escalón que había. Ocupa la fila entera.
      if (ultimoSuelto) {
        filas.add(SizedBox(width: double.infinity, child: filtros[i]));
        continue;
      }

      filas.add(
        // `start` y NO `stretch`: la barra vive dentro de un `ListView`, o sea
        // con alto sin acotar, y `stretch` le pide a la fila que ocupe todo lo
        // alto —que ahí es infinito— y revienta el trazado entero. Lo cazó
        // `test/diseno/barra_de_filtros_test.dart` antes de salir de aquí.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: filtros[i]),
            const SizedBox(width: Aire.sm),
            Expanded(child: filtros[i + 1]),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: filas,
    );
  }
}

/// En escritorio, la fila que fluye de siempre.
class _Fila extends StatelessWidget {
  const _Fila({required this.filtros});

  final List<Widget> filtros;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Aire.sm,
      runSpacing: Aire.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: filtros,
    );
  }
}
