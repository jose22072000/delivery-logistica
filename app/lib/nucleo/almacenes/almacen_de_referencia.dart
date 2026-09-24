// DE DONDE SE MIDE, EN UN SOLO SITIO.
//
// Tres pantallas hacen la MISMA pregunta sobre el MISMO dato: «¿tiene esta
// sucursal un almacen del que salir?».
//
//  * el **Panel**, para decir «✓ Al menos un almacen con su punto puesto»;
//  * el **Tablero**, que sin el no se pinta y ensena «<Sucursal> no tiene ningun
//    almacen con coordenadas»;
//  * **Clientes**, que sin el no mide la distancia y lo dice en la ficha.
//
// El 22/09/2026 contestaban tres cosas distintas sobre la misma sucursal, que es
// el patron del `CLAUDE.md` §3-bis: dos preguntas sobre lo mismo que se separan
// sin que salte nada. Cada una se habia escrito por su lado y cada una eligio
// sus condiciones: una pedia `activo`, otra no; una descartaba el (0,0) y la
// otra lo daba por bueno. **Y la que manda —el Tablero— deja la pantalla sin
// usar cuando se equivoca.**
//
// Por eso la regla vive AQUI y una sola vez, en dos formas de la misma cosa:
// [AlmacenDeReferencia.elegir] para quien tiene las filas en la mano y
// [AlmacenDeReferencia.sqlSirveParaMedir] para quien lo pregunta dentro de una
// consulta. Las dos se comparan en
// `test/pantallas/tablero/las_tres_pantallas_contestan_igual_test.dart`, que es
// lo que de verdad las ata: un comentario no falla.
library;

import 'package:drift/drift.dart';

import '../base/base.dart';

/// El almacen desde el que se mide, y las condiciones para serlo.
///
/// ## Las condiciones, y por que cada una
///
///  * **De su sucursal.** `warehouses` guarda la sucursal por CODIGO (`STG`),
///    no por id: viene de Accesos, que es otra base. El id de la sucursal se
///    traduce con `branches.external_id` y no se adivina — una sucursal sin
///    codigo no tiene con que preguntar, y se queda sin almacen, que es lo
///    honesto.
///  * **Con las dos coordenadas.** Media coordenada no es un punto.
///  * **Que no sea (0,0).** Es el golfo de Guinea, no Santiago: un almacen asi
///    no tiene coordenadas, las tiene sin poner. Medir desde ahi da un orden
///    que parece bueno y no lo es, y con esas mismas coordenadas se le cobra el
///    domicilio al cliente.
///  * **Activo.** Es la regla del aparato y la comparten el paso 2 del asistente
///    de rutas y el paso a paso del Panel. (El servidor, en `internal/cotizar`,
///    NO filtra por activo a proposito; cuando eso se unifique se unifica aqui,
///    en un sitio.)
///
/// ## Cual de los que sirven
///
/// La misma regla que `/api/quote/home-delivery` y que `GET /api/customers`:
///
///  1. el primero con `principal` **y** punto;
///  2. si no hay, el primero con punto, principal o no;
///  3. si no hay ninguno, **no hay desde donde medir** — y eso se dice, no se
///     aproxima.
class AlmacenDeReferencia {
  const AlmacenDeReferencia._();

  /// LAS CONDICIONES, EN SQL, para quien no puede traerse las filas.
  ///
  /// El alias de la tabla es `w`. La usa el paso a paso del Panel dentro de un
  /// `EXISTS`, donde hace falta una fila por sucursal en una sola sentencia.
  /// Esta escrito aqui y se interpola para que no pueda separarse de [elegir]:
  /// no viene de fuera ni una letra.
  static const sqlSirveParaMedir =
      'w.activo = 1 '
      'AND w.lat IS NOT NULL AND w.lng IS NOT NULL '
      'AND NOT (w.lat = 0 AND w.lng = 0)';

  /// Las mismas condiciones, para una consulta tipada de Drift.
  static Expression<bool> sirveParaMedir($WarehousesTable w) =>
      w.activo.equals(true) &
      w.lat.isNotNull() &
      w.lng.isNotNull() &
      // `isNotValue` no vale: hay que descartar la PAREJA (0,0), no cada
      // coordenada por su lado. El meridiano de Greenwich pasa por sitios de
      // verdad y la latitud 0 tambien.
      (w.lat.equals(0) & w.lng.equals(0)).not();

  /// El elegido de una lista ya filtrada por sucursal. `null` = no hay ninguno
  /// del que salir.
  static Almacen? elegir(Iterable<Almacen> almacenes) {
    final sirven = almacenes.where(_sirve).toList(growable: false);
    if (sirven.isEmpty) return null;
    for (final a in sirven) {
      if (a.principal) return a;
    }
    return sirven.first;
  }

  static bool _sirve(Almacen a) {
    final lat = a.lat;
    final lng = a.lng;
    if (!a.activo || lat == null || lng == null) return false;
    return !(lat == 0 && lng == 0);
  }

  /// El almacen de referencia de la sucursal cuyo CODIGO es [codigo].
  ///
  /// El orden del desempate —`principal` primero y luego el nombre— va en la
  /// consulta y no en Dart para que dos lecturas seguidas den siempre el mismo,
  /// que es lo que impide que los kilometros de una tarjeta bailen solos.
  static Future<Almacen?> de(BaseLocal base, String? codigo) async {
    if (codigo == null || codigo.isEmpty) return null;
    final filas =
        await (base.select(base.warehouses)
              ..where((w) => w.sucursalCodigo.equals(codigo))
              // `principal` primero: en SQLite es 1/0, asi que descendente.
              ..orderBy([
                (w) => OrderingTerm.desc(w.principal),
                (w) => OrderingTerm.asc(w.nombre),
              ]))
            .get();
    return elegir(filas);
  }

  /// ¿Ha bajado esta coleccion alguna vez a este aparato?
  ///
  /// Separa dos cosas que se ven iguales y no se arreglan igual: «esta sucursal
  /// no tiene almacen» —que se arregla poniendolo— y «los almacenes todavia no
  /// han llegado aqui» —que no se arregla poniendo nada—. El Panel ya hacia esa
  /// distincion ([ComoVa.sinSaber]) y el Tablero no, y por eso el Tablero
  /// acusaba a la sucursal de un hueco que no tenia.
  static Future<bool> bajaronLosAlmacenes(BaseLocal base) async {
    final fila =
        await (base.select(base.frescura)..where(
              (f) =>
                  f.coleccion.equals(Colecciones.almacenes) &
                  f.bajadaAt.isNotNull(),
            ))
            .getSingleOrNull();
    return fila != null;
  }
}
