import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../registro/registro.dart';

/// El aviso de `connectivity_plus`, reducido a lo unico que se puede creer: que
/// el aparato **CREE** que hay red.
///
/// `pubspec.yaml` lo dice al lado de la dependencia y es literal: «PISTA de que
/// hay red, nunca la verdad». En Cuba el telefono ensena el wifi conectado y no
/// sale un paquete — el portal cautivo del hotel, la antena que responde al ARP
/// y a nada mas, la linea que se cayo aguas arriba. Por eso esto no dice «hay
/// red»: dice «vale la pena intentarlo», y quien decide si habia red es la
/// peticion, que o va o da `FalloDeRed`.
///
/// Se queda sólo con el flanco de subida. «Se fue la red» no dispara nada:
/// no hay nada que hacer sin red, y la aplicacion ya se comporta igual siempre.
Stream<bool> avisosDeConnectivityPlus() => Connectivity().onConnectivityChanged
    .map((resultados) => resultados.any((r) => r != ConnectivityResult.none));

/// La MISMA pista, preguntada una vez en vez de escuchada.
///
/// Hace falta para el boton: quien le da y no tiene senal no puede quedarse
/// cuarenta segundos mirando una rueda para acabar leyendo «no se pudo». Si el
/// aparato dice que no hay red, se dice **antes** de intentarlo y no se toca
/// nada.
///
/// **Y solo sirve para eso.** Si contesta que SI hay red, no se da por buena:
/// se intenta de verdad, porque en Cuba el telefono ensena el wifi conectado y
/// no sale un paquete. La pista sirve para ahorrar la espera cuando dice que no,
/// nunca para dar por hecho que la hay.
typedef PistaDeRed = Future<bool> Function();

Future<bool> hayPistaDeRed() async {
  try {
    final resultados = await Connectivity().checkConnectivity();
    return resultados.any((r) => r != ConnectivityResult.none);
  } on Object catch (e) {
    // Un destino sin soporte o un canal que no contesta **no es «no hay red»**:
    // es «no lo se», y ante la duda se intenta. Rendirse aqui dejaria sin
    // sincronizar a quien si tiene senal.
    Registro.aviso('no se pudo preguntar por la red, se intenta igual: $e');
    return true;
  }
}

/// Como se crea el temporizador. Se inyecta para poder probarlo: un
/// `Timer.periodic` suelto en una prueba es un temporizador colgado que hace
/// fallar por un motivo que no tiene nada que ver con lo que se estaba probando.
typedef CrearTemporizador = Timer Function(Duration, void Function(Timer));

/// EL VIGIA. Lo que dispara el ciclo cuando nadie se lo pide.
///
/// Tres ocasiones, y las tres hacen falta:
///
///  1. **Al entrar** — no es cosa de esta clase: lo dispara el portero en cuanto
///     hay sesion.
///  2. **Cuando vuelve la red** — el aviso de `connectivity_plus`. Es el camino
///     bueno en la APK: el logistico sale del almacen, coge cobertura y el dia
///     sube solo sin que toque nada.
///  3. **Cada tanto, mientras la aplicacion este delante** — porque el aviso de
///     arriba **puede no llegar nunca**. En web es lo normal, y en Android
///     tampoco esta garantizado despues de una siesta larga del proceso. Sin el
///     reloj, un aviso perdido es un dia perdido.
///
/// **Nada de esto corre sin sesion.** Quien lo comprueba es el ciclo, que le
/// pregunta al portero; aqui lo que se hace es no tener nada vivo cuando se sale:
/// al cerrar sesion se llama a [parar] y no queda ni suscripcion ni
/// temporizador. Un temporizador vivo despues de salir es trabajo corriendo
/// sobre una sesion muerta, y en las pruebas es un fallo que no dice nada.
class VigiaDeSincronizacion {
  VigiaDeSincronizacion({
    required Future<void> Function(String motivo) ciclo,
    Stream<bool> Function() avisosDeRed = avisosDeConnectivityPlus,
    Duration periodo = periodoPorDefecto,
    CrearTemporizador crearTemporizador = Timer.periodic,
  }) : _ciclo = ciclo,
       _avisosDeRed = avisosDeRed,
       _periodo = periodo,
       _crearTemporizador = crearTemporizador;

