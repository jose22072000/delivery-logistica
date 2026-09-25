// LA BAJADA DE ALMACENES NO DEJA LA TABLA VACÍA NI UN INSTANTE.
//
// Esta bajada reemplaza la copia entera —Accesos no da marca de cambio ni dice
// qué borró, así que la lista que llega ES la verdad— y hasta el 25/09/2026 lo
// hacía de la manera fácil: `DELETE` de toda la tabla y a rellenar. Dos cosas
// caras salieron de ahí, y las dos se prueban aquí.
//
// **1 · El hueco.** Mientras esa transacción corría, la tabla estaba vacía, y el
// Tablero —que pregunta desde qué almacén mide en cuanto se pinta— leía justo
// ahí y ponía la pantalla en blanco acusando: «Camagüey no tiene ningún almacén
// con coordenadas». Y no era raro: **el ciclo entero corre en cada cambio de
// sucursal**, así que salía cada vez que Jose cambiaba arriba. Reproducido en la
// web con Granma, Holguín y Camagüey; las tres lo tienen en Accesos. La otra
// mitad del arreglo, la del que lee, está en
// `test/pantallas/tablero/no_acusa_con_la_copia_a_medias_test.dart`.
//
// **2 · La respuesta vacía.** `CLAUDE.md` §3: una respuesta vacía no es una
// respuesta buena. Accesos caído o un alcance mal resuelto devuelven
// `{"sucursales": []}` con un 200 limpio, y con el `DELETE` de antes eso borraba
// los ocho almacenes de un aparato que estaba perfectamente. Sin almacén no hay
// desde dónde medir: o sea, sin Tablero y sin cotizar domicilios, hasta la
// siguiente bajada buena.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/sincro/bajada.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/servidor_falso.dart';

void main() {
  late BaseLocal base;
  late RegistroDeFrescura frescura;
  final ahora = DateTime(2026, 9, 25, 17);

  late _LoQueSeEjecuto vigia;

  setUp(() {
    // LA BASE CON UN VIGÍA DEL SQL, y no la de siempre.
    //
    // El primer intento de esta prueba miraba la tabla desde un `tableUpdates`
    // para ver si llegaba a estar en cero. **Salía verde con el `DELETE` puesto
    // otra vez**: Drift no suelta los avisos de una transacción hasta que
    // confirma, así que desde fuera el hueco no se ve nunca. Una prueba que no
    // caza la mutación que dice cazar es peor que no tenerla (`CLAUDE.md` §5).
    //
    // Lo que sí se puede mirar es el SQL que se ejecuta: un `DELETE FROM
    // warehouses` **sin `WHERE`** es el hueco, lo vea alguien o no.
    vigia = _LoQueSeEjecuto();
    base = BaseLocal.con(NativeDatabase.memory().interceptWith(vigia));
    frescura = RegistroDeFrescura(base, reloj: () => ahora);
  });
  tearDown(() => base.close());

  /// Una bajada cuyo `/almacenes` contesta lo que se le diga.
  Bajada conAlmacenes(List<Object?> sucursales) => Bajada(
    cliente: clienteFalso((p) async {
      if (p.ruta.endsWith('/almacenes')) {
        return RespuestaFalsa(200, <String, Object?>{
          'sucursales': sucursales,
        });
      }
      return RespuestaFalsa(200, <String, Object?>{
        'hasta': ahora.toIso8601String(),
        'completa': true,
        'cambios': <String, Object?>{},
      });
    }),
    base: base,
    frescura: frescura,
    reloj: () => ahora,
  );

  Map<String, Object?> sucursalCon(String codigo, List<String> ids) =>
      <String, Object?>{
        'codigo': codigo,
        'almacenes': [
          for (final id in ids)
            <String, Object?>{
              'id': id,
              'nombre': 'Almacén $id',
              'latitud': 20.02,
              'longitud': -75.82,
              'principal': true,
            },
        ],
      };

  Future<void> sembrar(String id, String codigo) => base
      .into(base.warehouses)
      .insertOnConflictUpdate(
        WarehousesCompanion.insert(
          id: id,
          sucursalCodigo: codigo,
          nombre: 'Almacén $id',
          lat: const Value(20.02),
          lng: const Value(-75.82),
          principal: const Value(true),
        ),
      );

  Future<List<String>> idsGuardados() async {
    final filas = await base.select(base.warehouses).get();
    return filas.map((f) => f.id).toList()..sort();
  }

  // ─────────────────────────── el hueco ───────────────────────────

  test('la tabla nunca se queda en cero: se pone y luego se quita', () async {
    // El aparato ya tiene los de antes.
    for (final (id, codigo) in const [
      ('a-cam', 'CAM'),
      ('a-stg', 'STG'),
      ('a-hol', 'HOL'),
    ]) {
      await sembrar(id, codigo);
    }

    final puestos = await conAlmacenes([
      sucursalCon('CAM', ['a-cam']),
      sucursalCon('STG', ['a-stg']),
      sucursalCon('HOL', ['a-hol']),
    ]).almacenes();

    expect(puestos, 3);
    expect(await idsGuardados(), ['a-cam', 'a-hol', 'a-stg']);
    expect(
      vigia.vacioLaTablaEntera,
      isFalse,
      reason:
          'un DELETE sin WHERE deja la tabla en cero mientras la transacción '
          'corre, y el Tablero que lea en ese instante se queda en blanco '
          'acusando a la sucursal. Ejecutado: ${vigia.borrados}',
    );
  });

  test('lo que ya no viene SÍ se quita', () async {
    await sembrar('a-cam', 'CAM');
    await sembrar('a-viejo', 'CAM'); // dado de baja en Accesos

    final puestos = await conAlmacenes([
      sucursalCon('CAM', ['a-cam']),
    ]).almacenes();

    expect(puestos, 1);
    expect(
      await idsGuardados(),
      ['a-cam'],
      reason:
          'un almacén borrado en Accesos no puede seguir midiendo aquí: de '
          'ahí sale lo que se le cobra al cliente por el domicilio',
    );
  });

  // ─────────────────── la respuesta vacía (§3) ───────────────────

  test('una respuesta vacía NO borra los almacenes que ya están', () async {
    await sembrar('a-cam', 'CAM');
    await sembrar('a-stg', 'STG');

    final puestos = await conAlmacenes(const []).almacenes();

    expect(puestos, 0);
    expect(
      await idsGuardados(),
      ['a-cam', 'a-stg'],
      reason:
          'Accesos caído contesta 200 con la lista vacía; quedarse sin ningún '
          'almacén es quedarse sin Tablero y sin cotizar domicilios',
    );
  });
}

/// Se queda con los `DELETE` que pasan por aquí, para poder mirarlos después.
///
/// No cambia nada: deja pasar cada sentencia tal cual y sólo la apunta.
class _LoQueSeEjecuto extends QueryInterceptor {
  final borrados = <String>[];

  /// ¿Se borró la tabla de almacenes ENTERA, sin `WHERE` que lo acote?
  bool get vacioLaTablaEntera => borrados.any(
    (s) =>
        s.contains('warehouses') &&
        !s.toLowerCase().contains('where'),
  );

  void _apuntar(String sentencia) {
    if (sentencia.trimLeft().toLowerCase().startsWith('delete')) {
      borrados.add(sentencia);
    }
  }

  @override
  Future<int> runDelete(QueryExecutor executor, String statement, List<Object?> args) {
    _apuntar(statement);
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<void> runCustom(QueryExecutor executor, String statement, List<Object?> args) {
    _apuntar(statement);
    return super.runCustom(executor, statement, args);
  }
}
