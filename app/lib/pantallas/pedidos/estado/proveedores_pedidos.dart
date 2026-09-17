// Los providers de Pedidos.
//
// Todos cuelgan de la base local y de `sucursalMiradaProvider`. Eso ultimo es lo
// que hace verdad el literal del pliego «al cambiar de sucursal se invalidan
// todas las consultas (no se recarga la página)»: como cada provider la mira con
// `ref.watch`, cambiarla los reconstruye solos y los numeros cambian en el sitio.

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../datos/filtros_pedidos.dart';
import '../datos/repositorio_pedidos.dart';

final consultasPedidosProvider = Provider<ConsultasPedidos>(
  (ref) => ConsultasPedidos(ref.watch(baseProvider)),
);

/// Los filtros de la pantalla. Arrancan ACOTADOS a lo que puede subir a un
/// camion, que es lo que pinta la franja azul.
class FiltrosPedidosNotifier extends Notifier<FiltrosPedidos> {
  @override
  FiltrosPedidos build() => const FiltrosPedidos();

  void poner(FiltrosPedidos nuevos) => state = nuevos;

  void cambiar(FiltrosPedidos Function(FiltrosPedidos) como) =>
      state = como(state);

  /// `Ver todos los pedidos`: quita **sólo** los dos del arranque.
  void verTodos() => state = state.copiarCon(
    factura: FacturaFiltro.cualquiera,
    archivado: ArchivadoFiltro.cualquiera,
  );

  /// `quitarlos todos`: los nueve, incluidos los del arranque.
  void quitarTodos() => state = const FiltrosPedidos.sinNada();

  void irAPagina(int pagina) => state = state.copiarCon(pagina: pagina);

  /// Las dos fechas a la vez, y con `null` explicito.
  ///
  /// Van juntas porque son un solo filtro: el rango. Y con `null` que borra,
  /// porque `copiarCon` no puede distinguir «ponlo a nada» de «no lo toques»
  /// —los dos llegan como `null`— y sin esto no habria forma de quitar una
  /// fecha ya puesta.
  void ponerFechas(DateTime? desde, DateTime? hasta) => state = state.copiarCon(
    desde: desde,
    limpiarDesde: desde == null,
    hasta: hasta,
    limpiarHasta: hasta == null,
  );
}

final filtrosPedidosProvider =
    NotifierProvider<FiltrosPedidosNotifier, FiltrosPedidos>(
      FiltrosPedidosNotifier.new,
    );

/// Lo marcado a mano. Es LOCAL y no se guarda: el pre-despacho de lo elegido se
/// arma y se imprime en el momento.
class SeleccionPedidos extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void alternar(String id) {
    final copia = {...state};
    if (!copia.remove(id)) copia.add(id);
    state = copia;
  }

  /// La casilla de la cabecera marca o desmarca **toda la pagina**, no toda la
  /// consulta: marcar doce mil pedidos de un golpe no lo pidio nadie.
  void marcarPagina(List<String> ids, {required bool marcar}) {
    final copia = {...state};
    if (marcar) {
      copia.addAll(ids);
    } else {
      copia.removeAll(ids);
    }
    state = copia;
  }

  void quitarLaMarca() => state = <String>{};
}

final seleccionPedidosProvider =
    NotifierProvider<SeleccionPedidos, Set<String>>(SeleccionPedidos.new);

/// El total que sale en la cabecera: `<total> pedidos`.
final totalPedidosProvider = StreamProvider<int>(
  (ref) => ref
      .watch(consultasPedidosProvider)
      .contar(
        ref.watch(filtrosPedidosProvider),
        sucursalId: ref.watch(sucursalMiradaProvider),
      ),
);

/// La pagina visible, ya ordenada por el orden LOCAL que eligio la persona.
final paginaPedidosProvider = StreamProvider<List<Pedido>>((ref) {
  final filtros = ref.watch(filtrosPedidosProvider);
  return ref
      .watch(consultasPedidosProvider)
      .pagina(filtros, sucursalId: ref.watch(sucursalMiradaProvider))
      .map((pagina) => ordenarPagina(pagina, filtros.orden));
});

/// Los renglones de los pedidos de la pagina: la columna `Artículos` y el peso
/// por linea de la ficha salen de aqui.
final renglonesDePaginaProvider =
    FutureProvider<Map<String, List<RenglonConPeso>>>((ref) async {
      final pagina = await ref.watch(paginaPedidosProvider.future);
      return ref.watch(consultasPedidosProvider).renglonesDe([
        for (final p in pagina) p.id,
      ]);
    });

