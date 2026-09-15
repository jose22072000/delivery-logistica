import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/pantallas.dart';

/// Lo que garantiza el contrato de registro. Si un agente de pantalla lo rompe,
/// falla aqui y no en la pantalla de alguien.
void main() {
  final pantallas = pantallasDeLaAplicacion();

  test('ninguna ruta repetida', () {
    final rutas = pantallas.map((p) => p.ruta).toList();
    expect(rutas.toSet().length, rutas.length, reason: 'hay una ruta repetida');
  });

  test('todas las rutas empiezan por barra', () {
    for (final p in pantallas) {
      expect(p.ruta.startsWith('/'), isTrue, reason: p.ruta);
    }
  });

  test('las seis del pliego mas el tablero y reportes estan registradas', () {
    final rutas = pantallas.map((p) => p.ruta).toSet();
    expect(
      rutas,
      containsAll(<String>[
        '/dashboard',
        '/routes',
        '/orders',
        '/customers',
        '/vehicles',
        '/warehouses',
        '/reports',
        '/tablero',
      ]),
    );
  });

  test('Reportes SI esta en el menu, a proposito', () {
    // Iba en `false` copiando al Next, que no la tiene en su barra lateral y
    // solo se llega desde las acciones rapidas del Panel. Asi copiado, Jose no
    // la encontro: «esa vista de reportes no sale en los links para moverse».
    //
    // Una pantalla entera detras de un atajo del Panel es una pantalla que nadie
    // abre, y esta es la que se usa para cuadrar la caja. El patron se sigue
    // salvo donde se equivoca.
    final reportes = pantallas.firstWhere((p) => p.ruta == '/reports');
    expect(
      reportes.enElMenu,
      isTrue,
      reason: 'si vuelve a salir del menu que sea por una razon, no por copiar',
    );
    expect(reportes.titulo, 'Reportes');
  });

  test('las etiquetas del menu son las literales del pliego', () {
    final porRuta = {for (final p in pantallas) p.ruta: p.titulo};
    expect(porRuta['/dashboard'], 'Panel');
    expect(porRuta['/routes'], 'Rutas');
    expect(porRuta['/orders'], 'Pedidos');
    expect(porRuta['/customers'], 'Clientes');
    expect(porRuta['/vehicles'], 'Vehículos');
    expect(porRuta['/warehouses'], 'Almacenes');
  });

  test('todo lo que sale en el menu tiene icono', () {
    for (final p in pantallas.where((p) => p.enElMenu)) {
      expect(p.icono, isNotNull, reason: p.ruta);
    }
  });
}
