import '../base/base.dart';
import '../red/cliente_api.dart';
import '../registro/registro.dart';

/// EL IDENTIFICADOR DE ESTA INSTALACION. Va en cada `POST /sync/subida`.
///
/// Es lo que deja al panel de control decir «Palma lleva desde el martes sin
/// subir» en vez de mirar diez telefonos (`sincronizacion.md` §3).
///
/// ## LO PONE EL SERVIDOR, no el aparato
///
/// `sync/internal/sincro/aparato.go` lo dice con todas las letras: «El
/// identificador lo pone la base y el aparato lo guarda; nunca se lo inventa
/// él. Uno inventado por el teléfono podría repetirse entre dos instalaciones, y
/// entonces dos aparatos compartirían cola, claves de idempotencia y marca de
/// bajada.»
///
/// Hasta el 15/09/2026 esto se inventaba un UUID aqui y lo mandaba. El resultado
/// era que `POST /sync/subida` contestaba **404 «Ese aparato no está
/// registrado»** contra el servidor de verdad: el ciclo corria entero, el
/// trabajo se quedaba guardado, y no subia nada. El alta es lo que faltaba.
///
/// ## Por que el alta va ANTES del primer envio y se recuerda
///
/// El alta abre ademas la fila de estado del panel (`AbrirEstado`), que es lo
/// que hace que un aparato recien dado de alta salga como «nunca ha subido» en
/// vez de no salir. Darla en cada subida crearia un aparato nuevo por envio y
/// llenaria el panel de fantasmas; no darla nunca es el 404 de arriba.
class IdentidadDelAparato {
  IdentidadDelAparato(this._base, {ClienteApi? sync}) : _sync = sync;

  /// La clave en `preferencias`.
  ///
  /// **SOBREVIVE A CERRAR SESION**, y por eso `borrarTodoLoDelDominio()` la
  /// respeta a mano (ver `base.dart`). El aparato es el mismo aparato: si el
  /// identificador muriera con la salida, cada logout daria de alta uno nuevo y
  /// el panel acabaria con una lista de instalaciones fantasma —todas «nunca han
  /// subido»— entre las que no se podria distinguir el telefono que de verdad
  /// lleva tres dias sin aparecer. Y eso es justo lo unico que ese panel sirve
  /// para ver.
  ///
  /// Lo que NO sobrevive es el dominio: los clientes, los pedidos y las
  /// direcciones se borran igual (regla 8). Aqui solo queda un UUID que no dice
  /// nada de nadie.
  static const clave = ClaveDePreferencia.aparato;

  final BaseLocal _base;

  /// El cliente contra `sync`, que es otro servicio y otra URL. Opcional para
  /// poder leer el identificador guardado sin montar red.
  final ClienteApi? _sync;

  /// Se cachea porque esto se pide en cada subida y la respuesta no cambia.
  String? _cache;

  /// El identificador guardado, o `null` si este aparato **no esta dado de
  /// alta**. No inventa nada.
  Future<String?> leer() async {
    final ya = _cache;
    if (ya != null) return ya;

    final fila = await (_base.select(
      _base.preferencias,
    )..where((p) => p.clave.equals(clave))).getSingleOrNull();
    final guardado = fila?.valor;
    if (guardado == null || guardado.isEmpty) return null;
    return _cache = guardado;
  }

  /// El identificador, dando de alta el aparato si hacia falta.
  ///
  /// Lo que lance sale tal cual (`fallos.dart`): sin alta no se puede subir, y
  /// quien llama tiene que poder decir **por que** en vez de tragarselo y dejar
  /// la cola parada sin explicacion.
  Future<String> asegurar({String? nombre}) async {
    final ya = await leer();
    if (ya != null) return ya;
    return _darDeAlta(nombre: nombre);
  }

  /// Olvida el alta de este aparato para que la proxima vez se pida otra.
  ///
  /// Se llama cuando el servidor contesta que el aparato **no esta registrado**:
  /// se lo borraron del registro, o se restauro una copia de la base. No se
  /// toca la cola — el trabajo sigue entero y sube en cuanto haya alta nueva.
  Future<void> olvidar() async {
    _cache = null;
    await (_base.delete(
      _base.preferencias,
    )..where((p) => p.clave.equals(clave))).go();
  }

  Future<String> _darDeAlta({String? nombre}) async {
    final cliente = _sync;
    if (cliente == null) {
      throw StateError('no hay cliente de sync para dar de alta el aparato');
    }

    // La SUCURSAL no se manda: la pone el servidor a partir de la sesion, y
    // mandarla seria ofrecerle a cualquiera darse de alta en otra sucursal y
    // bajar desde ahi (`aparato.go`). El Super Admin es la excepcion y hoy no la
    // usa nadie desde aqui.
    final respuesta = await cliente.mandar<Map<String, Object?>>(
      'POST',
      '/aparato',
      <String, Object?>{'nombre': ?nombre},
    );

    final id = respuesta['aparato'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('el alta del aparato no devolvio `aparato`');
    }

    await _base
        .into(_base.preferencias)
        .insertOnConflictUpdate(
          PreferenciasCompanion.insert(clave: clave, valor: id),
        );
    Registro.info('aparato dado de alta: $id');
    return _cache = id;
  }
}
