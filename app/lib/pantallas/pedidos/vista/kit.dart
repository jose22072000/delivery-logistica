// El kit que usan Pedidos y Rutas: cajon, insignias, paginacion, selector con
// buscador, estados vacios y la barra con el reloj de datos.
//
// **Ya NO tiene colores ni anchos propios.** Los tenia: una copia de la paleta y
// otra del enum de anchos, escritas cuando `lib/diseno/` todavia no existia. Con
// las dos copias vivas, «ámbar» era un ámbar aqui y otro en el Panel, y el azul
// de una insignia de Pedidos no era el azul de una de Rutas. Ahora los dos
// salen de `lib/diseno/` y se reexportan desde aqui para que las ocho pantallas
// que importan este fichero no tengan que cambiar sus `import`.
//
// Lo que si sigue viviendo aqui son las piezas con la forma que usan estas dos
// pantallas (el `Cajon` de `cuerpo:`, el `Selector` de `MenuAnchor`); lo que
// cambio es **como se ven**, que ahora es lo mismo que en `lib/diseno/`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/frescura/reloj_de_datos.dart';
import '../../../nucleo/proveedores.dart';

/// La paleta y los anchos de cajon son los de `lib/diseno/`, punto. Se
/// reexportan para no tocar los `import` de las ocho pantallas que los leen
/// desde aqui.
export '../../../diseno/anchos.dart' show AnchoCajon;
export '../../../diseno/colores.dart' show Colores;

/// Por debajo de esto es «movil»: el cajon ocupa la pantalla entera y las
/// columnas prescindibles de la tabla se esconden.
const anchoEscritorio = Anchos.escritorio;

// -----------------------------------------------------------------------------
// El cajon
// -----------------------------------------------------------------------------

/// El patron cajon: entra deslizandose por la derecha, a alto completo, sobre un
/// velo negro al 40 %.
///
/// **Esta aplicacion usa cajon tambien en escritorio.** Es la excepcion aprobada
/// del 05/09/2026 (`pantallas.md` §0 y §9.2): en el resto de Procovar es modal en
/// escritorio y cajon en movil, aqui no hay variante modal. Lo que se conserva de
/// la regla de la casa es lo que de verdad importa: en movil ocupa la pantalla
/// entera, en escritorio es un panel lateral a alto completo —nunca un
/// `AlertDialog` centrado— y **la ✕ de cerrar no desaparece nunca**, esté donde
/// esté el desplazamiento del cuerpo.
class Cajon extends StatelessWidget {
  const Cajon({
    required this.titulo,
    required this.cuerpo,
    this.subtitulo,
    this.ancho = AnchoCajon.lg,
    this.pie,
    super.key,
  });

  final String titulo;
  final String? subtitulo;
  final Widget cuerpo;

  /// Pegado abajo, con los botones de accion **siempre a la vista**.
  final Widget? pie;
  final AnchoCajon ancho;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final pantalla = MediaQuery.sizeOf(context);
    final enMovil = pantalla.width < anchoEscritorio;
    final anchoFinal = enMovil
        ? pantalla.width
        : ancho.px.clamp(0.0, pantalla.width);

    return Align(
      alignment: Alignment.centerRight,
      child: DecoratedBox(
        // `shadow-2xl` y borde fino a la izquierda, como el `Drawer.tsx` de
        // delivery: sobre el velo al 40 %, un panel sin sombra se pega al borde
        // y no se lee como algo que esta por encima de la lista.
        decoration: BoxDecoration(
          color: Colores.blanco,
          border: Border(left: BorderSide(color: Colores.linea)),
          boxShadow: Sombras.xl,
        ),
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: anchoFinal,
            height: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Aire.xl,
                      Aire.lg,
                      Aire.sm,
                      Aire.lg,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                titulo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tema.textTheme.titleMedium,
                              ),
                              if (subtitulo != null)
                                Text(
                                  subtitulo!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tema.textTheme.bodySmall?.copyWith(
                                    color: Colores.tintaSuave,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // La ✕: fuera del cuerpo desplazable, para que no se pueda
                        // ir de la vista por mucho que se baje.
                        IconButton(
                          tooltip: 'Cerrar',
                          icon: const Icon(Icons.close, size: 20),
                          color: Colores.tintaSuave,
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, thickness: 1, color: Colores.linea),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      Aire.xl,
                      Aire.lg,
                      Aire.xl,
                      Aire.xl,
                    ),
                    child: cuerpo,
                  ),
                ),
                if (pie != null) ...[
                  Divider(height: 1, thickness: 1, color: Colores.linea),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Aire.xl,
                        vertical: Aire.md,
                      ),
                      child: pie,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Abre un [Cajon]. `Escape` y el velo cierran, y la animacion es la del pliego:
/// 180 ms desde 24 px a la derecha.
Future<T?> abrirCajon<T>(BuildContext context, WidgetBuilder construir) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: Colores.tinta.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (contexto, _, _) => construir(contexto),
    transitionBuilder: (contexto, animacion, _, hijo) {
      final curva = CurvedAnimation(parent: animacion, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curva,
        child: Transform.translate(
          offset: Offset(24 * (1 - curva.value), 0),
          child: hijo,
        ),
      );
    },
  );
}

