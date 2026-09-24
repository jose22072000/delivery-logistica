import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/vehiculos/datos/repositorio_vehiculos.dart';
import 'package:reparto/pantallas/vehiculos/datos/vehiculo_api.dart';
import 'package:reparto/pantallas/vehiculos/estado/estado_vehiculos.dart';

/// EL GESTO QUE NO DICE NADA.
///
/// `ControlVehiculos._hacer` sabía nombrar tres fallos —`FalloDeRed`,
/// `Rechazo`, `SesionMuerta`— y **cualquier otra cosa se le escapaba entera**.
/// Y lo primero que hace es `state = null`, o sea volver al estado de calma:
/// así que un fallo que no sea uno de esos tres dejaba la pantalla exactamente
/// como si no se hubiera pulsado nada. Se toca Guardar y no pasa nada.
///
/// **Y hay que ser honesto con lo que esta prueba demuestra y con lo que no.**
/// Se intentó llegar a ese hueco desde fuera, con el servidor contestando `200`
/// y el cuerpo con la forma cambiada, y **no se llegó**: `RepositorioVehiculos`
/// escribe con `mandar<Object?>`, así que cualquier JSON le vale y no revienta
/// nada. O sea que hoy **no se conoce un gesto de usuario que caiga aquí**, y
/// esto no es un fallo cazado en la calle: es un hueco tapado.
///
/// Lo que sí se comprueba es que el hueco está tapado: el día que algo del
/// camino de guardar lance otra cosa, la pantalla lo dice en vez de quedarse
/// muda. El fallo se inyecta en el repositorio, que es la única manera de
/// ejercitar ese camino sin inventarse un caso que no existe.
///
/// Aquí no se pierde trabajo —Vehículos vive del servidor y no tiene cola— pero
/// un gesto mudo tampoco es inofensivo: quien no ve respuesta vuelve a pulsar,
/// y el día que una de las dos sí llegue, el camión queda dado de alta dos
/// veces.
void main() {
  const camionNuevo = DatosVehiculo(
    nombre: 'Camión #9',
    tipo: 'truck',
    capacidad: 1000,
    estado: 'available',
  );

  ProviderContainer conRepositorio(RepositorioVehiculos repo) {
    final c = ProviderContainer(
      overrides: [repositorioVehiculosProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('un fallo que no es ninguno de los tres: se DICE, y se dice que no se '
      'guardó nada', () async {
    final c = conRepositorio(_RepoQueRevienta());
    final control = c.read(controlVehiculosProvider.notifier);

    final guardo = await control.crear(camionNuevo);

    expect(guardo, isFalse, reason: 'no se guardó, y se contesta que no');

    final aviso = c.read(controlVehiculosProvider);
    expect(
      aviso,
      isNotNull,
      reason:
          'sin esto la pantalla vuelve a la calma y el gesto es mudo: se pulsa '
          'Guardar y no pasa nada',
    );
    expect(aviso!.esFallo, isTrue);
    expect(
      aviso.texto,
      contains('NO se guardó nada'),
      reason: 'lo que de verdad hay que saber es si quedó algo o no',
    );
  });

  test('cuando el guardado sale bien NO sale ningún aviso de fallo', () async {
    // La pareja del §3-quinquies: la guarda nueva no puede encenderse siempre.
    final c = conRepositorio(_RepoQueGuarda());
    final control = c.read(controlVehiculosProvider.notifier);

    expect(await control.crear(camionNuevo), isTrue);
    final aviso = c.read(controlVehiculosProvider);
    expect(aviso, isNotNull);
    expect(aviso!.esFallo, isFalse);
  });
}

/// Un repositorio que lanza algo que `_hacer` **no sabe nombrar**.
class _RepoQueRevienta implements RepositorioVehiculos {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.error(
    StateError('la respuesta vino con la forma cambiada'),
  );
}

/// Y uno que guarda sin rechistar.
class _RepoQueGuarda implements RepositorioVehiculos {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
