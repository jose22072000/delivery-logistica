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

import '../../../diseno/anchos.dart';
import '../../../diseno/caja_de_busqueda.dart';
import '../../../diseno/cargando.dart';
import '../../../diseno/rango_de_fechas.dart';
import '../../../diseno/tabla_ancha.dart';
import '../../../diseno/tema.dart';
import '../../../impresion/hoja.dart' as papel;
import '../../../impresion/pre_despacho.dart' show pdfPreDespacho;
import '../../../impresion/vista_previa.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/frescura/primera_bajada.dart';
import '../../../nucleo/frescura/reloj_de_datos.dart';
import '../../../nucleo/proveedores.dart';
import '../datos/filtros_pedidos.dart';
import '../datos/formato.dart';
import '../datos/repositorio_pedidos.dart';
import '../estado/proveedores_pedidos.dart';
import 'cajon_detalle_pedido.dart';
import 'cajon_mandar_al_tablero.dart';
import 'kit.dart';
import 'tabla_pedidos.dart';

class PantallaPedidos extends ConsumerWidget {
  const PantallaPedidos({super.key});

  /// El texto literal de la franja azul del arranque acotado.
  static const franjaAzul =
      'Enseñando sólo lo que puede subir a un camión: lo que tiene factura '
      '—cuadre o no— y sin archivar. Lo que cambió también sube: se carga con '
      'las líneas de la factura, no con las del pedido.';

  /// El gesto de la barra de lo marcado que abre el cajón del tablero. Literal
  /// aquí arriba para que la prueba busque lo que lee quien está delante.
  static const mandarAUnaZona = 'Mandar a una zona';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtros = ref.watch(filtrosPedidosProvider);
    final total = ref.watch(totalPedidosProvider);
    final pagina = ref.watch(paginaPedidosProvider);
    final descargados = ref.watch(pedidosDescargadosProvider);

