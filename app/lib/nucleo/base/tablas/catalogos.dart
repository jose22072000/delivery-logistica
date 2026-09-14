/// Los conjuntos cerrados del servidor, como CONSTANTES y no como enum de Drift.
///
/// El porque: estas tablas son un ESPEJO. Si manana el servidor anade un valor a
/// `stop_result` y aqui hubiera un `textEnum`, la bajada reventaria al leer la fila
/// y el aparato se quedaria sin datos en la calle — que es justo el momento en que
/// no hay nadie para arreglarlo. Guardando el texto tal cual, lo desconocido entra,
/// se guarda y se puede pintar; lo que no reconocemos lo trata la pantalla.
library;

/// `orders.status` — ../api/db/migrations/00001_init.sql
abstract final class EstadoPedido {
  static const pendiente = 'pending';
  static const entregado = 'delivered';
}

/// `orders.resultado` — como acabo la parada cuando el camion vuelve.
/// De aqui sale el post-despacho: lo que queda en el camion es lo que NO esta
/// entregado.
abstract final class ResultadoParada {
  static const entregado = 'entregado';
  static const devuelto = 'devuelto';
  static const cancelado = 'cancelado';
}

/// `routes.status` — las tres pestanas de Rutas salen de aqui.
abstract final class EstadoRuta {
  static const planificada = 'planned';
  static const enCurso = 'in_progress';
  static const completada = 'completed';
  static const cancelada = 'cancelled';
}

/// `vehicles.status`
abstract final class EstadoVehiculo {
  static const disponible = 'available';
  static const enUso = 'in_use';
}

/// `orders.trip_leg`
abstract final class Tramo {
  static const ida = 'outbound';
  static const regreso = 'return';
}

/// `orders.estado` — el estado EN PEDIDO, copiado. Manda PEDIDO.
abstract final class EstadoEnPedido {
  static const completada = 'completada';
  static const enProceso = 'en_proceso';
}

/// `orders.factura_estado` — NULL no es `sin_factura`: NULL es «no cotejado».
abstract final class EstadoFactura {
  static const igual = 'igual';
  static const cambiado = 'cambiado';
  static const sinFactura = 'sin_factura';
}

/// `orders.source` / `customers.source` — NULL = alta manual en el reparto.
abstract final class Procedencia {
  static const pedido = 'pedido';
}
