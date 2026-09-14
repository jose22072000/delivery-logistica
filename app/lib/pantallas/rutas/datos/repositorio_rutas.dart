// Lo que Rutas LEE. Todo de la base local, igual que Pedidos: sin conexion se ve
// la lista, se filtra, se pagina, se abre el detalle con sus paradas y su carga
// total. Lo unico que cambia sin red es que el mapa se queda sin baldosas y que
// `Abrir en Google Maps` no puede salir.

import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import '../../pedidos/datos/repositorio_pedidos.dart';

/// Las tres pestanas, con los estados que agrupa cada una y su texto de vacio.
enum PestanaRutas {
  activas('Activas', 'Sin rutas activas. Crea la primera.'),
  enCurso('En curso', 'Sin rutas en curso.'),
  historial('Historial', 'Sin rutas completadas aún.');

  const PestanaRutas(this.etiqueta, this.vacio);

  final String etiqueta;
  final String vacio;

  /// `Activas` es «ni completada ni en curso», no «planificada»: una ruta con un
  /// estado que todavia no conocemos tiene que salir en algun sitio, y el sitio
  /// es donde se trabaja.
  bool agrupa(String estado) => switch (this) {
    PestanaRutas.activas =>
      estado != EstadoRuta.completada && estado != EstadoRuta.enCurso,
    PestanaRutas.enCurso => estado == EstadoRuta.enCurso,
    PestanaRutas.historial => estado == EstadoRuta.completada,
  };
}

/// Los filtros de la columna izquierda. Se aplican **en el cliente** sobre las
/// rutas ya traidas, como en la de Next.
class FiltrosRutas {
  const FiltrosRutas({
    this.q = '',
    this.vehiculoId = '',
    this.desde,
    this.hasta,
  });

  final String q;
  final String vehiculoId;
  final DateTime? desde;
  final DateTime? hasta;

  bool get hayAlguno =>
      q.isNotEmpty || vehiculoId.isNotEmpty || desde != null || hasta != null;
}

/// Una ruta con lo que la tarjeta y el detalle necesitan, ya resuelto.
class RutaConTodo {
  const RutaConTodo({
    required this.ruta,
    required this.paradas,
    this.vehiculo,
    this.sucursal,
  });

  final Ruta ruta;

  /// Las paradas son los pedidos con `ultimaRutaId = ruta.id`, **no**
  /// `routeId`: lo que no se entrega suelta su `routeId` para poder ir en la
  /// ruta de manana, y si se mirara esa columna desapareceria de su propia hoja
  /// de cierre en cuanto se marcara como devuelto.
  final List<Pedido> paradas;

  final Vehiculo? vehiculo;
  final Sucursal? sucursal;

  double get pesoTotal => paradas.fold<double>(0, (suma, p) => suma + p.weight);

  bool get sobrepeso {
    final capacidad = vehiculo?.capacity;
    return capacidad != null && pesoTotal > capacidad;
  }

  int get sinMarcar => paradas.where((p) => p.resultado == null).length;
}

class ConsultasRutas {
  ConsultasRutas(this._base) : _pedidos = ConsultasPedidos(_base);

  final BaseLocal _base;
  final ConsultasPedidos _pedidos;

  /// 20 por pagina, en el cliente. Lo fija el pliego (§9.7).
  static const porPagina = 20;

