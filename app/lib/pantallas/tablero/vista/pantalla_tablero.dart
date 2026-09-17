import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../nucleo/plataforma.dart';

import '../datos/modelos.dart';
import '../estado/filtros_en_la_url.dart';
import '../estado/proveedores.dart';
import 'acciones.dart';
import 'columna.dart';
import 'kit.dart';
import 'panel_sin_colocar.dart';
import 'tarjeta.dart';

/// EL TABLERO DE PREPARACION.
///
/// Entre «me han llegado 180 pedidos» y «sale este camion con estas 14 paradas»
/// hay un trabajo que hoy se hace en la cabeza del logistico y en un papel:
/// agrupar por zona. Esto es ese paso — columnas que pone el, tarjetas que
/// arrastra el.
///
/// Y es la pantalla que mas sentido tiene **sin red**: preparar es mover cosas
/// de sitio, y es justo lo que se hace durante el dia, que es cuando no hay
/// senal. No hay ningun «modo sin conexion» que encender: se guarda en el
/// aparato y se sube por detras.
///
/// **Sin `Scaffold` ni `AppBar`**: los pone el armazon
/// (`navegacion/pantalla_registrada.dart`). Devolver otro deja dos barras
/// superiores y rompe el selector de sucursal.
class PantallaTablero extends ConsumerStatefulWidget {
  const PantallaTablero({this.filtrosDeLaUrl, super.key});

  /// Los filtros que venian en la direccion. En web, mandar un enlace al
  /// tablero ya filtrado tiene que llevar al mismo sitio.
  final FiltrosSinColocar? filtrosDeLaUrl;

  @override
  ConsumerState<PantallaTablero> createState() => _PantallaTableroState();
}

class _PantallaTableroState extends ConsumerState<PantallaTablero> {
  /// En el movil las dos mitades no caben a la vez. Se ensena una y se cambia.
  bool _verColumnas = false;

  /// Por debajo de esto, las dos mitades no caben una al lado de la otra.
  static const _anchoDeDosMitades = anchoDeDosMitades;

  @override
  void initState() {
    super.initState();
    _adoptarLaUrl();
  }

  @override
  void didUpdateWidget(PantallaTablero anterior) {
    super.didUpdateWidget(anterior);
    _adoptarLaUrl();
  }

  /// Los filtros de la direccion mandan al entrar.
  ///
  /// Se hace fuera del `build` —despues del fotograma— porque tocar un provider
  /// mientras se construye es lo que Riverpod prohibe, con razon: dejaria el
  /// arbol a medio pintar con dos estados distintos.
  void _adoptarLaUrl() {
    final deLaUrl = widget.filtrosDeLaUrl;
    if (deLaUrl == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ahora = ref.read(filtrosTableroProvider);
      if (!FiltrosEnLaUrl.iguales(ahora, deLaUrl)) {
        ref.read(filtrosTableroProvider.notifier).poner(deLaUrl);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final asincrono = ref.watch(tableroProvider);
    return asincrono.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Problema(texto: _texto(e)),
      data: _conDatos,
    );
  }

  Widget _conDatos(Tablero tablero) {
    // Las dos situaciones normales que no son un tablero: sin sucursal elegida
    // y sin almacen con coordenadas. Se dicen con las palabras del pliego.
    final problema = tablero.problema;
    if (problema != null) return _Problema(texto: problema);
    return _cuerpo(tablero);
  }

  Widget _cuerpo(Tablero tablero) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (tablero.desaparecidos.isNotEmpty)
        _AvisoDesaparecidos(desaparecidos: tablero.desaparecidos),
      _BarraDeArriba(tablero: tablero),
      Expanded(
        child: LayoutBuilder(
          builder: (contexto, medidas) {
            if (medidas.maxWidth >= _anchoDeDosMitades) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 340,
                    child: PanelSinColocar(
                      tablero: tablero,
                      alPulsarTarjeta: (pedido) =>
                          _moverTarjeta(tablero, pedido),
                      alDevolver: _devolver,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: _Tira(tablero: tablero, alto: true)),
                ],
              );
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment<bool>(
                        value: false,
                        label: Text(
                          'Sin colocar (${tablero.sinColocar.total})',
                        ),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('Zonas (${tablero.columnas.length})'),
                      ),
                    ],
                    selected: {_verColumnas},
                    onSelectionChanged: (cual) =>
                        setState(() => _verColumnas = cual.first),
                  ),
                ),
                Expanded(
                  child: _verColumnas
                      ? _Tira(tablero: tablero, alto: false)
                      : PanelSinColocar(
                          tablero: tablero,
                          alPulsarTarjeta: (pedido) =>
                              _moverTarjeta(tablero, pedido),
                          alDevolver: _devolver,
                        ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );

  void _moverTarjeta(Tablero tablero, TarjetaPedido pedido) {
    unawaited(
      AccionesTablero.moverTarjeta(
        context,
        ref,
        pedido: pedido,
        tablero: tablero,
      ),
    );
  }

  void _devolver(TarjetaArrastrada datos) {
    // Arrastrar a la izquierda algo que ya estaba a la izquierda no es una
    // orden: es un dedo que se escapo.
    if (datos.desdeColumnaId == null) return;
    unawaited(ref.read(tableroProvider.notifier).quitar(datos.pedidoId));
  }
}

