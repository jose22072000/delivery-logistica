import 'package:dio/dio.dart';
import 'package:synchronized/synchronized.dart';

import '../red/fallos.dart';
import '../registro/registro.dart';
import 'almacen_sesion.dart';
import 'sesion.dart';

/// EL CANDADO. Una sola renovacion en vuelo (regla 3).
///
/// Si esta pieza falla deja a diez personas fuera con el trabajo del dia dentro.
/// El refresh es de un solo uso: dos renovaciones a la vez presentan el mismo,
/// el servidor lo lee como robo y **revoca todas las sesiones de la cuenta**.
///
/// En reparto es mas peligroso que en ningun otro sitio de Procovar: el telefono
/// recupera senal y dispara la cola entera de golpe. Veinte peticiones a la vez,
/// veinte 401 a la vez.
///
/// **Hacen falta las DOS mitades y ninguna sirve sola:**
///
///  1. El `Lock`, desde la PRIMERA linea. Sin el, veinte renovaciones
///     simultaneas.
///  2. La comparacion del refresh. Sólo con el `Lock` habria veinte
///     renovaciones **EN FILA**, cada una presentando el refresh que ya gasto la
///     anterior — que para el servidor es exactamente la misma reutilizacion, y
///     revoca igual. Quien llega tarde compara el refresh que traia con el
///     guardado y, si cambio, **reutiliza el resultado de la que ya se hizo**.
///
/// El candado se suelta pase lo que pase (`synchronized` lo garantiza): una
/// renovacion fallida que dejara el candado puesto impediria cualquier intento
/// posterior, y eso es el aparato muerto hasta reinstalar.
class Renovador {
  Renovador(this._crudo, this._almacen);

  /// Dio **SIN** `InterceptorSesion`: renovar no se renueva a si mismo. Con el
  /// interceptor puesto, un 401 del propio `/refresh` dispararia otra
  /// renovacion, que daria otro 401, y asi hasta la pila.
  final Dio _crudo;

  final AlmacenDeSesion _almacen;
  final _candado = Lock();

  /// Cuantas veces se ha llamado de verdad a `POST /refresh`. Es lo que cuenta
  /// el test del candado, y lo que hay que mirar en el registro del servidor
  /// despues de quitar el modo avion: **tiene que ser una**.
  int get renovacionesPedidas => _renovacionesPedidas;
  int _renovacionesPedidas = 0;

  /// Renueva, o devuelve la renovacion que otro ya hizo.
  ///
  /// [vista] es la sesion que tenia en la mano quien pide renovar. Es el dato
  /// que distingue «hay que renovar» de «ya te renovaron mientras esperabas».
  Future<Sesion> renovar(Sesion vista) => _candado.synchronized(() async {
    // ← EL CANDADO, PRIMERA LINEA.
    final actual = await _almacen.leer();

    if (actual == null) {
      // En web el almacen siempre devuelve null: alli la cookie es la sesion y
      // quien la renueva es auth por su cuenta. Si se llega aqui sin nada
      // guardado en un destino que si guarda, no hay con que renovar.
      throw const SesionMuerta('no hay sesion guardada');
    }

    if (actual.refresh != vista.refresh) {
      // Otro renovo mientras esperabamos el candado. Se REUTILIZA su resultado.
      // Esta es la mitad que evita las veinte renovaciones en fila.
      Registro.info('renovacion reutilizada: otro ya la hizo');
      return actual;
    }

    try {
      _renovacionesPedidas++;
      final respuesta = await _crudo.post<Map<String, Object?>>(
        '/refresh',
        data: <String, Object?>{'refresh': actual.refresh},
      );
      final nueva = Sesion.deJson(respuesta.data ?? const <String, Object?>{});
      // El refresh se sustituye ENTERO. El viejo no se guarda nunca.
      await _almacen.guardar(nueva);
      return nueva;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        // El servidor no acepta el refresh: la sesion murio de verdad.
        await _almacen.borrar();
        throw SesionMuerta(_mensajeDe(e));
      }
      // Red o 5xx: **los tokens SE QUEDAN**. Una caida pasajera no puede
      // obligar a entrar otra vez (regla 5, caso I6).
      Registro.aviso('no se pudo renovar, los tokens se quedan: ${e.type}');
      throw FalloDeRed(codigo: e.response?.statusCode, detalle: _mensajeDe(e));
    }
  });

  /// El mensaje literal del servidor, si lo mando. Un refresh reutilizado llega
  /// con su explicacion y esa explicacion tiene que llegar a la pantalla.
  static String? _mensajeDe(DioException e) {
    final datos = e.response?.data;
    if (datos is Map && datos['mensaje'] is String) {
      return datos['mensaje'] as String;
    }
    if (datos is Map && datos['error'] is String) {
      return datos['error'] as String;
    }
    return e.message;
  }
}
