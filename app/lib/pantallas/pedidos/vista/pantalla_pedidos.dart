// La pantalla de Pedidos.
//
// Lectura pura: aqui no se escribe nada y por eso no toca la cola. Lo que si
// hace, y es la mitad del valor de la pantalla, es SUMAR el pre-despacho: cuanto
// hay que sacar del almacen de lo filtrado o de lo marcado a mano.
//
// Todo sale de la base local. Sin conexion funciona entero —los 9 filtros, el
// orden de la pagina, la ficha, la seleccion y los dos pre-despachos—; lo unico
// que cambia es lo que dice el reloj de datos de arriba.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/frescura/reloj_de_datos.dart';
import '../../../nucleo/proveedores.dart';
import '../datos/filtros_pedidos.dart';
import '../datos/formato.dart';
import '../datos/repositorio_pedidos.dart';
import '../estado/proveedores_pedidos.dart';
import 'cajon_detalle_pedido.dart';
import 'kit.dart';
import 'tabla_pedidos.dart';

class PantallaPedidos extends ConsumerWidget {
  const PantallaPedidos({super.key});

  /// El texto literal de la franja azul del arranque acotado.
  static const franjaAzul =
      'Enseñando sólo lo que puede subir a un camión: lo que tiene factura '
      '—cuadre o no— y sin archivar. Lo que cambió también sube: se carga con '
      'las líneas de la factura, no con las del pedido.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtros = ref.watch(filtrosPedidosProvider);
    final total = ref.watch(totalPedidosProvider);
    final pagina = ref.watch(paginaPedidosProvider);
    final descargados = ref.watch(pedidosDescargadosProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos'),
        // El reloj de datos va ARRIBA y siempre visible (caso S8). Cuando exista
        // el armazon comun se sube alli y se quita de aqui; mientras tanto no se
        // deja ni una pantalla sin decir de que hora son sus datos.
        actions: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: BarraDeDatos(colecciones: ColeccionesDePantalla.pedidos),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            'Todos los pedidos acumulados de todas las rutas',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colores.gris),
          ),
          if (filtros.arranqueAcotado) const _FranjaAzul(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    textoDelConteo(
                      total.value ?? 0,
                      filtros,
                      fechaCorta,
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (total.isLoading || pagina.isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const _BarraDeFiltros(),
          const _PreDespachoDeLoElegido(),
          const _PreDespachoDeLoFiltrado(),
          const SizedBox(height: 8),
          // Una lista vacia de una coleccion que nunca se bajo NO es «no hay
          // nada»: es un fallo que se lee como un dato (caso S7). Se dice con
          // otras palabras y antes de mirar el total.
          if (descargados.value == false)
            const EstadoVacio(SinDescargar.textoDeLaPantallaVacia)
          else
            _Cuerpo(filtros: filtros, pagina: pagina, total: total),
          if ((total.value ?? 0) > 0)
            Paginacion(
              pagina: filtros.pagina,
              porPagina: ConsultasPedidos.porPagina,
              total: total.value ?? 0,
              alIr: (n) =>
                  ref.read(filtrosPedidosProvider.notifier).irAPagina(n),
            ),
        ],
      ),
    );
  }
}

class _FranjaAzul extends ConsumerWidget {
  const _FranjaAzul();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colores.azul.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(PantallaPedidos.franjaAzul),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () =>
              ref.read(filtrosPedidosProvider.notifier).verTodos(),
          child: const Text('Ver todos los pedidos'),
        ),
      ],
    ),
  );
}

class _BarraDeFiltros extends ConsumerWidget {
  const _BarraDeFiltros();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtros = ref.watch(filtrosPedidosProvider);
    final notas = ref.read(filtrosPedidosProvider.notifier);
    final facetas = ref.watch(facetasPedidosProvider).value ?? Facetas.vacias;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Buscar',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (t) => notas.cambiar((f) => f.copiarCon(q: t)),
          ),
        ),
        Selector<RepartoFiltro>(
          titulo: 'Estado de reparto en delivery',
          valor: filtros.reparto,
          opciones: [
            for (final r in RepartoFiltro.values) OpcionSelector(r, r.etiqueta),
          ],
          alElegir: (r) => notas.cambiar((f) => f.copiarCon(reparto: r)),
        ),
        Selector<String>(
          titulo: 'Municipio del cliente',
          valor: filtros.municipio,
          opciones: [
            const OpcionSelector('', 'Todos los municipios'),
            for (final m in facetas.municipios)
              OpcionSelector(m.valor, m.valor, nota: '${m.pedidos}'),
          ],
          alElegir: (m) => notas.cambiar((f) => f.copiarCon(municipio: m)),
        ),
        Selector<CotizadoFiltro>(
          titulo: 'Precio del domicilio',
          valor: filtros.cotizado,
          opciones: [
            for (final c in CotizadoFiltro.values)
              OpcionSelector(c, c.etiqueta),
          ],
          alElegir: (c) => notas.cambiar((f) => f.copiarCon(cotizado: c)),
        ),
        Selector<String>(
          titulo: 'Vendedor del pedido',
          valor: filtros.vendedor,
          opciones: [
            const OpcionSelector('', 'Todos los vendedores'),
            for (final v in facetas.vendedores)
              OpcionSelector(v.valor, v.valor, nota: '${v.pedidos}'),
          ],
          alElegir: (v) => notas.cambiar((f) => f.copiarCon(vendedor: v)),
        ),
        Selector<OrdenLocal>(
          titulo: 'Cómo se ordena esta página',
          valor: filtros.orden,
          opciones: [
            for (final o in OrdenLocal.values) OpcionSelector(o, o.etiqueta),
          ],
          alElegir: (o) => notas.cambiar((f) => f.copiarCon(orden: o)),
        ),
        if (filtros.desde != null || filtros.hasta != null)
          IconButton(
            tooltip: 'Quitar el filtro de fechas',
            icon: const Icon(Icons.close),
            onPressed: () => notas.cambiar(
              (f) => f.copiarCon(limpiarDesde: true, limpiarHasta: true),
            ),
          ),
      ],
    );
  }
}

