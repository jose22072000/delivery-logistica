import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../plataforma.dart';
import '../sincro/ciclo.dart';

/// POR QUE LA COPIA ESTA VACIA. **Son tres cosas, y hoy se decian como una.**
///
/// ## El caso, con fecha
///
/// Jose, 17/09/2026, entrando a `reparto.procovar.cloud`:
///
/// > «cuando entraste a la web me salia un mensaje de que habia que configurar
/// > un almacen en esa sucursal y despues aparecieron las cosas. Eso no puede
/// > pasar mi loco»
///
/// El almacen existia. Lo que pasaba es que **la web ya no tiene base en
/// disco**: desde el 16/09/2026 su base es en memoria, asi que **nace vacia en
/// cada carga de la pagina** y el ciclo la llena un segundo despues. En ese
/// segundo cada pantalla miraba su copia, la veia vacia y sacaba una conclusion
/// — y la conclusion era falsa: el Panel acusaba a la sucursal de no tener
/// almacen, Reportes decia que no habia nada que cuadrar.
///
/// En la APK eso no pasa y por eso no se habia visto: alli la base es un fichero
/// que sobrevive al cierre, se entra con el dia ya dentro, y «no se ha
/// descargado» es un estado de verdad que dura hasta que alguien trae el dia.
///
/// ## Las tres
///
///  * [todaviaBajando] — **la web, el primer segundo.** No se sabe nada porque
///    no ha dado tiempo. Lo unico honesto es *cargando*, sin diagnostico.
///  * [noSeDescargo] — **el aparato.** Es un estado real y se dice con las
///    palabras de siempre: se arregla trayendo el dia.
///  * [noPudoBajar] — **la web, cuando la bajada falla de verdad.** Aqui hay que
///    decirlo y dejar entrar: una rueda que no para nunca es peor que el mensaje
///    falso.
///
/// ## Y el suelo esta puesto, a proposito
///
/// [todaviaBajando] **no puede durar para siempre**. Sale de ahi por dos sitios
/// independientes, y hacen falta los dos:
///
///  1. **El ciclo termina** —bien o mal, da igual— y lo anota
///     ([EstadoDeLaPrimeraBajada.anotar], cableado en `proveedores.dart`). Es el
///     camino normal: una red muerta tumba el ciclo en menos de un minuto.
///  2. **El suelo de tiempo** ([EstadoDeLaPrimeraBajada.elSuelo]). Si por lo que
///     sea no llega a correr ningun ciclo, a los 20 s se deja de esperar igual.
///     Sin esto bastaria un ciclo que no arranca para dejar la web girando sin
///     fin, que es exactamente el fallo que esto viene a quitar, sólo que mudo.
enum PorQueEstaVacio { todaviaBajando, noSeDescargo, noPudoBajar }

/// ¿YA SE INTENTO BAJAR desde que cargo la pagina?
///
/// En el aparato nace en `true` y no se mueve: alli no hay «primera bajada de
/// esta carga» —la base es un fichero y lo que tenga dentro es lo que hay—, asi
/// que el mundo de la APK se queda **exactamente** como estaba.
class EstadoDeLaPrimeraBajada extends Notifier<bool> {
  /// EL SUELO. Lo que se espera como mucho antes de dejar de decir «cargando».
  ///
  /// Veinte segundos: mas de lo que tarda un ciclo con una conexion normal
  /// —el de la web entra en un segundo— y menos de lo que nadie aguanta mirando
  /// una rueda sin que nadie le diga nada.
  static const elSuelo = Duration(seconds: 20);

  @override
  bool build() {
    // Android, Windows y Linux: no hay nada que esperar.
    if (ref.watch(trabajaSinConexionProvider)) return true;

    final temporizador = Timer(elSuelo, () => state = true);
    ref.onDispose(temporizador.cancel);
    return false;
  }

  /// Lo llama el ciclo al acabar, **haya salido bien o mal**.
  ///
  /// Un ciclo [ResumenDelCiclo.sinSesion] no cuenta: ahi no se intento nada, ni
  /// una peticion, asi que no dice nada de si la bajada llega o no.
  void anotar(ResumenDelCiclo resumen) {
    if (resumen.sinSesion) return;
    state = true;
  }
}

final primeraBajadaProvider = NotifierProvider<EstadoDeLaPrimeraBajada, bool>(
  EstadoDeLaPrimeraBajada.new,
);

/// LA PREGUNTA QUE HACE CADA PANTALLA cuando su copia esta vacia.
///
/// Se lee por provider —y no llamando a [Destino] a pelo— para que una prueba
/// pueda ponerse en el otro destino sin compilar para web, que es lo mismo que
/// hacen `trabajaSinConexionProvider` y compania.
final porQueEstaVacioProvider = Provider<PorQueEstaVacio>((ref) {
  if (ref.watch(trabajaSinConexionProvider)) return PorQueEstaVacio.noSeDescargo;
  return ref.watch(primeraBajadaProvider)
      ? PorQueEstaVacio.noPudoBajar
      : PorQueEstaVacio.todaviaBajando;
});

/// LO QUE SE DICE EN LA WEB cuando algo no esta.
///
/// Van juntos y con nombre por lo mismo que [TextosDeCaida]: para que no se
/// cuele en la web ni una palabra del mundo del aparato. «Aparato», «sin
/// conexion», «se descargara», «con conexion baja sola» y parientes le explican
/// a quien esta sentado en la oficina con internet algo que en su caso no pasa
/// nunca.
abstract final class TextosDeLaWeb {
  /// Mientras la primera bajada va en camino. **Sin diagnostico**: todavia no
  /// se ha mirado nada, asi que no hay nada que acusar.
  static String cargando(String que) => 'Cargando $que...';

  /// Cuando la bajada no llego. Se dice, y se deja entrar.
  ///
  /// Mismo razonamiento que [TextosDeCaida.queHacer]: si la pagina cargo,
  /// conexion hay. Mandar a mirar la señal a quien esta en la oficina es
  /// mandarlo a mirar donde no es.
  static String noPudoBajar(String que) =>
      'No se pudieron traer $que. La página cargó, así que conexión hay: el '
      'que no contesta es el servidor. Prueba otra vez y, si sigue igual, '
      'avisa a la oficina.';
}
