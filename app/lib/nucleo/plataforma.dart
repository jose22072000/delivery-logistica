import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// LO QUE ESTE DESTINO TIENE QUE SABER HACER.
///
/// ## Por que una capacidad con nombre y no `kIsWeb` repartido
///
/// Palabras de Jose, 15/09/2026:
///
/// > «el trabajo sin conexion es solo para las aplicaciones cojone la web
/// > siempre va a estar en internet»
/// > «la web siempre va a tener el internet por q esta en la nube eso es para la
/// > apk y la desktop quitame eso de la web»
///
/// O sea: el aparato de prepararse para no tener senal —«Configurando
/// Reparto», traer el dia a mano, la franja de «Trabajando sin conexion», la
/// promesa del dia entero sin cobertura— es de la APK y del escritorio. En un
/// navegador con internet eso no le explica nada a nadie: le explica algo que en
/// su caso nunca pasa.
///
/// `kIsWeb` escrito a mano en cinco ficheros dice **como se pregunta**, no **que
/// se pregunta**: quien lee `if (kIsWeb) ... ` dentro del Panel tiene que
/// adivinar por que la web no ensena esa pieza. `trabajaSinConexion` lo dice, y
/// ademas deja el dia que aparezca un cuarto destino —una PWA instalada, un
/// kiosco— en un solo sitio que cambiar.
///
/// ## Lo que esto NO decide
///
/// **La base local y la sincronizacion se quedan enteras en web.** Las siete
/// pantallas leen de Drift y no del servidor; quitarle la descarga a la web la
/// dejaria en blanco. Lo que esta capacidad apaga es **lo que se ve y lo que se
/// le pide a la persona**, nunca el motor: en web la base local es una cache de
/// la que nadie habla.
abstract final class Destino {
  /// ¿Hay que prepararse para quedarse sin senal?
  ///
  /// `true` en Android, Windows y Linux — el logistico se va al patio de un
  /// almacen con el dia dentro del aparato. `false` en web, que se abre desde un
  /// navegador con conexion, siempre.
  ///
  /// **Este es el unico `kIsWeb` de todo lo que cuelga de aqui**, y es a
  /// proposito: la prueba de mutacion consiste en cambiar esta linea por `true`
  /// o por `false` y ver caer el par de pruebas del otro lado.
  static bool get trabajaSinConexion => _comoSiFueraWeb ? false : !kIsWeb;

  /// SOLO PARA PRUEBAS: correr algo como si se estuviera en un navegador.
  ///
  /// Las reglas de la web —no guardar copia, no proteger trabajo que no existe,
  /// no enseñar el aparato de prepararse para no tener senal— son la mitad de
  /// este proyecto, y hasta hoy no habia forma de ejercitarlas sin compilar para
  /// web. El resultado es que se escribian y nadie las comprobaba: la web estuvo
  /// sin poder subir un solo apunte desde que existe y no habia ni una prueba
  /// que lo dijera.
  ///
  /// Se restaura SIEMPRE, tambien si lo de dentro lanza.
  static Future<T> comoSiFueraWeb<T>(Future<T> Function() que) async {
    _comoSiFueraWeb = true;
    try {
      return await que();
    } finally {
      _comoSiFueraWeb = false;
    }
  }

  static bool _comoSiFueraWeb = false;
}

/// La capacidad, por Riverpod.
///
/// Se lee por provider y no llamando a [Destino] directamente para que una
/// prueba pueda ponerse en el otro destino sin compilar para web: montar la
/// aplicacion con `trabajaSinConexionProvider.overrideWithValue(false)` es
/// exactamente lo que ve alguien que abre el navegador.
final trabajaSinConexionProvider = Provider<bool>(
  (ref) => Destino.trabajaSinConexion,
);

/// LO QUE SE LE DICE A ALGUIEN CUANDO EL SERVIDOR NO CONTESTA, segun donde
/// tenga abierta la aplicacion.
///
/// Es una funcion con nombre y no un `if` metido en la pantalla por un motivo
/// concreto: el 16/09/2026 el acceso de la WEB fallaba por CORS —auth no
/// autorizaba el origen del reparto— y la pantalla lo contaba como «comprueba la
/// señal». Un fallo de configuracion del servidor disfrazado de problema de
/// cobertura, en un producto donde la cobertura falla de verdad todos los dias.
/// Nadie lo habria buscado donde estaba.
///
/// La regla:
///
///  * **En el aparato** (Android, escritorio) «no hay señal» es casi siempre
///    verdad, y ademas hay algo que contar: lo que se bajo sigue dentro.
///  * **En la web** es casi siempre mentira. Si la pagina cargo, conexion hay.
///    Lo que no contesta es el servidor, y mandar a mirar la señal a quien esta
///    sentado en la oficina es mandarlo a mirar donde no es.
abstract final class TextosDeCaida {
  /// El titular del recuadro.
  static String titular({required bool sinConexion}) => sinConexion
      ? 'Sin conexión con el servidor. Para entrar hace falta conexión; '
            'prueba otra vez cuando haya señal.'
      : 'El servidor de acceso no contesta.';

  /// La linea de debajo: que hacer.
  static String queHacer({required bool sinConexion}) => sinConexion
      ? 'Comprueba la señal. Lo que ya estaba descargado sigue en el aparato.'
      : 'La página cargó, así que conexión hay: el que no contesta es el '
            'servidor. Prueba otra vez y, si sigue igual, avisa a la oficina.';
}
