import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../navegacion/pantalla_registrada.dart';
import 'vista/pantalla_pedidos.dart';

export 'vista/pantalla_pedidos.dart' show PantallaPedidos;

/// PEDIDOS EN EL REGISTRO. El contrato esta en
/// `navegacion/pantalla_registrada.dart`.
///
/// La pantalla **no monta `Scaffold` ni `AppBar`**: el armazon ya pone la barra
/// lateral, la barra superior con este mismo titulo y la franja de estado. Aqui
/// solo se declara donde vive y como se llama.
///
/// `ruta_pedidos.dart` es de antes del armazon y ya no lo usa nadie: la ruta
/// `/orders` sale de aqui. Se deja mientras se confirma que nada externo lo
/// importa, y entonces se borra.
PantallaRegistrada registrarPedidos() => const PantallaRegistrada(
  ruta: '/orders',
  titulo: 'Pedidos',
  icono: Icons.inventory_2_outlined,
  enElMenu: true,
  construir: _construir,
);

Widget _construir(BuildContext contexto, GoRouterState estado) =>
    const PantallaPedidos();
