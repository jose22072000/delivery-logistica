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

/// Las claves de `preferencias`. Viven aqui, y no en quien las usa, porque
/// `borrarTodoLoDelDominio()` tiene que saber cual **no** se borra sin importar
/// media aplicacion.
abstract final class ClaveDePreferencia {
  /// El alta de esta instalacion contra `POST /sync/aparato`. La pone el
  /// servidor y **sobrevive a cerrar sesion**: el porque, en
  /// `sincro/identidad_del_aparato.dart` y en `borrarTodoLoDelDominio()`.
  static const aparato = 'aparato';

  /// DE QUIEN ES ESTA COPIA: el `sub` del token de la persona.
  ///
  /// Se escribe la primera vez que se abre la base de alguien y no se toca mas.
  /// Es la segunda cerradura de «la cola de A no sube con el token de B»: la
  /// primera es que cada persona tiene su fichero, asi que con B delante la cola
  /// de A ni siquiera esta abierta; esta es la que sigue valiendo el dia que
  /// alguien cambie como se abren las bases. La mira `Subida` antes de mandar un
  /// solo apunte.
  static const dueno = 'dueno';

  /// EL NOMBRE de quien es esta copia, para PINTARLO.
  ///
  /// Sin esto, el gesto de olvidar a alguien tendria que ensenar el `sub`
  /// —`uaoOUHqTXNYUv672kjdLoZLpFrseCz9e`—, que a quien lo lee no le dice nada y
  /// que es sacar la base de auth a la cara. Se escribe al entrar, porque es el
  /// unico momento en el que se tiene el token delante.
  static const nombreDelDueno = 'nombreDelDueno';
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
  /// La base de una persona. [dueno] es el `sub` de su token.
  ///
  /// **Un fichero por persona**, y el porque entero esta en
  /// `conexion/nombre.dart`. `null` es «todavia no ha entrado nadie»: una base
  /// neutra y aparte, que no es la de nadie.
  BaseLocal({String? dueno})
    : _dueno = dueno,
      super(abrirConexion(dueno: dueno));

  /// Para los tests y para el dia que haga falta una segunda base.
  BaseLocal.con(super.executor, {String? dueno}) : _dueno = dueno;

  /// El `sub` de quien es esta copia, o `null` si no es de nadie.
  final String? _dueno;

  String? get dueno => _dueno;

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
      // QUIEN ES EL DUENO, dentro de la propia base. Escrito al abrir y no al
      // guardar el primer apunte: la cola tiene que poder decir de quien es
      // AUNQUE este vacia, porque lo que se comprueba antes de subir es de quien
      // es la copia, no de quien es cada apunte.
      final quien = _dueno;
      if (quien != null && quien.isNotEmpty) {
        await into(preferencias).insertOnConflictUpdate(
          PreferenciasCompanion.insert(
            clave: ClaveDePreferencia.dueno,
            valor: quien,
          ),
        );
      }
    },
  );

  /// Vacia el dominio de ESTA copia.
  ///
  /// ## Ya NO se llama al cerrar sesion
  ///
  /// Hasta el 15/09/2026 esto era lo que pasaba al salir, y era la mitad de un
  /// fallo: borraba el dominio y dejaba la cola, asi que los 23 apuntes del que
  /// se iba se quedaban esperando a que entrara otro para subir con SU token.
  /// Ahora cada persona tiene su copia, cerrar sesion **cambia de copia** y no
  /// borra nada, y quien vuelve encuentra lo suyo (`conexion/nombre.dart`).
  ///
  /// Esto se sigue usando para **olvidar a alguien**, que es un gesto aparte y
  /// explicito, y por eso sigue sin tocar la cola: quien olvida a una persona
  /// tiene que haber mirado antes si le queda trabajo sin subir, y esa pregunta
  /// se hace fuera, con [cuantosPendientes], para poder avisar ANTES.
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
      ]) {
        await delete(tabla).go();
      }

      // `preferencias` se vacia MENOS el alta del aparato.
      //
      // El aparato es el mismo aparato antes y despues de que alguien salga. Si
      // su identificador muriera aqui, la proxima entrada daria de alta uno
      // nuevo y el panel de sincronizacion —que existe para ver que «Palma lleva
      // desde el martes sin subir»— se llenaria de instalaciones fantasma, todas
      // «nunca han subido», entre las que no se podria distinguir el telefono
      // que de verdad se quedo atras.
      //
      // Lo que se borra es el DOMINIO (regla 8): los clientes con sus
      // direcciones y los pedidos del dia, que es lo que no puede quedarse en un
      // telefono que cambia de manos. Aqui solo sobrevive un UUID que no dice
      // nada de nadie. Y si el telefono cambia de sucursal, el servidor lo corta
      // solo: `aparatoDeLaPeticion` contesta 403 «Ese aparato no es de tu
      // sucursal» (`sync/internal/sincro/bajada.go`).
      await (delete(
        preferencias,
      )..where((p) => p.clave.equals(ClaveDePreferencia.aparato).not())).go();
    });
  }

  /// OLVIDAR A ESTA PERSONA: su dominio y **su cola**, todo.
  ///
  /// Es lo unico que borra una cola, y por eso es un gesto aparte: quien llama
  /// tiene que haber preguntado antes con [cuantosPendientes] y haber avisado
  /// si queda trabajo sin subir. Un apunte que desaparece solo es trabajo
  /// perdido que nadie sabe que perdio (`sincronizacion.md`).
  ///
  /// El alta del aparato TAMBIEN se va aqui, al reves que en
  /// [borrarTodoLoDelDominio]: es el alta de esta copia, y la copia deja de
  /// existir. El aparato como tal sigue dado de alta en las demas copias.
  Future<void> olvidar() async {
    await borrarTodoLoDelDominio();
    await transaction(() async {
      await delete(equivalencias).go();
      await delete(apuntes).go();
      await delete(preferencias).go();
    });
  }

  /// DE QUIEN DICE LA PROPIA BASE que es esta copia.
  ///
  /// Sale de `preferencias` y no de [dueno], que es lo que le pasaron al
  /// constructor: lo que hay que comprobar antes de subir una cola es de quien
  /// son las filas que hay escritas, no con que nombre se abrio el fichero.
  /// `null` en una base que nunca tuvo dueno — la neutra de antes de entrar, o
  /// una de prueba.
  Future<String?> duenoGuardado() async {
    final fila =
        await (select(preferencias)
              ..where((p) => p.clave.equals(ClaveDePreferencia.dueno)))
            .getSingleOrNull();
    final valor = fila?.valor;
    return (valor == null || valor.isEmpty) ? null : valor;
  }

  Future<String?> nombreDelDueno() async {
    final fila =
        await (select(preferencias)
              ..where((p) => p.clave.equals(ClaveDePreferencia.nombreDelDueno)))
            .getSingleOrNull();
    return fila?.valor;
  }

  /// Anota el nombre para PINTAR de quien es esta copia. Se llama al entrar.
  Future<void> anotarNombreDelDueno(String nombre) async {
    if (nombre.isEmpty) return;
    await into(preferencias).insertOnConflictUpdate(
      PreferenciasCompanion.insert(
        clave: ClaveDePreferencia.nombreDelDueno,
        valor: nombre,
      ),
    );
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
