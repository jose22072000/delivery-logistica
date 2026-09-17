import 'dart:async';

import 'package:drift/drift.dart' show OrderingTerm, TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../../nucleo/refresco_en_vivo.dart';
import '../../../nucleo/red/fallos.dart';
import '../../../nucleo/plataforma.dart';
import '../../../nucleo/registro/registro.dart';
import '../datos/consultas.dart';
import '../datos/esquema.dart';
import '../datos/modelos.dart';
import '../datos/repositorio.dart';
import '../datos/servicio.dart';

export '../datos/consultas.dart' show FiltrosSinColocar;

final consultasTableroProvider = Provider<ConsultasTablero>(
  (ref) => ConsultasTablero(ref.watch(baseProvider)),
);

final repositorioTableroProvider = Provider<RepositorioTablero>(
  (ref) => RepositorioTablero(
    ref.watch(baseProvider),
    ref.watch(colaProvider),
    reloj: ref.watch(relojProvider),
  ),
);

final servicioTableroProvider = Provider<ServicioTablero>(
  (ref) => ServicioTablero(
    ref.watch(baseProvider),
    ref.watch(clienteApiProvider),
    ref.watch(frescuraProvider),
    reloj: ref.watch(relojProvider),
  ),
);

/// QUE SUCURSAL SE ESTA MIRANDO.
///
/// La del Super Admin cuando ha elegido una; si no, la suya. **Si no hay
/// ninguna no se ensena «todo»**: las columnas son de una sucursal y la cercania
/// se mide desde el almacen de una sucursal, asi que un tablero de las diez
/// mezcladas ordenaria los pedidos de Holguin por su distancia al almacen de
/// Santiago (§2).
final sucursalDelTableroProvider = FutureProvider<String?>((ref) async {
  final mirada = ref.watch(sucursalMiradaProvider);
  if (mirada != null && mirada.isNotEmpty) return mirada;
  final sesion = await ref.watch(almacenSesionProvider).leer();
  return sesion?.sucursalId;
});

/// Los filtros de la mitad izquierda.
class FiltrosTablero extends Notifier<FiltrosSinColocar> {
  @override
  FiltrosSinColocar build() => const FiltrosSinColocar();

  void poner(FiltrosSinColocar filtros) => state = filtros;

  void limpiar() => state = const FiltrosSinColocar();
}

/// LO QUE LA WEB INTENTO GUARDAR Y EL SERVIDOR RECHAZO.
///
/// ## Por que existe
///
/// En la APK un gesto se escribe aqui, se encola y sube cuando hay señal. Si
/// tarda no pasa nada: para eso esta la cola, y el reloj de arriba dice «N sin
/// subir», y ademas hay una bandeja de rechazos. En la web ese reloj se quito
/// —hablarle de trabajo sin conexion a quien esta en un navegador es mentirle,
/// regla 1— y quitarlo sin poner nada deja algo peor: la tarjeta se mueve, el
/// servidor dice que no, y **no se entera nadie** hasta que alguien recarga y
/// la ve volver a su sitio.
///
/// ## Las dos formas en que ya me equivoque aqui, para no repetirlas
///
/// 1. **Esperar al ciclo despues de cada gesto y mirar si la cola quedaba
///    vacia.** Salta en CADA movimiento, porque un apunte esta legitimamente
///    pendiente el instante que va del gesto a la subida. Un aviso que sale
///    siempre deja de leerse. Lo unico inequivoco es un apunte **rechazado**:
///    ahi el servidor contesto que no.
/// 2. **Calcularlo dentro del notifier, al bajar la foto.** Parecia bien y no
///    salia NUNCA en el caso real: bajar la foto ocurre al cambiar de sucursal
///    y con un aviso del canal, y el rechazo llega despues, con la pantalla ya
///    abierta y sin que nadie vuelva a preguntar. Lo cazo el auditor
///    ejecutandolo en el orden de la vida real — y mi prueba no lo cazaba
///    porque sembraba el rechazo ANTES de montar, que es justo la forma que el
///    `CLAUDE.md` §3-ter prohibe.
///
/// Por eso esto es un **stream sobre la tabla**: se entera pase lo que pase y
/// cuando pase, sin depender de que alguien se acuerde de preguntar.
///
/// El motivo va LITERAL, el del servidor: «Ese pedido ya va en otra ruta» le
/// dice a alguien que hacer; «no se pudo guardar» no le dice nada.
final loQueElServidorRechazoProvider = StreamProvider<String?>((ref) {
  // En el aparato esto no sale: alli hay bandeja de rechazos y reloj arriba, y
  // este seria el tercero diciendo lo mismo.
  if (Destino.trabajaSinConexion) return Stream<String?>.value(null);

  final base = ref.watch(baseProvider);
  // La consulta TIPADA y no SQL a mano: `estado` es texto con conversor, no un
  // numero. Escrito a mano con el indice del enum no casaba ninguna fila y el
  // aviso no salia nunca — en verde y sin avisar de nada, que es el peor de los
  // dos fallos posibles aqui.
  return (base.select(base.apuntes)
        ..where((a) => a.estado.equalsValue(EstadoApunte.rechazado))
        ..orderBy([(a) => OrderingTerm.desc(a.orden)])
        ..limit(1))
      .watchSingleOrNull()
      .map((fila) {
        if (fila == null) return null;
        final motivo = fila.motivo;
        return motivo == null || motivo.isEmpty
            ? 'El servidor no aceptó el último cambio.'
            : 'El servidor no aceptó el último cambio: $motivo';
      })
      .handleError((Object e) {
        // Que no se pueda leer la bandeja no puede tumbar el tablero.
        Registro.aviso('tablero: no se pudo mirar si algo fue rechazado: $e');
      });
});

