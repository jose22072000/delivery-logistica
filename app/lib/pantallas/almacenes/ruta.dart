import 'package:go_router/go_router.dart';

import 'vista/pantalla_almacenes.dart';

export 'vista/pantalla_almacenes.dart' show PantallaAlmacenes;

/// La ruta de Almacenes, declarada por la propia pantalla (ver
/// `clientes/ruta.dart` para el porque).
final GoRoute rutaAlmacenes = GoRoute(
  path: PantallaAlmacenes.ruta,
  name: 'almacenes',
  builder: (context, estado) => const PantallaAlmacenes(),
);
