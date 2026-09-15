import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../datos/consultas_informes.dart';

final consultasInformesProvider = Provider<ConsultasInformes>(
  (ref) => ConsultasInformes(ref.watch(baseProvider)),
);

/// Los filtros. Viven en un provider y no en la URL porque, a diferencia de
/// Pedidos, esta pantalla no se comparte por enlace: se llega a ella a mano y se
/// mira un rato.
class FiltroDeInformes extends Notifier<FiltroDeInforme> {
  @override
  FiltroDeInforme build() => const FiltroDeInforme();

  void poner(FiltroDeInforme nuevo) => state = nuevo;

  void limpiar() => state = const FiltroDeInforme();
}

final filtroDeInformesProvider =
    NotifierProvider<FiltroDeInformes, FiltroDeInforme>(FiltroDeInformes.new);

final informeProvider = StreamProvider<Informe>(
  (ref) => ref
      .watch(consultasInformesProvider)
      .mirar(
        ref.watch(filtroDeInformesProvider),
        sucursalId: ref.watch(sucursalMiradaProvider),
      ),
);

/// Los vehiculos del selector. De la base local, como todo lo demas.
///
/// **FILTRADO POR LA SUCURSAL QUE SE MIRA**, con el mismo criterio que Rutas
/// (`repositorio_rutas.vehiculos`) y que el resto de la aplicacion: la sucursal
/// sale de [sucursalMiradaProvider] y, cuando hay una elegida, sólo entran los
/// vehiculos de esa.
///
/// Sin este filtro un operador de una sucursal veia los camiones de las otras
/// siete en el desplegable, y elegir uno le abria el informe de esa sucursal:
/// sus ingresos, sus pedidos y sus precios. Ya paso en delivery —Santiago vio
/// los precios de La Habana— y es la unica razon por la que esta linea existe.
///
/// Con «todas las sucursales» (`null`) se ven todos, que es lo que esa eleccion
/// significa y lo que ya hacen Pedidos, Rutas y el Panel.
final vehiculosDelInformeProvider = StreamProvider<List<Vehiculo>>((ref) {
  final base = ref.watch(baseProvider);
  final sucursal = ref.watch(sucursalMiradaProvider);
  final consulta = base.select(base.vehicles)
    ..orderBy([(v) => OrderingTerm(expression: v.name)]);
  if (sucursal != null && sucursal.isNotEmpty) {
    consulta.where((v) => v.branchId.equals(sucursal));
  }
  return consulta.watch();
});