    // SIN `Scaffold` ni `AppBar` propios: los pone el armazon
    // (`navegacion/pantalla_registrada.dart`), que ya trae barra lateral, barra
    // superior con el titulo «Pedidos» y franja de estado. Uno dentro de otro
    // apila dos superficies de Material y deja los avisos emergentes colgando
    // del de dentro, que es el que no se ve entero.
    // `p-3 sm:p-6` de delivery.
    final estrecho = MediaQuery.sizeOf(context).width < Anchos.idioma;

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.all(estrecho ? Aire.md : Aire.xl),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Todos los pedidos acumulados de todas las rutas',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Colores.tintaSuave),
                ),
              ),
              // El reloj de datos de ESTA pantalla. La franja del armazon dice
              // la frescura global; esta dice la de las colecciones que se estan
              // mirando, que es lo que decide si se arma la ruta de hoy o la de
              // ayer (caso S8).
              const BarraDeDatos(colecciones: ColeccionesDePantalla.pedidos),
            ],
          ),
          if (filtros.arranqueAcotado) const _FranjaAzul(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Aire.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    textoDelConteo(total.value ?? 0, filtros, fechaCorta),
                    style: Tipos.texto(
                      tamano: 13,
                      peso: FontWeight.w500,
                      color: Colores.tintaSuave,
                    ),
                  ),
                ),
                if (total.isLoading || pagina.isLoading)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colores.tintaSuave,
                    ),
                  ),
              ],
            ),
          ),
          const _BarraDeFiltros(),
          const _PreDespachoDeLoElegido(),
          const _PreDespachoDeLoFiltrado(),
          const SizedBox(height: Aire.lg),
          // Una lista vacia de una coleccion que nunca se bajo NO es «no hay
          // nada»: es un fallo que se lee como un dato (caso S7). Se dice con
          // otras palabras y antes de mirar el total.
          // La tabla y su paginacion van dentro de la MISMA caja blanca: en
          // delivery la paginacion es el pie de la tabla (`border-t bg-white`),
          // no una barra suelta debajo.
          TarjetaDeTabla(
            pie: (total.value ?? 0) > 0
                ? Paginacion(
                    pagina: filtros.pagina,
                    porPagina: ConsultasPedidos.porPagina,
                    total: total.value ?? 0,
                    alIr: (n) =>
                        ref.read(filtrosPedidosProvider.notifier).irAPagina(n),
                  )
                : null,
            // EN LA WEB SON TRES CASOS, NO UNO — 17/09/2026.
            //
            // Esta pantalla se quedó fuera de la pasada que separó los tres, y
            // era **la que Jose nombró**: en la web salía «Esta pantalla no se
            // ha descargado todavía. Con conexión baja sola» en cada carga,
            // porque su base nace vacía. Dos de las frases que él lleva todo el
            // día pidiendo que desaparezcan, en la pantalla de la queja.
            child: descargados.value == false
                ? switch (ref.watch(porQueEstaVacioProvider)) {
                    // El aparato: ahí «no se ha descargado» es un estado real.
                    PorQueEstaVacio.noSeDescargo => const EstadoVacio(
                      SinDescargar.textoDeLaPantallaVacia,
                    ),
                    // La web, el primer segundo: cargando y sin acusar a nadie.
                    PorQueEstaVacio.todaviaBajando => EstadoVacio(
                      TextosDeLaWeb.cargando('los pedidos'),
                    ),
                    // Y si no llegó, se dice y se deja entrar.
                    PorQueEstaVacio.noPudoBajar => EstadoVacio(
                      TextosDeLaWeb.noPudoBajar('los pedidos'),
                    ),
                  }
                : _Cuerpo(filtros: filtros, pagina: pagina, total: total),
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
    margin: const EdgeInsets.only(top: Aire.sm),
    padding: const EdgeInsets.all(Aire.lg),
    decoration: BoxDecoration(
      color: Colores.enCursoFondo,
      border: Border.all(color: Colores.primario.withValues(alpha: 0.2)),
      borderRadius: BorderRadius.circular(Radios.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          PantallaPedidos.franjaAzul,
          style: Tipos.texto(tamano: 13, color: Colores.tinta, alto: 1.5),
        ),
        const SizedBox(height: Aire.md),
        OutlinedButton(
          onPressed: () => ref.read(filtrosPedidosProvider.notifier).verTodos(),
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
        // Busca sola a los 400 ms, y **se vacia cuando se vacian los
        // filtros**: antes se quedaba el texto puesto filtrando en silencio
        // debajo de una lista que ya no estaba filtrada.
        CajaDeBusqueda(
          valor: filtros.q,
          alBuscar: (t) => notas.cambiar((f) => f.copiarCon(q: t)),
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
        // `Desde` / `Hasta` / `sólo ese día` / ✕. El SQL que acota por fecha
        // ya estaba escrito y la ✕ tambien; lo que no habia era con que PONER
        // las fechas, asi que «el pre-despacho de HOY» era inalcanzable.
        RangoDeFechas(
          desde: filtros.desde,
          hasta: filtros.hasta,
          tituloDesde: 'Desde (fecha del pedido)',
          tituloHasta: 'Hasta (fecha del pedido)',
          hoy: ref.watch(relojProvider)(),
          alCambiar: notas.ponerFechas,
        ),
      ],
    );
  }
}

/// El dia tal y como lo escribe la hoja: `AAAA-MM-DD`, y **sólo cuando el rango
/// es un dia**, igual que la de Next. Con un rango de varios dias la cabecera
/// no dice ninguno: escribir uno de los dos seria mentir sobre lo que hay
/// debajo.
String? diaDeLaHoja(FiltrosPedidos f) {
  final desde = f.desde;
  if (desde == null || desde != f.hasta) return null;
  return '${desde.year.toString().padLeft(4, '0')}-'
      '${desde.month.toString().padLeft(2, '0')}-'
      '${desde.day.toString().padLeft(2, '0')}';
}