// -----------------------------------------------------------------------------
// Piezas sueltas
// -----------------------------------------------------------------------------

/// Una insignia de color con su texto. Nada de emojis: color y palabra.
class Insignia extends StatelessWidget {
  const Insignia(this.texto, {required this.color, this.tooltip, super.key});

  final String texto;
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final pinta = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radios.pastilla),
      ),
      child: Text(
        texto,
        style: Tipos.texto(
          tamano: 11,
          peso: FontWeight.w600,
          color: color,
          interletra: 0.1,
        ),
      ),
    );
    return tooltip == null ? pinta : Tooltip(message: tooltip!, child: pinta);
  }
}

/// El estado vacio. Son tres textos distintos y se confunden con facilidad, asi
/// que el que toca lo decide quien llama y aqui sólo se pinta.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio(this.texto, {this.accion, super.key});

  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: Aire.xl),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          texto,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Colores.tintaSuave),
        ),
        if (accion != null) ...[const SizedBox(height: Aire.lg), accion!],
      ],
    ),
  );
}

/// La barra de paginas del pliego (§9.7). No se pinta si el total es 0.
class Paginacion extends StatelessWidget {
  const Paginacion({
    required this.pagina,
    required this.porPagina,
    required this.total,
    required this.alIr,
    super.key,
  });

  final int pagina;
  final int porPagina;
  final int total;
  final void Function(int) alIr;

  int get paginas => total == 0 ? 1 : ((total - 1) ~/ porPagina) + 1;

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox.shrink();
    final desde = ((pagina - 1) * porPagina) + 1;
    final hasta = (pagina * porPagina).clamp(0, total);

