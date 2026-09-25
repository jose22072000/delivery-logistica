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

    // EL MENÚ VA ANCLADO AL BOTÓN, Y LO SIGUE.
    //
    // Era `showMenu`, que fija la posición una sola vez al abrirse y deja el
    // menú clavado en el `Overlay`: al desplazar la lista de clientes el botón
    // se iba y el menú se quedaba flotando. Jose, 25/09/2026: «los select
    // también son modales, se mueven en la vista si me muevo con el scroll en
    // vez de quedarse debajo de su input». El mismo arreglo y el mismo motivo
    // que en `lib/diseno/selector.dart`, atado allí por
    // `test/diseno/selector_sigue_al_boton_test.dart`.
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Colores.blanco),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radios.lg),
            side: BorderSide(color: Colores.linea),
          ),
        ),
      ),
      menuChildren: [
        _Menu<T>(
          titulo: titulo,
          textoTodos: textoTodos,
          opciones: opciones,
          conBuscador: opciones.length >= desdeCuantasBusca,
          alElegir: alElegir,
        ),
      ],
      builder: (contexto, controlador, _) => Column(
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
          onPressed: () =>
              controlador.isOpen ? controlador.close() : controlador.open(),
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
              Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: Colores.tintaSuave,
              ),
            ],
          ),
        ),
      ],
      ),
    );
  }
}

class _Menu<T> extends StatefulWidget {
  const _Menu({
    required this.titulo,
    required this.textoTodos,
    required this.opciones,
    required this.conBuscador,
    required this.alElegir,
  });

  final String titulo;
  final String textoTodos;
  final List<OpcionSelector<T>> opciones;
  final bool conBuscador;

  /// Se avisa por aqui y NO con `Navigator.pop`. El `pop` era de `showMenu`,
  /// que abria el menu como una ruta aparte; con `MenuAnchor` el menu vive en
  /// la misma pantalla y un `pop` cerraria la pantalla de debajo.
  final ValueChanged<T?> alElegir;

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
            Divider(height: 1, thickness: 1, color: Colores.linea),
          ],
          Flexible(
            // NO ES UN `ListView`, Y NO PUEDE SERLO — lo mismo que ya decía
            // `lib/diseno/selector.dart`, y que aquí costó un reventón.
            //
            // `MenuAnchor` pregunta a su contenido cuánto mide de ancho para
            // decidir el ancho del menú, y un `ListView` no sabe contestar a
            // eso: «RenderShrinkWrappingViewport does not support returning
            // intrinsic dimensions». Un `SingleChildScrollView` sobre una
            // `Column` sí, porque su hijo es una caja normal. Con `showMenu` no
            // pasaba porque el menú era una ruta con ancho impuesto.
            //
            // `primary: false`: el desplazamiento de un menú es SUYO y nunca el
            // principal de la pantalla. Sin esto quedan dos desplazamientos
            // colgando del mismo `PrimaryScrollController` —el de la lista de
            // clientes y el del menú— y Flutter lo corta en seco: «The
            // PrimaryScrollController is attached to more than one
            // ScrollPosition».
            child: SingleChildScrollView(
              primary: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                // La opcion «todos» es SIEMPRE la primera y no se filtra con el
                // buscador: es la salida de vuelta.
                ListTile(
                  dense: true,
                  title: Text(
                    widget.textoTodos,
                    style: Tipos.texto(tamano: 14, color: Colores.tinta),
                  ),
                  onTap: () {
                    widget.alElegir(null);
                    MenuController.maybeOf(context)?.close();
                  },
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
                    onTap: () {
                      widget.alElegir(o.valor);
                      MenuController.maybeOf(context)?.close();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
