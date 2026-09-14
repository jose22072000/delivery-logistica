// Los 9 filtros de la pantalla de Pedidos, tal y como los define el pliego
// (../../../../docs/pantallas.md §2) y con los MISMOS valores de parametro que
// manda el servidor (../../../../docs/contratos-api.md, «Filtros compartidos»).
//
// Van en su propio fichero, como datos puros y sin Flutter dentro, porque son
// tres cosas a la vez: lo que pinta la barra de filtros, lo que traduce el
// repositorio a SQL y lo que se compara en las pruebas de paridad contra la de
// Next. Si vivieran dentro del widget no se podrian probar sin pintar.

import 'package:flutter/foundation.dart' show immutable;

/// `reparto` — el estado de reparto EN DELIVERY. Manda `resultado` de la parada,
/// nunca el estado de la ruta: una ruta completada no convierte en entregado un
/// pedido que volvio.
enum RepartoFiltro {
  cualquiera('', 'Cualquier reparto'),
  sinEntregar('sin_entregar', 'Sin entregar'),
  enDespacho('en_despacho', 'En despacho'),
  enRuta('en_ruta', 'En ruta'),
  entregado('entregado', 'Entregado'),
  devuelto('devuelto', 'Devuelto o cancelado');

  const RepartoFiltro(this.param, this.etiqueta);

  final String param;
  final String etiqueta;
}

/// `factura` — `con_factura` admite `igual` y `cambiado`; `cuadra` sólo `igual`.
/// La diferencia importa: el armador de rutas exige `cuadra` y esta pantalla
/// arranca en `con_factura`.
enum FacturaFiltro {
  cualquiera('', 'Cualquier factura'),
  conFactura('con_factura', 'Con factura'),
  cuadra('cuadra', 'Sólo lo que cuadra'),
  sinCotejar('sin_cotejar', 'Sin cotejar');

  const FacturaFiltro(this.param, this.etiqueta);

  final String param;
  final String etiqueta;
}

/// `archivado` — NO es un booleano de tres estados por gusto: «cualquiera» es
/// distinto de «no archivado», y el arranque acotado depende de poder decir
/// exactamente `0`.
enum ArchivadoFiltro {
  cualquiera('', 'Archivados y sin archivar'),
  no('0', 'Sin archivar'),
  si('1', 'Sólo archivados');

  const ArchivadoFiltro(this.param, this.etiqueta);

  final String param;
  final String etiqueta;
}

/// `cotizado` — si Entrega ya le puso costo de domicilio.
enum CotizadoFiltro {
  cualquiera('', 'Cualquier precio'),
  conPrecio('1', 'Con precio puesto'),
  sinCotizar('0', 'Sin cotizar');

  const CotizadoFiltro(this.param, this.etiqueta);

  final String param;
  final String etiqueta;
}

/// `Cómo se ordena esta página`.
///
/// **Ordena SÓLO la pagina visible**, no la consulta. Es lo que hace la de Next
/// y es deliberado: el orden de la consulta lo fija el servidor
/// (`orderDate desc nulls last, createdAt desc`) y cambiarlo aqui haria que dos
/// paginas consecutivas ensenaran el mismo pedido dos veces.
enum OrdenLocal {
  recientes('recientes', 'Más recientes'),
  antiguos('antiguos', 'Más antiguos'),
  precioDesc('precio_desc', 'Precio: mayor a menor'),
  precioAsc('precio_asc', 'Precio: menor a mayor'),
  distanciaDesc('distancia_desc', 'Distancia: más larga'),
  pesoDesc('peso_desc', 'Peso: mayor');

  const OrdenLocal(this.valor, this.etiqueta);

  final String valor;
  final String etiqueta;
}

/// El juego completo de filtros de la pantalla.
///
/// Inmutable y con `==` de verdad porque es el argumento de los providers de
/// Riverpod: sin `==` cada reconstruccion del widget crearia un provider nuevo y
/// la pantalla volveria a consultar sin que nada hubiera cambiado.
@immutable
class FiltrosPedidos {
  /// El arranque de la pantalla: **acotado a lo que puede subir a un camion**.
  /// Mientras estos dos sigan exactamente asi se pinta la franja azul.
  const FiltrosPedidos({
    this.q = '',
    this.reparto = RepartoFiltro.cualquiera,
    this.municipio = '',
    this.vendedor = '',
    this.cotizado = CotizadoFiltro.cualquiera,
    this.factura = FacturaFiltro.conFactura,
    this.archivado = ArchivadoFiltro.no,
    this.desde,
    this.hasta,
    this.orden = OrdenLocal.recientes,
    this.pagina = 1,
  });

  /// Sin ningun filtro puesto. Es lo que deja `Ver todos los pedidos` en los dos
  /// del arranque y `quitarlos todos` en los nueve.
  const FiltrosPedidos.sinNada()
    : q = '',
      reparto = RepartoFiltro.cualquiera,
      municipio = '',
      vendedor = '',
      cotizado = CotizadoFiltro.cualquiera,
      factura = FacturaFiltro.cualquiera,
      archivado = ArchivadoFiltro.cualquiera,
      desde = null,
      hasta = null,
      orden = OrdenLocal.recientes,
      pagina = 1;