final filtrosTableroProvider =
    NotifierProvider<FiltrosTablero, FiltrosSinColocar>(FiltrosTablero.new);

/// Los camiones de la sucursal, para el «camion previsto» de la columna.
///
/// **Stream y no Future** — 17/09/2026. Era un `FutureProvider` que leia la
/// flota UNA vez y no lo invalidaba nadie: si se leia antes de que bajaran los
/// camiones —que en la web es siempre, porque la base nace vacia en cada
/// carga—, el cajon de «Camion previsto» se quedaba con «Sin camion» toda la
/// sesion, y aunque la flota llegara dos segundos despues la lista cacheada no
/// cambiaba.
///
/// Es el mismo patron congelado que dejo Pedidos sin sus desplegables y el
/// tablero sin sus tarjetas. Aqui se corta de raiz: se vigila la tabla.
final camionesProvider = StreamProvider<List<Vehiculo>>((ref) {
  final base = ref.watch(baseProvider);

  Future<List<Vehiculo>> mirar() async {
    final sucursalId = await ref.read(sucursalDelTableroProvider.future);
    final todos = await base.select(base.vehicles).get();
    return todos
        .where((v) => sucursalId == null || v.branchId == sucursalId)
        .toList(growable: false);
  }

  return () async* {
    yield await mirar();
    yield* base
        .tableUpdates(TableUpdateQuery.onTable(base.vehicles))
        .asyncMap((_) => mirar());
  }();
});

/// De cuando son los datos del tablero. Va arriba, con todas las letras: un
/// tablero que parece vivo y lleva seis horas congelado es peor que uno que
/// avisa (§6).
final vistoAtProvider = StreamProvider<DateTime?>(
  (ref) => ref.watch(frescuraProvider).laMasVieja(const [
    EsquemaTablero.coleccionColumnas,
    EsquemaTablero.coleccionColocaciones,
  ]),
);

/// EL TABLERO. Siempre desde la base local, con red y sin ella.
class TableroDelDia extends AsyncNotifier<Tablero> {
  /// La lectura que esta en curso, si la hay.
  Future<void>? _enCurso;

  /// Llego un aviso mientras se leia: hay que volver a leer al terminar.
  bool _otraVez = false;