String _texto(Object fallo) => switch (fallo) {
  // No se ensena «todo», que es lo que pareceria razonable y seria lo peor.
  final FaltaElegirSucursal e => e.mensaje,
  // Se ordena desde el sitio del que sale la mercancia, o no se ordena.
  final SinAlmacenConCoordenadas e => e.mensaje,
  final RechazoDelTablero e => e.mensaje,
  _ => 'No se pudo abrir el tablero: $fallo',
};

/// La tira de columnas, que se desplaza a lo ancho, con el «+» al final.
class _Tira extends ConsumerWidget {
  const _Tira({required this.tablero, required this.alto});

  final Tablero tablero;

  /// En pantalla ancha las columnas llevan ancho fijo; en el movil, una ocupa
  /// todo.
  final bool alto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ancho = alto ? 300.0 : MediaQuery.sizeOf(context).width - 24;
    if (tablero.columnas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Las zonas las pones tú.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Cada sucursal divide su territorio a su manera: por distritos, '
                'por carreteras o por barrios de toda la vida. Crea la primera '
                'columna con el «+».',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    unawaited(AccionesTablero.crearColumna(context, ref)),
                icon: const Icon(Icons.add),
                label: const Text('Nueva columna'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(4),
      // Una mas: el «+» del final, que es como dice el pliego que se crea una
      // columna.
      itemCount: tablero.columnas.length + 1,
      itemBuilder: (contexto, i) {
        if (i == tablero.columnas.length) {
          return _BotonNuevaColumna(ancho: alto ? 140 : ancho);
        }
        final columna = tablero.columnas[i];
        return ColumnaDelTablero(
          columna: columna,
          ancho: ancho,
          tarjetas: tablero.deColumna(columna.id),
          alSoltar: (datos, posicion) {
            // Soltar una tarjeta donde ya estaba no es una orden: es un dedo
            // que se escapo. Sin esto, cada roce deja un apunte en la cola.
            if (datos.desdeColumnaId == columna.id && posicion == null) return;
            unawaited(
              ref
                  .read(tableroProvider.notifier)
                  .colocar(
                    pedidoId: datos.pedidoId,
                    columnaId: columna.id,
                    posicion: posicion,
                  ),
            );
          },
          alSoltarColumna: (arrastrada) {
            final ids = tablero.columnas.map((c) => c.id).toList()
              ..remove(arrastrada.columnaId);
            ids.insert(i.clamp(0, ids.length), arrastrada.columnaId);
            unawaited(ref.read(tableroProvider.notifier).reordenar(ids));
          },
          alPulsarTarjeta: (tarjeta) => unawaited(
            AccionesTablero.moverTarjeta(
              contexto,
              ref,
              pedido: tarjeta.pedido,
              tablero: tablero,
              columnaActual: tarjeta.columnaId,
              posicionActual: tarjeta.posicion,
            ),
          ),
          alAbrirMenu: () => unawaited(
            AccionesTablero.menuDeColumna(
              contexto,
              ref,
              columna: columna,
              tablero: tablero,
            ),
          ),
        );
      },
    );
  }
}

class _BotonNuevaColumna extends ConsumerWidget {
  const _BotonNuevaColumna({required this.ancho});

