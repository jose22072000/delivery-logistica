// El kit compartido por Pedidos y Rutas: cajon, insignias, paginacion, selector
// con buscador, estados vacios y la barra con el reloj de datos.
//
// **Por que vive aqui y no en `lib/diseno/`:** el kit de PLAN.md §1 todavia no
// existe y esta tarea sólo escribe dentro de `lib/pantallas/`. Cuando se cree
// `lib/diseno/`, este fichero se mueve entero y lo unico que cambia son los
// `import`. Se deja en Pedidos porque es la pantalla que, segun el plan, «levanta
// de una vez todo lo que las demas reutilizan».

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/frescura/reloj_de_datos.dart';
import '../../../nucleo/proveedores.dart';

/// Los colores del pliego. En un solo sitio para que «ámbar» sea el mismo ámbar
/// en las dos pantallas.
abstract final class Colores {
  static const ambar = Color(0xFFB45309);
  static const verde = Color(0xFF15803D);
  static const azul = Color(0xFF1D4ED8);
  static const indigo = Color(0xFF4338CA);
  static const gris = Color(0xFF6B7280);
  static const rojo = Color(0xFFB91C1C);
}

/// Por debajo de esto es «movil»: el cajon ocupa la pantalla entera y las
/// columnas prescindibles de la tabla se esconden.
const anchoEscritorio = 1024.0;

// -----------------------------------------------------------------------------
// El cajon
// -----------------------------------------------------------------------------

/// Los anchos del pliego (§9.2). En movil siempre es la pantalla entera.
enum AnchoCajon {
  md(448),
  lg(672),
  xl(896),
  completo(double.infinity);

  const AnchoCajon(this.px);

  final double px;
}

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
      child: Material(
        color: tema.colorScheme.surface,
        elevation: 8,
        child: SizedBox(
          width: anchoFinal,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              titulo,
                              style: tema.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (subtitulo != null)
                              Text(
                                subtitulo!,
                                style: tema.textTheme.bodySmall?.copyWith(
                                  color: Colores.gris,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // La ✕: fuera del cuerpo desplazable, para que no se pueda
                      // ir de la vista por mucho que se baje.
                      IconButton(
                        tooltip: 'Cerrar',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(child: SingleChildScrollView(child: cuerpo)),
              if (pie != null) ...[
                const Divider(height: 1),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: pie,
                  ),
                ),
              ],
            ],
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
    barrierColor: Colors.black.withValues(alpha: 0.4),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        texto,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
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
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          texto,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colores.gris,
          ),
        ),
        if (accion != null) ...[const SizedBox(height: 12), accion!],
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
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          Text(
            'Mostrando $desde–$hasta de $total',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
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

  Widget _boton(
    BuildContext context,
    String texto,
    VoidCallback? alPulsar, {
    bool actual = false,
  }) => SizedBox(
    height: 32,
    child: actual
        ? FilledButton(
            onPressed: null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: Size.zero,
            ),
            child: Text(texto),
          )
        : OutlinedButton(
            onPressed: alPulsar,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: Size.zero,
            ),
            child: Text(texto),
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
    final elegida = opciones
        .where((o) => o.valor == valor)
        .firstOrNull;
    return MenuAnchor(
      builder: (contexto, controlador, _) => Tooltip(
        message: titulo,
        child: OutlinedButton.icon(
          onPressed: () =>
              controlador.isOpen ? controlador.close() : controlador.open(),
          icon: const Icon(Icons.expand_more, size: 18),
          label: Text(elegida?.etiqueta ?? titulo),
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
          if (widget.conBuscador)
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: 'Buscar',
                ),
                onChanged: (t) => setState(() => _texto = t),
              ),
            ),
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
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colores.gris,
                              ),
                            ),
                      child: Text(opcion.etiqueta),
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
    this.actualizando = false,
    this.alPulsarPendientes,
    super.key,
  });

  final List<String> colecciones;
  final bool actualizando;
  final VoidCallback? alPulsarPendientes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frescura = ref.watch(frescuraDePantallaProvider(colecciones));
    final sinSubir = ref.watch(sinSubirProvider);

    return RelojDeDatos(
      // Mientras carga la propia consulta de frescura no se puede afirmar que
      // los datos esten al dia: se dice lo mismo que si no se hubieran bajado.
      estado: frescura.value ?? const SinDescargar(),
      actualizando: actualizando,
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
