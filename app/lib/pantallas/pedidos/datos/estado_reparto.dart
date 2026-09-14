// Como acabo un pedido, visto desde el reparto. Dart puro: se prueba sin base y
// sin pintar.
//
// **La regla que no se puede equivocar** (`pantallas.md` §2): manda `resultado`
// de la parada, **no** el estado de la ruta. Una ruta completada NO convierte en
// «entregado» un pedido que volvio en el camion; si se mirara el estado de la
// ruta, la hoja del almacen daria por salida mercancia que sigue arriba.

import '../../../nucleo/base/base.dart';

enum EstadoReparto {
  sinEntregar('Sin entregar'),
  enDespacho('En despacho'),
  enRuta('En ruta'),
  entregado('Entregado'),
  devuelto('Devuelto'),
  cancelado('Cancelado');

  const EstadoReparto(this.etiqueta);

  final String etiqueta;
}

/// [estadoDeSuRuta] es el `routes.status` de la ruta que lo lleva, o `null` si no
/// va en ninguna. Entra por parametro para que esto siga siendo una funcion pura.
EstadoReparto estadoDeReparto(Pedido pedido, String? estadoDeSuRuta) {
  switch (pedido.resultado) {
    case ResultadoParada.entregado:
      return EstadoReparto.entregado;
    case ResultadoParada.devuelto:
      return EstadoReparto.devuelto;
    case ResultadoParada.cancelado:
      return EstadoReparto.cancelado;
  }
  // Los pedidos viejos del espejo traen `deliveredAt` sin resultado de parada.
  if (pedido.deliveredAt != null) return EstadoReparto.entregado;
  if (pedido.routeId != null) {
    if (estadoDeSuRuta == EstadoRuta.enCurso) return EstadoReparto.enRuta;
    if (estadoDeSuRuta == EstadoRuta.planificada) {
      return EstadoReparto.enDespacho;
    }
  }
  return EstadoReparto.sinEntregar;
}

/// El estado EN PEDIDO, que es otro y se pinta en otra columna. `Expirada` no es
/// un valor guardado: es `no completada` con la fecha comprometida ya pasada.
enum EstadoEnPedidoVisto {
  completada('Completada'),
  expirada('Expirada'),
  enProceso('En proceso');

  const EstadoEnPedidoVisto(this.etiqueta);

  final String etiqueta;
}

EstadoEnPedidoVisto estadoEnPedido(Pedido pedido, {required DateTime ahora}) {
  if (pedido.estado == EstadoEnPedido.completada) {
    return EstadoEnPedidoVisto.completada;
  }
  final comprometida = pedido.fechaComprometida;
  if (comprometida != null && comprometida.isBefore(ahora)) {
    return EstadoEnPedidoVisto.expirada;
  }
  return EstadoEnPedidoVisto.enProceso;
}
