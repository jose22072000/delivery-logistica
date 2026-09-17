/// QUE LE FALTA A ESTA SUCURSAL PARA PODER ARMAR UNA RUTA.
///
/// No es una lista de tareas inventada. Son las cuatro cosas **sin las cuales el
/// trabajo del dia no se puede hacer**, y las cuatro se saben mirando la base
/// local — ninguna necesita red, que es justo lo que hace que sirvan en el patio
/// del almacen.
///
/// ## Por que cada una, y en este orden
///
///  1. **El punto de partida de la sucursal** (`branches.origin_configured`).
///     Sin el no hay desde donde medir la distancia hasta el cliente, y la
///     cotizacion se salta esos pedidos enteros
///     (`api/internal/api/cotizacion.go`, `sucursal-sin-punto-de-partida`).
///  2. **Al menos un vehiculo.** Sin el no se termina el paso 3 del asistente de
///     rutas y una columna del tablero no puede llevar camion.
///  3. **Al menos un almacen con punto.** De ahi sale lo que se le cobra al
///     cliente por el domicilio; sin el se cobra desde el sitio equivocado.
///  4. **La tasa de cambio.** Sin ella los importes se quedan en USD.
///
/// El orden es el de dependencia y **no se toca**: sin punto de partida no sirve
/// de nada tener camion, y sin almacen no sirve de nada tener tasa.
///
/// ## Las consultas son LAS MISMAS que las de quien luego se queja
///
/// El conteo de vehiculos filtra por `branch_id` exactamente como
/// `RepositorioRutas.vehiculos`, y el de almacenes pide activo y con
/// coordenadas exactamente como el paso 2 del asistente. Si aqui se contara de
/// otra forma, el paso a paso diria «hecho» y el asistente diria «no hay
/// ninguno» — dos respuestas para la misma pregunta, y la que alguien cree es
/// siempre la equivocada.
library;

import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/frescura/primera_bajada.dart';

/// Cual de los cuatro. Se usa para probarlos por separado y para que la vista
/// no tenga que comparar textos.
enum ClaveDePaso { puntoDePartida, vehiculo, almacen, tasa }

/// Como esta un paso. **Son TRES y no dos**, y ahi esta todo el asunto:
///
///  * [hecho] — se miro y esta.
///  * [falta] — se miro y no esta. Hay que darlo de alta.
///  * [sinSaber] — **no se miro**, porque este aparato no ha descargado esa
///    coleccion todavia. No es lo mismo que [falta] y no se arregla igual: esto
///    se arregla con «Traer el dia», no dando de alta nada. Pintarlos iguales
///    manda a alguien a crear un camion que ya existe.
enum ComoVa { hecho, falta, sinSaber }

/// Uno de los cuatro pasos, ya resuelto contra la base.
class PasoDeConfiguracion {
  const PasoDeConfiguracion({
    required this.clave,
    required this.como,
    required this.titulo,
    required this.paraQue,
    required this.siFalta,
    required this.coleccion,
    this.ruta,
    this.textoDelBoton,
    this.dondeSeArregla,
  });

  final ClaveDePaso clave;
  final ComoVa como;

  /// Que es, en una linea y en las palabras del logistico.
  final String titulo;

  /// Por que hace falta. Una linea.
  final String paraQue;

  /// Que pasa si falta. Es la que decide si alguien lo hace hoy o el mes que
  /// viene.
  final String siFalta;

  /// La coleccion de la bajada de la que sale el dato. Es lo que permite decir
  /// «no se ha descargado» en vez de «no hay».
  final String coleccion;

  /// A donde lleva. **`null` = no se arregla en esta aplicacion**, y entonces
  /// NO se pinta boton: uno que no lleva a ningun sitio ensena a desconfiar del
  /// que si lleva. En su lugar se dice donde se arregla, en [dondeSeArregla].
  final String? ruta;

  final String? textoDelBoton;

  /// Donde se arregla cuando [ruta] es `null`.
  final String? dondeSeArregla;

  /// Lo que se lee debajo del titulo segun como este, **en el aparato**.
  String get explicacion => explicacionEn(PorQueEstaVacio.noSeDescargo);

