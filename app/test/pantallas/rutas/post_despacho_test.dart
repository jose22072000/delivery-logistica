// La cuenta del post-despacho. Es una resta que decide si falta mercancia, asi
// que se comprueba con un caso escrito a mano.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/rutas/datos/post_despacho.dart';

void main() {
  final paradas = <ParadaDelCierre>[
    const ParadaDelCierre(
      pedidoId: 'p1',
      cliente: 'Ana',
      resultado: 'entregado',
      lineas: [LineaDeParada('Arroz', 2), LineaDeParada('Frijol', 1)],
    ),
    const ParadaDelCierre(
      pedidoId: 'p2',
      cliente: 'Beto',
      resultado: 'devuelto',
      nota: 'no había nadie',
      lineas: [LineaDeParada('Arroz', 3)],
    ),
    // NADIE la marco. Cuenta como que sigue arriba.
    const ParadaDelCierre(
      pedidoId: 'p3',
      cliente: 'Carla',
      lineas: [LineaDeParada('Arroz', 1), LineaDeParada('Aceite', 5)],
    ),
    const ParadaDelCierre(
      pedidoId: 'p4',
      cliente: 'Dani',
      resultado: 'cancelado',
      lineas: [LineaDeParada('Frijol', 2)],
    ),
  ];

  test('lo que QUEDA es todo lo que no se entrego, incluido lo sin marcar', () {
    final hoja = armarPostDespacho(paradas);

    final arroz = hoja.lineas.firstWhere((l) => l.producto == 'Arroz');
    expect(arroz.salio, 6);
    expect(arroz.entregado, 2);
    // 3 devueltos + 1 sin marcar: los dos siguen en el camion.
    expect(arroz.queda, 4);
    // La invariante que no se puede romper.
    expect(arroz.salio, arroz.entregado + arroz.queda);
  });

  test('un producto entregado entero NO sale en la hoja', () {
    final hoja = armarPostDespacho(const [
      ParadaDelCierre(
        pedidoId: 'p1',
        cliente: 'Ana',
        resultado: 'entregado',
        lineas: [LineaDeParada('Arroz', 2)],
      ),
    ]);
    expect(hoja.lineas, isEmpty);
  });

  test('el orden es por lo que mas queda y, a igualdad, por nombre', () {
    final hoja = armarPostDespacho(paradas);
    expect(
      [for (final l in hoja.lineas) l.producto],
      ['Aceite', 'Arroz', 'Frijol'],
    );
    // Aceite queda 5, Arroz 4, Frijol 2.
    expect(hoja.lineas.first.queda, 5);
  });

  test('las paradas se cuentan por como acabaron, y lo desconocido no se da por bueno', () {
    final hoja = armarPostDespacho([
      ...paradas,
      const ParadaDelCierre(
        pedidoId: 'p5',
        cliente: 'Eva',
        // Un valor que no reconocemos: cuenta como sin marcar.
        resultado: 'lo_que_sea',
        lineas: [],
      ),
    ]);
    expect(hoja.entregadas, 1);
    expect(hoja.devueltas, 1);
    expect(hoja.canceladas, 1);
    expect(hoja.sinMarcar, 2);
    // Pendientes = todo lo que no se entrego, en el orden en que llegaron.
    expect(
      [for (final p in hoja.pendientes) p.pedidoId],
      ['p2', 'p3', 'p4', 'p5'],
    );
  });

  test('una linea sin nombre no se puede sacar del almacen: se salta', () {
    final hoja = armarPostDespacho(const [
      ParadaDelCierre(
        pedidoId: 'p1',
        cliente: 'Ana',
        lineas: [LineaDeParada('   ', 9), LineaDeParada('Arroz', 1)],
      ),
    ]);
    expect(hoja.lineas.length, 1);
    expect(hoja.lineas.single.producto, 'Arroz');
  });
}
