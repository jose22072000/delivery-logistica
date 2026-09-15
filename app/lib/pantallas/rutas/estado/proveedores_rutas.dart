// Los providers de Rutas.
//
// Igual que en Pedidos: todo cuelga de la base local y de `sucursalMiradaProvider`.
// Lo que esta pantalla anade es la ESCRITURA, y la escritura no tiene provider de
// «guardando»: se escribe en local, se pinta como hecho y la cola se encarga. Lo
// unico que la pantalla mira despues es `sinSubirProvider`, que ya vive en el
// nucleo.

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../pedidos/datos/repositorio_pedidos.dart';
import '../datos/acciones_rutas.dart';
import '../datos/repositorio_rutas.dart';

final consultasRutasProvider = Provider<ConsultasRutas>(
  (ref) => ConsultasRutas(ref.watch(baseProvider)),
);

/// Las cinco acciones de escritura. Comparten la MISMA cola y el MISMO reloj que
/// el resto de la aplicacion: dos relojes distintos serian dos horas distintas
/// para el mismo cierre.
final accionesDeRutaProvider = Provider<AccionesDeRuta>(
  (ref) => AccionesDeRuta(
    ref.watch(baseProvider),
    ref.watch(colaProvider),
    reloj: ref.watch(relojProvider),
  ),
);

class PestanaElegida extends Notifier<PestanaRutas> {
  @override
  PestanaRutas build() => PestanaRutas.activas;

  void elegir(PestanaRutas cual) => state = cual;
}

final pestanaRutasProvider = NotifierProvider<PestanaElegida, PestanaRutas>(
  PestanaElegida.new,
);

class FiltrosDeRutas extends Notifier<FiltrosRutas> {
  @override
  FiltrosRutas build() => const FiltrosRutas();

  void poner(FiltrosRutas nuevos) => state = nuevos;

  void limpiar() => state = const FiltrosRutas();
}

final filtrosRutasProvider = NotifierProvider<FiltrosDeRutas, FiltrosRutas>(
  FiltrosDeRutas.new,
);

class PaginaDeRutas extends Notifier<int> {
  @override
  int build() => 1;

  void ir(int pagina) => state = pagina;
}

final paginaRutasProvider = NotifierProvider<PaginaDeRutas, int>(
  PaginaDeRutas.new,
);

/// La ruta seleccionada en la columna izquierda. `null` = el detalle dice
/// `Selecciona una ruta para ver el detalle`.
class RutaElegida extends Notifier<String?> {
  @override
  String? build() => null;

  void elegir(String? rutaId) => state = rutaId;
}

final rutaElegidaProvider = NotifierProvider<RutaElegida, String?>(
  RutaElegida.new,
);

final todasLasRutasProvider = StreamProvider<List<Ruta>>(
  (ref) => ref
      .watch(consultasRutasProvider)
      .rutas(sucursalId: ref.watch(sucursalMiradaProvider)),
);

final vehiculosProvider = StreamProvider<List<Vehiculo>>(
  (ref) => ref
      .watch(consultasRutasProvider)
      .vehiculos(sucursalId: ref.watch(sucursalMiradaProvider)),
);

final sucursalesProvider = StreamProvider<List<Sucursal>>(
  (ref) => ref.watch(consultasRutasProvider).sucursales(),
);

/// Cuantas rutas hay en cada pestana. Va en la propia pestana, como en el
/// pliego.
final contadoresDePestanaProvider = Provider<Map<PestanaRutas, int>>((ref) {
  final rutas = ref.watch(todasLasRutasProvider).value ?? const <Ruta>[];
  return {
    for (final pestana in PestanaRutas.values)
      pestana: rutas.where((r) => pestana.agrupa(r.status)).length,
  };
});