  /// Lo mismo, sabiendo POR QUE esta vacia la copia.
  ///
  /// Sólo cambia el caso [ComoVa.sinSaber], que es el unico que habla de la
  /// bajada. Los otros dos son del negocio y se dicen igual en los tres
  /// destinos: un almacen que falta, falta en el navegador y en el telefono.
  String explicacionEn(PorQueEstaVacio porQue) => switch (como) {
    ComoVa.hecho => paraQue,
    ComoVa.falta => siFalta,
    ComoVa.sinSaber => switch (porQue) {
      PorQueEstaVacio.noSeDescargo => textoSinDescargar,
      // En la web no hay «aparato» ni gesto de traer el dia: la unica verdad es
      // que esto no llego.
      //
      // Los dos casos de web dicen lo MISMO a proposito, y no es pereza:
      // mientras la bajada va en camino este paso **no se pinta siquiera**
      // (`paso_a_paso.dart`), asi que si se llega hasta aqui es porque ya se
      // dejo de esperar. Un tercer literal seria uno que nadie lee nunca.
      PorQueEstaVacio.todaviaBajando ||
      PorQueEstaVacio.noPudoBajar => textoNoLlego,
    },
  };

  /// El literal de «esto no se ha bajado». Es de la pieza, no de la pantalla,
  /// para que diga lo mismo en los cuatro pasos.
  static const textoSinDescargar =
      'Este aparato no lo ha descargado todavía, así que no se sabe si falta. '
      'Se arregla trayendo el día, no dando nada de alta.';

  /// EL MISMO ESTADO, EN LA WEB. Se dice, sin mandar a nadie a mirar la señal
  /// ni a traer ningun dia: ninguna de las dos cosas existe en un navegador.
  static const textoNoLlego =
      'Esto no se pudo traer, así que no se sabe si falta. No es que no esté '
      'dado de alta: es que no llegó. Prueba a recargar y, si sigue igual, '
      'avisa a la oficina.';
}

/// Los cuatro pasos y la regla de cuando se ensenan.
class ElPasoAPaso {
  const ElPasoAPaso(this.pasos);

  final List<PasoDeConfiguracion> pasos;

  PasoDeConfiguracion paso(ClaveDePaso clave) =>
      pasos.firstWhere((p) => p.clave == clave);

  List<PasoDeConfiguracion> get pendientes =>
      pasos.where((p) => p.como != ComoVa.hecho).toList();

  List<PasoDeConfiguracion> get hechos =>
      pasos.where((p) => p.como == ComoVa.hecho).toList();

  /// Nada bajado: el aparato no sabe nada de nada.
  bool get noSeSabeNada => pasos.every((p) => p.como == ComoVa.sinSaber);

  /// Hay algun paso que **no se ha llegado a mirar**.
  ///
  /// En el aparato es un estado tranquilo —falta traer el dia—; en la web es el
  /// segundo que tarda en entrar la primera bajada, y ahi no se puede
  /// diagnosticar nada todavia. Ver `frescura/primera_bajada.dart`.
  bool get algoSinMirar => pasos.any((p) => p.como == ComoVa.sinSaber);

  /// Hay algo que de verdad FALTA: se miro y no esta.
  ///
  /// Es lo que separa «falta configurar esta sucursal» de «esto todavia no ha
  /// bajado». Sin esta distincion, un aparato al que sólo le falta una
  /// coleccion por bajar acusaba a la sucursal de estar a medio configurar.
  bool get faltaAlgoDeVerdad => pasos.any((p) => p.como == ComoVa.falta);

  /// SI SE PINTA O NO. Las dos unicas veces que no:
  ///
  ///  * **Cuando no falta nada.** Un asistente que sigue ahi cuando ya no hace
  ///    falta es ruido para siempre, y el ruido de siempre se deja de leer.
  ///  * **Cuando el aparato no ha bajado NADA.** Ahi no hay nada que configurar
  ///    todavia: lo primero es traer el dia, y de eso ya se ocupa
  ///    `EstadoDelDia`, que es lo primero de la pantalla. Poner los cuatro pasos
  ///    en «no se sabe» encima del gesto que los resolveria es tapar la
  ///    respuesta con la pregunta.
  bool get seEnsena => pendientes.isNotEmpty && !noSeSabeNada;
}

/// El detector. Una sola consulta y un solo `watch`.
class ConfiguracionPendiente {
  ConfiguracionPendiente(this._base);

  final BaseLocal _base;

