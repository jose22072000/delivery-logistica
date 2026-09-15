/// Los modelos de Vehiculos, leidos del JSON de la API.
///
/// **No son tablas de Drift a proposito.** Vehiculos es una pantalla de sólo
/// con conexion: se configura una vez, en la oficina, y lo que se ve sale
/// siempre del servidor. Guardar una copia local abriria la puerta a ensenar
/// una flota de anteayer y a tener que decidir quien gana cuando las dos
/// difieran, y eso es complejidad a cambio de nada.
library;

import 'package:collection/collection.dart';

/// Lee un numero venga como venga: la API manda unos como numero y otros como
/// texto segun por donde pasaron.
double? _numero(Object? valor) => switch (valor) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};

/// La ruta viva de un vehiculo, para la caja azul `Ruta activa`.
class RutaDelVehiculo {
  const RutaDelVehiculo({this.nombre, this.codigo});

  factory RutaDelVehiculo.deJson(Map<String, Object?> j) => RutaDelVehiculo(
    nombre: j['name'] as String?,
    codigo: j['routeCode'] as String?,
  );

  final String? nombre;
  final String? codigo;

  /// Nombre, si no codigo, si no el respaldo del pliego.
  String get titulo {
    final n = nombre?.trim();
    if (n != null && n.isNotEmpty) return n;
    final c = codigo?.trim();
    if (c != null && c.isNotEmpty) return c;
    return 'sin nombre';
  }
}

class VehiculoDeLaApi {
  const VehiculoDeLaApi({
    required this.id,
    required this.nombre,
    required this.capacidad,
    required this.estado,
    this.tipo,
    this.placa,
    this.costoKmUsd,
    this.usarParaDomicilio = false,
    this.notas,
    this.rutas = 0,
    this.pedidos = 0,
    this.rutaActiva,
  });

  factory VehiculoDeLaApi.deJson(Map<String, Object?> j) {
    final cuenta = j['_count'] as Map<String, Object?>?;
    final rutas = (j['routes'] as List<Object?>?) ?? const [];
    return VehiculoDeLaApi(
      id: j['id']! as String,
      nombre: (j['name'] as String?) ?? '',
      capacidad: _numero(j['capacity']) ?? 1000,
      estado: (j['status'] as String?) ?? 'available',
      tipo: j['type'] as String?,
      placa: j['plate'] as String?,
      costoKmUsd: _numero(j['costoKmUsd']),
      usarParaDomicilio: j['usarParaDomicilio'] == true,
      notas: j['notes'] as String?,
      rutas: (_numero(cuenta?['routes']) ?? 0).toInt(),
      pedidos: (_numero(cuenta?['orders']) ?? 0).toInt(),
      rutaActiva: rutas.isEmpty
          ? null
          : RutaDelVehiculo.deJson(rutas.first! as Map<String, Object?>),
    );
  }

  final String id;
  final String nombre;
  final double capacidad;
  final String estado;
  final String? tipo;
  final String? placa;
  final double? costoKmUsd;
  final bool usarParaDomicilio;
  final String? notas;
  final int rutas;
  final int pedidos;
  final RutaDelVehiculo? rutaActiva;

  /// `in_use` es el del esquema y `in_route` el que manda la ficha del pliego.
  /// Los dos significan lo mismo para quien mira la tarjeta, asi que los dos
  /// pintan `En uso`.
  bool get enUso => estado == 'in_use' || estado == 'in_route';
  bool get enMantenimiento => estado == 'maintenance';

  /// El texto de la insignia, literal del pliego (§5).
  String get etiquetaEstado {
    if (enUso) return 'En uso';
    if (enMantenimiento) return 'Mantenimiento';
    return 'Disponible';
  }

  /// Filtra **en el cliente** por nombre y placa, que es lo que hace la de Next.
  bool cuadraCon(String busqueda) {
    final q = busqueda.trim().toLowerCase();
    if (q.isEmpty) return true;
    return nombre.toLowerCase().contains(q) ||
        (placa ?? '').toLowerCase().contains(q);
  }
}

