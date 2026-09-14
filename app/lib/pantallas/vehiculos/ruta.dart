import 'package:go_router/go_router.dart';

import 'vista/pantalla_vehiculos.dart';

export 'vista/pantalla_vehiculos.dart' show PantallaVehiculos;

/// La ruta de Vehiculos, declarada por la propia pantalla (ver
/// `clientes/ruta.dart` para el porque).
final GoRoute rutaVehiculos = GoRoute(
  path: PantallaVehiculos.ruta,
  name: 'vehiculos',
  builder: (context, estado) => const PantallaVehiculos(),
);