/// La hoja que se manda al PDF, como funcion pura.
///
/// Va aparte del widget porque es lo que de verdad lleva los numeros al papel:
/// asi se comprueba sin pintar nada. La usan los DOS botones `Ver e imprimir`
/// de esta pantalla —el de lo marcado y el de lo filtrado—, para que las dos
/// hojas salgan con la misma forma.
papel.HojaPreDespacho hojaDePreDespacho({
  required TotalesPreDespacho totales,
  required String sucursal,
  required String? dia,
}) => papel.HojaPreDespacho(
  sucursal: sucursal,
  // Pedidos no sabe de camiones: esta hoja sale del almacen, no de una ruta.
  vehiculo: '',
  dia: dia,
  pedidos: totales.pedidos,
  pesoKg: totales.pesoDeLosPedidos,
  lineas: [
    for (final linea in totales.lineas)
      papel.LineaPreDespacho(
        producto: linea.producto,
        formatos: linea.empaques,
        unidades: linea.unidades,
        // En el papel el peso es un numero: un producto sin peso resuelto
        // suma cero kilos, que es lo que pesa lo que no sabemos.
        pesoKg: linea.pesoKg ?? 0,
      ),
  ],
);

/// Abre la hoja del pre-despacho: **se mira primero y se imprime desde la
/// propia vista previa**. Es el orden que tenia la de Next y el que tiene
/// sentido cuando quien saca la mercancia es otra persona.
void verEImprimirPreDespacho(
  BuildContext context, {
  required TotalesPreDespacho totales,
  required String sucursal,
  required String? dia,
}) {
  final hoja = hojaDePreDespacho(
    totales: totales,
    sucursal: sucursal,
    dia: dia,
  );

  abrirCajon<void>(
    context,
    (contexto) => Cajon(
      titulo: 'Pre-despacho',
      subtitulo:
          '${totales.pedidos} pedido(s) · '
          '${totales.pesoDeLosPedidos.toStringAsFixed(1)} kg',
      ancho: AnchoCajon.xl,
      // La vista previa quiere todo el alto que le den, y el cuerpo del cajon
      // es un desplazable: sin un alto concreto no hay nada que le diga
      // cuanto, y la hoja no llega a pintarse.
      cuerpo: SizedBox(
        height: MediaQuery.sizeOf(contexto).height * 0.75,
        child: VistaPreviaPdf(
          armar: (formato) => pdfPreDespacho(hoja, impresoEn: DateTime.now()),
          nombreDeFichero: 'pre-despacho.pdf',
        ),
      ),
    ),
  );
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

    final renglones = ref.watch(renglonesDePaginaProvider).value ?? const {};
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
      alMarcarPagina: (ids, marcar) => marcas.marcarPagina(ids, marcar: marcar),
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

    return Container(
      margin: const EdgeInsets.symmetric(vertical: Aire.md),
      decoration: BoxDecoration(
        color: Colores.primarioTenue,
        border: Border.all(color: Colores.primario.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(Radios.xl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Aire.lg),
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
                    style: Tipos.texto(
                      tamano: 14,
                      peso: FontWeight.w600,
                      color: Colores.tinta,
                    ),
                  ),
                ),
                // EL GESTO QUE CERRABA EL FLUJO Y NO ESTABA.
                //
                // Se marca aqui lo que se va a repartir —con los nueve filtros,
                // que es como se decide— y se manda de golpe a una zona del
                // tablero. Sin esto habia que irse al tablero y colocarlos uno a
                // uno, y Jose lo pregunto tal cual: «sigo sin ver, cuando escojo
                // los pedidos, seleccionar un tablero».
                TextButton(
                  onPressed: () => abrirCajonMandarAlTablero(context),
                  child: const Text(PantallaPedidos.mandarAUnaZona),
                ),
                // Sin esto no hay papel para el almacen: el PDF existia y
                // estaba probado, y no habia ningun boton que lo llamara.
                TextButton(
                  onPressed: totales == null || totales.lineas.isEmpty
                      ? null
                      : () => verEImprimirPreDespacho(
                          context,
                          totales: totales,
                          sucursal:
                              ref.watch(sucursalDeLaHojaProvider).value ?? '',
                          dia: diaDeLaHoja(ref.watch(filtrosPedidosProvider)),
                        ),
                  child: const Text('Ver e imprimir'),
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

    return Container(
      margin: const EdgeInsets.only(bottom: Aire.sm),
      decoration: BoxDecoration(
        color: Colores.blanco,
        border: Border.all(color: Colores.linea),
        borderRadius: BorderRadius.circular(Radios.xl),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        // Sin el tinte ni la linea gruesa que Material le pone al abrirse: aqui
        // la caja ya tiene su borde fino y su radio.
        shape: const Border(),
        collapsedShape: const Border(),
        backgroundColor: Colores.blanco,
        collapsedBackgroundColor: Colores.blanco,
        iconColor: Colores.tintaSuave,
        collapsedIconColor: Colores.tintaSuave,
        tilePadding: const EdgeInsets.symmetric(horizontal: Aire.lg),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Pre-despacho de lo filtrado'
                '${totales == null ? '' : ' · ${totales.productos} producto(s)'
                          ' · ${cantidad(totales.empaques)} empaques'
                          ' · ${totales.pesoKg.toStringAsFixed(1)} kg'}',
                style: Tipos.texto(tamano: 14, peso: FontWeight.w600),
              ),
            ),
            // Deshabilitado mientras no haya suma: cerrado no se ha sumado
            // nada todavia, y una hoja en blanco no es una hoja.
            TextButton(
              onPressed: totales == null || totales.lineas.isEmpty
                  ? null
                  : () => verEImprimirPreDespacho(
                      context,
                      totales: totales,
                      sucursal: ref.watch(sucursalDeLaHojaProvider).value ?? '',
                      dia: diaDeLaHoja(ref.watch(filtrosPedidosProvider)),
                    ),
              child: const Text('Ver e imprimir'),
            ),
          ],
        ),
        onExpansionChanged: (abierto) => setState(() => _abierto = abierto),
        children: [
          Divider(height: 1, thickness: 1, color: Colores.linea),
          if (totales == null)
            const Cargando('Cargando...')
          else
            _TablaPreDespacho(totales: totales),
        ],
      ),
    );
  }
}

