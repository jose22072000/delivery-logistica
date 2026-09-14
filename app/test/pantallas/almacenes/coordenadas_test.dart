import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/almacenes/datos/coordenadas.dart';

/// `parseCoordInput`, con los formatos de `reglas-negocio.md` §9.
///
/// Es la unica via para poner un punto cuando no hay autocompletado, asi que un
/// formato que no se acepte es un almacen que no se puede colocar.
void main() {
  test('los formatos que acepta', () {
    expect(leerCoordenadas('-23.5505, -46.6333'), const PuntoEnElMapa(-23.5505, -46.6333));
    expect(leerCoordenadas('23.55 -46.63'), const PuntoEnElMapa(23.55, -46.63));
    expect(leerCoordenadas('19.83;-75.82'), const PuntoEnElMapa(19.83, -75.82));
    // Con espacios de sobra delante y detras, que es como llega de un pegado.
    expect(leerCoordenadas('  20.0247 , -75.8219  '), const PuntoEnElMapa(20.0247, -75.8219));
    expect(leerCoordenadas('0,0'), const PuntoEnElMapa(0, 0));
  });

  test('lo que rechaza', () {
    expect(leerCoordenadas(''), isNull);
    expect(leerCoordenadas('19.83'), isNull);
    expect(leerCoordenadas('calle 5 entre 3 y 7'), isNull);
    // Maximo 3 digitos enteros.
    expect(leerCoordenadas('1234.5, -75.8'), isNull);
    // Fuera del mundo.
    expect(leerCoordenadas('91, 0'), isNull);
    expect(leerCoordenadas('0, 181'), isNull);
    expect(leerCoordenadas('-91, 0'), isNull);
    expect(leerCoordenadas('0, -181'), isNull);
  });
}
