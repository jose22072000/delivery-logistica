// Las tablas del DOMINIO: las mismas que el esquema del servidor
// (../api/db/migrations/00001_init.sql), con los MISMOS nombres de columna.
//
// El porque de calcarlas: asi la bajada por diferencias es un
// `insertOnConflictUpdate` del JSON que llega y nada mas. Cualquier renombre aqui
// obliga a un traductor en medio, y un traductor en medio es donde se pierden los
// campos que nadie mira hasta que hacen falta.
//
// Los `id` son TEXTO, no uuid: tienen que poder alojar tambien los provisionales
// `local-…` que el aparato se inventa cuando arma una ruta sin conexion (§2.2).

import 'package:drift/drift.dart';

@DataClassName('Sucursal')
class Branches extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  RealColumn get areaKm2 => real().withDefault(const Constant(1))();
  TextColumn get externalId => text().nullable()();
  BoolColumn get originConfigured =>
      boolean().withDefault(const Constant(false))();
  TextColumn get creadoPor => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TipoVehiculo')
class VehicleTypes extends Table {
  TextColumn get id => text()();
  TextColumn get nombre => text()();
  RealColumn get costoKmUsd => real().nullable()();
  BoolColumn get activo => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Vehiculo')
class Vehicles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get vehicleTypeId => text().nullable()();
  TextColumn get plate => text().nullable()();
  RealColumn get capacity => real().withDefault(const Constant(1000))();
  RealColumn get costoKmUsd => real().nullable()();

  /// El vehiculo de REFERENCIA de su sucursal para calcular el domicilio.
  /// En el servidor lo limita un indice unico parcial; aqui hay que hacer lo
  /// mismo a mano y EN LA MISMA TRANSACCION, o la pantalla ensena dos marcados
  /// hasta la proxima bajada (PLAN.md §3.4).
  BoolColumn get usarParaDomicilio =>
      boolean().withDefault(const Constant(false))();
  TextColumn get status => text().withDefault(const Constant('available'))();
  TextColumn get notes => text().nullable()();
  TextColumn get branchId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Producto')
class Products extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get weight => real().withDefault(const Constant(0))();
  TextColumn get packaging => text().nullable()();
  RealColumn get unitsPerPackage => real().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get sku => text().nullable()();
  TextColumn get sucursalCodigo => text().nullable()();
  RealColumn get price => real().nullable()();
  RealColumn get stock => real().nullable()();
  TextColumn get unit => text().nullable()();

  /// Cuando lo trajo Ventra. No es `updatedAt`: dice si lo que se mira es de hace
  /// diez minutos o de hace tres dias porque la VPN lleva caida desde el lunes.
  DateTimeColumn get traidoAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Cliente')
class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get source => text().nullable()();
  TextColumn get externalId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get municipio => text().nullable()();
  TextColumn get zona => text().nullable()();
  TextColumn get codigo => text().nullable()();
  TextColumn get vendedor => text().nullable()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  TextColumn get sucursalCodigo => text().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Pedido')
class Orders extends Table {
  TextColumn get id => text()();
  TextColumn get operationNumber => text().nullable()();
  TextColumn get customerName => text()();
  TextColumn get address => text()();
  TextColumn get endAddress => text().nullable()();
  RealColumn get endLat => real().nullable()();
  RealColumn get endLng => real().nullable()();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  RealColumn get weight => real().withDefault(const Constant(1))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get tripLeg => text().withDefault(const Constant('outbound'))();
  TextColumn get notes => text().nullable()();

  /// La ruta que lo lleva AHORA. Con esto puesto el pedido esta ocupado.
  TextColumn get routeId => text().nullable()();

  /// En que ruta VIAJO. Esto no se libera nunca — un devuelto suelta `routeId`
  /// pero CONSERVA `ultimaRutaId`, o desaparece de la hoja de lo que bajo del
  /// camion.
  TextColumn get ultimaRutaId => text().nullable()();

  TextColumn get vehicleId => text().nullable()();

  RealColumn get price => real().nullable()();
  RealColumn get segmentKm => real().nullable()();
  RealColumn get deliveryPrice => real().nullable()();
  RealColumn get deliveryDistanceKm => real().nullable()();
  TextColumn get branchId => text().nullable()();

