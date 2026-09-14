import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';

/// Las dos tablas del tablero EN LA BASE LOCAL, calcadas de
/// `api/db/migrations/00002_tablero.sql`.
///
/// **Por qué van en SQL suelto y no como tablas de Drift.** El esquema del
/// nucleo (`nucleo/base/tablas/`) es el espejo de lo que baja la
/// sincronizacion y no es de esta pantalla; el tablero se monta entero dentro
/// de su carpeta. Creando las tablas aqui, con `CREATE TABLE IF NOT EXISTS`,
/// el tablero vive en LA MISMA base y por tanto en la MISMA transaccion que la
/// cola de salida — que es el requisito que manda: arrastrar escribe la
/// colocacion y encola su apunte de una vez, o no escribe ninguna de las dos.
/// Con una segunda base serian dos transacciones y el dia que la segunda
/// fallara, la tarjeta se habria movido sin que nadie lo fuera a subir.
///
/// Las dos claves ajenas son las reglas de la especificacion, no un adorno:
///
///  * `order_id … ON DELETE CASCADE` (§7.5): si el pedido se borra de verdad,
///    la colocacion no puede sobrevivir — una tarjeta apuntando a un pedido que
///    no existe es una parada fantasma que la ruta cargaria sin renglones.
///  * `column_id … ON DELETE RESTRICT` (§7.6): borrar una columna con pedidos
///    dentro TIENE que doler. Con cascade las tarjetas volverian a «sin
///    colocar» sin decir nada y quien borro «Centro» creyendola vacia se entera
///    al dia siguiente, cuando a la ruta le faltan ocho paradas.
///
/// Van encendidas porque `BaseLocal.migration` pone `PRAGMA foreign_keys = ON`.
abstract final class EsquemaTablero {
  static const columnas = 'board_columns';
  static const colocaciones = 'board_placements';
  static const desaparecidos = 'board_desaparecidos';

  /// Las dos colecciones que la sincronizacion gana en `cambios`
  /// (`docs/tablero.md` §9). Se usan como clave en la tabla `frescura`, que es
  /// texto libre, para poder decir «visto por ultima vez a las 9:14».
  static const coleccionColumnas = 'boardColumns';
  static const coleccionColocaciones = 'boardPlacements';

  /// Las fechas van como TEXTO ISO-8601, que es como las guarda el resto de la
  /// base (`build.yaml`: `store_date_time_values_as_text`). Un entero de
  /// segundos aqui y texto en `orders` obligaria a convertir en cada `JOIN` y
  /// seria el sitio perfecto para perder una hora por el camino.
  static const _sentencias = <String>[
    '''
CREATE TABLE IF NOT EXISTS $columnas (
  id          TEXT NOT NULL PRIMARY KEY,
  branch_id   TEXT NOT NULL,
  nombre      TEXT NOT NULL,
  posicion    INTEGER NOT NULL,
  vehicle_id  TEXT,
  creado_por  TEXT,
  created_at  TEXT,
  updated_at  TEXT
)''',
    // Dos «Vista Alegre» en el mismo tablero es colocar la mitad de los pedidos
    // en la equivocada y no enterarse hasta que salen dos camiones al mismo
    // barrio. Sin distinguir mayusculas: «centro» y «Centro» son la misma zona
    // para quien las escribe.
    'CREATE UNIQUE INDEX IF NOT EXISTS board_columns_nombre_idx '
        'ON $columnas (branch_id, lower(nombre))',
    'CREATE INDEX IF NOT EXISTS board_columns_branch_idx '
        'ON $columnas (branch_id, posicion)',
    // OJO: aqui NO va la unica de `(branch_id, posicion)` que si tiene
    // Postgres. Alli es DEFERRABLE y la comprobacion espera al final de la
    // transaccion; SQLite no sabe diferir nada, asi que la misma unica
    // reventaria a mitad del baile de reordenar, cuando hay dos columnas con la
    // misma posicion durante un instante. El orden lo sostiene quien escribe.
    '''
CREATE TABLE IF NOT EXISTS $colocaciones (
  order_id     TEXT NOT NULL PRIMARY KEY
               REFERENCES orders(id) ON DELETE CASCADE,
  column_id    TEXT NOT NULL
               REFERENCES $columnas(id) ON DELETE RESTRICT,
  posicion     INTEGER NOT NULL,
  colocado_por TEXT,
  colocado_at  TEXT,
  updated_at   TEXT
)''',
    'CREATE INDEX IF NOT EXISTS board_placements_column_idx '
        'ON $colocaciones (column_id, posicion)',
    // Lo que se llevo la cascada, para poder decirlo (§7.5).
    //
    // La cascada es silenciosa, y eso es justo lo que hay que tapar: el pedido
    // se archivo en PEDIDO, la bajada lo trajo en `quitados`, la fila
    // desaparecio y con ella la tarjeta. Sin esto, el logistico vuelve a
    // «Centro» y ve once paradas donde puso doce, sin manera de saber cual
    // falta ni por que.
    '''
CREATE TABLE IF NOT EXISTS $desaparecidos (
  order_id         TEXT NOT NULL PRIMARY KEY,
  operation_number TEXT,
  customer_name    TEXT,
  columna          TEXT,
  visto_at         TEXT
)''',
    // El disparador va sobre `orders` y es BEFORE DELETE porque despues del
    // borrado ya no queda nada que copiar: ni el numero de operacion ni de que
    // columna salio. Sólo escribe si el pedido estaba PUESTO, asi que el
    // barrido normal de pedidos viejos no deja rastro ninguno.
    '''
CREATE TRIGGER IF NOT EXISTS board_pedido_borrado
BEFORE DELETE ON orders
BEGIN
  INSERT OR REPLACE INTO $desaparecidos
    (order_id, operation_number, customer_name, columna, visto_at)
  SELECT OLD.id, OLD.operation_number, OLD.customer_name, c.nombre,
         datetime('now')
  FROM $colocaciones p
  JOIN $columnas c ON c.id = p.column_id
  WHERE p.order_id = OLD.id;
END''',
  ];

  /// Crea lo que falte. Una vez por base abierta: el `Expando` evita cinco
  /// `CREATE TABLE IF NOT EXISTS` por cada pintada de la pantalla.
  static Future<void> asegurar(BaseLocal base) =>
      _listas[base] ??= _crear(base);

  static Future<void> _crear(BaseLocal base) async {
    for (final sentencia in _sentencias) {
      await base.customStatement(sentencia);
    }
  }

  /// Avisa a Drift de que estas tablas cambiaron. Hace falta a mano porque no
  /// son tablas suyas: sin esto, lo que este mirando la pantalla no se entera
  /// de que la tarjeta se movio.
  static void avisarDeCambio(BaseLocal base) => base.notifyUpdates({
    const TableUpdate(columnas),
    const TableUpdate(colocaciones),
  });
}

final Expando<Future<void>> _listas = Expando<Future<void>>('tablas tablero');