  /// Mira la base y devuelve los cuatro pasos, en vivo.
  ///
  /// [sucursalId] es la sucursal de la barra superior; `null` = todas las que
  /// esta persona ve. Con varias a la vista, un paso esta **hecho sólo si lo
  /// esta en todas**: decir que esta hecho porque lo esta en una deja a las
  /// otras siete sin cotizar y sin que nada lo diga.
  Stream<ElPasoAPaso> mirar({String? sucursalId}) {
    // `?1 IS NULL OR …` en vez de dos consultas, como en `consultas_panel.dart`:
    // una sola sentencia, y la version «todas las sucursales» no puede quedarse
    // atras de la filtrada porque son el mismo SQL.
    //
    // Los nombres de coleccion van interpolados y no como variables porque son
    // constantes de `Colecciones`, escritas en el codigo: no viene de fuera ni
    // una letra.
    final sql =
        '''
SELECT
  (SELECT COUNT(*) FROM branches b
     WHERE (?1 IS NULL OR b.id = ?1)) AS sucursales,
  (SELECT COUNT(*) FROM branches b
     WHERE (?1 IS NULL OR b.id = ?1) AND b.origin_configured = 1) AS con_punto,
  (SELECT COUNT(*) FROM vehicles v
     WHERE (?1 IS NULL OR v.branch_id = ?1)) AS vehiculos,
  (SELECT COUNT(*) FROM warehouses w
     WHERE w.activo = 1 AND w.lat IS NOT NULL AND w.lng IS NOT NULL
       AND w.sucursal_codigo IN (
         SELECT b.external_id FROM branches b
          WHERE b.external_id IS NOT NULL
            AND (?1 IS NULL OR b.id = ?1))) AS almacenes,
  -- LA TASA ES DE LA SUCURSAL, y por eso sale de `branches` y no de `settings`.
  --
  -- Este paso se llama «la tasa de cambio de la sucursal» y miraba
  -- `settings.cup_rate`, que es la GLOBAL y vieja de delivery — la que hacía que
  -- Granma enseñara los 685 de La Habana. La API lo dice con todas las letras
  -- (`api/internal/api/ajustes.go`): «los ajustes son GLOBALES… la tasa POR
  -- SUCURSAL es otra cosa y vive en Accesos, no aquí».
  --
  -- Va con el mismo filtro `?1` que los otros tres pasos, así que con varias
  -- sucursales a la vista sólo cuenta como hecho si lo está **en todas**: decir
  -- «hecho» porque una de las ocho tiene tasa deja a las otras siete en dólares
  -- sin que nadie lo sepa.
  --
  -- Y se exige la FECHA, no el número: `cup_rate` puede traer un valor sin que
  -- nadie haya puesto nada, y un número sin fecha no es una tasa.
  (SELECT COUNT(*) FROM branches b
     WHERE (?1 IS NULL OR b.id = ?1)
       AND b.cup_rate_traido_at IS NOT NULL AND b.cup_rate > 0) AS tasa,
  (SELECT COUNT(*) FROM frescura f
     WHERE f.bajada_at IS NOT NULL
       AND f.coleccion = '${Colecciones.sucursales}') AS bajo_sucursales,
  (SELECT COUNT(*) FROM frescura f
     WHERE f.bajada_at IS NOT NULL
       AND f.coleccion = '${Colecciones.vehiculos}') AS bajo_vehiculos,
  (SELECT COUNT(*) FROM frescura f
     WHERE f.bajada_at IS NOT NULL
       AND f.coleccion = '${Colecciones.almacenes}') AS bajo_almacenes,
  (SELECT COUNT(*) FROM frescura f
     WHERE f.bajada_at IS NOT NULL
       AND f.coleccion = '${Colecciones.ajustes}') AS bajo_ajustes
''';

    return _base
        .customSelect(
          sql,
          variables: [Variable<String>(sucursalId)],
          readsFrom: {
            _base.branches,
            _base.vehicles,
            _base.warehouses,
            _base.settings,
            _base.frescura,
          },
        )
        .watchSingle()
        .map(_leer);
  }