class _Cuerpo extends ConsumerWidget {
  const _Cuerpo({
    required this.filtros,
    required this.pagina,
    required this.total,
  });

  final FiltrosPedidos filtros;
  final AsyncValue<List<Pedido>> pagina;
  final AsyncValue<int> total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filas = pagina.value;
    if (filas == null) return const EstadoVacio('Cargando...');

    if (filas.isEmpty) {
      return EstadoVacio(
        'Aún no hay pedidos. Crea una ruta con pedidos.',
        accion: filtros.hayAlguno
            ? OutlinedButton(
                onPressed: () =>
                    ref.read(filtrosPedidosProvider.notifier).quitarTodos(),
                child: const Text(
                  'Ningún pedido cuadra con estos filtros — quitarlos todos',
                ),
              )
            : null,
      );
    }

    final renglones =
        ref.watch(renglonesDePaginaProvider).value ?? const {};
    final rutas = ref.watch(rutasPorIdProvider).value ?? const {};
    final seleccion = ref.watch(seleccionPedidosProvider);
    final marcas = ref.read(seleccionPedidosProvider.notifier);

    return TablaPedidos(
      pedidos: filas,
      renglones: renglones,
      rutas: rutas,
      seleccion: seleccion,
      conSucursal: ref.watch(sucursalMiradaProvider) == null,
      ahora: ref.watch(relojProvider)(),
      alMarcar: marcas.alternar,
      alMarcarPagina: (ids, marcar) =>
          marcas.marcarPagina(ids, marcar: marcar),
      alAbrir: (pedido) => abrirCajon<void>(
        context,
        (_) => CajonDetallePedido(pedidoId: pedido.id),
      ),
    );
  }
}

class _PreDespachoDeLoElegido extends ConsumerWidget {
  const _PreDespachoDeLoElegido();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seleccion = ref.watch(seleccionPedidosProvider);
    if (seleccion.isEmpty) return const SizedBox.shrink();
    final totales = ref.watch(preDespachoElegidoProvider).value;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${seleccion.length} pedido(s) elegidos'
                    '${totales == null ? '' : ' · ${totales.productos} producto(s)'
                        ' · ${cantidad(totales.empaques)} empaques'
                        ' · ${totales.pesoKg.toStringAsFixed(1)} kg'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () => ref
                      .read(seleccionPedidosProvider.notifier)
                      .quitarLaMarca(),
                  child: const Text('Quitar la marca'),
                ),
              ],
            ),
            if (totales != null) _TablaPreDespacho(totales: totales),
          ],
        ),
      ),
    );
  }
}

class _PreDespachoDeLoFiltrado extends ConsumerStatefulWidget {
  const _PreDespachoDeLoFiltrado();

  @override
  ConsumerState<_PreDespachoDeLoFiltrado> createState() =>
      _PreDespachoDeLoFiltradoState();
}

class _PreDespachoDeLoFiltradoState
    extends ConsumerState<_PreDespachoDeLoFiltrado> {
  bool _abierto = false;

  @override
  Widget build(BuildContext context) {
    // Se suma **sólo al abrir**: en el aparato no hay tope de 5000 (PLAN.md §7.2)
    // pero sumar doce mil pedidos al pintar la pantalla es trabajo que casi nadie
    // mira.
    final totales = _abierto
        ? ref.watch(preDespachoFiltradoProvider).value
        : null;

    return ExpansionTile(
      title: Text(
        'Pre-despacho de lo filtrado'
        '${totales == null ? '' : ' · ${totales.productos} producto(s)'
            ' · ${cantidad(totales.empaques)} empaques'
            ' · ${totales.pesoKg.toStringAsFixed(1)} kg'}',
      ),
      onExpansionChanged: (abierto) => setState(() => _abierto = abierto),
      children: [
        if (totales == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Cargando...'),
          )
        else
          _TablaPreDespacho(totales: totales),
      ],
    );
  }
}

class _TablaPreDespacho extends StatelessWidget {
  const _TablaPreDespacho({required this.totales});

  final TotalesPreDespacho totales;

  @override
  Widget build(BuildContext context) {
    if (totales.lineas.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Sin productos'),
      );
    }
    // Su propio desplazamiento horizontal: sin el, esta tabla empuja la pagina
    // entera de lado en el telefono (§11 del pliego).
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Producto')),
          DataColumn(label: Text('Empaques')),
          DataColumn(label: Text('Unidades')),
          DataColumn(label: Text('kg')),
        ],
        rows: [
          for (final linea in totales.lineas)
            DataRow(
              cells: [
                DataCell(Text(linea.producto)),
                DataCell(Text(cantidad(linea.empaques))),
                DataCell(Text(cantidad(linea.unidades))),
                // Sin peso resuelto se pinta `—`, nunca un cero.
                DataCell(
                  Text(
                    linea.pesoKg == null
                        ? '—'
                        : linea.pesoKg!.toStringAsFixed(1),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
