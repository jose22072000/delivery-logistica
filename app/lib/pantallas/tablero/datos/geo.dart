import 'dart:math' as math;

/// La distancia en linea recta, la MISMA formula que `km_haversine` en Postgres
/// y que `pricing.haversineDistance` en delivery. R = 6371 km.
///
/// Esta copiada aqui, en Dart, porque sin conexion el aparato tiene que poder
/// ordenar la mitad izquierda del tablero por si mismo: es media pantalla y es
/// justo por la tarde, que es cuando no hay senal. Lo que NO puede haber son
/// dos medidas distintas de «cuan lejos esta este cliente» — con esta misma se
/// le cobra el domicilio al cliente y con esta misma se arma la ruta.
double kmHaversine(double lat1, double lng1, double lat2, double lng2) {
  const radioKm = 6371.0;
  final dLat = _radianes(lat2 - lat1);
  final dLng = _radianes(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_radianes(lat1)) *
          math.cos(_radianes(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  // `clamp` porque con dos puntos identicos el redondeo puede dar 1.0000000002
  // y `asin` de eso es NaN — y un NaN en la clave de ordenacion desordena la
  // lista entera sin fallar por ningun sitio.
  return 2 * radioKm * math.asin(math.sqrt(a).clamp(0.0, 1.0));
}

double _radianes(double grados) => grados * math.pi / 180.0;
