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
final vehiculosDelInformeProvider = StreamProvider<List<Vehiculo>>(
  (ref) =>
      (ref.watch(baseProvider).select(ref.watch(baseProvider).vehicles)
            ..orderBy([(v) => OrderingTerm(expression: v.name)]))
          .watch(),
);
