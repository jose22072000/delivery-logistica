import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import 'colores.dart';

/// Una opcion del selector: etiqueta a la izquierda y **nota** pequena a la
/// derecha (un conteo, un codigo de sucursal, una tasa).
class OpcionSelector<T> {
  const OpcionSelector({required this.valor, required this.etiqueta, this.nota});

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
    final tema = Theme.of(context);
    final elegida = widget.opciones
        .where((o) => o.valor == widget.valor)
        .firstOrNull;

    final boton = OutlinedButton.icon(
      onPressed: widget.opciones.isEmpty ? null : _abrir,
      icon: widget.icono == null ? null : Icon(widget.icono, size: 18),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              elegida?.etiqueta ?? widget.etiquetaVacia,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 20),
        ],
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: tema.colorScheme.onSurface,
        side: const BorderSide(color: Colores.borde),
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
        caja.localToGlobal(caja.size.bottomLeft(Offset.zero), ancestor: overlay),
        caja.localToGlobal(caja.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final conBuscador = widget.siempreConBuscador ||
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
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Buscar',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _busca = v),
              ),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (visibles.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Sin resultados.'),
                  ),
                for (final o in visibles)
                  ListTile(
                    dense: true,
                    selected: o.valor == widget.valor,
                    title: Text(o.etiqueta),
                    trailing: o.nota == null
                        ? null
                        : Text(
                            o.nota!,
                            style: tema.textTheme.bodySmall?.copyWith(
                              color: Colores.gris,
                            ),
                          ),
                    onTap: () => Navigator.of(context).pop(o.valor),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