/// La lista ya filtrada por la pestana y por los filtros del cliente.
final rutasDeLaPestanaProvider = Provider<List<Ruta>>((ref) {
  final pestana = ref.watch(pestanaRutasProvider);
  final rutas = ref.watch(todasLasRutasProvider).value ?? const <Ruta>[];
  final vehiculos = {
    for (final v in ref.watch(vehiculosProvider).value ?? const <Vehiculo>[])
      v.id: v,
  };
  final sucursales = {
    for (final s in ref.watch(sucursalesProvider).value ?? const <Sucursal>[])
      s.id: s,
  };
  return filtrarRutas(
    [
      for (final ruta in rutas)
        if (pestana.agrupa(ruta.status)) ruta,
    ],
    ref.watch(filtrosRutasProvider),
    vehiculos: vehiculos,
    sucursales: sucursales,
  );
});

final rutaConTodoProvider = StreamProvider.family<RutaConTodo?, String>(
  (ref, rutaId) => ref.watch(consultasRutasProvider).rutaConTodo(rutaId),
);

/// Las paradas en vivo: el cierre se tiene que ver marcado en el detalle sin
/// esperar a nada ni a nadie.
final paradasDeRutaProvider = StreamProvider.family<List<Pedido>, String>(
  (ref, rutaId) => ref.watch(consultasRutasProvider).mirarParadasDe(rutaId),
);

/// Los renglones de las paradas: de aqui sale la `Carga total` y el bloque
/// `Queda en el camión` del cierre.
final renglonesDeParadasProvider =
    FutureProvider.family<Map<String, List<RenglonConPeso>>, String>((
      ref,
      rutaId,
    ) async {
      final paradas = await ref.watch(paradasDeRutaProvider(rutaId).future);
      return ref.watch(consultasRutasProvider).renglonesDe([
        for (final p in paradas) p.id,
      ]);
    });

final rutasDescargadasProvider = FutureProvider<bool>(
  (ref) => ref.watch(frescuraProvider).seDescargo(Colecciones.rutas),
);

/// Los filtros del paso 4 del asistente. Van como valor con `==` porque son el
/// argumento de un `family`.
@immutable
class FiltrosDisponibles {
  const FiltrosDisponibles({
    this.sucursalId,
    this.q = '',
    this.municipio = '',
    this.vendedor = '',
    this.estado = EstadoDelPedido.cualquiera,
    this.domicilio = DomicilioFiltro.soloCon,
    this.cotizado = CotizadoDelDomicilio.cualquiera,
    this.dia,
    this.kmMax,
    this.costoMin,
  });

  final String? sucursalId;
  final String q;
  final String municipio;
  final String vendedor;
  final EstadoDelPedido estado;

  /// **Arranca en `Sólo con domicilio`** (pliego §3, paso 4), y `Limpiar` vuelve
  /// aqui, no a «con y sin».
  final DomicilioFiltro domicilio;

  final CotizadoDelDomicilio cotizado;
  final DateTime? dia;
  final double? kmMax;
  final double? costoMin;

  /// `Limpiar` del paso 4: se queda la sucursal —es de lo que va la ruta— y
  /// vuelve el domicilio a `1`.
  FiltrosDisponibles limpios() => FiltrosDisponibles(sucursalId: sucursalId);

