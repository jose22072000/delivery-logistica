import 'package:dio/dio.dart';

import '../../../nucleo/identidad/almacen_sesion.dart';
import '../../../nucleo/identidad/sesion.dart';
import '../../../nucleo/registro/registro.dart';

/// Por que no se pudo entrar, en cristiano.
///
/// Cada uno lleva su mensaje porque **lo que se le dice a alguien que no puede
/// entrar decide lo que hace después**: «usuario o contraseña incorrectos» se
/// arregla probando otra vez; «no estás en ninguna sucursal» se arregla llamando
/// a la oficina, y decirle a esa persona «ha ocurrido un error» la deja
/// probando su contraseña buena una y otra vez hasta que el limitador la echa.
enum MotivoDeAcceso {
  /// 401. Usuario que no existe, cuenta sin contraseña o contraseña mal: auth
  /// los contesta los tres igual a propósito, y aquí se respeta.
  credenciales,

  /// 403 `sin_sucursal`. **Esto no es un fallo de la aplicación**: la contraseña
  /// era buena. Es que la cuenta no está dada de alta en ninguna sucursal, y en
  /// el reparto un token sin sucursal no es un token limitado — es el que abre
  /// las ocho. Por eso auth prefiere no emitirlo.
  sinSucursal,

  /// 403 con la cuenta dada de baja.
  cuentaDeBaja,

  /// 429. Demasiados intentos.
  demasiadosIntentos,

  /// No hay red, o el servidor no contesta. **Para entrar hace falta conexión**,
  /// y esto es exactamente eso y no una sesión muerta.
  sinConexion,

  /// 5xx y todo lo demás.
  servidor,
}

class FalloDeAcceso implements Exception {
  const FalloDeAcceso(this.motivo, this.mensaje, {this.detalle});

  final MotivoDeAcceso motivo;

  /// Lo que se pinta debajo del botón.
  final String mensaje;

  /// Lo que dijo el servidor, para el registro. No se pinta.
  final String? detalle;

  @override
  String toString() => 'FalloDeAcceso($motivo, $mensaje, $detalle)';
}

/// LA PUERTA. Usuario y contraseña contra `POST /api/auth/token`.
///
/// Va con el Dio **crudo** de auth (`dioAuthProvider`), sin `InterceptorSesion`:
/// entrar no se renueva a sí mismo, y un 401 de aquí es «esa contraseña no es»,
/// no «la sesión murió».
///
/// La aplicación **no lleva ninguna clave dentro** (`docs/identidad.md`): manda
/// usuario y contraseña por HTTPS y recibe el par de tokens. Una APK se
/// descompila.
class ServicioDeAcceso {
  ServicioDeAcceso({required Dio auth, required AlmacenDeSesion almacen})
    : _auth = auth,
      _almacen = almacen;

  final Dio _auth;
  final AlmacenDeSesion _almacen;

  /// Entra y **guarda el par**. Lo que devuelve ya está guardado.
  Future<Sesion> entrar({
    required String usuario,
    required String contrasena,
    String? sucursal,
  }) async {
    try {
      final respuesta = await _auth.post<Map<String, Object?>>(
        '/token',
        data: <String, Object?>{
          // `identifier` y no `email`: aquí se entra con el nombre de usuario de
          // PEDIDO (`yasmani`, `claudia.hab`) tanto como con el correo, y auth
          // admite los dos por este mismo campo.
          'identifier': usuario,
          'password': contrasena,
          if (sucursal != null && sucursal.isNotEmpty) 'sucursal': sucursal,
        },
      );
      final sesion = Sesion.deJson(respuesta.data ?? const <String, Object?>{});
      await _almacen.guardar(sesion);
      Registro.info('dentro: ${sesion.sub} (${sesion.sucursalId ?? "todas"})');
      return sesion;
    } on DioException catch (e) {
      throw _traducir(e);
    } on FormatException catch (e) {
      // Auth contestó 200 con algo que no es un par de tokens. Es del servidor,
      // no de quien escribió la contraseña, y se dice así.
      throw FalloDeAcceso(
        MotivoDeAcceso.servidor,
        'El servidor contestó algo que no se entiende. Avisa a la oficina.',
        detalle: e.message,
      );
    }
  }

  /// Cierra la sesión de ESTE aparato. Auth contesta 200 pase lo que pase, así
  /// que esto no puede impedir salir: lo local se borra igual.
  Future<void> salir(Sesion? sesion) async {
    try {
      if (sesion != null) {
        await _auth.post<Object?>(
          '/logout',
          data: <String, Object?>{'refresh_token': sesion.refresh},
        );
      }
    } on DioException catch (e) {
      // Sin red no se puede revocar, y aun así se sale: el refresh caduca solo y
      // dejar la sesión abierta en el teléfono porque el servidor tuvo un mal
      // momento es peor.
      Registro.aviso('no se pudo avisar a auth del cierre: ${e.type}');
    }
    await _almacen.borrar();
  }

  static FalloDeAcceso _traducir(DioException e) {
    final codigo = e.response?.statusCode;
    final cuerpo = e.response?.data;
    final error = cuerpo is Map ? cuerpo['error'] as String? : null;
    final mensaje = cuerpo is Map ? cuerpo['message'] as String? : null;

    if (codigo == null) {
      return FalloDeAcceso(
        MotivoDeAcceso.sinConexion,
        'Sin conexión con el servidor. Para entrar hace falta conexión; '
        'prueba otra vez cuando haya señal.',
        detalle: e.message ?? e.type.name,
      );
    }

    return switch (codigo) {
      401 => const FalloDeAcceso(
        MotivoDeAcceso.credenciales,
        'Usuario o contraseña incorrectos.',
      ),
      403 when error == 'sin_sucursal' => FalloDeAcceso(
        MotivoDeAcceso.sinSucursal,
        mensaje ??
            'La cuenta no está dada de alta en ninguna sucursal, o la '
                'sucursal pedida no es suya.',
        detalle: error,
      ),
      403 => FalloDeAcceso(
        MotivoDeAcceso.cuentaDeBaja,
        mensaje ?? 'La cuenta está dada de baja.',
        detalle: error,
      ),
      429 => const FalloDeAcceso(
        MotivoDeAcceso.demasiadosIntentos,
        'Demasiados intentos seguidos. Espera un minuto y vuelve a probar.',
      ),
      400 => const FalloDeAcceso(
        MotivoDeAcceso.credenciales,
        'Falta el usuario o la contraseña.',
      ),
      _ => FalloDeAcceso(
        MotivoDeAcceso.servidor,
        'El servidor no está respondiendo bien ($codigo). Vuelve a probar en '
        'un momento.',
        detalle: mensaje ?? error,
      ),
    };
  }
}