  /// Todas las rutas del alcance, de la mas nueva a la mas vieja.
  Stream<List<Ruta>> rutas({String? sucursalId}) {
    final consulta = _base.select(_base.routes)
      ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]);
    if (sucursalId != null && sucursalId.isNotEmpty) {
      consulta.where((r) => r.branchId.equals(sucursalId));
    }
    return consulta.watch();
  }

  /// Una ruta con sus paradas, su vehiculo y su sucursal.
  Stream<RutaConTodo?> rutaConTodo(String rutaId) {
    final consulta = _base.select(_base.routes)
      ..where((r) => r.id.equals(rutaId));
    return consulta.watchSingleOrNull().asyncMap((ruta) async {
      if (ruta == null) return null;
      return RutaConTodo(
        ruta: ruta,
        paradas: await paradasDe(rutaId),
        vehiculo: await _vehiculo(ruta.vehicleId),
        sucursal: await _sucursal(ruta.branchId),
      );
    });
  }

  Future<List<Pedido>> paradasDe(String rutaId) {
    final consulta = _base.select(_base.orders)
      ..where((o) => o.ultimaRutaId.equals(rutaId))
      ..orderBy([
        (o) => OrderingTerm.asc(o.stopOrder),
        (o) => OrderingTerm.asc(o.customerName),
      ]);
    return consulta.get();
  }

  /// Las paradas se miran en vivo para que el cierre se vea marcado en el
  /// detalle sin esperar a nada.
  Stream<List<Pedido>> mirarParadasDe(String rutaId) {
    final consulta = _base.select(_base.orders)
      ..where((o) => o.ultimaRutaId.equals(rutaId))
      ..orderBy([
        (o) => OrderingTerm.asc(o.stopOrder),
        (o) => OrderingTerm.asc(o.customerName),
      ]);
    return consulta.watch();
  }

  Future<Vehiculo?> _vehiculo(String? id) async => id == null
      ? null
      : (await (_base.select(
          _base.vehicles,
        )..where((v) => v.id.equals(id))).getSingleOrNull());

  Future<Sucursal?> _sucursal(String? id) async => id == null
      ? null
      : (await (_base.select(
          _base.branches,
        )..where((b) => b.id.equals(id))).getSingleOrNull());

  Stream<List<Vehiculo>> vehiculos({String? sucursalId}) {
    final consulta = _base.select(_base.vehicles)
      ..orderBy([(v) => OrderingTerm.asc(v.name)]);
    if (sucursalId != null && sucursalId.isNotEmpty) {
      consulta.where((v) => v.branchId.equals(sucursalId));
    }
    return consulta.watch();
  }

  Stream<List<Sucursal>> sucursales() => (_base.select(
    _base.branches,
  )..orderBy([(b) => OrderingTerm.asc(b.name)])).watch();

  /// Los almacenes de una sucursal, **el principal primero**: es el punto de
  /// partida por defecto y el origen desde el que se mide todo.
  Future<List<Almacen>> almacenesDe(String sucursalCodigo) {
    final consulta = _base.select(_base.warehouses)
      ..where(
        (a) => a.sucursalCodigo.equals(sucursalCodigo) & a.activo.equals(true),
      )
      ..orderBy([
        (a) => OrderingTerm.desc(a.principal),
        (a) => OrderingTerm.asc(a.nombre),
      ]);
    return consulta.get();
  }

  /// Los pedidos que se pueden meter en una ruta.
  ///
  /// Las condiciones fijas son las del servidor y **no son negociables**:
  /// `source='pedido'`, sin ruta, con coordenadas de entrega y facturado. El
  /// filtro de factura de la pantalla NO es configurable: siempre `cuadra`
  /// (`facturaEstado = 'igual'`), que es lo unico que el armado del servidor
  /// acepta. Ofrecer aqui lo que alli se rechaza es fabricar rechazos tardios.
  Future<List<Pedido>> disponibles({
    String? sucursalId,
    String q = '',
    String municipio = '',
    String vendedor = '',
    DateTime? dia,
    double? kmMax,
    double? costoMin,
  }) async {
    final o = _base.orders;
    Expression<bool> donde =
        o.source.equals(Procedencia.pedido) &
        o.routeId.isNull() &
        o.endLat.isNotNull() &
        o.endLng.isNotNull() &
        o.facturaEstado.equals(EstadoFactura.igual);

    if (sucursalId != null && sucursalId.isNotEmpty) {
      donde = donde & o.branchId.equals(sucursalId);
    }
    if (municipio.isNotEmpty) donde = donde & o.municipio.equals(municipio);
    if (vendedor.isNotEmpty) donde = donde & o.vendedor.equals(vendedor);

    final busca = q.trim().toLowerCase();
    if (busca.isNotEmpty) {
      donde =
          donde &
          (o.customerName.lower().contains(busca) |
              o.operationNumber.lower().contains(busca) |
              o.endAddress.lower().contains(busca) |
              o.address.lower().contains(busca));
    }
    if (dia != null) {
      // Un dia natural completo, igual que el servidor.
      final inicio = DateTime(dia.year, dia.month, dia.day);
      final fin = inicio.add(const Duration(days: 1));
      donde =
          donde &
          ((o.orderDate.isBiggerOrEqualValue(inicio) &
                  o.orderDate.isSmallerThanValue(fin)) |
              (o.orderDate.isNull() &
                  o.createdAt.isBiggerOrEqualValue(inicio) &
                  o.createdAt.isSmallerThanValue(fin)));
    }

    final consulta = _base.select(_base.orders)
      ..where((_) => donde)
      ..orderBy([
        (o) => OrderingTerm.desc(o.orderDate),
        (o) => OrderingTerm.desc(o.createdAt),
      ]);
    final filas = await consulta.get();

    return [
      for (final pedido in filas)
        // `kmMax` y `costoMin` se filtran despues de la consulta, igual que en el
        // servidor. Un pedido SIN distancia medida nunca se descarta: no saber
        // cuan lejos esta no es lo mismo que estar lejos.
        if (!(kmMax != null &&
                pedido.deliveryDistanceKm != null &&
                pedido.deliveryDistanceKm! > kmMax) &&
            !(costoMin != null && (pedido.pedidoCosto ?? 0) < costoMin))
          pedido,
    ];
  }

  /// Los renglones de unos pedidos, con el peso por empaque ya resuelto. Se
  /// reutiliza el de Pedidos: la carga del camion y el pre-despacho tienen que
  /// contar igual en las dos pantallas.
  Future<Map<String, List<RenglonConPeso>>> renglonesDe(List<String> ids) =>
      _pedidos.renglonesDe(ids);
}