  TextColumn get source => text().nullable()();
  TextColumn get externalId => text().nullable()();

  /// La FECHA DEL PEDIDO en PEDIDO, que NO es `createdAt`.
  DateTimeColumn get orderDate => dateTime().nullable()();
  DateTimeColumn get pedidoUpdatedAt => dateTime().nullable()();

  TextColumn get estado => text().nullable()();
  BoolColumn get archivado => boolean().withDefault(const Constant(false))();
  DateTimeColumn get fechaComprometida => dateTime().nullable()();

  BoolColumn get requiereDomicilio => boolean().nullable()();

  /// El costo que le puso la APK de Entrega EN PEDIDO. En la pantalla es
  /// `Precio`. NO es `price` — confundirlos es cobrar uno por el otro.
  RealColumn get pedidoCosto => real().nullable()();

  TextColumn get municipio => text().nullable()();
  TextColumn get vendedor => text().nullable()();
  TextColumn get sucursalCodigo => text().nullable()();

  TextColumn get facturaEstado => text().nullable()();
  TextColumn get facturaNumero => text().nullable()();
  DateTimeColumn get facturaAt => dateTime().nullable()();
  RealColumn get facturaDomicilio => real().nullable()();
  DateTimeColumn get facturaCorregidoAt => dateTime().nullable()();

  TextColumn get customerPhone => text().nullable()();

  IntColumn get stopOrder => integer().nullable()();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  TextColumn get resultado => text().nullable()();
  DateTimeColumn get resultadoAt => dateTime().nullable()();
  TextColumn get resultadoNota => text().nullable()();

  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('RenglonPedido')
class OrderItems extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text()();
  IntColumn get linea => integer()();
  TextColumn get description => text()();
  RealColumn get quantity => real()();

  /// Los bultos, cuando la factura los distingue de las unidades. El numero de
  /// una linea son sus `packs` y si no los trae sus `quantity`, nunca cero
  /// (reglas-negocio §12).
  RealColumn get packs => real().nullable()();
  TextColumn get productId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Ruta')
class Routes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().nullable()();
  TextColumn get routeCode => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('planned'))();
  TextColumn get originAddress => text().nullable()();
  RealColumn get originLat => real().nullable()();
  RealColumn get originLng => real().nullable()();
  RealColumn get totalDistance => real().withDefault(const Constant(0))();
  RealColumn get totalWeight => real().withDefault(const Constant(0))();
  RealColumn get totalPrice => real().withDefault(const Constant(0))();
  DateTimeColumn get deliveryDate => dateTime().nullable()();
  TextColumn get vehicleId => text().nullable()();
  TextColumn get creadoPor => text().nullable()();
  TextColumn get branchId => text().nullable()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  BoolColumn get optimized => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Los almacenes. No estan en el esquema de la API: viven en Accesos y se leen
/// por `GET /api/almacenes`. Aqui se guarda la copia bajada.
@DataClassName('Almacen')
class Warehouses extends Table {
  TextColumn get id => text()();
  TextColumn get sucursalCodigo => text()();
  TextColumn get nombre => text()();
  TextColumn get direccion => text().nullable()();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();

  /// El principal de la sucursal: es el punto de partida y el origen desde el
  /// que se miden los km de los clientes.
  BoolColumn get principal => boolean().withDefault(const Constant(false))();
  BoolColumn get activo => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Una sola fila, como en el servidor: dos filas de ajustes es media aplicacion
/// mirando una y media mirando la otra.
@DataClassName('Ajustes')
class Settings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  IntColumn get syncBarridoDia => integer().withDefault(const Constant(0))();
  DateTimeColumn get catalogoTraidoAt => dateTime().nullable()();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  RealColumn get cupRate => real().withDefault(const Constant(320))();
  DateTimeColumn get cupRateUpdatedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('Moneda')
class Currencies extends Table {
  TextColumn get code => text()();

  /// Unidades de esta moneda por 1 USD. CUP = 320.
  RealColumn get rate => real()();
  BoolColumn get activa => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {code};
}
