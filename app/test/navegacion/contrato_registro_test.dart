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

  test('Reportes NO esta en el menu (pliego §8.1)', () {
    final reportes = pantallas.firstWhere((p) => p.ruta == '/reports');
    expect(reportes.enElMenu, isFalse);
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
