import 'dart:math' as math;

/// Haversine, calcado de `reglas-negocio.md` §1.1: R = 6371 km.
///
/// Vive aqui y no en `nucleo/geo/` porque esa pieza del PLAN (§1) todavia no
/// esta escrita y esta pantalla no toca nada fuera de su carpeta. El dia que
/// `nucleo/geo/geo.dart` exista, este fichero se borra y se importa aquel: la
/// distancia que ve el cliente y la que suma una ruta **tienen que salir de la
/// misma cuenta**, o el mismo cliente esta a 12,4 km en una pantalla y a 12,6 en
/// la otra.
abstract final class Geo {
  static const radioTierraKm = 6371.0;

  static double _rad(double grados) => grados * math.pi / 180;

  static double haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return radioTierraKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// A dos decimales, que es como los pinta la pantalla y como los devuelve
  /// `GET /api/customers` (`kmDelAlmacen`). Se redondea **una sola vez**, aqui:
  /// redondear dos veces mueve el limite de `Hasta 5 km` en los casos justos.
  static double km2(double valor) => (valor * 100).roundToDouble() / 100;
}
