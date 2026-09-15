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
///
/// ## CUANTO PUEDE TARDAR UNA PETICION EN RENDIRSE — 15/09/2026
///
/// Hasta hoy esto era `[1, 4, 15, 60]` con 30 s de recepcion, o sea cinco
/// intentos de hasta 40 s mas 80 s de esperas: **casi cuatro minutos** mirando
/// una rueda antes de que la aplicacion dijera una palabra. Con la conexion de
/// alla ese no es el caso raro, es el de todos los dias, y cuatro minutos
/// delante de una rueda es la aplicacion rota aunque acabe contestando.
///
/// Con `[1, 4, 10]` y los plazos de abajo son **cuatro intentos y 15 s de
/// esperas**, y la cuenta sale asi:
///
/// | Como se cae | Cuanto tarda cada intento | Peor caso |
/// |---|---|---|
/// | no hay ruta / el puerto no abre (lo normal sin senal) | el sistema falla al momento | **segundos** |
/// | la conexion no llega a establecerse (lo normal con senal mala) | 10 s de `connect` | 4×10 + 15 = **55 s** |
/// | el servidor acepta y despues se queda mudo | 10 + 15 s | 4×25 + 15 = **115 s** |
///
/// El de en medio es el que se vive en Cuba y es el que Jose queria en un
/// minuto. El ultimo —que el servidor coja la conexion y no conteste nada, las
/// cuatro veces— sigue siendo el doble de eso, y esta escrito aqui en vez de
/// redondeado a «un minuto» porque el numero que importa es el que ve quien
/// espera.
///
/// Bajar mas la recepcion no se puede: la primera bajada de una sucursal
/// grande por la conexion de alla tarda mas de 15 s de cuerpo, y para eso
/// existe `truncado` en el protocolo. Lo que se acorta es cuanto se insiste,
/// no cuanto se deja hablar al servidor.
const esperasPorDefecto = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 4),
  Duration(seconds: 10),
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
        // 10 s para conectar y 15 s para recibir. Los 30 s de recepcion de
        // antes, multiplicados por los cinco intentos que habia, eran los
        // cuatro minutos de rueda que se cuentan arriba en `esperasPorDefecto`.
        //
        // Los 10 s de `connect` se quedan: establecer la conexion con una
        // senal mala tarda, y ahi el TLS todavia no ha empezado. Lo que se
        // acorto es la ESPERA A QUE CONTESTE, que es donde se iba el tiempo.
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
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
