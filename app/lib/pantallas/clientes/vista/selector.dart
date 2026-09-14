import 'package:flutter/material.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titulo, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () => _abrir(context),
          icon: Icon(icono ?? Icons.filter_list, size: 18),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  elegida?.etiqueta ?? textoTodos,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.expand_more, size: 18),
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
          if (widget.conBuscador)
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(),
                ),
                onChanged: (t) => setState(() => _busqueda = t),
              ),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                // La opcion «todos» es SIEMPRE la primera y no se filtra con el
                // buscador: es la salida de vuelta.
                ListTile(
                  dense: true,
                  title: Text(widget.textoTodos),
                  onTap: () => Navigator.pop(context, _Eleccion<T>(null)),
                ),
                for (final o in filtradas)
                  ListTile(
                    dense: true,
                    title: Text(o.etiqueta),
                    trailing: o.nota == null
                        ? null
                        : Text(
                            o.nota!,
                            style: Theme.of(context).textTheme.bodySmall,
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
