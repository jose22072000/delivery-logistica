// La geometria del recorrido. Se calcula EN EL APARATO, asi que es lo que decide
// el orden en que sale el camion cuando no hay con quien consultarlo.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/rutas/datos/geo.dart';

void main() {
  // Un grado de longitud en el ecuador: 6371 × π/180 ≈ 111.19 km. Con el origen
  // en (0,0) los numeros se pueden comprobar a mano.
  const origen = Punto(0, 0);
  const unDecimoDeGrado = 11.1195;

  test('haversine da los km y no redondea', () {
    expect(
      haversineKm(origen, const Punto(0, 0.1)),
      closeTo(unDecimoDeGrado, 0.001),
    );
    expect(haversineKm(origen, origen), 0);
    // Simetrica: de ida y de vuelta es lo mismo.
    expect(
      haversineKm(const Punto(21.38, -77.91), const Punto(20.88, -76.26)),
      closeTo(
        haversineKm(const Punto(20.88, -76.26), const Punto(21.38, -77.91)),
        1e-9,
      ),
    );
  });

  test('los casos limite del orden de visita son explicitos', () {
    expect(vecinoMasCercano(origen, const []), isEmpty);
    expect(vecinoMasCercano(origen, const [Parada('a', 5, 5)]), ['a']);
  });

  test('el orden es vecino mas proximo, no el orden de entrada', () {
    final orden = vecinoMasCercano(origen, const [
      Parada('lejos', 0, 0.3),
      Parada('cerca', 0, 0.1),
      Parada('medio', 0, 0.2),
    ]);
    expect(orden, ['cerca', 'medio', 'lejos']);
  });

  test('EL DESEMPATE LO GANA LA PRIMERA DE LA LISTA', () {
    // Dos paradas exactamente a la misma distancia del origen. La comparacion es
    // `<` estricta, asi que gana la primera. Si esto cambiara, el orden de las
    // paradas dejaria de cuadrar con el del servidor sin que nada estuviera roto.
    final orden = vecinoMasCercano(origen, const [
      Parada('norte', 0.1, 0),
      Parada('este', 0, 0.1),
    ]);
    expect(orden.first, 'norte');
  });

  test('los tramos son consecutivos y NO cierran el circuito', () {
    final medidas = tramos(origen, const [
      Parada('a', 0, 0.1),
      Parada('b', 0, 0.2),
    ]);
    expect(medidas.length, 2);
    expect(medidas[0], closeTo(unDecimoDeGrado, 0.001));
    expect(medidas[1], closeTo(unDecimoDeGrado, 0.001));
  });

  test('los km del camion incluyen el regreso', () {
    // origen → 0.1 → 0.2 → origen = 0.1 + 0.1 + 0.2 grados = 4 décimas.
    final km = kmDelCircuito(origen, const [
      Parada('a', 0, 0.1),
      Parada('b', 0, 0.2),
    ]);
    expect(km, closeTo(unDecimoDeGrado * 4, 0.01));
    expect(kmDelCircuito(origen, const []), 0);
  });
}
