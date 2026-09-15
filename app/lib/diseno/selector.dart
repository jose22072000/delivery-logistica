import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import 'colores.dart';
import 'tema.dart';

/// Una opcion del selector: etiqueta a la izquierda y **nota** pequena a la
/// derecha (un conteo, un codigo de sucursal, una tasa).
class OpcionSelector<T> {
  const OpcionSelector({
    required this.valor,
    required this.etiqueta,
    this.nota,
  });

  final T valor;
  final String etiqueta;
  final String? nota;
}

/// El desplegable del pliego (§9.6). **No es un `<select>` del sistema**: es un
/// boton que abre un menu anclado a su propio borde, con buscador **a partir de
/// 4 opciones**.
///
/// El buscador no es un adorno: el selector de vendedor del armador de rutas
/// tiene ciento y pico opciones, y en el teclado de un telefono escribir tres
/// letras es mas rapido que recorrer la lista con el dedo. Por eso se puede
/// forzar con [siempreConBuscador].
class Selector<T> extends StatefulWidget {
  const Selector({
    required this.opciones,
    required this.valor,
    required this.alElegir,
    required this.etiquetaVacia,
    this.icono,
    this.desdeCuantasBusca = 4,
    this.siempreConBuscador = false,
    this.tooltip,
    super.key,
  });

  /// La opcion «todos» va **la primera** y su texto lo pone cada pantalla
  /// (`Todas las sucursales (8)`, `Todos los vehículos`), asi que entra en esta
  /// lista como una mas.
  final List<OpcionSelector<T>> opciones;
  final T? valor;
  final ValueChanged<T> alElegir;

  /// Lo que se pinta cuando `valor` no esta en la lista.
  final String etiquetaVacia;

  final IconData? icono;
  final int desdeCuantasBusca;
  final bool siempreConBuscador;
  final String? tooltip;

  @override
  State<Selector<T>> createState() => _SelectorState<T>();
}

class _SelectorState<T> extends State<Selector<T>> {
  @override
  Widget build(BuildContext context) {
    final elegida = widget.opciones
        .where((o) => o.valor == widget.valor)
        .firstOrNull;

    // Cuando hay algo elegido el borde se tine de primario y la letra se pone
    // en semibold: es como se ve en `Selector.tsx` que un filtro ESTA PUESTO
    // sin tener que leer la etiqueta entera.
    final filtrando = elegida != null;

    final boton = OutlinedButton(
      onPressed: widget.opciones.isEmpty ? null : _abrir,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colores.blanco,
        foregroundColor: filtrando ? Colores.tinta : Colores.tintaSuave,
        side: BorderSide(
          color: filtrando
              ? Colores.primario.withValues(alpha: 0.5)
              : Colores.linea,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        textStyle: Tipos.texto(
          tamano: 14,
          peso: filtrando ? FontWeight.w600 : FontWeight.w400,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radios.lg),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icono != null) ...[
            Icon(widget.icono, size: 16, color: Colores.tintaSuave),
            const SizedBox(width: Aire.sm),
          ],
          Flexible(
            child: Text(
              elegida?.etiqueta ?? widget.etiquetaVacia,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (elegida?.nota != null) ...[
            const SizedBox(width: 6),
            Text(
              elegida!.nota!,
              style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
            ),
          ],
          const SizedBox(width: Aire.xs),
          const Icon(
            Icons.keyboard_arrow_down,
            size: 16,
            color: Colores.tintaSuave,
          ),
        ],
      ),
    );

    return widget.tooltip == null
        ? boton
        : Tooltip(message: widget.tooltip!, child: boton);
  }

