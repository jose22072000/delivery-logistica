import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../base/base.dart';
import '../reloj.dart';

const _uuid = Uuid();

/// Los identificadores provisionales: `local-9f3a2b7c` → `cm2x…`.
///
/// Una ruta armada sin conexion no tiene identificador —lo pone la base de
/// datos— pero la pantalla necesita uno YA para poder ensenarla, imprimir el
/// despacho y cerrarla despues. Asi que el aparato se inventa uno.
///
/// **Y aqui esta el agujero por el que se pierde el dia entero.** Cuando el
/// apunte que crea la ruta sube, la respuesta trae el id de verdad; si no se
/// sustituye en todo lo que quedara en la cola detras, el cierre de la tarde se
/// va a `POST /api/routes/local-9f3a/results`, que no existe en ningun sitio, y
/// el trabajo se pierde JUSTO DESPUES de haberlo subido (caso S4).
class Provisionales {
  Provisionales(this._base, {Reloj reloj = relojDelAparato}) : _reloj = reloj;

  final BaseLocal _base;
  final Reloj _reloj;

  /// Las columnas donde puede haber un id provisional.
  ///
  /// Va como lista y no a mano en la consulta porque sin red no sólo se arman
  /// rutas: tambien se crean vehiculos y almacenes (PLAN.md §3.4 y §3.5), y el
  /// dia que se anada otro, esto es lo unico que hay que tocar.
  static const _dondeMirar = <(String tabla, String columna)>[
    ('routes', 'id'),
    ('routes', 'vehicle_id'),
    ('orders', 'route_id'),
    ('orders', 'ultima_ruta_id'),
    ('orders', 'vehicle_id'),
    ('vehicles', 'id'),
    ('warehouses', 'id'),
  ];

  /// Un id provisional nuevo. `local-` delante para que se reconozca de un
  /// vistazo en un registro, en la barra de direcciones o en un cuerpo JSON.
  static String nuevoId() =>
      'local-${_uuid.v4().replaceAll('-', '').substring(0, 8)}';

  static bool esProvisional(String? id) => id != null && id.startsWith('local-');

  /// Cambia `provisional` por `real` en TODO: la equivalencia, los apuntes que
  /// quedan por subir y las filas locales.
  ///
  /// Va entero en UNA transaccion. A medias es peor que nada: la ruta ya subida
  /// con su id bueno y el cierre de la tarde apuntando a un id que no existe.
  Future<void> sustituir(String provisional, String real) async {
    if (provisional == real) return;

    await _base.transaction(() async {
      // 1. El rastro. Sirve para leer un registro viejo y para no repetir.
      await _base
          .into(_base.equivalencias)
          .insertOnConflictUpdate(
            EquivalenciasCompanion.insert(
              provisional: provisional,
              idReal: real,
              at: _reloj(),
            ),
          );

      // 2. Los apuntes que AUN NO HAN SUBIDO. Sólo los pendientes: reescribir un
      //    apunte ya aplicado o rechazado seria falsear lo que de verdad se
      //    mando, y esa es la unica prueba que queda de lo que paso.
      await _base.customUpdate(
        'UPDATE apuntes SET ruta = replace(ruta, ?1, ?2), '
        'cuerpo = replace(cuerpo, ?1, ?2) '
        "WHERE estado = 'pendiente' AND (ruta LIKE ?3 OR cuerpo LIKE ?3)",
        variables: [
          Variable<String>(provisional),
          Variable<String>(real),
          Variable<String>('%$provisional%'),
        ],
        updates: {_base.apuntes},
      );

      // 3. Las filas locales, para que la pantalla deje de ensenar el `local-…`
      //    sin esperar a la proxima bajada.
      for (final (tabla, columna) in _dondeMirar) {
        await _base.customUpdate(
          'UPDATE $tabla SET $columna = ?1 WHERE $columna = ?2',
          variables: [Variable<String>(real), Variable<String>(provisional)],
          updates: {_base.tablaLlamada(tabla)},
        );
      }
    });
  }

  /// El id de verdad de un provisional, si ya se resolvio.
  Future<String?> real(String provisional) async {
    final fila =
        await (_base.select(_base.equivalencias)
              ..where((f) => f.provisional.equals(provisional)))
            .getSingleOrNull();
    return fila?.idReal;
  }
}

extension on BaseLocal {
  /// Drift necesita saber que tablas toca un `customUpdate` para poder avisar a
  /// los `watch()` que estan mirando. Sin esto la pantalla se queda con el
  /// `local-…` puesto hasta que algo mas la despierte.
  TableInfo<Table, Object?> tablaLlamada(String nombre) =>
      allTables.firstWhere((t) => t.actualTableName == nombre);
}
