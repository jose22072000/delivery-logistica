import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'vista/pantalla_tablero.dart';

export 'vista/pantalla_tablero.dart' show PantallaTablero;

/// LA RUTA DE ESTA PANTALLA, para enchufarla al `go_router` de la aplicacion.
///
/// Va en su propio fichero y no en `navegacion/rutas.dart` porque esta pantalla
/// se construye entera dentro de su carpeta: quien monte el armazon sólo tiene
/// que anadir `rutaDelTablero` a la lista de rutas y una entrada de menu que
/// apunte a [RutaDelTablero.camino].
///
/// La URL es `/board`, la misma del contrato de la API (`/api/board`), para que
/// en la web la direccion diga lo mismo que la peticion que la llena.
abstract final class RutaDelTablero {
  static const camino = '/board';
  static const nombre = 'tablero';

  /// Lo que va en la barra lateral.
  static const etiqueta = 'Tablero';
}

/// La ruta, ya montada. Sin `redirect` ni guardas propias: el acceso lo decide
/// el armazon, igual que en las otras siete pantallas.
final GoRoute rutaDelTablero = GoRoute(
  path: RutaDelTablero.camino,
  name: RutaDelTablero.nombre,
  builder: (BuildContext context, GoRouterState state) =>
      const PantallaTablero(),
);
