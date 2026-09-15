import 'package:drift/drift.dart';

import '../base/base.dart';

/// QUE TIENE ESTE APARATO BAJADO DE UNA COLECCION.
///
/// Existe para poder contestar la unica pregunta que separa un dato de un fallo:
/// **¿esto esta vacio, o es que no se ha descargado?**
///
/// Las dos se ven iguales —una lista sin nada— y se arreglan al reves: lo vacio
/// se arregla dando de alta, lo no bajado se arregla trayendo el dia. Quien no
/// puede distinguirlas acaba dando de alta un camion que ya existe.
class CopiaBajada {
  const CopiaBajada({required this.cuantos, this.bajadaAt});

  /// Cuantas filas tiene el aparato de esa coleccion.
  final int cuantos;

  /// Cuando se bajo. `null` = **nunca**, que no es «hace mucho»
  /// (`frescura/reloj_de_datos.dart`).
  final DateTime? bajadaAt;

  /// Se bajo alguna vez.
  bool get seDescargo => bajadaAt != null;

  /// Se miro y de verdad no hay ninguno.
  bool get vacioDeVerdad => seDescargo && cuantos == 0;

  /// El aparato tiene una copia, aunque sea vieja.
  bool get hayCopia => seDescargo && cuantos > 0;
}

/// Mira, en vivo, cuantas filas tiene el aparato de [coleccion] y de cuando son.
///
/// [tabla] es la tabla espejo de esa coleccion. Su nombre entra en el SQL por
/// interpolacion, y se puede: sale de `TableInfo`, o sea del esquema compilado,
/// no de nada que venga de fuera.
Stream<CopiaBajada> copiaBajada(
  BaseLocal base, {
  required String coleccion,
  required TableInfo<Table, Object?> tabla,
}) => base
    .customSelect(
      '''
SELECT (SELECT COUNT(*) FROM ${tabla.actualTableName}) AS cuantos,
       (SELECT f.bajada_at FROM frescura f WHERE f.coleccion = ?1) AS bajada_at
''',
      variables: [Variable<String>(coleccion)],
      readsFrom: {tabla, base.frescura},
    )
    .watchSingle()
    .map(
      (fila) => CopiaBajada(
        cuantos: fila.read<int>('cuantos'),
        bajadaAt: fila.readNullable<DateTime>('bajada_at'),
      ),
    );