  @override
  Future<Tablero> build() async {
    final sucursalId = await ref.watch(sucursalDelTableroProvider.future);
    if (sucursalId == null) {
      return const Tablero.imposible('Elige una sucursal para ver su tablero');
    }
    final filtros = ref.watch(filtrosTableroProvider);
    final base = ref.watch(baseProvider);

    // CON CONEXION, DEL SERVIDOR. Al abrir el tablero y al cambiar de sucursal —
    // y SOLO entonces.
    //
    // **La APK conectada hace lo mismo que la web.** Esa es la arquitectura
    // entera, en una frase de Jose: «cuando las apk estén conectadas deben hacer
    // lo mismo, estar directas a la base de datos del servidor; esto [la copia]
    // es sólo para cuando se quiten de una red y no puedan ver la base de datos
    // del servidor: ahí es donde entra el sync».
    //
    // ## POR SUCURSAL Y NO POR CADA `build`
    //
    // `build` mira tambien `filtrosTableroProvider`, asi que **cada filtro lo
    // vuelve a ejecutar**. Sin esta guarda, abrir el cajon de filtros y tocar
    // cuatro cosas eran cuatro descargas completas del tablero: la pantalla en
    // blanco, la rueda girando y una ida y vuelta por la conexion de alla —que el
    // propio cliente documenta en 55 s en el caso normal y 115 s en el peor—
    // **por un filtro que es local y no necesita servidor para nada**.
    //
    // ## AQUI Y NO EN `_leer`, o es un bucle
    //
    // `descargar` ESCRIBE en las tablas del tablero, y ahi abajo hay un
    // `tableUpdates` que llama a `refrescar()` con cada escritura. Pidiendolo en
    // cada lectura: descargar → cambian las tablas → refrescar → leer →
    // descargar… sin parar.
    //
    // Lo demas ya esta cubierto: el ciclo del sincronizador, el canal en vivo y
    // el boton de refrescar.
    if (sucursalId != _sucursalYaBajada) {
      _sucursalYaBajada = sucursalId;
      // El aviso de la sucursal anterior se va: «hay 1 zona sin subir» de Holguin
      // no es verdad en el tablero de La Habana.
      _porQueNoSeRefresca = null;
      _yaSeReintento = false;
      await _traerDelServidor(sucursalId);
    }

    // Y EL AVISO EN VIVO DEL SERVIDOR.
    //
    // Sin esto el canal funcionaba y no servia de nada. El aviso disparaba el
    // ciclo de sincronizacion, y **el tablero no viaja en el ciclo**: la bajada
    // por diferencias sirve pedidos, clientes, rutas y catalogo, y las zonas se
    // piden aparte con `GET /api/board`, que sólo se llamaba al abrir la
    // pantalla. Se vio con el telefono delante: la zona subia con un 201, el
    // servidor registraba la conexion abierta, y la web seguia igual hasta que
    // pasaba el temporizador de dos minutos.
    //
    // Se mira el TIPO: un cambio de clientes o de catalogo no tiene por que
    // costar una foto entera del tablero.
    //
    // `descargar` trae y escribe, y esa escritura despierta al `tableUpdates` de
    // aqui abajo, que repinta. No hay bucle: la bajada no cambia nada de lo que
    // `build` observa.
    final enVivo = ref
        .watch(avisosDelServidorProvider)
        // La constante, no el literal. Era el ultimo sitio de `app/lib` que
        // comparaba a mano, y el docstring de `CambioEnVivo` ya lo nombraba
        // como el motivo por el que se creo — o sea, un comentario que daba por
        // hecho un cambio que no se habia hecho.
        .where((tipo) => tipo == CambioEnVivo.tablero)
        .listen((_) async {
          await _traerDelServidor(sucursalId);
          await refrescar();
        });
    ref.onDispose(enVivo.cancel);

    final sub = base
        .tableUpdates(
          TableUpdateQuery.allOf([
            TableUpdateQuery.onTableName(EsquemaTablero.columnas),
            TableUpdateQuery.onTableName(EsquemaTablero.colocaciones),
            TableUpdateQuery.onTable(base.orders),
            // ALMACENES Y SUCURSALES, que faltaban y dejaban la pantalla muerta.
            //
            // El tablero se ordena desde el punto del que sale la mercancia. Si
            // ese almacen todavia no esta en la copia, `_leer` devuelve «La
            // Habana no tiene ningun almacen con coordenadas» — que ademas es
            // FALSO: lo tiene, lo que pasa es que todavia no habia bajado.
            //
            // Mientras la copia era un fichero que sobrevivia, eso casi nunca se
            // veia: los almacenes ya estaban de la vez anterior. **En la web ya
            // no**: desde que su base es en memoria, cada carga empieza vacia, y
            // sin esto la pantalla se quedaba con ese mensaje **para siempre** —
            // `build` no se vuelve a ejecutar solo, y los almacenes llegan por el
            // ciclo, que toca otra tabla.
            TableUpdateQuery.onTable(base.warehouses),
            TableUpdateQuery.onTable(base.branches),
            // LA COLA, para enterarse de cuando deja de haber trabajo sin subir.
            //
            // El tablero se niega a bajar mientras quede algo sin subir —para no
            // pisarlo, que es la regla que no se negocia— y lo DICE arriba: «No
            // se actualiza: hay 1 cambio sin subir». Ese texto se escribia al
            // intentar la bajada y **no lo recalculaba nadie**: el apunte subia
            // cuatro segundos despues y el cartel se quedaba puesto.
            //
            // Jose, 17/09/2026, con el telefono delante: «ahi en el movil me
            // sale como que no se ha subido aun, ¿por que razon me sale eso si
            // ya esta?».
            TableUpdateQuery.onTable(base.apuntes),
          ]),
        )
        .listen((_) => unawaited(_alCambiarLasTablas(sucursalId)));
    ref.onDispose(sub.cancel);

    return _leer(sucursalId, filtros);
  }