  FiltrosDisponibles copiarCon({
    String? sucursalId,
    String? q,
    String? municipio,
    String? vendedor,
    EstadoDelPedido? estado,
    DomicilioFiltro? domicilio,
    CotizadoDelDomicilio? cotizado,
    DateTime? dia,
    bool limpiarDia = false,
    double? kmMax,
    bool limpiarKmMax = false,
    double? costoMin,
    bool limpiarCostoMin = false,
  }) => FiltrosDisponibles(
    sucursalId: sucursalId ?? this.sucursalId,
    q: q ?? this.q,
    municipio: municipio ?? this.municipio,
    vendedor: vendedor ?? this.vendedor,
    estado: estado ?? this.estado,
    domicilio: domicilio ?? this.domicilio,
    cotizado: cotizado ?? this.cotizado,
    dia: limpiarDia ? null : (dia ?? this.dia),
    // Sin el `limpiar…` no habria forma de BORRAR un tope: pasar `null` es
    // indistinguible de «no lo toques», y el `km máx.` se quedaria puesto para
    // siempre.
    kmMax: limpiarKmMax ? null : (kmMax ?? this.kmMax),
    costoMin: limpiarCostoMin ? null : (costoMin ?? this.costoMin),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FiltrosDisponibles &&
          other.sucursalId == sucursalId &&
          other.q == q &&
          other.municipio == municipio &&
          other.vendedor == vendedor &&
          other.estado == estado &&
          other.domicilio == domicilio &&
          other.cotizado == cotizado &&
          other.dia == dia &&
          other.kmMax == kmMax &&
          other.costoMin == costoMin;

  @override
  int get hashCode => Object.hash(
    sucursalId,
    q,
    municipio,
    vendedor,
    estado,
    domicilio,
    cotizado,
    dia,
    kmMax,
    costoMin,
  );
}

/// Los pedidos elegibles para una ruta. **El cuadre con la factura no es
/// configurable**: siempre `cuadra`, que es lo unico que el armado acepta.
final disponiblesProvider =
    FutureProvider.family<List<Pedido>, FiltrosDisponibles>(
      (ref, filtros) => ref
          .watch(consultasRutasProvider)
          .disponibles(
            sucursalId: filtros.sucursalId,
            q: filtros.q,
            municipio: filtros.municipio,
            vendedor: filtros.vendedor,
            estado: filtros.estado.param,
            domicilio: filtros.domicilio.param,
            cotizado: filtros.cotizado.param,
            dia: filtros.dia,
            kmMax: filtros.kmMax,
            costoMin: filtros.costoMin,
            // El MISMO reloj que el resto de la aplicacion: `expirada` se decide
            // contra la hora, y dos relojes distintos son dos listas distintas.
            ahora: ref.watch(relojProvider)(),
          ),
    );

/// Los municipios y los vendedores que hay **entre los disponibles**, para los
/// dos selectores del paso 4.
///
/// Salen de la lista SIN `q`, sin vendedor y sin municipio a proposito (es lo
/// que hace `/api/orders/available` para las opciones de filtro): si se sacaran
/// de la lista ya filtrada, elegir un vendedor borraria del desplegable a todos
/// los demas y no habria forma de cambiar de opinion sin limpiar.
final opcionesDeDisponiblesProvider =
    FutureProvider.family<OpcionesDeDisponibles, FiltrosDisponibles>((
      ref,
      filtros,
    ) async {
      final pedidos = await ref.watch(
        disponiblesProvider(
          filtros.copiarCon(q: '', vendedor: '', municipio: ''),
        ).future,
      );
      return OpcionesDeDisponibles(
        municipios: {
          for (final p in pedidos)
            if ((p.municipio ?? '').isNotEmpty) p.municipio!,
        }.toList()..sort(),
        vendedores: {
          for (final p in pedidos)
            if ((p.vendedor ?? '').isNotEmpty) p.vendedor!,
        }.toList()..sort(),
      );
    });

/// Los renglones de los pedidos elegibles: de aqui salen los articulos de cada
/// fila del paso 4.
final renglonesDeDisponiblesProvider =
    FutureProvider.family<
      Map<String, List<RenglonConPeso>>,
      FiltrosDisponibles
    >((ref, filtros) async {
      final pedidos = await ref.watch(disponiblesProvider(filtros).future);
      return ref.watch(consultasRutasProvider).renglonesDe([
        for (final p in pedidos) p.id,
      ]);
    });

/// Lo que llena los dos desplegables del paso 4.
@immutable
class OpcionesDeDisponibles {
  const OpcionesDeDisponibles({
    required this.municipios,
    required this.vendedores,
  });

  static const vacias = OpcionesDeDisponibles(
    municipios: <String>[],
    vendedores: <String>[],
  );

  final List<String> municipios;
  final List<String> vendedores;
}

/// Los almacenes de una sucursal, por su CODIGO (`branches.externalId`), que es
/// como los guarda Accesos. El principal viene primero.
final almacenesProvider = FutureProvider.family<List<Almacen>, String>(
  (ref, sucursalCodigo) =>
      ref.watch(consultasRutasProvider).almacenesDe(sucursalCodigo),
);
