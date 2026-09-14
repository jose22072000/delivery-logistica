import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// ============================================================================
/// EL CONTRATO DE REGISTRO DE RUTAS — léelo antes de escribir tu pantalla.
/// ============================================================================
///
/// El armazon (barra lateral, barra superior, franja de estado) lo monta
/// `navegacion/`. Tu pantalla **no monta ninguna de esas tres cosas**: se
/// enchufa, y el armazon la envuelve.
///
/// Son tres pasos y ninguno toca un fichero de otro:
///
///  1. En tu carpeta creas **un fichero propio**, `lib/pantallas/<tuya>/registro.dart`,
///     con **una sola funcion de nivel superior** que devuelve una
///     `PantallaRegistrada`:
///
///     ```dart
///     // lib/pantallas/pedidos/registro.dart
///     import 'package:flutter/widgets.dart';
///     import '../../navegacion/pantalla_registrada.dart';
///     import 'vista/pantalla_pedidos.dart';
///
///     PantallaRegistrada registrarPedidos() => PantallaRegistrada(
///           ruta: '/orders',
///           titulo: 'Pedidos',              // literal de la barra superior
///           icono: Icons.inventory_2_outlined,
///           enElMenu: true,
///           construir: (contexto, estado) => const PantallaPedidos(),
///         );
///     ```
///
///  2. En `lib/navegacion/pantallas.dart` sustituyes **tu** linea
///     `_pendiente('/orders', …)` por `registrarPedidos()` y anades el import.
///     Es la UNICA linea que tocas fuera de tu carpeta: una linea por pantalla,
///     asi que dos agentes no chocan aunque entren a la vez.
///
///  3. Ya esta. La entrada del menu, el titulo, el reloj de datos, la cola
///     pendiente y el selector de sucursal salen solos.
///
/// **Los filtros van en la URL** (`estado.uri.queryParameters`), que es lo que
/// hace que en web se pueda mandar un enlace a la lista ya filtrada. Lee de ahi
/// y escribe con `context.go(...)`; no guardes el filtro solo en un `State`.
///
/// **Tu pantalla no lleva `Scaffold` ni `AppBar`.** El armazon ya pone los dos:
/// devolver otro deja dos barras superiores y rompe el selector de sucursal.
/// ============================================================================
typedef ConstructorDePantalla =
    Widget Function(BuildContext contexto, GoRouterState estado);

class PantallaRegistrada {
  const PantallaRegistrada({
    required this.ruta,
    required this.titulo,
    required this.construir,
    this.icono,
    this.enElMenu = false,
    this.subrutas = const <RouteBase>[],
  });

  /// La ruta, con barra delante: `/dashboard`, `/orders`, `/routes`…
  final String ruta;

  /// El titulo que pinta la barra superior. **Literal del pliego**, en espanol.
  final String titulo;

  final ConstructorDePantalla construir;

  /// El icono de la barra lateral. Solo hace falta si [enElMenu].
  final IconData? icono;

  /// Si sale en la barra lateral. **Reportes va a `false`**: el pliego (§8.1)
  /// dice que la pantalla existe pero NO esta en el menu; se llega por URL y
  /// desde las acciones rapidas del Panel.
  final bool enElMenu;

  /// Rutas colgando de esta, si tu pantalla las necesita.
  final List<RouteBase> subrutas;

  /// Lo que consume `rutas.dart`. Aqui y en ningun otro sitio se decide como se
  /// traduce una pantalla registrada a una ruta de go_router.
  GoRoute aGoRoute() => GoRoute(
    path: ruta,
    builder: construir,
    routes: subrutas,
  );
}
