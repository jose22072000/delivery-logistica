import 'preferencias_stub.dart'
    if (dart.library.js_interop) 'preferencias_web.dart'
    as destino;

/// LO QUE SE ELIGIO Y SOBREVIVE A CERRAR: la sucursal y la moneda.
///
/// ## Por que no vale la base local en la web
///
/// Se guardaban en la tabla `preferencias` de Drift, que en la APK es un fichero
/// y sobrevive. **En la web ya no**: desde que la base del navegador es en
/// memoria —la web lee del servidor y no guarda copia— esa tabla se vacia en cada
/// recarga, y con ella la sucursal elegida.
///
/// Se notaba: un Super Admin abria el tablero y tenia que volver a elegir La
/// Habana cada vez, y mientras tanto la pantalla decia «elige una sucursal».
/// Justo lo que se arreglo el 16/09 y se rompio por el otro lado el 17.
///
/// Asi que van donde le corresponde a cada destino:
///
///  * **web** → `localStorage`, que es donde ya vive la sesion
///    (`identidad/almacen_sesion_web.dart`) y lo unico que persiste ahi.
///  * **APK y escritorio** → la tabla de siempre, que es de la base de esa
///    persona y se va con ella al olvidarla.
///
/// Son dos elecciones de pantalla, no datos: si se pierden, lo peor que pasa es
/// que alguien vuelva a tocar un desplegable. Por eso nada de esto lanza.
abstract final class PreferenciasDelAparato {
  /// `true` donde hay que guardarlas fuera de la base local.
  static bool get fueraDeLaBase => destino.fueraDeLaBase;

  static String? leer(String clave) => destino.leer(clave);

  /// `null` borra. Guardar una cadena vacia y leerla luego como una eleccion es
  /// el fallo que ya se evito en la tabla.
  static void escribir(String clave, String? valor) =>
      destino.escribir(clave, valor);
}