  /// Cinco minutos, y el numero esta pensado.
  ///
  /// Corto no puede ser: cada tic es una renovacion, una subida y una bajada por
  /// la conexion de alla, y hacerlo cada minuto es gastarle los datos y la
  /// bateria al logistico todo el dia para nada.
  ///
  /// Largo tampoco: esto es la unica red de seguridad de quien trabaja en web,
  /// donde el aviso de connectivity no llega. Media hora significa que alguien
  /// entra en la oficina, deja el dia arriba y se va antes de que suba.
  ///
  /// Cinco minutos son unos noventa ciclos en una jornada de ocho horas, y cada
  /// uno es una bajada por diferencias que casi siempre vuelve vacia.
  static const periodoPorDefecto = Duration(minutes: 5);

  final Future<void> Function(String motivo) _ciclo;
  final Stream<bool> Function() _avisosDeRed;
  final Duration _periodo;
  final CrearTemporizador _crearTemporizador;

  StreamSubscription<bool>? _suscripcion;
  Timer? _temporizador;
  bool _andando = false;
  bool _delante = true;

  bool get andando => _andando;

  /// `true` mientras haya un temporizador vivo. Es lo que mira la prueba de que
  /// al cerrar sesion no queda nada corriendo.
  bool get hayTemporizador => _temporizador != null;

  /// Hay sesion: a vigilar. Llamarlo dos veces no monta dos vigilancias.
  void arrancar() {
    if (_andando) return;
    _andando = true;

    _suscripcion = _avisosDeRed().listen(
      (hayPista) {
        if (!hayPista) return;
        _disparar('volvio la red');
      },
      // Que el plugin no conteste —un destino sin soporte, una prueba sin
      // canales— no puede tumbar la vigilancia: queda el reloj, que es
      // justamente para esto.
      onError: (Object e) =>
          Registro.aviso('vigia: el aviso de red no se pudo escuchar: $e'),
      cancelOnError: false,
    );

    _ponerTemporizador();
    Registro.info('vigia: en marcha (cada ${_periodo.inMinutes} min)');
  }

  /// Se cerro la sesion, o se para la aplicacion. **No queda nada vivo.**
  void parar() {
    if (!_andando && _temporizador == null && _suscripcion == null) return;
    _andando = false;
    _quitarTemporizador();
    unawaited(_suscripcion?.cancel());
    _suscripcion = null;
    Registro.info('vigia: parado');
  }

  /// El reloj sólo corre con la aplicacion delante.
  ///
  /// Detras no se gasta: en la APK el sistema congela el proceso de todas formas
  /// y en web la pestanna en segundo plano estrangula los temporizadores. Lo que
  /// no puede pasar es quedarse con un tic a medias de por vida, asi que al
  /// volver se dispara uno **ya**, que es justo el momento en que alguien saca el
  /// telefono del bolsillo despues de la mannana entera sin cobertura.
  void enPrimerPlano(bool si) {
    if (_delante == si) return;
    _delante = si;
    if (!_andando) return;
    if (si) {
      _ponerTemporizador();
      _disparar('la aplicacion volvio delante');
    } else {
      _quitarTemporizador();
    }
  }

  void _ponerTemporizador() {
    if (!_delante || _temporizador != null) return;
    _temporizador = _crearTemporizador(
      _periodo,
      (_) => _disparar('toco el reloj'),
    );
  }

  void _quitarTemporizador() {
    _temporizador?.cancel();
    _temporizador = null;
  }

  /// Un intento. Si falla no se marca nada como hecho: se vuelve a la espera.
  ///
  /// No se espera al resultado a proposito —quien dispara es un aviso o un tic,
  /// no hay nadie escuchando— pero el ciclo no lanza nunca, asi que aqui no se
  /// pierde ningun error.
  void _disparar(String motivo) {
    if (!_andando) return;
    _ciclo(motivo).ignore();
  }
}
