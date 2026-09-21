import 'package:dio/dio.dart';

import 'fallos.dart';

/// Traduce lo que devuelve Dio a los tres tipos de `fallos.dart`. Es la tabla de
/// la regla 5 y nada mas.
///
/// Va DESPUES de `InterceptorSesion`: lo que llega aqui ya no tiene arreglo por
/// renovacion.
class InterceptorFallos extends Interceptor {
  const InterceptorFallos();

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Si alguien de mas arriba ya decidio que fallo es, se respeta.
    if (err.error is FalloApi) {
      handler.next(err);
      return;
    }
    handler.next(err.copyWith(error: traducir(err)));
  }

  static FalloApi traducir(DioException error) {
    final codigo = error.response?.statusCode;

    // La peticion ni salio, o se agoto el tiempo: red.
    if (codigo == null) {
      return FalloDeRed(detalle: error.message ?? error.type.name);
    }

    // 5xx: el servidor esta mal, no nosotros. Se conserva y se reintenta.
    if (codigo >= 500) {
      return FalloDeRed(codigo: codigo, detalle: mensajeDelServidor(error));
    }

    if (codigo == 401) {
      return SesionMuerta(mensajeDelServidor(error));
    }

    // 4xx que no es 401: el servidor dijo que no, con su motivo.
    return Rechazo(
      codigo,
      mensajeDelServidor(error) ?? 'El servidor rechazó la petición.',
      marca: marcaDelServidor(error),
    );
  }

  /// La marca legible por una maquina, si vino. Ver [Rechazo.marca].
  static String? marcaDelServidor(DioException error) {
    final datos = error.response?.data;
    if (datos is Map) {
      final valor = datos['codigo'];
      if (valor is String && valor.isNotEmpty) return valor;
    }
    return null;
  }

  /// El mensaje del servidor, **literal y en espanol**. Se busca en las claves
  /// que la API usa de verdad (`contratos-api.md`, apendice).
  static String? mensajeDelServidor(DioException error) {
    final datos = error.response?.data;
    if (datos is Map) {
      for (final clave in const ['mensaje', 'error', 'message']) {
        final valor = datos[clave];
        if (valor is String && valor.isNotEmpty) return valor;
      }
    }
    if (datos is String && datos.isNotEmpty) return datos;
    return null;
  }
}