/// Un tipo de vehiculo, de `settings.tiposVehiculo`.
class TipoDeVehiculo {
  const TipoDeVehiculo({required this.nombre, this.costoKmUsd});

  factory TipoDeVehiculo.deJson(Map<String, Object?> j) => TipoDeVehiculo(
    nombre: (j['nombre'] as String?) ?? '',
    costoKmUsd: _numero(j['costoKmUsd']),
  );

  final String nombre;
  final double? costoKmUsd;

  Map<String, Object?> aJson() => {'nombre': nombre, 'costoKmUsd': costoKmUsd};

  /// Los tipos que hay que ENSEÑAR en el cajon: los de ajustes **mas los que
  /// ya usan los vehiculos** y todavia no estan en la lista.
  ///
  /// Sin esto, `truck` —el tipo por defecto de todo vehiculo nuevo— no aparece
  /// en ninguna lista donde ponerle su costo por km, y ese costo es el que
  /// cotiza el domicilio que se le cobra al cliente. En produccion los cinco
  /// tipos tenian `costo_km_usd` en NULL por exactamente esto.
  ///
  /// El costo que se siembra sale de un vehiculo de ese tipo que ya lo tenga.
  /// **Si ninguno lo tiene se deja vacio, no en cero**: aqui la de Next pone un
  /// `0`, y un cero guardado se lee como «el kilometro es gratis» —un numero
  /// creible y equivocado— mientras que un hueco se ve y se rellena.
  static List<TipoDeVehiculo> paraElCajon({
    required List<TipoDeVehiculo> deAjustes,
    required List<VehiculoDeLaApi> vehiculos,
  }) {
    final conocidos = {for (final t in deAjustes) t.nombre};
    final sembrados = <TipoDeVehiculo>[];
    for (final v in vehiculos) {
      final nombre = v.tipo?.trim();
      if (nombre == null || nombre.isEmpty) continue;
      if (!conocidos.add(nombre)) continue;
      sembrados.add(
        TipoDeVehiculo(
          nombre: nombre,
          costoKmUsd: vehiculos
              .where((o) => o.tipo == nombre && o.costoKmUsd != null)
              .firstOrNull
              ?.costoKmUsd,
        ),
      );
    }
    return [...deAjustes, ...sembrados];
  }
}

/// Lo que hace falta de `GET /api/settings`: los tipos y la tasa.
class AjustesDeLaApi {
  const AjustesDeLaApi({required this.tipos, required this.cupRate});

  factory AjustesDeLaApi.deJson(Map<String, Object?> j) => AjustesDeLaApi(
    tipos: [
      for (final t in (j['tiposVehiculo'] as List<Object?>?) ?? const [])
        TipoDeVehiculo.deJson(t! as Map<String, Object?>),
    ],
    // 320 por defecto, lo dice el pliego. Sin tasa el ayudante del costo por km
    // no se puede calcular, y quedarse sin ayudante es peor que usar la de la
    // casa diciendo cual es.
    cupRate: _numero(j['cupRate']) ?? 320,
  );

  final List<TipoDeVehiculo> tipos;
  final double cupRate;
}

/// Lo que se manda al crear o editar. Los nombres son los del contrato.
class DatosVehiculo {
  const DatosVehiculo({
    required this.nombre,
    this.tipo,
    this.placa,
    this.capacidad,
    this.estado,
    this.notas,
    this.costoKmUsd,
    this.usarParaDomicilio,
  });

  final String nombre;
  final String? tipo;
  final String? placa;
  final double? capacidad;
  final String? estado;
  final String? notas;
  final double? costoKmUsd;
  final bool? usarParaDomicilio;

  Map<String, Object?> aJson() => <String, Object?>{
    'name': nombre,
    'type': tipo,
    'plate': placa,
    'capacity': capacidad,
    'status': estado,
    'notes': notas,
    'costoKmUsd': costoKmUsd,
    'usarParaDomicilio': usarParaDomicilio,
  };
}
