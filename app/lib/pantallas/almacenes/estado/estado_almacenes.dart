import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/fallos.dart';

import '../datos/almacen_api.dart';
import '../datos/repositorio_almacenes.dart';

final repositorioAlmacenesProvider = Provider<RepositorioAlmacenes>(
  (ref) => RepositorioAlmacenes(ref.watch(clienteApiProvider)),
);

/// Las sucursales con sus almacenes, tal y como las devuelve Accesos.
final almacenesProvider = FutureProvider.autoDispose<List<SucursalDeAccesos>>((
  ref,
) {
  ref.watch(sucursalMiradaProvider);
  return ref.watch(repositorioAlmacenesProvider).listar();
});

/// Que sucursal se esta mirando DENTRO de la pantalla. `null` = la primera de la
/// lista.
final sucursalElegidaProvider = NotifierProvider<SucursalElegida, String?>(
  SucursalElegida.new,
);

class SucursalElegida extends Notifier<String?> {
  @override
  String? build() => null;

  void poner(String? codigo) => state = codigo;
}

class AvisoAlmacenes {
  const AvisoAlmacenes(this.texto, {required this.esFallo});

  /// Literal NUEVO. Dice lo unico que importa: **no salio del aparato**. El
  /// mensaje bueno, `Guardado en Accesos.`, sólo se puede dar cuando Accesos
  /// contesto; decirlo sin red seria mentir en la pantalla.
  const AvisoAlmacenes.sinConexion()
    : texto =
          'Sin conexión: no se guardó nada en Accesos. Los almacenes se '
          'configuran con conexión; inténtalo otra vez cuando haya red.',
      esFallo = true;

  final String texto;
  final bool esFallo;
}

/// El guardado. Como en Vehiculos: **sin cola y sin base local**. O sale, o se
/// dice que no salio.
class ControlAlmacenes extends Notifier<AvisoAlmacenes?> {
  @override
  AvisoAlmacenes? build() => null;

  void limpiar() => state = null;

  Future<bool> guardar(String codigo, List<AlmacenDeAccesos> almacenes) async {
    state = null;
    try {
      final resultado = await ref
          .read(repositorioAlmacenesProvider)
          .guardar(codigo, almacenes);
      ref.invalidate(almacenesProvider);
      // El aviso de Accesos («N sin coordenadas…») se ensena TAL CUAL y detras
      // de la confirmacion: se guardo, pero hay algo que mirar.
      final aviso = resultado.aviso;
      state = AvisoAlmacenes(
        aviso == null ? 'Guardado en Accesos.' : 'Guardado en Accesos. $aviso',
        esFallo: false,
      );
      return true;
    } on FalloDeRed {
      state = const AvisoAlmacenes.sinConexion();
      return false;
    } on Rechazo catch (e) {
      // Los mensajes de Accesos son literales y en espanol: `Accesos no aceptó
      // el cambio: …`, `Sin acceso a esa sucursal`. Se pintan tal cual.
      state = AvisoAlmacenes(e.mensaje, esFallo: true);
      return false;
    } on SesionMuerta catch (e) {
      state = AvisoAlmacenes(e.mensaje, esFallo: true);
      return false;
    }
  }
}

final controlAlmacenesProvider =
    NotifierProvider<ControlAlmacenes, AvisoAlmacenes?>(ControlAlmacenes.new);