/// Los filtros de la lista, aplicados en el cliente.
List<Ruta> filtrarRutas(
  List<Ruta> rutas,
  FiltrosRutas filtros, {
  required Map<String, Vehiculo> vehiculos,
  required Map<String, Sucursal> sucursales,
}) {
  final busca = filtros.q.trim().toLowerCase();
  return [
    for (final ruta in rutas)
      if (_cuadra(ruta, filtros, busca, vehiculos, sucursales)) ruta,
  ];
}

bool _cuadra(
  Ruta ruta,
  FiltrosRutas filtros,
  String busca,
  Map<String, Vehiculo> vehiculos,
  Map<String, Sucursal> sucursales,
) {
  if (filtros.vehiculoId.isNotEmpty && ruta.vehicleId != filtros.vehiculoId) {
    return false;
  }
  final creada = ruta.createdAt;
  if (filtros.desde != null && creada != null) {
    final inicio = DateTime(
      filtros.desde!.year,
      filtros.desde!.month,
      filtros.desde!.day,
    );
    if (creada.isBefore(inicio)) return false;
  }
  if (filtros.hasta != null && creada != null) {
    // `hasta` incluye el dia entero: si no, filtrar «hasta hoy» deja fuera lo de
    // hoy y parece que no hay rutas.
    final fin = DateTime(
      filtros.hasta!.year,
      filtros.hasta!.month,
      filtros.hasta!.day,
      23,
      59,
      59,
      999,
    );
    if (creada.isAfter(fin)) return false;
  }
  if (busca.isEmpty) return true;

  final donde = [
    ruta.routeCode ?? '',
    ruta.name ?? '',
    ruta.originAddress ?? '',
    vehiculos[ruta.vehicleId]?.name ?? '',
    sucursales[ruta.branchId]?.name ?? '',
  ].join(' ').toLowerCase();
  return donde.contains(busca);
}
