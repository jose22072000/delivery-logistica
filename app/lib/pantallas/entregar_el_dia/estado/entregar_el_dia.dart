import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../../nucleo/registro/registro.dart';

/// COMO QUEDO EL GESTO de entregar el dia.
///
/// El espejo de `LoQueSeTrajo`, y por el mismo motivo: lo que se ve al soltar el
/// boton no puede ser un tic. Aqui la cifra que importa es **cuantos quedan**,
/// porque un apunte que se queda en el telefono es trabajo que nadie sabe que
/// falta hasta que no cuadra el inventario.
class LoQueSeEntrego {
  const LoQueSeEntrego({
    required this.hora,
    required this.subidos,
    required this.quedan,
    required this.rechazados,
    this.fallo,
    this.sinSesion = false,
    this.sinSenal = false,
  });

  /// Cuando acabo el gesto, con el reloj del aparato.
  final DateTime hora;

  /// Cuantos apuntes aceptó el servidor en este gesto.
  final int subidos;

  /// Cuantos siguen pendientes en la cola DESPUES del gesto. **Contado en la
  /// base**, no restado de lo que se mando.
  final int quedan;

  /// Cuantos hay rechazados esperando a que una persona decida. No se reintentan
  /// y no se borran.
  final int rechazados;

  final Object? fallo;
  final bool sinSesion;

  /// El aparato dijo que no habia red y **no se intento nada**.
  final bool sinSenal;

  /// LA GUARDA. Verde solo si NO QUEDA NADA.
  ///
  /// Los rechazados cuentan, y es a proposito: un apunte rechazado **no subio**.
  /// Esta ahi, con su motivo, esperando a que alguien decida — y mientras
  /// espera, el dia no esta entregado. Pintar verde con tres rechazos en la
  /// bandeja es exactamente la forma de que nadie los mire nunca, que es lo
  /// mismo que borrarlos pero con peor conciencia.
  bool get completo =>
      !sinSenal &&
      !sinSesion &&
      fallo == null &&
      quedan == 0 &&
      rechazados == 0;

  /// Subio algo pero no todo. Es el estado del que hay que hablar.
  bool get aMedias => !completo && !sinSenal && !sinSesion;

  @override
  String toString() =>
      'LoQueSeEntrego(hora: $hora, subidos: $subidos, quedan: $quedan, '
      'rechazados: $rechazados, fallo: $fallo, sinSesion: $sinSesion, '
      'sinSenal: $sinSenal)';
}

/// EL GESTO: «entrego el día que trabajé».
///
/// El otro lado de traer el dia. El logistico cierra rutas toda la tarde en el
/// almacen sin cobertura, sale a la calle, y **quiere darle a un boton y ver que
/// se fue**. Hoy sube solo cuando el vigia se entera, y ese «solo» es justo lo
/// que no se ve: cierra el dia, se va a su casa, y nadie descubre que no subio
/// hasta que no cuadra el inventario (`sincronizacion.md` §3).
///
/// ## Lo que esta clase NO hace
///
///  * **No escribe otra subida.** Llama al MISMO ciclo que el boton de bajar
///    (renovar → subir → bajar): quien entrega el dia tambien quiere las rutas
///    nuevas, y partir el ciclo en dos seria dos protocolos para lo mismo.
///  * **No monta un segundo candado.** El de «un solo ciclo en vuelo» vive en
///    `ciclo.dart`, asi que dar a los DOS botones a la vez no lanza dos ciclos:
///    el segundo se engancha al primero.
///  * **No borra nada de la cola.** Quien resuelve un apunte es la cola, con la
///    respuesta del servidor en la mano.
class EntregarElDia extends Notifier<LoQueSeEntrego?> {
  @override
  LoQueSeEntrego? build() => null;

  Future<LoQueSeEntrego> ahora({String motivo = 'entregar el dia'}) async {
    state = null;

    final reloj = ref.read(relojProvider);
    final base = ref.read(baseProvider);

    // SIN SENAL SE DICE ANTES DE INTENTARLO. Y aqui importa mas que en el otro
    // gesto: quien le da a esto lleva el dia dentro del telefono y necesita
    // saber, en el acto, que sigue ahi y que no se ha ido.
    if (!await ref.read(pistaDeRedProvider)()) {
      Registro.info('entregar el dia: sin red, no se sale');
      return state = LoQueSeEntrego(
        hora: reloj(),
        subidos: 0,
        quedan: await base.cuantosPendientes(),
        rechazados: await _cuantosRechazados(base),
        sinSenal: true,
      );
    }

    final resumen = await ref.read(cicloProvider).ahora(motivo: motivo);

    // Y AHORA se cuenta EN LA COLA, no en lo que el servidor dijo que acepto.
    // Un apunte que el servidor dio por bueno pero que la cola no llego a marcar
    // —se corto la luz entre una cosa y la otra— sigue pendiente, y lo que hay
    // que ensenar es lo que va a volver a salir, no lo que se creyo enviar.
    final entrego = LoQueSeEntrego(
      hora: reloj(),
      subidos: resumen.subidos,
      quedan: await base.cuantosPendientes(),
      rechazados: await _cuantosRechazados(base),
      fallo: resumen.fallo,
      sinSesion: resumen.sinSesion,
    );

    Registro.info('entregar el dia: $entrego');
    return state = entrego;
  }

  void olvidar() => state = null;

  Future<int> _cuantosRechazados(BaseLocal base) async {
    final filas = await (base.select(
      base.apuntes,
    )..where((a) => a.estado.equalsValue(EstadoApunte.rechazado))).get();
    return filas.length;
  }
}

final entregarElDiaProvider = NotifierProvider<EntregarElDia, LoQueSeEntrego?>(
  EntregarElDia.new,
);

/// LOS RECHAZADOS que esperan a que una persona decida.
///
/// Sale de la cola local y no del panel de `/sync`: el panel es lo que ve quien
/// vigila los diez aparatos, y esto es lo que tiene que ver **el logistico de
/// este telefono**, tambien sin conexion.
final rechazadosProvider = StreamProvider<List<Apunte>>(
  (ref) => ref.watch(colaProvider).rechazados(),
);