  final double ancho;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    width: ancho,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    child: OutlinedButton(
      onPressed: () => unawaited(AccionesTablero.crearColumna(context, ref)),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add),
          SizedBox(height: 4),
          Text('Columna', textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

/// De donde se mide, de cuando son los datos y qué ha dejado de servir.
///
/// Lo que queda sin subir NO se pinta aqui: ya lo dice la franja del armazon,
/// en las siete pantallas. Dos contadores del mismo numero es el sitio perfecto
/// para que un dia digan cosas distintas.
class _BarraDeArriba extends ConsumerWidget {
  const _BarraDeArriba({required this.tablero});

  final Tablero tablero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final avisos = tablero.avisos;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      color: tema.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${tablero.sucursalNombre} · desde ${tablero.almacen.nombre}',
                  style: tema.textTheme.labelMedium,
                ),
                // Un tablero que parece vivo y lleva seis horas congelado es
                // peor que uno que avisa.
                //
                // Y si hay algo aqui que no esta arriba, eso manda sobre la
                // hora: refrescar borraria la foto de aqui y se lo llevaria por
                // delante, asi que la aplicacion se niega — y lo DICE, que es la
                // mitad que faltaba. Callarselo dejaba a quien pulsaba sin saber
                // si es que no habia cambios o que se estaba protegiendo su
                // trabajo.
                // EL GESTO QUE NO LLEGÓ AL SERVIDOR. Sólo en la web, donde
                // no hay cola que lo guarde para luego: si no subió, no está.
                // Va el PRIMERO de la franja porque es lo único de aquí que
                // exige hacer algo ahora mismo.
                // `watch` y no `read`: el rechazo llega DESPUES, con la
                // pantalla ya abierta, y con `read` no se repintaba nunca.
                if (ref.watch(loQueElServidorRechazoProvider).value
                    case final fallo?)
                  Text(
                    fallo,
                    style: tema.textTheme.labelMedium?.copyWith(
                      color: ColoresTablero.ambar,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (ref
                        .read(tableroProvider.notifier)
                        .porQueNoSeRefresca
                    case final pendiente?)
                  Text(
                    'No se actualiza: hay $pendiente. Se sube primero y '
                    'después se trae — así no se pierde nada.',
                    style: tema.textTheme.labelMedium?.copyWith(
                      color: ColoresTablero.ambar,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                // «Visto por ultima vez a las 10:41» — SOLO DONDE HAY UNA
                // COPIA QUE PUEDA ENVEJECER, o sea en la APK y el escritorio.
                //
                // En la web el tablero sale del servidor y se repinta solo en
                // cuanto algo cambia, asi que esa hora no avisa de nada: es la
                // hora de hace un segundo, puesta ahi para siempre. Y «Sin
                // descargar todavia» es directamente falso en un navegador.
                // Regla 1 del CLAUDE.md, y van cinco veces.
                else if (Destino.trabajaSinConexion)
                  Text(
                    tablero.vistoAt == null
                        ? 'Sin descargar todavía'
                        : 'Visto por última vez a las '
                              '${horaBonita(tablero.vistoAt!)}',
                    style: tema.textTheme.labelMedium?.copyWith(
                      color: tablero.vistoAt == null
                          ? ColoresTablero.ambar
                          : tema.colorScheme.onSurfaceVariant,
                    ),
                  ),
                // Tres contadores y no uno: se arreglan de tres maneras
                // distintas, y un numero unico obligaria a abrir las doce
                // columnas para saber cual es.
                if (avisos.archivados > 0)
                  insigniaGrave('${avisos.archivados} archivados en PEDIDO'),
                if (avisos.enOtraRuta > 0)
                  insigniaGrave('${avisos.enOtraRuta} ya en otra ruta'),
                if (avisos.sinFactura > 0)
                  insigniaGrave(
                    '${avisos.sinFactura} sin factura o sin cotejar',
                  ),
                if (avisos.cambiados > 0)
                  insigniaAviso('${avisos.cambiados} cambiaron en la factura'),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Traer lo del servidor',
            visualDensity: VisualDensity.compact,
            onPressed: () => unawaited(
              ref.read(tableroProvider.notifier).bajarDelServidor(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Los que se llevo la cascada: se avisa UNA vez, con lo que se sabia de ellos
/// antes de que se fueran (§7.5).
class _AvisoDesaparecidos extends ConsumerWidget {
  const _AvisoDesaparecidos({required this.desaparecidos});

  final List<PedidoDesaparecido> desaparecidos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cuantos = desaparecidos.length;
    final lista = desaparecidos
        .map(
          (d) =>
              '${d.operationNumber ?? d.pedidoId}'
              '${d.columna == null ? '' : ' (${d.columna})'}',
        )
        .join(', ');
    return MaterialBanner(
      backgroundColor: ColoresTablero.rojoFondo,
      content: Text(
        cuantos == 1
            ? '1 pedido que tenías puesto ya no está en PEDIDO: $lista'
            : '$cuantos pedidos que tenías puestos ya no están en PEDIDO: '
                  '$lista',
      ),
      actions: [
        TextButton(
          onPressed: () => unawaited(
            ref.read(tableroProvider.notifier).olvidarDesaparecidos(),
          ),
          child: const Text('Entendido'),
        ),
      ],
    );
  }
}

/// Lo que no deja pintar el tablero, dicho con las palabras del pliego.
class _Problema extends StatelessWidget {
  const _Problema({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(texto, textAlign: TextAlign.center),
    ),
  );
}
