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
//
// Y HAY UN CUARTO CONSUMIDOR, QUE NO ES DE AQUI: el servidor
// (`api/internal/cotizar/almacen.go`, `ElegirAlmacen`), que es quien resuelve
// «Armar la ruta de esta zona» cuando se pulsa en la WEB. Hasta el 24/09/2026
// elegia distinto —no filtraba `activo` y desempataba por el orden de la lista
// en vez de por el nombre—, asi que el mismo boton daba dos kilometrajes segun
// se pulsara en el navegador o en el telefono, y de esos km sale el cobro.
// Jose: «no puede dar distinto, debe dar igual. ¿Como que distinto si es la
// misma API los dos? No tienen que elegir distinto, eso debe dar igual en todos
// los datos. Es un lugar distinto pero ya mas nada.» Lo que ata los dos
// lenguajes es `docs/almacen-de-origen.casos.json`, el MISMO fichero que leen
// `test/nucleo/almacenes/almacen_de_origen_casos_compartidos_test.dart` y
// `api/internal/cotizar/almacen_casos_compartidos_test.go`.
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
///    de rutas y el paso a paso del Panel. **Y desde el 24/09/2026 tambien el
///    servidor**: `internal/cotizar` no filtraba por activo a proposito y era el
///    unico de los cuatro que no lo hacia. Un almacen dado de baja con
///    coordenadas BUENAS es el caso mas caro que hay: la cuenta sale, el numero
///    es creible y ninguna pantalla lo desmiente.
///
/// ## Cual de los que sirven
///
/// La misma regla que `/api/quote/home-delivery` y que `GET /api/customers`:
///
///  1. de los que sirven, el `principal`;
///  2. si hay varios o ninguno, el primero por **nombre ascendente**;
///  3. si no sirve ninguno, **no hay desde donde medir** — y eso se dice, no se
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

  // AQUI HUBO UNA TERCERA FORMA, `sirveParaMedir($WarehousesTable w)`, una
  // version tipada de Drift de estas mismas condiciones. Se quito el
  // 24/09/2026 porque **no tenia ni una llamada** en `lib` ni en `test`: el
  // auditor le quito el `activo` y le hizo aceptar el (0,0) y las dos
  // mutaciones salieron VERDES. Una regla que nadie ejecuta no es una tercera
  // forma de la misma cosa, es una cuarta respuesta esperando a separarse de
  // las otras sin que salte nada — el §3-bis otra vez. Quedan dos, y las dos
  // estan cazadas. Si algun dia hace falta filtrar en una consulta tipada, se
  // escribe entonces y con su prueba al lado.

  /// El elegido de una lista ya filtrada por sucursal. `null` = no hay ninguno
  /// del que salir.
  ///
  /// EL DESEMPATE VA AQUI DENTRO, no en quien llama. Antes esto devolvia «el
  /// primero de la lista» cuando ninguno era principal, y el orden se lo daba
  /// el `ORDER BY` de [de]. El servidor recibe su lista de Accesos por HTTP y
  /// no tiene ese `ORDER BY`, asi que los dos lados podian elegir almacenes
  /// distintos de los mismos datos sin que nada fallara — lo mismo que pasaba
  /// con el `activo`. Con el desempate dentro, la respuesta sale de los datos y
  /// no de quien sirvio la lista. El `nombre` desempata al `principal` y el
  /// `id` al `nombre`, que es lo unico que queda cuando dos almacenes se llaman
  /// igual.
  static Almacen? elegir(Iterable<Almacen> almacenes) {
    final sirven = almacenes.where(_sirve).toList();
    if (sirven.isEmpty) return null;
    sirven.sort((a, b) {
      if (a.principal != b.principal) return a.principal ? -1 : 1;
      final porNombre = a.nombre.compareTo(b.nombre);
      if (porNombre != 0) return porNombre;
      return a.id.compareTo(b.id);
    });
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
  /// El desempate —`principal` primero y luego el nombre— lo pone la consulta y
  /// lo vuelve a poner [elegir], que es quien manda: dos lecturas seguidas
  /// tienen que dar siempre el mismo o los kilometros de la misma tarjeta
  /// bailan solos. El `ORDER BY` de aqui es el mismo criterio escrito en SQL.
  ///
  /// Aviso para quien venga a mutar esto: el `ORDER BY` de aqui y el orden de
  /// [elegir] **se tapan el uno al otro**, asi que quitar cualquiera de los dos
  /// por separado sale en verde y no es un fallo de las pruebas: es que la
  /// respuesta sigue siendo la buena. El `ORDER BY` se queda porque una lista
  /// que ya llega ordenada se lee igual en un volcado que en la pantalla; el
  /// que decide es [elegir], y lo que lo caza —con las listas dadas al reves a
  /// proposito— esta en `docs/almacen-de-origen.casos.json` y en
  /// `test/pantallas/tablero/las_tres_pantallas_contestan_igual_test.dart`.
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

  // AQUI ESTABA `bajaronLosAlmacenes`, que preguntaba a la frescura si esta
  // coleccion habia bajado alguna vez. Se quito el 25/09/2026 al quedarse sin
  // una sola llamada, que es la misma razon por la que se fue `sirveParaMedir`
  // el 24: una regla que nadie ejecuta es una respuesta mas esperando a
  // separarse de las otras sin que salte nada (`CLAUDE.md` §3-bis).
  //
  // Lo que hacia lo hace ahora, mejor, mirar la tabla: **sin bajada no hay
  // filas**, asi que una tabla vacia ya dice «no se sabe» sin tener que
  // preguntarselo a nadie. Y de paso cubre el caso que la marca no cubria y que
  // costo la pantalla en blanco del 25/09: `bajadaAt` se pone la primera vez y
  // ya no se quita, asi que despues de la primera bajada la marca decia «ya
  // bajaron» tambien en los instantes en que la copia se estaba rehaciendo.
  // Ver `pantallas/tablero/datos/consultas.dart`, `_noHayConQueAfirmarlo`.
}
