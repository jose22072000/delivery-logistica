import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../../nucleo/red/fallos.dart';
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

final filtrosTableroProvider =
    NotifierProvider<FiltrosTablero, FiltrosSinColocar>(FiltrosTablero.new);

/// Los camiones de la sucursal, para el «camion previsto» de la columna.
final camionesProvider = FutureProvider<List<Vehiculo>>((ref) async {
  final sucursalId = await ref.watch(sucursalDelTableroProvider.future);
  final base = ref.watch(baseProvider);
  final todos = await base.select(base.vehicles).get();
  return todos
      .where((v) => sucursalId == null || v.branchId == sucursalId)
      .toList(growable: false);
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
    // AL CAMBIAR DE SUCURSAL, el aviso de la anterior se va. `build` se rehace
    // cuando cambia `sucursalDelTableroProvider`, así que éste es el sitio.
    // Arrastrar «hay 1 zona sin subir» de Holguín al tablero de La Habana es
    // decir algo que ahí no es verdad.
    _porQueNoSeRefresca = null;
    final sucursalId = await ref.watch(sucursalDelTableroProvider.future);
    if (sucursalId == null) {
      return const Tablero.imposible('Elige una sucursal para ver su tablero');
    }
    final filtros = ref.watch(filtrosTableroProvider);

    // Lo que cambie por debajo —una bajada que trae pedidos nuevos, una ruta
    // que se lleva unos cuantos— tiene que verse sin que nadie tire de la
    // pantalla. Las tablas del tablero no son de Drift, asi que se escuchan por
    // su nombre.
    final base = ref.watch(baseProvider);
    final sub = base
        .tableUpdates(
          TableUpdateQuery.allOf([
            TableUpdateQuery.onTableName(EsquemaTablero.columnas),
            TableUpdateQuery.onTableName(EsquemaTablero.colocaciones),
            TableUpdateQuery.onTable(base.orders),
          ]),
        )
        .listen((_) => unawaited(refrescar()));
    ref.onDispose(sub.cancel);

    return _leer(sucursalId, filtros);
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
      final r = await ref
          .read(servicioTableroProvider)
          .descargar(sucursalId);
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
