import '../../../nucleo/plataforma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/copia_bajada.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/nucleo/refresco_en_vivo.dart';

import '../datos/repositorio_vehiculos.dart';
import '../datos/vehiculo_api.dart';

final repositorioVehiculosProvider = Provider<RepositorioVehiculos>(
  (ref) => RepositorioVehiculos(ref.watch(clienteApiProvider)),
);

/// La flota. Es una peticion y no un stream sobre la base **porque aqui no hay
/// base**: lo que se ve es lo que hay en el servidor ahora mismo, o no se ve.
///
/// Y por eso mismo **el ciclo de sincronizacion no la repinta**: el ciclo escribe
/// en la base, y aqui no se lee de la base. Hasta el 17/09/2026 lo unico que
/// actualizaba esta pantalla era salir de ella y volver a entrar, aunque el aviso
/// en vivo del servidor estuviera llegando. El mismo fallo del Tablero, en otra
/// pantalla. Ver `nucleo/refresco_en_vivo.dart`.
final vehiculosProvider = FutureProvider.autoDispose<List<VehiculoDeLaApi>>((
  ref,
) {
  // Al cambiar de sucursal en la barra se vuelve a pedir: el alcance lo
  // resuelve el servidor con la cabecera `x-sucursal-id`.
  ref.watch(sucursalMiradaProvider);
  refrescarConElAviso(ref, const [CambioEnVivo.vehiculos]);
  return ref.watch(repositorioVehiculosProvider).listar();
});

/// La moneda y el costo por km. Escucha DOS tipos porque la pantalla enseña las
/// dos cosas: los tipos de vehiculo con su costo (`vehiculos`) y la tasa con la
/// que se convierten los importes (`ajustes`).
final ajustesVehiculosProvider = FutureProvider.autoDispose<AjustesDeLaApi>((
  ref,
) {
  refrescarConElAviso(ref, const [
    CambioEnVivo.ajustes,
    CambioEnVivo.vehiculos,
  ]);
  return ref.watch(repositorioVehiculosProvider).ajustes();
});

/// LO QUE EL APARATO TIENE BAJADO de la flota.
///
/// Esta pantalla vive de la red y no de la base, pero la base **si** tiene una
/// copia de `vehicles`: la deja la bajada del dia, y de ella comen el asistente
/// de rutas y el tablero. Sin conexion eso es lo unico que hay, y decirlo separa
/// las dos situaciones que hoy se ven iguales:
///
///  * el aparato bajo la flota y no hay red → se sigue pudiendo armar la ruta
///    con lo que hay dentro;
///  * el aparato **no la ha bajado nunca** → no se arregla dando de alta un
///    camion, se arregla trayendo el dia.
final flotaEnElAparatoProvider = StreamProvider<CopiaBajada>(
  (ref) => copiaBajada(
    ref.watch(baseProvider),
    coleccion: Colecciones.vehiculos,
    tabla: ref.watch(baseProvider).vehicles,
  ),
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
  /// EL MISMO FALLO, DOS TEXTOS, PORQUE NO SE ARREGLA IGUAL — 17/09/2026.
  ///
  /// En el aparato «inténtalo otra vez cuando haya red» es lo que hay que
  /// hacer: se está en el patio de un almacén y la red vuelve sola.
  ///
  /// En la web no. Si la página cargó, conexión hay; el que no contesta es el
  /// servidor, y mandar a mirar la señal a quien está sentado en la oficina es
  /// mandarlo a mirar donde no es. Es el mismo razonamiento de
  /// `TextosDeCaida.queHacer`, que ya lo tenía resuelto para la puerta.
  ///
  /// Lo que NO cambia en ninguno de los dos, y es la mitad que importa:
  /// **que no se guardó nada**.
  factory AvisoVehiculos.sinConexion() => AvisoVehiculos(
    Destino.trabajaSinConexion
        ? 'Sin conexión: no se guardó nada. Los vehículos se configuran con '
              'conexión; inténtalo otra vez cuando haya red.'
        : 'Sin conexión con el servidor: no se guardó nada. La página cargó, '
              'así que conexión hay: el que no contesta es el servidor. Prueba '
              'otra vez y, si sigue igual, avisa a la oficina.',
    esFallo: true,
  );

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
      state = AvisoVehiculos.sinConexion();
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
