import 'package:dio/dio.dart';

import '../identidad/almacen_sesion.dart';
import '../identidad/renovador.dart';
import '../registro/registro.dart';
import 'fallos.dart';
import 'interceptor_fallos.dart';
import 'interceptor_sesion.dart';

/// Cuanto se espera entre reintentos, y sólo para `FalloDeRed`.
///
/// Creciente a proposito: en la conexion de alla un reintento inmediato sólo
/// anade ruido a un enlace que ya va justo. Un `Rechazo` **no se reintenta
/// jamas**: el servidor ya dijo que no y repetirlo no lo va a cambiar.
const esperasPorDefecto = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 4),
  Duration(seconds: 15),
  Duration(seconds: 60),
];

/// Un `Dio` por destino (`api`, `sync`, `auth`) con los interceptores de la
/// casa.
///
/// Envuelve a Dio en vez de exponerlo para que ninguna pantalla pueda hacer un
/// `dio.get` sin pasar por la sesion y por la tabla de la regla 5.
class ClienteApi {
  ClienteApi({
    required Dio dio,
    List<Duration> esperas = esperasPorDefecto,
    Future<void> Function(Duration)? esperar,
  }) : _dio = dio,
       _esperas = esperas,
       _esperar = esperar ?? Future<void>.delayed;

  /// El montaje de verdad: crea el Dio, le pone los interceptores EN ORDEN y
  /// devuelve el cliente.
  factory ClienteApi.montar({
    required String baseUrl,
    required AlmacenDeSesion almacen,
    required Renovador renovador,
    String? Function()? sucursalMirada,
    void Function()? alMorirLaSesion,
    List<Duration> esperas = esperasPorDefecto,
    Future<void> Function(Duration)? esperar,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        // 10 s para conectar, 30 s para recibir: la primera bajada de una
        // sucursal grande por la conexion de alla es lenta, y para eso existe
        // `truncado` en el protocolo.
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        contentType: Headers.jsonContentType,
      ),
    );
    dio.interceptors.addAll([
      InterceptorSesion(
        almacen: almacen,
        renovador: renovador,
        dio: dio,
        sucursalMirada: sucursalMirada,
        alMorirLaSesion: alMorirLaSesion,
      ),
      const InterceptorFallos(),
    ]);
    return ClienteApi(dio: dio, esperas: esperas, esperar: esperar);
  }

  final Dio _dio;
  final List<Duration> _esperas;
  final Future<void> Function(Duration) _esperar;

  Dio get dio => _dio;

  Future<T> pedir<T>(String ruta, {Map<String, Object?>? params}) =>
      _conReintento(
        () => _dio.get<T>(ruta, queryParameters: params),
        '$ruta GET',
      );

  Future<T> mandar<T>(String metodo, String ruta, Object? cuerpo) =>
      _conReintento(
        () => _dio.request<T>(
          ruta,
          data: cuerpo,
          options: Options(method: metodo),
        ),
        '$ruta $metodo',
      );

  /// Reintenta **sólo** lo que es red o 5xx.
  ///
  /// Un `Rechazo` sale a la primera y un `SesionMuerta` tambien: reintentar
  /// cualquiera de los dos es perder tiempo y, en el caso del 401, arriesgarse a
  /// una tanda de renovaciones.
  Future<T> _conReintento<T>(
    Future<Response<T>> Function() intento,
    String que,
  ) async {
    var vuelta = 0;
    while (true) {
      try {
        final respuesta = await intento();
        return respuesta.data as T;
      } on DioException catch (e) {
        final fallo = e.error is FalloApi
            ? e.error! as FalloApi
            : InterceptorFallos.traducir(e);

        if (fallo is! FalloDeRed || vuelta >= _esperas.length) throw fallo;

        Registro.aviso(
          'reintento ${vuelta + 1} de $que en ${_esperas[vuelta].inSeconds}s',
        );
        await _esperar(_esperas[vuelta]);
        vuelta++;
      }
    }
  }
}
