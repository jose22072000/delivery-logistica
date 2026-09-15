import 'package:reparto/nucleo/red/cliente_api.dart';

import 'panel_sincronizacion.dart';

/// El panel del sincronizador, contra `sync` y **solo contra `sync`**.
///
/// La verdad de si hay red es si la peticion salio: un `FalloDeRed` de
/// `ClienteApi`. No hay base local que consultar y no se quiere: lo que esta
/// pantalla contesta es «¿esta Palma subiendo AHORA?», y esa pregunta no se
/// puede responder con lo que se bajo ayer.
class RepositorioSincronizacion {
  RepositorioSincronizacion(this._api);

  final ClienteApi _api;

  /// `GET /sync/estado`. El cliente ya trae `…/sync` de base (`Entorno.syncUrl`),
  /// igual que la subida pide `/subida`.
  ///
  /// **El alcance por sucursal lo cierra el servidor**, no esto: sale de quien
  /// pregunta (`estado.go`, regla 6). [sucursal] solo ESTRECHA, y solo se lo
  /// admite al Super Admin; a cualquier otro se le ignora y sigue viendo su
  /// sucursal y nada mas. Se manda porque es lo que el manejador lee para
  /// dejar al Super Admin mirar una sola.
  Future<EstadoDelSincronizador> leer({String? sucursal}) async {
    final datos = await _api.pedir<Map<String, Object?>>(
      '/estado',
      params: sucursal == null ? null : <String, Object?>{'sucursal': sucursal},
    );
    return EstadoDelSincronizador.deJson(datos);
  }
}
