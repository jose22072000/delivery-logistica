import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/tablero/datos/geo.dart';

void main() {
  group('la distancia al almacén', () {
    test('dos puntos iguales dan cero, no NaN', () {
      // El redondeo puede sacar 1.0000000002 de la raiz, y `asin` de eso es
      // NaN. Un NaN en la clave de ordenacion desordena la lista entera sin
      // fallar por ningun sitio.
      final km = kmHaversine(20.0247, -75.8219, 20.0247, -75.8219);
      expect(km, 0);
      expect(km.isNaN, isFalse);
    });

    test('un grado de latitud son ~111,19 km', () {
      final km = kmHaversine(20.0247, -75.8219, 21.0247, -75.8219);
      expect(km, closeTo(111.19, 0.05));
    });

    test('es la misma fórmula del servidor: simétrica', () {
      final ida = kmHaversine(20.0247, -75.8219, 20.1, -75.9);
      final vuelta = kmHaversine(20.1, -75.9, 20.0247, -75.8219);
      expect(ida, closeTo(vuelta, 0.000001));
    });
  });
}
