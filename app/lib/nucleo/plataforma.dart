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
  static bool get trabajaSinConexion => !kIsWeb;
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
