import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/fallos.dart';

import '../datos/repositorio_vehiculos.dart';
import '../datos/vehiculo_api.dart';

final repositorioVehiculosProvider = Provider<RepositorioVehiculos>(
  (ref) => RepositorioVehiculos(ref.watch(clienteApiProvider)),
);

/// La flota. Es una peticion y no un stream sobre la base **porque aqui no hay
/// base**: lo que se ve es lo que hay en el servidor ahora mismo, o no se ve.
final vehiculosProvider = FutureProvider.autoDispose<List<VehiculoDeLaApi>>((
  ref,
) {
  // Al cambiar de sucursal en la barra se vuelve a pedir: el alcance lo
  // resuelve el servidor con la cabecera `x-sucursal-id`.
  ref.watch(sucursalMiradaProvider);
  return ref.watch(repositorioVehiculosProvider).listar();
});

final ajustesVehiculosProvider = FutureProvider.autoDispose<AjustesDeLaApi>(
  (ref) => ref.watch(repositorioVehiculosProvider).ajustes(),
);

/// La busqueda de la cabecera. Filtra **en el cliente** por nombre y placa.
final busquedaVehiculosProvider = NotifierProvider<BusquedaVehiculos, String>(
  BusquedaVehiculos.new,
);

class BusquedaVehiculos extends Notifier<String> {
  @override
  String build() => '';

  void poner(String texto) => state = texto;
}

/// Cuantos por pagina: 25 por defecto, cambiable a 50 o 100 (§5).
final porPaginaVehiculosProvider = NotifierProvider<PorPaginaVehiculos, int>(
  PorPaginaVehiculos.new,
);

class PorPaginaVehiculos extends Notifier<int> {
  @override
  int build() => 25;

  void poner(int cuantos) => state = cuantos;
}

final paginaVehiculosProvider = NotifierProvider<PaginaVehiculos, int>(
  PaginaVehiculos.new,
);

class PaginaVehiculos extends Notifier<int> {
  @override
  int build() => 1;

  void poner(int pagina) => state = pagina;
}

/// El resultado de una accion de escritura, para pintarlo.
class AvisoVehiculos {
  const AvisoVehiculos(this.texto, {required this.esFallo});

  /// Literal NUEVO (no existe en la de Next): la de Next nunca se queda sin
  /// red porque vive en un navegador con el servidor al lado. Dice dos cosas y
  /// las dos importan: que no hubo red y, sobre todo, **que no se guardo nada**.
  const AvisoVehiculos.sinConexion()
    : texto =
          'Sin conexión: no se guardó nada. Los vehículos se configuran con '
          'conexión; inténtalo otra vez cuando haya red.',
      esFallo = true;

  final String texto;
  final bool esFallo;
}

/// Las escrituras de la pantalla.
///
/// **Aqui no hay `ColaDeSalida` y no la puede haber.** Si una accion no sale,
/// no se guarda en ningun sitio y se dice. Fingir que se guardo es lo unico que
/// esta prohibido: alguien daria por hecho que el camion nuevo esta dado de
/// alta y manana la ruta no se puede armar.
class ControlVehiculos extends Notifier<AvisoVehiculos?> {
  @override
  AvisoVehiculos? build() => null;

  void limpiar() => state = null;

  Future<bool> crear(DatosVehiculo datos) =>
      _hacer(() => _repositorio.crear(datos), 'Vehículo agregado.');

  Future<bool> editar(String id, DatosVehiculo datos) =>
      _hacer(() => _repositorio.editar(id, datos), 'Vehículo actualizado.');

  Future<bool> eliminar(String id) =>
      _hacer(() => _repositorio.eliminar(id), 'Vehículo eliminado.');

  Future<bool> marcarDisponible(String id) => _hacer(
    () => _repositorio.marcarDisponible(id),
    'Vehículo marcado como disponible.',
  );

  Future<bool> usarParaDomicilio(String id) => _hacer(
    () => _repositorio.usarParaDomicilio(id),
    'Se usará este vehículo para calcular el domicilio.',
  );

  Future<bool> guardarTipos(List<TipoDeVehiculo> tipos) =>
      _hacer(() => _repositorio.guardarTipos(tipos), 'Tipos guardados.');

  RepositorioVehiculos get _repositorio =>
      ref.read(repositorioVehiculosProvider);

  Future<bool> _hacer(Future<void> Function() accion, String exito) async {
    state = null;
    try {
      await accion();
    } on FalloDeRed {
      // Red caida, tiempo agotado o 5xx: la peticion NO llego. No se encola, no
      // se escribe en local, no se dice que se guardo.
      state = const AvisoVehiculos.sinConexion();
      return false;
    } on Rechazo catch (e) {
      // El servidor entendio y dijo que no. Su mensaje se ensena LITERAL, en
      // espanol, sin envolver en «Ha ocurrido un error».
      state = AvisoVehiculos(e.mensaje, esFallo: true);
      return false;
    } on SesionMuerta catch (e) {
      state = AvisoVehiculos(e.mensaje, esFallo: true);
      return false;
    }
    // Sólo se refresca cuando de verdad se aplico.
    ref.invalidate(vehiculosProvider);
    ref.invalidate(ajustesVehiculosProvider);
    state = AvisoVehiculos(exito, esFallo: false);
    return true;
  }
}

final controlVehiculosProvider =
    NotifierProvider<ControlVehiculos, AvisoVehiculos?>(ControlVehiculos.new);
