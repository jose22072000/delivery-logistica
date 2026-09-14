import 'package:go_router/go_router.dart';

import 'vista/pantalla_clientes.dart';

export 'vista/pantalla_clientes.dart' show PantallaClientes;

/// La ruta de Clientes, declarada por la propia pantalla.
///
/// Va aqui y no en `navegacion/rutas.dart` para que anadir o mover una pantalla
/// no obligue a tocar un fichero compartido por las siete: quien monta el
/// `go_router` sólo tiene que meter esta constante en su lista.
final GoRoute rutaClientes = GoRoute(
  path: PantallaClientes.ruta,
  name: 'clientes',
  builder: (context, estado) => const PantallaClientes(),
);