  /// Algo cambio en las tablas que pinta el tablero. Casi siempre es repintar y
  /// ya; la excepcion es la carrera de la web.
  ///
  /// **La carrera:** la web abre con la base vacia, el tablero pide `/board`
  /// nada mas pintarse y los pedidos llegan despues por el ciclo, que es otro
  /// camino. Las tarjetas llegan primero y se caen todas —una colocacion
  /// necesita su pedido—, y como la foto no se vuelve a pedir, la zona se queda
  /// a cero con sus pedidos en «Sin colocar». Eso es lo que vio Jose: «Vista»
  /// con 6 pedidos en el telefono y «Vista (0)» en la web.
  ///
  /// Aqui es donde se cierra: la llegada de los pedidos ES una escritura en la
  /// tabla `orders`, o sea este mismo aviso. Se vuelve a pedir la foto **una
  /// sola vez por sucursal**, que es lo que hace falta y no mas.
  Future<void> _alCambiarLasTablas(String sucursalId) async {
    // YA NO QUEDA NADA SIN SUBIR: se vuelve a intentar la bajada que se negó.
    //
    // Sin esto el cartel de «no se actualiza» se queda puesto hasta que alguien
    // pulse refrescar o cambie de sucursal, diciendo algo que dejó de ser verdad
    // hace rato. Y el tablero, mientras, sin bajar.
    if (_porQueNoSeRefresca != null && await _yaNoQuedaNadaSinSubir()) {
      Registro.info('tablero: ya subió lo que faltaba; se vuelve a bajar');
      await _traerDelServidor(sucursalId);
    }
    if (_faltabanPedidos && !_yaSeReintento) {
      _yaSeReintento = true;
      Registro.info(
        'tablero: la foto traía tarjetas sin pedido y los pedidos ya están; '
        'se vuelve a pedir',
      );
      await _traerDelServidor(sucursalId);
    }
    await refrescar();
  }

