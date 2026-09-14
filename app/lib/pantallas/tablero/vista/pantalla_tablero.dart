import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/proveedores.dart';
import '../datos/modelos.dart';
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
class PantallaTablero extends ConsumerStatefulWidget {
  const PantallaTablero({super.key});

  @override
  ConsumerState<PantallaTablero> createState() => _PantallaTableroState();
}

String _texto(Object fallo) => switch (fallo) {
  // No se ensena «todo», que es lo que pareceria razonable y seria lo peor.
  final FaltaElegirSucursal e => e.mensaje,
  // Se ordena desde el sitio del que sale la mercancia, o no se ordena.
  final SinAlmacenConCoordenadas e => e.mensaje,
  final RechazoDelTablero e => e.mensaje,
  _ => 'No se pudo abrir el tablero: $fallo',
};

class _PantallaTableroState extends ConsumerState<PantallaTablero> {
  /// En el movil las dos mitades no caben a la vez. Se ensena una y se cambia.
  bool _verColumnas = false;

  /// Por debajo de esto, las dos mitades no caben una al lado de la otra.
  static const _anchoDeDosMitades = 900.0;

  @override
  Widget build(BuildContext context) {
    final asincrono = ref.watch(tableroProvider);
    final sinSubir = ref.watch(sinSubirProvider).value ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tablero de preparación'),
        actions: [
          if (sinSubir > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  '$sinSubir sin subir',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: ColoresTablero.ambar,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Traer lo del servidor',
            onPressed: () =>
                ref.read(tableroProvider.notifier).bajarDelServidor(),
          ),
        ],
      ),
      floatingActionButton:
          asincrono.hasValue && asincrono.value?.problema == null
          ? FloatingActionButton.extended(
              onPressed: () => AccionesTablero.crearColumna(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Columna'),
            )
          : null,
      body: asincrono.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Problema(texto: _texto(e)),
        data: _conDatos,
      ),
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
                      alDevolver: (datos) => _devolver(datos),
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
                        label: Text('Sin colocar (${tablero.sinColocar.total})'),
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

  void _moverTarjeta(
    Tablero tablero,
    TarjetaPedido pedido, {
    String? columnaId,
    int? posicion,
  }) {
    unawaited(
      AccionesTablero.moverTarjeta(
        context,
        ref,
        pedido: pedido,
        tablero: tablero,
        columnaActual: columnaId,
        posicionActual: posicion,
      ),
    );
  }

  void _devolver(TarjetaArrastrada datos) {
    if (datos.desdeColumnaId == null) return;
    unawaited(ref.read(tableroProvider.notifier).quitar(datos.pedidoId));
  }
}

/// La tira de columnas, que se desplaza a lo ancho.
class _Tira extends ConsumerWidget {
  const _Tira({required this.tablero, required this.alto});

  final Tablero tablero;

  /// En pantalla ancha las columnas llevan ancho fijo; en el movil, una ocupa
  /// todo.
  final bool alto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            ],
          ),
        ),
      );
    }

    final ancho = alto ? 300.0 : MediaQuery.sizeOf(context).width - 24;
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 72),
      itemCount: tablero.columnas.length,
      itemBuilder: (contexto, i) {
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

/// De donde se mide, de cuando son los datos y que ha dejado de servir.
class _BarraDeArriba extends StatelessWidget {
  const _BarraDeArriba({required this.tablero});

  final Tablero tablero;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final avisos = tablero.avisos;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      color: tema.colorScheme.surfaceContainerHighest,
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${tablero.sucursalNombre} · desde ${tablero.almacen.nombre}',
            style: tema.textTheme.labelMedium,
          ),
          // Un tablero que parece vivo y lleva seis horas congelado es peor que
          // uno que avisa.
          Text(
            tablero.vistoAt == null
                ? 'Sin descargar todavía'
                : 'Visto por última vez a las ${horaBonita(tablero.vistoAt!)}',
            style: tema.textTheme.labelMedium?.copyWith(
              color: tablero.vistoAt == null
                  ? ColoresTablero.ambar
                  : tema.colorScheme.onSurfaceVariant,
            ),
          ),
          // Tres contadores y no uno: se arreglan de tres maneras distintas.
          if (avisos.archivados > 0)
            Insignia(
              '${avisos.archivados} archivados en PEDIDO',
              color: ColoresTablero.rojo,
            ),
          if (avisos.enOtraRuta > 0)
            Insignia(
              '${avisos.enOtraRuta} ya en otra ruta',
              color: ColoresTablero.rojo,
            ),
          if (avisos.sinFactura > 0)
            Insignia(
              '${avisos.sinFactura} sin factura o sin cotejar',
              color: ColoresTablero.rojo,
            ),
          if (avisos.cambiados > 0)
            Insignia(
              '${avisos.cambiados} cambiaron en la factura',
              color: ColoresTablero.ambar,
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
      backgroundColor: ColoresTablero.rojo.withValues(alpha: 0.08),
      content: Text(
        cuantos == 1
            ? '1 pedido que tenías puesto ya no está en PEDIDO: $lista'
            : '$cuantos pedidos que tenías puestos ya no están en PEDIDO: '
                  '$lista',
      ),
      actions: [
        TextButton(
          onPressed: () =>
              ref.read(tableroProvider.notifier).olvidarDesaparecidos(),
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
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(texto, textAlign: TextAlign.center),
      ),
    );
  }
}
