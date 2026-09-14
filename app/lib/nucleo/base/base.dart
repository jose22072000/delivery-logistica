import 'package:drift/drift.dart';

import 'conexion/conexion.dart';
import 'tablas/aparato.dart';
import 'tablas/dominio.dart';

export 'tablas/aparato.dart' show EstadoApunte;
export 'tablas/catalogos.dart';

part 'base.g.dart';

/// Las colecciones que baja `GET /sync/bajada`. Son las claves de `cambios` y
/// las mismas que las filas de `frescura`.
abstract final class Colecciones {
  static const pedidos = 'orders';
  static const renglones = 'order_items';
  static const rutas = 'routes';
  static const clientes = 'customers';
  static const productos = 'products';
  static const vehiculos = 'vehicles';
  static const sucursales = 'branches';
  static const almacenes = 'warehouses';
  static const ajustes = 'settings';

  static const todas = <String>[
    pedidos,
    renglones,
    rutas,
    clientes,
    productos,
    vehiculos,
    sucursales,
    almacenes,
    ajustes,
  ];
}

@DriftDatabase(
  tables: [
    // dominio — espejo del esquema del servidor
    Branches,
    VehicleTypes,
    Vehicles,
    Products,
    Customers,
    Orders,
    OrderItems,
    Routes,
    Warehouses,
    Settings,
    Currencies,
    // aparato — no suben nunca
    Apuntes,
    Equivalencias,
    Frescura,
    Preferencias,
  ],
)
class BaseLocal extends _$BaseLocal {
  BaseLocal() : super(abrirConexion());

  /// Para los tests y para el dia que haga falta una segunda base.
  BaseLocal.con(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    beforeOpen: (detalles) async {
      // Las claves ajenas van ENCENDIDAS. SQLite las trae apagadas por defecto y
      // sin ellas un borrado de ruta deja renglones huerfanos que luego salen en
      // el post-despacho de una ruta que ya no existe.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Al cerrar sesion se borra lo local (regla 8): en el aparato quedan los
  /// clientes con sus direcciones y los pedidos del dia, y si el telefono cambia
  /// de manos eso no puede seguir ahi.
  ///
  /// **La cola NO se toca.** Si hay trabajo sin subir, quien pregunta es la
  /// pantalla y quien decide es la persona (caso I7). Borrar la cola aqui, de
  /// paso, seria tirar el dia de alguien sin decirselo.
  Future<void> borrarTodoLoDelDominio() async {
    await transaction(() async {
      for (final tabla in <TableInfo<Table, Object?>>[
        orderItems,
        orders,
        routes,
        customers,
        products,
        vehicles,
        vehicleTypes,
        warehouses,
        branches,
        currencies,
        settings,
        frescura,
        preferencias,
      ]) {
        await delete(tabla).go();
      }
    });
  }

  /// ¿Queda trabajo sin subir? Es lo que hay que preguntar ANTES de cerrar
  /// sesion.
  Future<int> cuantosPendientes() async {
    final cuenta = apuntes.orden.count();
    final fila =
        await (selectOnly(apuntes)
              ..addColumns([cuenta])
              ..where(apuntes.estado.equalsValue(EstadoApunte.pendiente)))
            .getSingle();
    return fila.read(cuenta) ?? 0;
  }
}
