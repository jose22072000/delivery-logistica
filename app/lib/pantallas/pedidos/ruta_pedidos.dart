// La ruta de navegacion de Pedidos.
//
// Cada pantalla registra la suya en su propio fichero, como hace la API en Go con
// sus `rutasX`: quien monta el armazon junta las listas y no tiene que saber nada
// de lo que hay dentro de esta carpeta.

import 'package:go_router/go_router.dart';

import 'vista/pantalla_pedidos.dart';

/// `/orders` — el mismo camino que la de Next, para que un enlace pegado en un
/// chat siga valiendo en las dos.
const caminoPedidos = '/orders';

final rutasPedidos = <RouteBase>[
  GoRoute(
    path: caminoPedidos,
    name: 'pedidos',
    builder: (contexto, estado) => const PantallaPedidos(),
  ),
];
