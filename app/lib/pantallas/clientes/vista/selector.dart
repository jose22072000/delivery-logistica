import 'package:flutter/material.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';

/// Una opcion de un selector: etiqueta y una **nota** pequena a la derecha (un
/// conteo, un codigo).
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

/// El `Selector` del pliego (`pantallas.md` §9.6): **no es un desplegable del
/// sistema**, es un boton que abre un menu anclado a su borde, con buscador a
/// partir de 4 opciones.
///
/// El buscador desde 4 no es capricho: en el telefono, con el teclado abierto,
/// una lista de municipios es mas rapida escribiendo que arrastrando.
class SelectorFiltro<T> extends StatelessWidget {
  const SelectorFiltro({
    required this.titulo,
    required this.textoTodos,
    required this.opciones,
    required this.valor,
    required this.alElegir,
    this.icono,
    this.desdeCuantasBusca = 4,
    super.key,
  });

  final String titulo;

  /// El texto de la opcion «todos», que lo pone cada pantalla. Va siempre la
  /// primera.
  final String textoTodos;
  final List<OpcionSelector<T>> opciones;
  final T? valor;
  final ValueChanged<T?> alElegir;
  final IconData? icono;
  final int desdeCuantasBusca;

  @override
  Widget build(BuildContext context) {
    final elegida = opciones.where((o) => o.valor == valor).firstOrNull;
    // Con algo elegido el borde se tine de primario y la letra se pone en
    // semibold, igual que en `lib/diseno/selector.dart`: asi se ve de un vistazo
    // cuales de los seis filtros estan puestos.
    final filtrando = elegida != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          titulo,
          style: Tipos.texto(
            tamano: 10,
            peso: FontWeight.w600,
            color: Colores.tintaSuave.withValues(alpha: 0.75),
            interletra: 0.4,
          ),
        ),
        const SizedBox(height: 5),
        OutlinedButton(
          onPressed: () => _abrir(context),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colores.blanco,
            foregroundColor: filtrando ? Colores.tinta : Colores.tintaSuave,
            side: BorderSide(
              color: filtrando
                  ? Colores.primario.withValues(alpha: 0.5)
                  : Colores.linea,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: Aire.md,
              vertical: 9,
            ),
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
              Icon(
                icono ?? Icons.filter_list,
                size: 16,
                color: Colores.tintaSuave,
              ),
              const SizedBox(width: Aire.sm),
              Flexible(
                child: Text(
                  elegida?.etiqueta ?? textoTodos,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Aire.xs),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: Colores.tintaSuave,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _abrir(BuildContext context) async {
    final caja = context.findRenderObject()! as RenderBox;
    final pantalla =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final sitio = RelativeRect.fromRect(
      Rect.fromPoints(
        caja.localToGlobal(Offset.zero, ancestor: pantalla),
        caja.localToGlobal(
          caja.size.bottomRight(Offset.zero),
          ancestor: pantalla,
        ),
      ),
      Offset.zero & pantalla.size,
    );
    final elegido = await showMenu<_Eleccion<T>>(
      context: context,
      position: sitio,
      items: [
        PopupMenuItem<_Eleccion<T>>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _Menu<T>(
            titulo: titulo,
            textoTodos: textoTodos,
            opciones: opciones,
            conBuscador: opciones.length >= desdeCuantasBusca,
          ),
        ),
      ],
    );
    if (elegido != null) alElegir(elegido.valor);
  }
}

class _Eleccion<T> {
  const _Eleccion(this.valor);
  final T? valor;
}

class _Menu<T> extends StatefulWidget {
  const _Menu({
    required this.titulo,
    required this.textoTodos,
    required this.opciones,
    required this.conBuscador,
  });

  final String titulo;
  final String textoTodos;
  final List<OpcionSelector<T>> opciones;
  final bool conBuscador;

  @override
  State<_Menu<T>> createState() => _MenuState<T>();
}

class _MenuState<T> extends State<_Menu<T>> {
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    final filtradas = widget.opciones
        .where(
          (o) => o.etiqueta.toLowerCase().contains(_busqueda.toLowerCase()),
        )
        .toList();
    return SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.conBuscador) ...[
            Padding(
              padding: const EdgeInsets.all(Aire.sm),
              child: TextField(
                autofocus: true,
                style: Tipos.texto(tamano: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Buscar…',
                  prefixIcon: Icon(Icons.search, size: 18),
                  prefixIconConstraints: BoxConstraints(minWidth: 34),
                ),
                onChanged: (t) => setState(() => _busqueda = t),
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Colores.linea),
          ],
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                // La opcion «todos» es SIEMPRE la primera y no se filtra con el
                // buscador: es la salida de vuelta.
                ListTile(
                  dense: true,
                  title: Text(
                    widget.textoTodos,
                    style: Tipos.texto(tamano: 14, color: Colores.tinta),
                  ),
                  onTap: () => Navigator.pop(context, _Eleccion<T>(null)),
                ),
                for (final o in filtradas)
                  ListTile(
                    dense: true,
                    title: Text(
                      o.etiqueta,
                      style: Tipos.texto(tamano: 14, color: Colores.tinta),
                    ),
                    trailing: o.nota == null
                        ? null
                        : Text(
                            o.nota!,
                            style: Tipos.texto(
                              tamano: 11,
                              color: Colores.tintaSuave,
                            ),
                          ),
                    onTap: () => Navigator.pop(context, _Eleccion<T>(o.valor)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