  Future<Tablero> _leer(String sucursalId, FiltrosSinColocar filtros) async {
    final consultas = ref.read(consultasTableroProvider);
    // Antes de leer, los `local-…` que ya tengan id de verdad. Si no, la
    // pantalla sigue ensenando el provisional hasta la proxima bajada.
    await ref.read(repositorioTableroProvider).asentarProvisionales();

    final nombre = await consultas.nombreDeSucursal(sucursalId);
    final AlmacenOrigen almacen;
    try {
      almacen = await consultas.almacenDe(sucursalId);
    } on SinAlmacenConCoordenadas catch (e) {
      // Se ordena desde el sitio del que sale la mercancia o no se ordena: no
      // se inventa un punto de partida.
      return Tablero.imposible(
        e.mensaje,
        sucursalId: sucursalId,
        sucursalNombre: nombre,
      );
    }
    return Tablero(
      sucursalId: sucursalId,
      sucursalNombre: nombre,
      almacen: almacen,
      columnas: await consultas.columnas(sucursalId),
      colocados: await consultas.colocados(sucursalId, almacen),
      avisos: await consultas.avisos(sucursalId),
      sinColocar: await consultas.sinColocar(
        sucursalId,
        almacen,
        filtros: filtros,
      ),
      desaparecidos: await consultas.desaparecidos(),
      vistoAt:
          (await ref
                  .read(frescuraProvider)
                  .leer(EsquemaTablero.coleccionColocaciones))
              ?.bajadaAt,
    );
  }

  /// Vuelve a leer la base **sin pintar el cargando**: lo que acaba de moverse
  /// no puede parpadear.
  ///
  /// Si ya hay una lectura en marcha se APUNTA que hay que volver a leer y se
  /// devuelve la misma espera, en vez de descartar el aviso. Descartarlo deja
  /// la pantalla ensenando lo de antes del ultimo cambio, que es exactamente el
  /// fallo que nadie sabe reproducir: «a veces la tarjeta se queda en la
  /// columna vieja». Y devolver la espera buena es lo que hace que quien llama
  /// —un gesto, o una prueba— pueda fiarse de que al volver ya esta puesto.
  /// La sucursal cuya foto ya se pidio. Sin esto, cada filtro era una descarga.
  String? _sucursalYaBajada;

  /// La ultima foto trajo tarjetas que no se pudieron poner: les faltaba el
  /// pedido. Se vuelve a pedir **una vez**, cuando los pedidos lleguen.
  bool _faltabanPedidos = false;

  /// Que ya se reintento por esto en esta sucursal. Es el tope: sin el, una
  /// tarjeta de un pedido que este aparato no va a tener nunca —archivado, de
  /// otra sucursal— pediria la foto entera con cada escritura de la tabla de
  /// pedidos, para siempre.
  bool _yaSeReintento = false;

  /// ¿Se vació la cola? Es la señal de que el motivo por el que no se bajaba ya
  /// no existe.
  ///
  /// Se pregunta por lo MISMO que preguntó la negativa —lo pendiente y lo que
  /// nació aquí y no está arriba—, que es lo que mira `descargar`. Preguntar
  /// sólo por la cola dejaría el cartel puesto cuando lo que queda es una zona
  /// huérfana, y al revés.
  Future<bool> _yaNoQuedaNadaSinSubir() async {
    try {
      return await ref.read(baseProvider).cuantosPendientes() == 0;
    } on Object catch (e) {
      Registro.aviso('tablero: no se pudo mirar si queda algo sin subir: $e');
      return false;
    }
  }