/// Lo que llena los desplegables «Municipio del cliente» y «Vendedor del
/// pedido», con su cuenta al lado.
///
/// ## STREAM, y por el mismo motivo que el de arriba — 17/09/2026
///
/// Esto era un `FutureProvider` que sólo miraba la sucursal, o sea que se
/// resolvía UNA vez y ya. En la web se resolvía siempre con la base vacía, y
/// entonces pasaba esto: el cartel de «no se ha descargado» se iba solo, la
/// cabecera pasaba a «299 pedidos», la lista salía… **y los dos desplegables se
/// quedaban vacíos para siempre**, sólo con «Todos los municipios». No había
/// forma de filtrar sin recargar.
///
/// Lo encontró el auditor justo después de arreglar el cartel: el mismo fallo,
/// en la misma pantalla, a doce líneas de distancia. Por eso se arreglan los
/// dos juntos y con la misma forma.
///
/// El primer valor sale enseguida —`tableUpdates` no emite al suscribirse, y sin
/// esto la pantalla arrancaría sin desplegables aunque los datos ya estuvieran—
/// y a partir de ahí se recalcula con cada escritura en la tabla de pedidos.
final facetasPedidosProvider = StreamProvider<Facetas>((ref) {
  final base = ref.watch(baseProvider);
  final consultas = ref.watch(consultasPedidosProvider);
  final sucursal = ref.watch(sucursalMiradaProvider);

  Future<Facetas> mirar() => consultas.facetas(sucursalId: sucursal);

  return () async* {
    yield await mirar();
    yield* base
        .tableUpdates(TableUpdateQuery.onTable(base.orders))
        .asyncMap((_) => mirar());
  }();
});

/// El pre-despacho de LO FILTRADO. Se pide sólo cuando se abre el bloque
/// plegable, igual que en la de Next: sumar doce mil pedidos al pintar la
/// pantalla es trabajo que casi nunca se mira.
final preDespachoFiltradoProvider = FutureProvider<TotalesPreDespacho>(
  (ref) => ref
      .watch(consultasPedidosProvider)
      .preDespachoDeLoFiltrado(
        ref.watch(filtrosPedidosProvider),
        sucursalId: ref.watch(sucursalMiradaProvider),
      ),
);

/// El pre-despacho de LO MARCADO.
final preDespachoElegidoProvider = FutureProvider<TotalesPreDespacho>(
  (ref) => ref
      .watch(consultasPedidosProvider)
      .preDespachoDe(ref.watch(seleccionPedidosProvider).toList()),
);

final detallePedidoProvider = FutureProvider.family<DetallePedido?, String>(
  (ref, id) => ref.watch(consultasPedidosProvider).detalle(id),
);

/// ¿Se bajaron los pedidos alguna vez?
///
/// Separa «no hay nada» de «no se ha descargado». Una lista vacia sin esta
/// respuesta es un fallo que se lee como un dato (caso S7).
///
/// ## STREAM, no Future — 17/09/2026
///
/// Esto era un `FutureProvider`, o sea **una sola respuesta, la del instante en
/// que la pantalla se pinta por primera vez**. En la APK daba igual: se entra
/// con el aparato ya configurado y para entonces la marca esta puesta. En la web
/// la base arranca VACIA en cada carga, asi que la primera respuesta era siempre
/// «no se descargo» — y como no se volvia a preguntar, se quedaba asi para
/// siempre.
///
/// Lo que se veia, y Jose lo vio: la cabecera diciendo «299 pedidos», el pie
/// diciendo «Mostrando 1-50 de 299» y en medio «Esta pantalla no se ha
/// descargado todavia». El total y la pagina son streams y se enteraban de la
/// bajada; esto no. Tres consultas sobre la misma tabla contando cosas
/// distintas.
///
/// `mirar` vigila la fila de frescura, asi que en cuanto la bajada la marca la
/// pantalla se rehace sola. Sin recargar, que es la otra cosa que Jose pidio.
final pedidosDescargadosProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(frescuraProvider)
      .mirar(Colecciones.pedidos)
      .map((fila) => fila?.bajadaAt != null),
);

/// El nombre de la sucursal que va en la cabecera de la hoja impresa.
///
/// Sin sucursal elegida arriba se escribe `Todas las sucursales`, literal de la
/// de Next: en la hoja del almacen no puede quedar un hueco donde tendria que
/// decir de donde sale la mercancia.
final sucursalDeLaHojaProvider = StreamProvider<String>((ref) {
  final base = ref.watch(baseProvider);
  final mirada = ref.watch(sucursalMiradaProvider);
  if (mirada == null || mirada.isEmpty) {
    return Stream<String>.value(SucursalDeLaHoja.todas);
  }
  return (base.select(base.branches)..where((b) => b.id.equals(mirada)))
      .watchSingleOrNull()
      .map((sucursal) => sucursal?.name ?? '');
});

abstract final class SucursalDeLaHoja {
  static const todas = 'Todas las sucursales';
}

/// Las rutas, por id. Lo necesita la columna `Entrega`: el estado
/// de reparto de un pedido «en despacho» o «en ruta» depende de en que estado
/// esta la ruta que lo lleva.
///
/// Va como mapa entero y no como consulta por fila porque las rutas de una
/// sucursal se cuentan por decenas: una sola lectura es mas barata que cincuenta.
final rutasPorIdProvider = StreamProvider<Map<String, Ruta>>((ref) {
  final base = ref.watch(baseProvider);
  return base
      .select(base.routes)
      .watch()
      .map((rutas) => {for (final ruta in rutas) ruta.id: ruta});
});