    // Ventana de 5 numeros alrededor de la actual.
    final primero = (pagina - 2).clamp(1, paginas);
    final ultimo = (primero + 4).clamp(1, paginas);
    final inicio = (ultimo - 4).clamp(1, paginas);

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: Aire.md,
        horizontal: Aire.lg,
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Aire.xs,
        runSpacing: Aire.xs,
        children: [
          // Las cifras en mono y en negrita, que es lo que se lee de un vistazo.
          Text.rich(
            TextSpan(
              style: Tipos.texto(tamano: 13, color: Colores.tintaSuave),
              children: [
                const TextSpan(text: 'Mostrando '),
                TextSpan(
                  text: '$desde–$hasta',
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
          const SizedBox(width: Aire.sm),
          _boton(context, '«', pagina > 1 ? () => alIr(1) : null),
          _boton(context, '‹', pagina > 1 ? () => alIr(pagina - 1) : null),
          for (var n = inicio; n <= ultimo; n++)
            _boton(
              context,
              '$n',
              n == pagina ? null : () => alIr(n),
              actual: n == pagina,
            ),
          _boton(
            context,
            '›',
            pagina < paginas ? () => alIr(pagina + 1) : null,
          ),
          _boton(context, '»', pagina < paginas ? () => alIr(paginas) : null),
        ],
      ),
    );
  }

  /// La actual va en primario LLENO y en blanco (`bg-blue-600 text-white`); las
  /// demas son cajas blancas con el borde fino, y las que no llevan a ninguna
  /// parte al 40 % (`disabled:opacity-40`).
  Widget _boton(
    BuildContext context,
    String texto,
    VoidCallback? alPulsar, {
    bool actual = false,
  }) => SizedBox(
    width: 34,
    height: 34,
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
              opacity: alPulsar == null && !actual ? 0.4 : 1,
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

/// Una opcion del selector: etiqueta y una nota pequena a la derecha (un
/// conteo, un codigo, `en ruta`).
class OpcionSelector<T> {
  const OpcionSelector(this.valor, this.etiqueta, {this.nota});

  final T valor;
  final String etiqueta;
  final String? nota;
}

/// El desplegable con buscador (§9.6): **caja de busqueda a partir de 4
/// opciones**, o siempre si se fuerza.
class Selector<T> extends StatelessWidget {
  const Selector({
    required this.titulo,
    required this.valor,
    required this.opciones,
    required this.alElegir,
    this.buscadorSiempre = false,
    super.key,
  });

  final String titulo;
  final T valor;

  /// La opcion «todos» va la primera y su texto lo pone cada pantalla.
  final List<OpcionSelector<T>> opciones;
  final void Function(T) alElegir;
  final bool buscadorSiempre;

  @override
  Widget build(BuildContext context) {
    final elegida = opciones.where((o) => o.valor == valor).firstOrNull;
    // Igual que el de `lib/diseno/selector.dart`: con algo elegido el borde se
    // tine de primario y la letra se pone en semibold, para que se vea que el
    // filtro ESTA PUESTO sin leer la etiqueta.
    final filtrando = elegida != null;

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
      builder: (contexto, controlador, _) => Tooltip(
        message: titulo,
        child: OutlinedButton(
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
              Flexible(
                child: Text(
                  elegida?.etiqueta ?? titulo,
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
      ),
      menuChildren: [
        _MenuConBuscador<T>(
          opciones: opciones,
          conBuscador: buscadorSiempre || opciones.length >= 4,
          alElegir: alElegir,
        ),
      ],
    );
  }
}

class _MenuConBuscador<T> extends StatefulWidget {
  const _MenuConBuscador({
    required this.opciones,
    required this.conBuscador,
    required this.alElegir,
  });

  final List<OpcionSelector<T>> opciones;
  final bool conBuscador;
  final void Function(T) alElegir;

  @override
  State<_MenuConBuscador<T>> createState() => _MenuConBuscadorState<T>();
}

class _MenuConBuscadorState<T> extends State<_MenuConBuscador<T>> {
  String _texto = '';

  @override
  Widget build(BuildContext context) {
    final busca = _texto.trim().toLowerCase();
    final visibles = busca.isEmpty
        ? widget.opciones
        : widget.opciones
              .where((o) => o.etiqueta.toLowerCase().contains(busca))
              .toList();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360, maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.conBuscador) ...[
            Padding(
              padding: const EdgeInsets.all(Aire.sm),
              child: TextField(
                autofocus: true,
                style: Tipos.texto(tamano: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  prefixIconConstraints: BoxConstraints(minWidth: 34),
                  hintText: 'Buscar…',
                ),
                onChanged: (t) => setState(() => _texto = t),
              ),
            ),
            Divider(height: 1, thickness: 1, color: Colores.linea),
          ],
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final opcion in visibles)
                    MenuItemButton(
                      onPressed: () => widget.alElegir(opcion.valor),
                      trailingIcon: opcion.nota == null
                          ? null
                          : Text(
                              opcion.nota!,
                              style: Tipos.texto(
                                tamano: 11,
                                color: Colores.tintaSuave,
                              ),
                            ),
                      child: Text(
                        opcion.etiqueta,
                        style: Tipos.texto(tamano: 14, color: Colores.tinta),
                      ),
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

// -----------------------------------------------------------------------------
// La barra con el reloj de datos
// -----------------------------------------------------------------------------

/// De que hora son los datos de unas colecciones, listo para el [RelojDeDatos].
///
/// Manda la bajada MAS VIEJA de las que usa la pantalla: una pantalla no esta al
/// dia si una de las colecciones que pinta no lo esta.
final frescuraDePantallaProvider =
    StreamProvider.family<EstadoFrescura, List<String>>((ref, colecciones) {
      final reloj = ref.watch(relojProvider);
      return ref
          .watch(frescuraProvider)
          .laMasVieja(colecciones)
          .map((bajada) => EstadoFrescura.de(bajada, ahora: reloj()));
    });

/// La franja de arriba, **siempre visible**: de que hora son los datos y cuanto
/// queda sin subir (caso S8). Sin esto, una pantalla con datos de anteayer es
/// indistinguible de una al dia.
class BarraDeDatos extends ConsumerWidget {
  const BarraDeDatos({
    required this.colecciones,
    this.alPulsarPendientes,
    super.key,
  });

  final List<String> colecciones;
  final VoidCallback? alPulsarPendientes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frescura = ref.watch(frescuraDePantallaProvider(colecciones));
    final sinSubir = ref.watch(sinSubirProvider);

    return RelojDeDatos(
      // Mientras carga la propia consulta de frescura no se puede afirmar que
      // los datos esten al dia: se dice lo mismo que si no se hubieran bajado.
      estado: frescura.value ?? const SinDescargar(),
      sinSubir: sinSubir.value ?? 0,
      alPulsarPendientes: alPulsarPendientes,
    );
  }
}

/// Las colecciones que mira cada pantalla. Se declaran aqui, al lado de la
/// barra, para que anadir una consulta nueva a una pantalla obligue a pensar si
/// su frescura cuenta.
abstract final class ColeccionesDePantalla {
  static const pedidos = <String>[
    Colecciones.pedidos,
    Colecciones.renglones,
    Colecciones.productos,
  ];

  static const rutas = <String>[
    Colecciones.rutas,
    Colecciones.pedidos,
    Colecciones.vehiculos,
    Colecciones.almacenes,
  ];
}
