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

    final conBuscador =
        widget.siempreConBuscador ||
        widget.opciones.length >= widget.desdeCuantasBusca;

    // EL MENÚ VA ANCLADO AL BOTÓN, Y LO SIGUE.
    //
    // Antes esto era `showMenu`, que calcula la posición UNA SOLA VEZ al
    // abrirse —con el `RenderBox` del botón en ese instante— y deja el menú
    // clavado en la pantalla, dentro del `Overlay`. En cuanto la página se
    // desplaza, el botón se va y el menú se queda donde estaba, flotando sobre
    // cualquier cosa. Jose, 25/09/2026:
    //
    //     «los select tambien son modales no se por q se mueven en la vista si
    //      me muevo con el scrool en ves de quedarse debajo de su input select»
    //
    // Y el comentario que había encima decía «anclado al borde del boton», que
    // era verdad sólo en el instante de abrirlo. `MenuAnchor` sí lo ancla de
    // verdad: recoloca el menú en cada pasada de trazado, así que se queda
    // debajo de su botón pase lo que pase. Es además el patrón que ya usaban
    // `rango_de_fechas.dart` y el selector de Pedidos, que nunca dieron este
    // problema.
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
          opciones: widget.opciones,
          conBuscador: conBuscador,
          valor: widget.valor,
          alElegir: (v) => widget.alElegir(v),
        ),
      ],
      builder: (contexto, controlador, _) {
        final boton = OutlinedButton(
      onPressed: widget.opciones.isEmpty
          ? null
          : () => controlador.isOpen ? controlador.close() : controlador.open(),
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
          // LA NOTA, EN LA CAJA, SOLO SI ES CORTA.
          //
          // En la lista la nota es todo lo larga que haga falta: ahi se esta
          // eligiendo y cuanto mas se sepa, mejor. En la CAJA es otra cosa: vive
          // dentro de una barra que tiene que caber, y una nota larga la infla y
          // empuja fuera de la pantalla lo que viene detras.
          //
          // Pasaba con la moneda: al elegir CUP, la caja pasaba a decir «CUP
          // 1 USD = 715 · del 16/9/2026» y se comia media barra. Jose, el
          // 16/09/2026: «cuando escojo la moneda ese boton se agranda mucho y me
          // jode la barra superior».
          //
          // El corte es por longitud y no por quien llama, porque el que decide
          // si cabe es el ancho, no el sitio. Las notas cortas —«HAB», «STG»—
          // son justo las que sirven de un vistazo y las que caben; una frase
          // entera se queda en la lista y en el tooltip, donde no estorba.
          if (_cabeEnLaCaja(elegida?.nota)) ...[
            const SizedBox(width: 6),
            Text(
              elegida!.nota!,
              style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
            ),
          ],
          const SizedBox(width: Aire.xs),
          Icon(Icons.keyboard_arrow_down, size: 16, color: Colores.tintaSuave),
        ],
      ),
    );

        return widget.tooltip == null
            ? boton
            : Tooltip(message: widget.tooltip!, child: boton);
      },
    );
  }

}

class _Menu<T> extends StatefulWidget {
  const _Menu({
    required this.opciones,
    required this.conBuscador,
    required this.valor,
    required this.alElegir,
  });

  final List<OpcionSelector<T>> opciones;
  final bool conBuscador;
  final T? valor;

  /// Se avisa por aqui y NO con `Navigator.pop`. El `pop` era de `showMenu`,
  /// que abria el menu como una ruta; con `MenuAnchor` el menu no es una ruta,
  /// asi que un `pop` cerraria la PANTALLA de debajo.
  final ValueChanged<T> alElegir;

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
            Divider(height: 1, thickness: 1, color: Colores.linea),
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
            // `primary: false`: el desplazamiento de un menu es SUYO y nunca el
            // principal de la pantalla. Antes daba igual porque `showMenu`
            // abria el menu como una RUTA aparte; ahora, con `MenuAnchor`, el
            // menu vive en la misma pantalla y sin esto quedan dos
            // desplazamientos colgando del mismo `PrimaryScrollController`
            // —el del cuerpo y el del menu— y Flutter lo corta en seco: «The
            // PrimaryScrollController is attached to more than one
            // ScrollPosition». Lo mismo que ya le pasó al menu de Pedidos
            // (`pedidos/vista/kit.dart`).
            child: SingleChildScrollView(
              primary: false,
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
                    _Opcion<T>(
                      opcion: o,
                      elegida: o.valor == widget.valor,
                      alElegir: widget.alElegir,
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

/// Una fila del menu. La elegida va en primario y con la marca a la derecha,
/// como en `Selector.tsx`; el resto en tinta.
class _Opcion<T> extends StatelessWidget {
  const _Opcion({
    required this.opcion,
    required this.elegida,
    required this.alElegir,
  });

  final OpcionSelector<T> opcion;
  final bool elegida;
  final ValueChanged<T> alElegir;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () {
      // Primero se avisa y luego se cierra: cerrar antes desmonta este
      // `State` y el aviso se perderia.
      alElegir(opcion.valor);
      MenuController.maybeOf(context)?.close();
    },
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
            Icon(Icons.check, size: 16, color: Colores.primario),
          ],
        ],
      ),
    ),
  );
}

/// Cuantos caracteres de nota caben al lado de la etiqueta sin inflar la caja.
///
/// Doce es lo que mide «HAB» con sitio de sobra y lo que NO mide una frase. El
/// numero esta aqui y no repartido para que cambiarlo sea un sitio.
const int _notaCortaEnLaCaja = 12;

bool _cabeEnLaCaja(String? nota) =>
    nota != null && nota.trim().length <= _notaCortaEnLaCaja;
