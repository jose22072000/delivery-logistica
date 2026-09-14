// La ruta de navegacion de Rutas, registrada aqui igual que la de Pedidos: quien
// monta el armazon junta las listas y no necesita saber nada de esta carpeta.

import 'package:go_router/go_router.dart';

import 'vista/pantalla_rutas.dart';

/// `/routes` — el mismo camino que la de Next.
const caminoRutas = '/routes';

final rutasRutas = <RouteBase>[
  GoRoute(
    path: caminoRutas,
    name: 'rutas',
    builder: (contexto, estado) => const PantallaRutas(),
  ),
];
