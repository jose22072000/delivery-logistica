import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'armazon.dart';
import 'pantalla_registrada.dart';
import 'pantallas.dart';

/// La primera pantalla: la de la manana.
const rutaDeInicio = '/dashboard';

/// Monta el enrutador a partir del REGISTRO.
///
/// Aqui no hay ni una ruta escrita a mano: salen todas de
/// `pantallasDeLaAplicacion()`. Por eso anadir una pantalla es una linea en
/// `pantallas.dart` y nada mas, y por eso el menu y las rutas **no pueden
/// desincronizarse**: son la misma lista.
///
/// [pantallas] se puede pasar en los tests para montar el armazon con dos
/// pantallas de mentira, sin arrastrar la base local a un test de widget.
GoRouter crearEnrutador({
  List<PantallaRegistrada>? pantallas,
  String inicial = rutaDeInicio,
}) {
  final lista = pantallas ?? pantallasDeLaAplicacion();

  return GoRouter(
    initialLocation: inicial,
    routes: <RouteBase>[
      // La raiz al panel. En web alguien escribe el dominio a secas y tiene que
      // caer en algun sitio.
      GoRoute(path: '/', redirect: (_, _) => inicial),
      ShellRoute(
        builder: (contexto, estado, hijo) => Armazon(
          pantallas: lista,
          // `matchedLocation` y no `uri.toString()`: los filtros van en la URL
          // (`/orders?municipio=…`) y la entrada del menu tiene que seguir
          // marcada con el filtro puesto.
          rutaActual: estado.matchedLocation,
          child: hijo,
        ),
        routes: <RouteBase>[for (final p in lista) p.aGoRoute()],
      ),
    ],
    errorBuilder: (contexto, estado) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No hay ninguna pantalla en ${estado.uri.path}.'),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => contexto.go(inicial),
                child: const Text('Ir al panel'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