  ElPasoAPaso _leer(QueryRow fila) {
    final sucursales = fila.read<int>('sucursales');
    final conPunto = fila.read<int>('con_punto');

    ComoVa como({required bool bajada, required bool esta}) => !bajada
        ? ComoVa.sinSaber
        : esta
        ? ComoVa.hecho
        : ComoVa.falta;

    return ElPasoAPaso([
      PasoDeConfiguracion(
        clave: ClaveDePaso.puntoDePartida,
        coleccion: Colecciones.sucursales,
        como: como(
          bajada: fila.read<int>('bajo_sucursales') > 0,
          // Con cero sucursales bajadas no hay ninguna con punto: falta, y se
          // dice. Una division por cero disfrazada de «hecho» seria peor.
          esta: sucursales > 0 && conPunto == sucursales,
        ),
        titulo: 'El punto de partida de la sucursal',
        paraQue:
            'Es el sitio desde el que se mide la distancia hasta cada cliente.',
        siFalta:
            'Sin él no hay desde dónde medir: los domicilios de esta sucursal '
            'se quedan sin cotizar y los pedidos salen sin precio.',
        // NO lleva a ningun sitio, y por eso no hay boton: el punto de partida
        // lo deja puesto quien da de alta la sucursal en delivery
        // (`POST /api/branches` pone `originConfigured: true`). Ni Almacenes ni
        // ninguna otra pantalla de esta aplicacion lo toca — mandar ahi seria un
        // boton que lleva a un sitio donde el problema no se arregla, que es
        // peor que no tener boton.
        dondeSeArregla:
            'No se pone aquí: lo deja hecho quien da de alta la sucursal. '
            'Pídelo a administración y baja solo con el día.',
      ),
      PasoDeConfiguracion(
        clave: ClaveDePaso.vehiculo,
        coleccion: Colecciones.vehiculos,
        como: como(
          bajada: fila.read<int>('bajo_vehiculos') > 0,
          esta: fila.read<int>('vehiculos') > 0,
        ),
        titulo: 'Al menos un vehículo',
        paraQue: 'Es el camión al que se le carga la ruta del día.',
        siFalta:
            'Sin ninguno no se puede terminar el paso 3 del asistente de rutas, '
            'y una columna del tablero no puede llevar camión.',
        ruta: '/vehicles',
        textoDelBoton: 'Agregar el primer vehículo',
      ),
      PasoDeConfiguracion(
        clave: ClaveDePaso.almacen,
        coleccion: Colecciones.almacenes,
        como: como(
          bajada: fila.read<int>('bajo_almacenes') > 0,
          esta: fila.read<int>('almacenes') > 0,
        ),
        titulo: 'Al menos un almacén con su punto puesto',
        paraQue:
            'Del almacén sale lo que se le cobra al cliente por el domicilio, '
            'y de ahí arranca el camión.',
        siFalta:
            'Sin él se cobra desde el sitio equivocado y el asistente de rutas '
            'no tiene de dónde salir. Un almacén sin coordenadas tampoco sirve.',
        ruta: '/warehouses',
        textoDelBoton: 'Poner el almacén',
      ),
      PasoDeConfiguracion(
        clave: ClaveDePaso.tasa,
        coleccion: Colecciones.ajustes,
        como: como(
          // La tasa viaja con la SUCURSAL, no con los ajustes: se mira si
          // bajaron las sucursales.
          bajada: fila.read<int>('bajo_sucursales') > 0,
          // **La marca de cuando, no el numero.** `cup_rate` puede traer un
          // valor sin que nadie haya puesto nada; sólo `cup_rate_traido_at`
          // —el `traidoAt` que da Accesos— demuestra que hay tasa de verdad.
          //
          // Y `== sucursales`, no `> 0`, por lo mismo que el punto de partida:
          // hoy en Accesos sólo tienen tasa Habana y Santiago. Con «todas» a la
          // vista, decir «hecho» porque dos de las ocho la tienen deja a las
          // otras seis en dolares sin que nadie lo sepa.
          esta: sucursales > 0 && fila.read<int>('tasa') == sucursales,
        ),
        titulo: 'La tasa de cambio de la sucursal',
        paraQue: 'Es lo que pasa los importes de USD a CUP.',
        siFalta:
            'Sin ella los importes sólo se ven en USD. No se convierte nada: '
            'convertir sin tasa es inventarse un número, y un número inventado '
            'acaba cobrado.',
        // Tampoco lleva a ningun sitio, y es la razon por la que existe la
        // regla: la tasa la mantiene Accesos, que la trae de Entrega. Aqui no
        // hay ninguna copia editable a proposito (`reglas-negocio.md` §8): dos
        // tasas para lo mismo se separan en cuanto una se olvida, y el mismo
        // domicilio vale distinto segun donde se mire.
        dondeSeArregla:
            'No se pone aquí: la mantiene Accesos, que la trae de Entrega. '
            'Se arregla allí y baja sola con el día.',
      ),
    ]);
  }
}
