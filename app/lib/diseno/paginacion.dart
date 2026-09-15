import 'package:flutter/material.dart';

import 'colores.dart';
import 'tema.dart';

/// Que se ve en el pie de una lista. Es una funcion pura para poder probarla
/// sin pintar: la aritmetica de paginas es donde salen los «Mostrando 51–50 de
/// 50» que nadie ve hasta que el cliente los ve.
class Rango {
  const Rango(this.desde, this.hasta);

  /// 1-based, como lo lee una persona. Con la lista vacia, `Rango(0, 0)`.
  factory Rango.de({
    required int pagina,
    required int porPagina,
    required int total,
  }) {
    if (total <= 0 || porPagina <= 0) return const Rango(0, 0);
    final desde = (pagina - 1) * porPagina + 1;
    if (desde > total) return Rango(total, total);
    final hasta = (desde + porPagina - 1).clamp(desde, total);
    return Rango(desde, hasta);
  }

  final int desde;
  final int hasta;
}

/// Cuantas paginas hay.
int totalDePaginas({required int total, required int porPagina}) =>
    (total <= 0 || porPagina <= 0) ? 1 : ((total + porPagina - 1) ~/ porPagina);

/// Hasta **5 numeros** alrededor de la actual, pegados al borde cuando la
/// actual esta cerca del principio o del final: con la ventana centrada a secas,
/// en la pagina 1 salen dos huecos a la izquierda.
List<int> paginasVisibles({
  required int actual,
  required int totalPaginas,
  int maximo = 5,
}) {
  if (totalPaginas <= maximo) {
    return <int>[for (var i = 1; i <= totalPaginas; i++) i];
  }
  var primera = actual - maximo ~/ 2;
  if (primera < 1) primera = 1;
  if (primera + maximo - 1 > totalPaginas) primera = totalPaginas - maximo + 1;
  return <int>[for (var i = 0; i < maximo; i++) primera + i];
}

/// La barra del pie (§9.7). **No se pinta si el total es 0.**
class Paginacion extends StatelessWidget {
  const Paginacion({
    required this.pagina,
    required this.porPagina,
    required this.total,
    required this.alIrA,
    this.tamanosPosibles,
    this.alCambiarTamano,
    super.key,
  });

  final int pagina;
  final int porPagina;
  final int total;
  final ValueChanged<int> alIrA;

  /// `null` = el tamano lo fija el servidor y no se ofrece cambiarlo (pedidos
  /// 50, clientes 50). Con lista: vehiculos 25/50/100.
  final List<int>? tamanosPosibles;
  final ValueChanged<int>? alCambiarTamano;

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();
    final paginas = totalDePaginas(total: total, porPagina: porPagina);
    final rango = Rango.de(pagina: pagina, porPagina: porPagina, total: total);

    // `px-4 py-3 border-t bg-white` de `Pagination.tsx`: la paginacion va DENTRO
    // de la caja de la tabla, separada por la linea fina. Por eso el fondo es
    // blanco y no papel.
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Aire.lg,
        vertical: Aire.md,
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          // «Mostrando 51–100 de 412», con las CIFRAS EN NEGRITA y en columna,
          // que es lo que se lee de un vistazo.
          Text.rich(
            TextSpan(
              style: Tipos.texto(tamano: 13, color: Colores.tintaSuave),
              children: [
                const TextSpan(text: 'Mostrando '),
                TextSpan(
                  text: '${rango.desde}–${rango.hasta}',
                  style: Tipos.mono(
                    tamano: 13,
                    peso: FontWeight.w600,
                    color: Colores.tinta,
                  ),
                ),
                const TextSpan(text: ' de '),
                TextSpan(
                  text: '$total',
                  style: Tipos.mono(
                    tamano: 13,
                    peso: FontWeight.w600,
                    color: Colores.tinta,
                  ),
                ),
              ],
            ),
          ),
          if (tamanosPosibles != null && alCambiarTamano != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: Colores.blanco,
                border: Border.all(color: Colores.linea),
                borderRadius: BorderRadius.circular(Radios.md),
              ),
              child: DropdownButton<int>(
                value: porPagina,
                underline: const SizedBox.shrink(),
                isDense: true,
                borderRadius: BorderRadius.circular(Radios.lg),
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: Colores.tintaSuave,
                ),
                style: Tipos.texto(tamano: 13, color: Colores.tinta),
                items: [
                  for (final t in tamanosPosibles!)
                    DropdownMenuItem<int>(value: t, child: Text('$t / pág.')),
                ],
                onChanged: (v) => v == null ? null : alCambiarTamano!(v),
              ),
            ),
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Boton('«', pagina > 1 ? () => alIrA(1) : null),
              _Boton('‹', pagina > 1 ? () => alIrA(pagina - 1) : null),
              for (final p in paginasVisibles(
                actual: pagina,
                totalPaginas: paginas,
              ))
                _Boton(
                  '$p',
                  p == pagina ? null : () => alIrA(p),
                  actual: p == pagina,
                ),
              _Boton('›', pagina < paginas ? () => alIrA(pagina + 1) : null),
              _Boton('»', pagina < paginas ? () => alIrA(paginas) : null),
            ],
          ),
        ],
      ),
    );
  }
}

/// Un numero de pagina. La actual va en primario LLENO y en blanco, como en
/// `Pagination.tsx` (`bg-blue-600 text-white border-blue-600`); las demas son
/// cajas blancas con el borde fino.
class _Boton extends StatelessWidget {
  const _Boton(this.texto, this.alPulsar, {this.actual = false});

  final String texto;
  final VoidCallback? alPulsar;
  final bool actual;

  @override
  Widget build(BuildContext context) {
    final apagado = alPulsar == null && !actual;
    return SizedBox(
      // 36 px: el minimo con el que un dedo acierta sin ampliar. Mas pequeno y
      // en el patio del almacen se pulsa la pagina de al lado.
      width: 36,
      height: 36,
      child: Material(
        color: actual ? Colores.primario : Colores.blanco,
        borderRadius: BorderRadius.circular(Radios.md),
        child: InkWell(
          onTap: alPulsar,
          borderRadius: BorderRadius.circular(Radios.md),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radios.md),
              border: Border.all(
                color: actual ? Colores.primario : Colores.linea,
              ),
            ),
            child: Center(
              child: Opacity(
                // `disabled:opacity-40`.
                opacity: apagado ? 0.4 : 1,
                child: Text(
                  texto,
                  style: Tipos.texto(
                    tamano: 13,
                    peso: actual ? FontWeight.w600 : FontWeight.w500,
                    color: actual ? Colors.white : Colores.tintaSuave,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
