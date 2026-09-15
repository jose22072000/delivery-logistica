import 'package:drift/drift.dart';

import '../base/base.dart';
import '../reloj.dart';

/// De que hora son los datos de cada coleccion.
///
/// Sin esto, una pantalla con datos de anteayer es indistinguible de una al dia,
/// y ese es el modo de fallo que nadie nota: el logistico arma la ruta de ayer
/// convencido de que es la de hoy.
class RegistroDeFrescura {
  RegistroDeFrescura(this._base, {Reloj reloj = relojDelAparato})
    : _reloj = reloj;

  final BaseLocal _base;
  final Reloj _reloj;

  /// Lo escribe la bajada, coleccion a coleccion.
  ///
  /// [hasta] se guarda **tal cual vino**, en texto. No se parsea ni se
  /// recalcula: la marca la pone el servidor, y un `DateTime` de ida y vuelta
  /// puede perder precision y saltarse cambios para siempre sin que nadie lo
  /// note (`sincronizacion.md` §1).
  Future<void> marcar(
    String coleccion, {
    required String? hasta,
    DateTime? bajadaAt,
    bool completa = false,
  }) => _base
      .into(_base.frescura)
      .insertOnConflictUpdate(
        FrescuraCompanion.insert(
          coleccion: coleccion,
          hasta: Value(hasta),
          bajadaAt: Value(bajadaAt ?? _reloj()),
          completa: Value(completa),
        ),
      );

  Future<FilaFrescura?> leer(String coleccion) => (_base.select(
    _base.frescura,
  )..where((f) => f.coleccion.equals(coleccion))).getSingleOrNull();

  Stream<FilaFrescura?> mirar(String coleccion) => (_base.select(
    _base.frescura,
  )..where((f) => f.coleccion.equals(coleccion))).watchSingleOrNull();

  /// La marca que va en el proximo `GET /sync/bajada?desde=…`. `null` = primera
  /// carga completa.
  Future<String?> desde(String coleccion) async =>
      (await leer(coleccion))?.hasta;

  /// La bajada mas VIEJA de todas. Es la que manda en la barra: una pantalla no
  /// esta al dia si una de las colecciones que usa no lo esta.
  Stream<DateTime?> laMasVieja([List<String> colecciones = Colecciones.todas]) {
    final consulta = _base.select(_base.frescura)
      ..where((f) => f.coleccion.isIn(colecciones));
    return consulta.watch().map((filas) => _laMasVieja(filas, colecciones));
  }

  /// LA MISMA PREGUNTA, una vez y sin stream.
  ///
  /// Hace falta para decidir **en seco**: el vigia, al volver la aplicacion
  /// delante, tiene que saber si lo que hay ya tiene edad antes de disparar un
  /// ciclo entero. Ahi no hay nada que pintar ni a quien avisar de los cambios,
  /// asi que un stream sobra — y un `await` sobre el primer valor de un stream
  /// de Drift lo deja abierto detras, que en una prueba de widget es un
  /// temporizador colgado y la sesion entera se va con el.
  Future<DateTime?> laMasViejaAhora([
    List<String> colecciones = Colecciones.todas,
  ]) async {
    final filas = await (_base.select(
      _base.frescura,
    )..where((f) => f.coleccion.isIn(colecciones))).get();
    return _laMasVieja(filas, colecciones);
  }

  static DateTime? _laMasVieja(
    List<FilaFrescura> filas,
    List<String> colecciones,
  ) {
    // Una coleccion que NUNCA se bajo no tiene fila. Eso no es «al dia»: es
    // «sin descargar», y se contesta con null para que el reloj lo diga.
    if (filas.length < colecciones.length) return null;
    final fechas = filas.map((f) => f.bajadaAt).whereType<DateTime>().toList();
    if (fechas.length < colecciones.length) return null;
    fechas.sort();
    return fechas.first;
  }

  /// ¿Se bajo alguna vez esta coleccion?
  ///
  /// Es la pregunta que separa «no hay nada» de «no se ha descargado». Una lista
  /// vacia sin respuesta a esto es un fallo que se lee como un dato (caso S7).
  Future<bool> seDescargo(String coleccion) async =>
      (await leer(coleccion))?.bajadaAt != null;
}
