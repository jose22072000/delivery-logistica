import 'package:reparto/nucleo/red/cliente_api.dart';

import 'almacen_api.dart';

/// Lo que devuelve un guardado: Accesos contesta la lista y, si algun almacen se
/// quedo sin coordenadas, un aviso.
class GuardadoDeAlmacenes {
  const GuardadoDeAlmacenes({required this.almacenes, this.aviso});

  final List<AlmacenDeAccesos> almacenes;

  /// El aviso literal del servidor: cuantos almacenes se quedaron sin
  /// coordenadas y que desde esos no se puede medir el domicilio. Llega con el
  /// numero ya puesto y se ensena tal cual.
  final String? aviso;
}

/// Almacenes, contra Accesos y **sólo contra Accesos**.
///
/// El dato vive alli y hay **una sola copia**. Encolarlo aqui significaria que
/// durante un rato el punto desde el que se mide un domicilio seria distinto en
/// el telefono y en Accesos, y los precios que salgan en ese rato no cuadrarian
/// con nada. Se configura una vez y en la oficina: sin red, la pantalla lo dice
/// y no toca nada.
class RepositorioAlmacenes {
  RepositorioAlmacenes(this._api);

  final ClienteApi _api;

  Future<List<SucursalDeAccesos>> listar() async {
    final datos = await _api.pedir<Map<String, Object?>>('/almacenes');
    return [
      for (final s in (datos['sucursales'] as List<Object?>?) ?? const [])
        SucursalDeAccesos.deJson(s! as Map<String, Object?>),
    ];
  }

  /// Se manda **la lista completa** de la sucursal, no el almacen suelto: es lo
  /// que espera `PUT /api/almacenes` y es lo que hace que quitar uno sea quitar
  /// uno y no dejarlo huerfano.
  Future<GuardadoDeAlmacenes> guardar(
    String codigo,
    List<AlmacenDeAccesos> almacenes,
  ) async {
    final datos = await _api.mandar<Map<String, Object?>>(
      'PUT',
      '/almacenes',
      <String, Object?>{
        'codigo': codigo,
        'almacenes': [for (final a in almacenes) a.aJson()],
      },
    );
    return GuardadoDeAlmacenes(
      almacenes: [
        for (final a in (datos['almacenes'] as List<Object?>?) ?? const [])
          AlmacenDeAccesos.deJson(a! as Map<String, Object?>),
      ],
      aviso: datos['aviso'] as String?,
    );
  }
}
