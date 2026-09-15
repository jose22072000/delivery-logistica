import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/frescura/frescura.dart';
import '../../../nucleo/red/cliente_api.dart';
import '../../../nucleo/registro/registro.dart';
import '../../../nucleo/reloj.dart';
import 'esquema.dart';

/// LA BAJADA DEL TABLERO: `GET /api/board`, una sola ida y vuelta.
///
/// Una y no cinco porque la conexion de alla no da para mas: columnas con sus
/// totales, tarjetas puestas, avisos y la primera pagina de sin colocar vienen
/// juntas. Aqui sólo se guardan las columnas y las colocaciones — los pedidos
/// ya los trae la sincronizacion normal, y copiarlos otra vez seria tener dos
/// versiones del mismo pedido en el mismo aparato.
///
/// **Quien pinta no llama a esto.** La pantalla mira siempre la base local; esto
/// es lo que la rellena cuando hay senal.
class ServicioTablero {
  ServicioTablero(
    this._base,
    this._cliente,
    this._frescura, {
    Reloj reloj = relojDelAparato,
  }) : _reloj = reloj;

  final BaseLocal _base;
  final ClienteApi _cliente;
  final RegistroDeFrescura _frescura;
  final Reloj _reloj;

  /// Baja el tablero de una sucursal y lo deja en la base local.
  ///
  /// **Si queda trabajo sin subir, no se baja nada.** Es la regla que impide el
  /// peor fallo posible de esta pantalla: la foto del servidor, que todavia no
  /// sabe nada de las cuarenta tarjetas que se movieron esta tarde, borraria
  /// las cuarenta de golpe y en silencio. Primero sube la cola; despues se
  /// refresca.
  Future<bool> descargar(String sucursalId) async {
    await EsquemaTablero.asegurar(_base);

    final pendientes = await _base.cuantosPendientes();
    if (pendientes > 0) {
      Registro.info(
        'tablero: $pendientes apuntes sin subir, no se baja para no pisarlos',
      );
      return false;
    }

    final datos = await _cliente.pedir<Map<String, Object?>>(
      '/board',
      params: <String, Object?>{'branchId': sucursalId},
    );

    final columnas = (datos['columnas'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .toList();
    final colocados = (datos['colocados'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .toList();

    await _base.transaction(() async {
      // Las colocaciones ANTES que las columnas: `ON DELETE RESTRICT` no deja
      // borrar una columna con tarjetas dentro, y eso es lo que se quiere en
      // todas partes menos aqui, donde se esta reemplazando la foto entera.
      await _base.customStatement(
        'DELETE FROM ${EsquemaTablero.colocaciones} WHERE column_id IN '
        '(SELECT id FROM ${EsquemaTablero.columnas} WHERE branch_id = ?1)',
        [sucursalId],
      );
      await _base.customStatement(
        'DELETE FROM ${EsquemaTablero.columnas} WHERE branch_id = ?1',
        [sucursalId],
      );

      for (final c in columnas) {
        await _base.customStatement(
          'INSERT INTO ${EsquemaTablero.columnas} '
          '(id, branch_id, nombre, posicion, vehicle_id, creado_por, '
          ' created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)',
          [
            c['id'] as String,
            (c['branchId'] as String?) ?? sucursalId,
            c['nombre'] as String,
            (c['posicion'] as num?)?.toInt() ?? 0,
            c['vehiculoId'] as String?,
            c['creadoPor'] as String?,
            _fecha(c['createdAt'] as String?),
            _fecha(c['updatedAt'] as String?),
          ],
        );
      }

      var huerfanas = 0;
      for (final t in colocados) {
        // El `WHERE EXISTS` es lo que impide que la bajada reviente entera por
        // una tarjeta de un pedido que este aparato todavia no tiene: se cuenta
        // y se dice, que es distinto de callarselo.
        await _base.customStatement(
          'INSERT INTO ${EsquemaTablero.colocaciones} '
          '(order_id, column_id, posicion, colocado_por, colocado_at, updated_at) '
          'SELECT ?1, ?2, ?3, ?4, ?5, ?5 '
          'WHERE EXISTS (SELECT 1 FROM orders WHERE id = ?1)',
          [
            t['pedidoId'] as String,
            t['columnaId'] as String,
            (t['posicion'] as num?)?.toInt() ?? 1,
            t['colocadoPor'] as String?,
            _fecha(t['colocadoAt'] as String?),
          ],
        );
        final cuantas = await _base
            .customSelect(
              'SELECT count(*) AS n FROM ${EsquemaTablero.colocaciones} '
              'WHERE order_id = ?1',
              variables: [Variable<String>(t['pedidoId'] as String)],
            )
            .getSingle();
        if (cuantas.read<int>('n') == 0) huerfanas++;
      }
      if (huerfanas > 0) {
        Registro.aviso(
          'tablero: $huerfanas tarjetas de pedidos que este aparato no tiene',
        );
      }
    });

    // La hora del SERVIDOR, tal cual vino: es la que se ensena como «visto por
    // ultima vez a las 9:14».
    final vistoAt = datos['vistoAt'] as String?;
    for (final coleccion in const [
      EsquemaTablero.coleccionColumnas,
      EsquemaTablero.coleccionColocaciones,
    ]) {
      await _frescura.marcar(
        coleccion,
        hasta: vistoAt,
        bajadaAt: _reloj(),
        completa: true,
      );
    }
    EsquemaTablero.avisarDeCambio(_base);
    return true;
  }

  /// La marca del servidor, pasada al formato en el que guarda las fechas el
  /// resto de la base. La conversion la hace Drift, no esta clase.
  Object? _fecha(String? iso) {
    if (iso == null) return null;
    final fecha = DateTime.tryParse(iso);
    return fecha == null ? null : _base.typeMapping.mapToSqlVariable(fecha);
  }
}