  Future<void> _abrir() async {
    final caja = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    // Anclado al borde del boton, no centrado en la pantalla: con dos selectores
    // seguidos en la barra, uno centrado no deja ver cual se abrio.
    final posicion = RelativeRect.fromRect(
      Rect.fromPoints(
        caja.localToGlobal(
          caja.size.bottomLeft(Offset.zero),
          ancestor: overlay,
        ),
        caja.localToGlobal(
          caja.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final conBuscador =
        widget.siempreConBuscador ||
        widget.opciones.length >= widget.desdeCuantasBusca;

    final elegido = await showMenu<T>(
      context: context,
      position: posicion,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
      items: [
        PopupMenuItem<T>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _Menu<T>(
            opciones: widget.opciones,
            conBuscador: conBuscador,
            valor: widget.valor,
          ),
        ),
      ],
    );
    if (elegido != null) widget.alElegir(elegido);
  }
}

class _Menu<T> extends StatefulWidget {
  const _Menu({
    required this.opciones,
    required this.conBuscador,
    required this.valor,
  });

  final List<OpcionSelector<T>> opciones;
  final bool conBuscador;
  final T? valor;

  @override
  State<_Menu<T>> createState() => _MenuState<T>();
}

class _MenuState<T> extends State<_Menu<T>> {
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final texto = _busca.trim().toLowerCase();
    final visibles = texto.isEmpty
        ? widget.opciones
        : widget.opciones
              .where(
                (o) =>
                    o.etiqueta.toLowerCase().contains(texto) ||
                    (o.nota ?? '').toLowerCase().contains(texto),
              )
              .toList();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.conBuscador)
            Padding(
              padding: const EdgeInsets.all(Aire.sm),
              child: TextField(
                autofocus: true,
                style: tema.textTheme.bodyMedium,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  prefixIconConstraints: BoxConstraints(minWidth: 34),
                  hintText: 'Buscar…',
                ),
                onChanged: (v) => setState(() => _busca = v),
              ),
            ),
          if (widget.conBuscador)
            const Divider(height: 1, thickness: 1, color: Colores.linea),
          // NO ES UN `ListView`, Y NO PUEDE SERLO.
          //
          // `PopupMenuItem` envuelve a su hijo en un `IntrinsicWidth` para que
          // el menu se ajuste a lo que hay dentro. Un `ListView` es un
          // `RenderShrinkWrappingViewport`, y una lista perezosa **no sabe decir
          // cuanto mide sin construir todos sus hijos**, que es precisamente lo
          // que la pereza evita. Preguntarselo lanza:
          //
          //     RenderShrinkWrappingViewport does not support returning
          //     intrinsic dimensions.
          //
          // Y eso pasaba al abrir CUALQUIER desplegable de la aplicacion: el de
          // sucursal, el de moneda, los filtros de las siete pantallas y los
          // cuatro pasos del asistente. Jose lo vio en el Tablero — el menu se
          // pintaba y elegir no hacia nada.
          //
          // `SingleChildScrollView` sobre una `Column` si sabe medirse, porque
          // su hijo es una caja normal. Y la pereza aqui no compra nada: la
          // lista mas larga es la de vendedores, ciento y pico filas de texto.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (visibles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(Aire.lg),
                      child: Text(
                        'Nada que cuadre con «$_busca»',
                        textAlign: TextAlign.center,
                        style: tema.textTheme.bodySmall?.copyWith(
                          color: Colores.tintaSuave,
                        ),
                      ),
                    ),
                  for (final o in visibles)
                    _Opcion<T>(opcion: o, elegida: o.valor == widget.valor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una fila del menu. La elegida va en primario y con la marca a la derecha,
/// como en `Selector.tsx`; el resto en tinta.
class _Opcion<T> extends StatelessWidget {
  const _Opcion({required this.opcion, required this.elegida});

  final OpcionSelector<T> opcion;
  final bool elegida;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => Navigator.of(context).pop(opcion.valor),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              opcion.etiqueta,
              overflow: TextOverflow.ellipsis,
              style: Tipos.texto(
                tamano: 14,
                peso: elegida ? FontWeight.w600 : FontWeight.w400,
                color: elegida ? Colores.primario : Colores.tinta,
              ),
            ),
          ),
          if (opcion.nota != null) ...[
            const SizedBox(width: Aire.sm),
            Text(
              opcion.nota!,
              style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
            ),
          ],
          if (elegida) ...[
            const SizedBox(width: Aire.sm),
            const Icon(Icons.check, size: 16, color: Colores.primario),
          ],
        ],
      ),
    ),
  );
}
