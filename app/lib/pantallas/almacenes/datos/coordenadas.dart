/// `parseCoordInput`, calcado de `reglas-negocio.md` §9.
///
/// Sin conexion no hay autocompletado de direccion ni geocodificacion inversa
/// —eso es Nominatim, y Nominatim es red—, asi que **escribir el punto a mano es
/// la unica via que queda siempre**. Por eso la funcion vive aparte y se prueba
/// sola: si acepta un formato de menos, alguien se queda sin poder poner el
/// almacen donde esta.
class PuntoEnElMapa {
  const PuntoEnElMapa(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) =>
      other is PuntoEnElMapa && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => '$lat, $lng';
}

/// Maximo 3 digitos enteros, `,` `;` o espacio como separador.
final _formato = RegExp(
  r'^(-?\d{1,3}(?:\.\d+)?)\s*[,;\s]\s*(-?\d{1,3}(?:\.\d+)?)$',
);

/// Devuelve el punto o `null`. `null` significa «no se entiende», y la pantalla
/// lo dice; no se inventa un 0,0, que cae en el golfo de Guinea y desde ahi se
/// cotizan domicilios de nueve mil kilometros.
PuntoEnElMapa? leerCoordenadas(String texto) {
  final casa = _formato.firstMatch(texto.trim());
  if (casa == null) return null;
  final lat = double.tryParse(casa.group(1)!);
  final lng = double.tryParse(casa.group(2)!);
  if (lat == null || lng == null) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return PuntoEnElMapa(lat, lng);
}