  final String q;
  final RepartoFiltro reparto;
  final String municipio;
  final String vendedor;
  final CotizadoFiltro cotizado;
  final FacturaFiltro factura;
  final ArchivadoFiltro archivado;

  /// `desde`/`hasta` son dias naturales sobre la FECHA DEL PEDIDO. `hasta`
  /// incluye el dia entero (hasta 23:59:59.999), que es como lo hace el
  /// servidor.
  final DateTime? desde;
  final DateTime? hasta;

  final OrdenLocal orden;
  final int pagina;

  /// Cuando los dos filtros del arranque siguen intactos. Es la condicion
  /// LITERAL de la franja azul del pliego.
  bool get arranqueAcotado =>
      factura == FacturaFiltro.conFactura && archivado == ArchivadoFiltro.no;

  /// ¿Hay algo puesto? Decide si debajo del estado vacio sale el boton de
  /// quitarlos todos.
  bool get hayAlguno =>
      q.isNotEmpty ||
      reparto != RepartoFiltro.cualquiera ||
      municipio.isNotEmpty ||
      vendedor.isNotEmpty ||
      cotizado != CotizadoFiltro.cualquiera ||
      factura != FacturaFiltro.cualquiera ||
      archivado != ArchivadoFiltro.cualquiera ||
      desde != null ||
      hasta != null;

  /// Cualquier cambio de filtro vuelve a la pagina 1: quedarse en la 7 de una
  /// lista que ahora tiene 2 paginas es una pantalla vacia sin motivo.
  FiltrosPedidos copiarCon({
    String? q,
    RepartoFiltro? reparto,
    String? municipio,
    String? vendedor,
    CotizadoFiltro? cotizado,
    FacturaFiltro? factura,
    ArchivadoFiltro? archivado,
    DateTime? desde,
    bool limpiarDesde = false,
    DateTime? hasta,
    bool limpiarHasta = false,
    OrdenLocal? orden,
    int? pagina,
  }) {
    final cambioUnFiltro =
        q != null ||
        reparto != null ||
        municipio != null ||
        vendedor != null ||
        cotizado != null ||
        factura != null ||
        archivado != null ||
        desde != null ||
        hasta != null ||
        limpiarDesde ||
        limpiarHasta;

    return FiltrosPedidos(
      q: q ?? this.q,
      reparto: reparto ?? this.reparto,
      municipio: municipio ?? this.municipio,
      vendedor: vendedor ?? this.vendedor,
      cotizado: cotizado ?? this.cotizado,
      factura: factura ?? this.factura,
      archivado: archivado ?? this.archivado,
      desde: limpiarDesde ? null : (desde ?? this.desde),
      hasta: limpiarHasta ? null : (hasta ?? this.hasta),
      orden: orden ?? this.orden,
      pagina: pagina ?? (cambioUnFiltro ? 1 : this.pagina),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FiltrosPedidos &&
          other.q == q &&
          other.reparto == reparto &&
          other.municipio == municipio &&
          other.vendedor == vendedor &&
          other.cotizado == cotizado &&
          other.factura == factura &&
          other.archivado == archivado &&
          other.desde == desde &&
          other.hasta == hasta &&
          other.orden == orden &&
          other.pagina == pagina;

  @override
  int get hashCode => Object.hash(
    q,
    reparto,
    municipio,
    vendedor,
    cotizado,
    factura,
    archivado,
    desde,
    hasta,
    orden,
    pagina,
  );

  @override
  String toString() =>
      'FiltrosPedidos(q: $q, reparto: ${reparto.param}, municipio: $municipio, '
      'vendedor: $vendedor, cotizado: ${cotizado.param}, '
      'factura: ${factura.param}, archivado: ${archivado.param}, '
      'desde: $desde, hasta: $hasta, orden: ${orden.valor}, pagina: $pagina)';
}

/// El conteo de la cabecera, literal del pliego: `<total> pedidos`, con el rango
/// de fechas si lo hay y siempre `, del más nuevo al más viejo`.
///
/// Va aqui, como funcion pura sobre los filtros, porque es un texto que se
/// compara caracter a caracter con el de Next y no quiero tener que pintar la
/// pantalla para comprobarlo.
String textoDelConteo(int total, FiltrosPedidos f, String Function(DateTime) dia) {
  final partes = StringBuffer('$total pedidos');
  final desde = f.desde;
  final hasta = f.hasta;
  if (desde != null && hasta != null) {
    partes.write(
      desde == hasta
          ? ' · del ${dia(desde)}'
          : ' · del ${dia(desde)} al ${dia(hasta)}',
    );
  } else if (desde != null) {
    partes.write(' · desde el ${dia(desde)}');
  } else if (hasta != null) {
    partes.write(' · hasta el ${dia(hasta)}');
  }
  partes.write(', del más nuevo al más viejo');
  return partes.toString();
}
