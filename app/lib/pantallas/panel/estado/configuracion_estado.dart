import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/proveedores.dart';
import '../datos/configuracion_pendiente.dart';

final configuracionPendienteProvider = Provider<ConfiguracionPendiente>(
  (ref) => ConfiguracionPendiente(ref.watch(baseProvider)),
);

/// QUE FALTA POR CONFIGURAR, en vivo y de la sucursal que se esta mirando.
///
/// `ref.watch(sucursalMiradaProvider)` dentro del provider, igual que las cifras
/// del Panel: al cambiar de sucursal arriba no se recarga la pagina, se
/// reconstruye esto y el paso a paso cambia en el sitio. Sin esto, un Super
/// Admin veria los pasos de la sucursal que mirara al abrir hasta que
/// recargara.
final pasoAPasoProvider = StreamProvider<ElPasoAPaso>(
  (ref) => ref
      .watch(configuracionPendienteProvider)
      .mirar(sucursalId: ref.watch(sucursalMiradaProvider)),
);