class _TablaPreDespacho extends StatelessWidget {
  const _TablaPreDespacho({required this.totales});

  final TotalesPreDespacho totales;

  @override
  Widget build(BuildContext context) {
    if (totales.lineas.isEmpty) {
      return const EstadoVacio('Sin productos');
    }
    // Su propio desplazamiento horizontal: sin el, esta tabla empuja la pagina
    // entera de lado en el telefono (§11 del pliego).
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Theme(
        data: Theme.of(context).copyWith(dataTableTheme: temaDeTabla(context)),
        child: DataTable(
          columns: [
            DataColumn(label: cabecera('Producto')),
            DataColumn(label: cabecera('Empaques'), numeric: true),
            DataColumn(label: cabecera('Unidades'), numeric: true),
            DataColumn(label: cabecera('kg'), numeric: true),
          ],
          rows: [
            for (final linea in totales.lineas)
              DataRow(
                cells: [
                  DataCell(Text(linea.producto)),
                  DataCell(_cifra(cantidad(linea.empaques))),
                  DataCell(_cifra(cantidad(linea.unidades))),
                  // Sin peso resuelto se pinta `—`, nunca un cero.
                  DataCell(
                    _cifra(
                      linea.pesoKg == null
                          ? '—'
                          : linea.pesoKg!.toStringAsFixed(1),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Las cifras de la tabla, en mono y de ancho fijo: se comparan de arriba
  /// abajo y con la proporcional las unidades bailan de fila a fila.
  static Widget _cifra(String texto) =>
      Text(texto, style: Tipos.mono(tamano: 13, color: Colores.tinta));
}