  /// Trae la foto del servidor y **se queda con el porque si no se pudo**.
  ///
  /// ## Lo que se traga y lo que NO — 17/09/2026
  ///
  /// `FalloDeRed` es lo normal sin señal y se sigue con lo de aqui, que es para
  /// lo que esta la copia. Lo demas hay que cogerlo tambien, y faltaba:
  ///
  ///  * un **403** —«esa sucursal no es tuya»— salia de `build` y el future del
  ///    provider **no se completaba nunca**: la pantalla se quedaba con la rueda
  ///    girando para siempre, sin el mensaje del servidor y **sin pintar la copia
  ///    local, que lo tenia todo**;
  ///  * un **401** terminal, igual;
  ///  * y un cuerpo que no se entiende llegaba a la pantalla de error con un
  ///    `type 'Null' is not a subtype of type 'String'`, que no le dice nada a
  ///    nadie.
  ///
  /// Ninguna de esas tres puede impedir ver el tablero: lo que hay en el aparato
  /// se pinta igual, y lo que pasó se DICE arriba.
  Future<void> _traerDelServidor(String sucursalId) async {
    try {
      final r = await ref.read(servicioTableroProvider).descargar(sucursalId);
      // Y si la bajada se NEGO —queda trabajo sin subir—, se dice. Antes se
      // tiraba el resultado y la barra enseñaba «Visto por última vez a las …»
      // con una hora congelada, como si estuviera al día.
      _porQueNoSeRefresca = r.porQue;
      // Tarjetas que el servidor mandó y no se pudieron poner porque su pedido
      // todavía no está en esta base. Se apunta para volver a pedir la foto en
      // cuanto lleguen; el porqué, en `ResultadoDeBajarElTablero`.
      _faltabanPedidos = r.tarjetasSinPedido > 0;
    } on FalloDeRed catch (e) {
      _porQueNoSeRefresca = null;
      Registro.info(
        'tablero: sin conexión al abrir, se sigue con lo de aquí ($e)',
      );
    } on Rechazo catch (e) {
      // El literal del servidor, que es lo único que le dice a alguien qué hacer.
      _porQueNoSeRefresca = e.mensaje;
      Registro.aviso('tablero: el servidor dijo que no al bajar: ${e.mensaje}');
    } on SesionMuerta catch (e) {
      _porQueNoSeRefresca = 'la sesión se perdió: hace falta volver a entrar';
      Registro.aviso('tablero: sesión muerta al bajar ($e)');
    } on Object catch (e, pila) {
      // EL SUELO. Cualquier otra cosa —un cuerpo que no cuadra, un fallo al
      // escribir— deja el tablero con lo que hay, no con una rueda eterna.
      _porQueNoSeRefresca = 'no se pudo traer del servidor';
      Registro.fallo('tablero: no se pudo bajar: $e', e, pila);
    }
  }

  Future<void> refrescar() {
    final enCurso = _enCurso;
    if (enCurso != null) {
      _otraVez = true;
      return enCurso;
    }
    final futuro = _bucleDeLectura();
    _enCurso = futuro;
    return futuro;
  }

  Future<void> _bucleDeLectura() async {
    try {
      do {
        _otraVez = false;
        // El aviso puede llegar cuando la pantalla ya se fue: el `Stream` de
        // Drift no se calla al instante. Escribir en un provider muerto revienta
        // con un error que no dice nada de lo que pasaba.
        if (!ref.mounted) return;
        final sucursalId =
            state.value?.sucursalId ??
            await ref.read(sucursalDelTableroProvider.future);
        if (sucursalId == null || sucursalId.isEmpty) return;
        final tablero = await _leer(
          sucursalId,
          ref.read(filtrosTableroProvider),
        );
        if (!ref.mounted) return;
        state = AsyncValue<Tablero>.data(tablero);
      } while (_otraVez);
    } on Object catch (e, pila) {
      if (ref.mounted) state = AsyncValue<Tablero>.error(e, pila);
    } finally {
      _enCurso = null;
    }
  }

  /// Pide el tablero al servidor. Sin senal **no es un fallo**: se sigue con lo
  /// que hay en el aparato, que es justo para lo que esta.
  /// Lo ultimo que impidio refrescar, para poder DECIRLO. `null` = nada lo
  /// impide.
  ///
  /// Sin esto, pulsar «actualizar» con trabajo sin subir no hacia nada visible:
  /// la negativa se escribia en el registro. Quien estaba delante no sabia si es
  /// que no habia cambios o que la aplicacion se estaba protegiendo, y volvia a
  /// pulsar.
  String? get porQueNoSeRefresca => _porQueNoSeRefresca;
  String? _porQueNoSeRefresca;

