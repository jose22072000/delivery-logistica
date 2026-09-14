// La geometria del recorrido, calcada de `../../../../docs/reglas-negocio.md` §1.
//
// **Por que vive aqui y no en `lib/nucleo/geo/`:** el nucleo de geometria es de
// otra ola y todavia no existe; esta tarea sólo escribe dentro de
// `lib/pantallas/`. Cuando se cree, este fichero se mueve tal cual —es Dart puro,
// sin Drift ni Flutter dentro— y sólo cambian los `import`.
//
// **Por que se calca en vez de pedirselo al servidor:** armar la ruta es lo que
// pasa en el patio del almacen, donde no hay senal. Si los km y el orden de
// visita los pusiera el servidor, la ruta no se podria armar sin conexion, que es
// justo el caso de uso principal del proyecto.

import 'dart:math' as math;

/// Un punto en el mapa. Deliberadamente tonto: lo unico que hace falta para
/// medir.
class Punto {
  const Punto(this.lat, this.lng);

  final double lat;
  final double lng;
}

/// Una parada: un punto con su identificador.
class Parada {
  const Parada(this.id, this.lat, this.lng);

  final String id;
  final double lat;
  final double lng;

  Punto get punto => Punto(lat, lng);
}

/// Radio terrestre en km. La misma constante que el servidor.
const radioTierraKm = 6371.0;

double _aRadianes(double grados) => grados * math.pi / 180;

/// Haversine. **Sin redondeo**, igual que `pricing.ts`: el redondeo lo pone
/// quien enseña el numero, no quien lo calcula. Redondear aqui hace que la suma
/// de diez tramos no cuadre con la suma que hace el servidor.
double haversineKm(Punto a, Punto b) {
  final dLat = _aRadianes(b.lat - a.lat);
  final dLng = _aRadianes(b.lng - a.lng);
  final s =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_aRadianes(a.lat)) *
          math.cos(_aRadianes(b.lat)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(s), math.sqrt(1 - s));
  return radioTierraKm * c;
}

/// El orden de visita por **vecino mas proximo**, sin 2-opt ni nada despues.
///
/// Dos detalles que hay que conservar letra a letra o el orden cambia:
///
///  * los casos limite son explicitos: 0 paradas → `[]`, 1 parada → `[su id]`;
///  * **el desempate lo gana la PRIMERA de la lista** (la comparacion es `<`
///    estricta, no `<=`). Con dos clientes a la misma distancia, el orden de
///    salida del camion tiene que ser el mismo aqui y en el servidor, o la
///    paridad falla sin que nada este roto.
List<String> vecinoMasCercano(Punto origen, List<Parada> paradas) {
  if (paradas.isEmpty) return const [];
  if (paradas.length == 1) return [paradas.first.id];

  final quedan = [...paradas];
  final orden = <String>[];
  var actual = origen;

  while (quedan.isNotEmpty) {
    var masCerca = 0;
    var distanciaMinima = double.infinity;
    for (var i = 0; i < quedan.length; i++) {
      final distancia = haversineKm(actual, quedan[i].punto);
      if (distancia < distanciaMinima) {
        distanciaMinima = distancia;
        masCerca = i;
      }
    }
    final elegida = quedan.removeAt(masCerca);
    orden.add(elegida.id);
    actual = elegida.punto;
  }
  return orden;
}

/// Las distancias consecutivas `origen→p1, p1→p2, …`, una por parada.
///
/// **No cierra el circuito**: el regreso al origen lo suma quien llame, porque
/// hay dos numeros distintos y el pliego pinta el de «incl. regreso».
List<double> tramos(Punto origen, List<Parada> ordenadas) {
  final salida = <double>[];
  var actual = origen;
  for (final parada in ordenadas) {
    salida.add(haversineKm(actual, parada.punto));
    actual = parada.punto;
  }
  return salida;
}

/// Los km del camion: los tramos **mas el regreso al origen**. Es un circuito
/// cerrado, y es el numero que la pantalla enseña como `<km> km (incl. regreso)`.
double kmDelCircuito(Punto origen, List<Parada> ordenadas) {
  if (ordenadas.isEmpty) return 0;
  final ida = tramos(origen, ordenadas).fold<double>(0, (a, b) => a + b);
  return ida + haversineKm(ordenadas.last.punto, origen);
}