  Future<void> bajarDelServidor() async {
    final sucursalId = state.value?.sucursalId;
    if (sucursalId == null || sucursalId.isEmpty) return;
    try {
      final r = await ref.read(servicioTableroProvider).descargar(sucursalId);
      _porQueNoSeRefresca = r.porQue;
      await refrescar();
    } on FalloDeRed catch (e) {
      // SIN SEÑAL NO HAY NADA QUE AVISAR, y el cartel viejo se va.
      //
      // Sin esto se quedaba pegado: la aplicación se negaba una vez con trabajo
      // sin subir, se subía la cola, se volvía a pulsar sin señal, y el cartel
      // seguía en pantalla diciendo algo que ya no era verdad. Un aviso que no
      // se retira deja de ser un aviso.
      _porQueNoSeRefresca = null;
      Registro.info('tablero: sin conexion, se sigue con lo de aqui ($e)');
    }
  }

  // ---------------------------------------------------------------------
  // Los gestos. Ninguno llama a nadie: escriben aqui y van a la cola.
  // ---------------------------------------------------------------------

  Future<void> colocar({
    required String pedidoId,
    required String columnaId,
    int? posicion,
  }) async {
    await ref
        .read(repositorioTableroProvider)
        .colocar(pedidoId: pedidoId, columnaId: columnaId, posicion: posicion);
    await refrescar();
  }

  Future<void> quitar(String pedidoId) async {
    await ref.read(repositorioTableroProvider).quitar(pedidoId);
    await refrescar();
  }

  Future<String> crearColumna(String nombre, {String? vehiculoId}) async {
    final sucursalId = state.value?.sucursalId;
    if (sucursalId == null || sucursalId.isEmpty) {
      throw const FaltaElegirSucursal();
    }
    final id = await ref
        .read(repositorioTableroProvider)
        .crearColumna(
          sucursalId: sucursalId,
          nombre: nombre,
          vehiculoId: vehiculoId,
        );
    await refrescar();
    return id;
  }

  Future<void> renombrar(String columnaId, String nombre) async {
    await ref
        .read(repositorioTableroProvider)
        .renombrarColumna(columnaId, nombre);
    await refrescar();
  }

  Future<void> elegirCamion(String columnaId, String? vehiculoId) async {
    await ref
        .read(repositorioTableroProvider)
        .elegirCamion(columnaId, vehiculoId);
    await refrescar();
  }

  Future<void> reordenar(List<String> idsEnOrden) async {
    final sucursalId = state.value?.sucursalId;
    if (sucursalId == null || sucursalId.isEmpty) return;
    await ref
        .read(repositorioTableroProvider)
        .reordenarColumnas(sucursalId, idsEnOrden);
    await refrescar();
  }

  Future<int> vaciar(String columnaId) async {
    final cuantos = await ref
        .read(repositorioTableroProvider)
        .vaciarColumna(columnaId);
    await refrescar();
    return cuantos;
  }

  Future<int> moverTodo(String origenId, String destinoId) async {
    final cuantos = await ref
        .read(repositorioTableroProvider)
        .moverTodo(origenId, destinoId);
    await refrescar();
    return cuantos;
  }

  Future<void> borrarColumna(
    String columnaId, {
    bool vaciar = false,
    String? destinoId,
  }) async {
    await ref
        .read(repositorioTableroProvider)
        .borrarColumna(columnaId, vaciar: vaciar, destinoId: destinoId);
    await refrescar();
  }

  Future<String> armarRuta(String columnaId, {String? nombre}) async {
    final tablero = state.value;
    if (tablero == null || tablero.problema != null) {
      throw const FaltaElegirSucursal();
    }
    final rutaId = await ref
        .read(repositorioTableroProvider)
        .armarRuta(
          columnaId: columnaId,
          origen: tablero.almacen,
          sucursalId: tablero.sucursalId,
          nombre: nombre,
        );
    await refrescar();
    return rutaId;
  }

  /// El aviso de los pedidos que ya no estan en PEDIDO se da una vez.
  Future<void> olvidarDesaparecidos() async {
    await ref.read(repositorioTableroProvider).olvidarDesaparecidos();
    await refrescar();
  }
}

final tableroProvider = AsyncNotifierProvider<TableroDelDia, Tablero>(
  TableroDelDia.new,
);
