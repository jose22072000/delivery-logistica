import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../navegacion/estado_navegacion.dart';
import '../../../nucleo/proveedores.dart';
import '../../../nucleo/registro/registro.dart';
import '../../../nucleo/sincro/recuento.dart';

/// COMO QUEDO EL GESTO de traer el dia.
///
/// Lo que aqui se guarda es lo que la persona ve al soltar el boton, y por eso
/// no es un `bool` ni un tic: son los numeros de lo que tiene, la hora de la que
/// son, y **lo que le falta**. Un gesto que solo pudiera decir «bien» o «mal»
/// dejaria fuera el unico caso que importa de verdad: el que bajo casi todo.
class LoQueSeTrajo {
  const LoQueSeTrajo({
    required this.hora,
    required this.recuento,
    this.faltan = const <Falta>[],
    this.subidos = 0,
    this.fallo,
    this.sinSesion = false,
    this.sinSenal = false,
  });

  /// Cuando acabo el gesto, con el reloj del aparato.
  final DateTime hora;

  /// Lo que hay en la BASE, contado despues de bajar.
  final RecuentoDeLoQueHay recuento;

  /// Lo que no esta, con su motivo. **Vacio no significa que todo fuera bien**:
  /// hay que mirar tambien [fallo].
  final List<Falta> faltan;

  /// Apuntes de la cola que subieron de paso. Se dice porque quien le da al
  /// boton por la mannana puede traer el cierre de ayer dentro del telefono.
  final int subidos;

  final Object? fallo;
  final bool sinSesion;

  /// El aparato dijo que no habia red y **no se intento nada**. No es un fallo:
  /// es que no se llego a salir.
  final bool sinSenal;

  /// LA GUARDA. Verde solo si se trajo TODO.
  ///
  /// Las cuatro condiciones estan aqui y no repartidas por la pantalla a
  /// proposito: el dia que alguien pinte un tic verde, lo va a pintar mirando
  /// esto. Si `faltan` saliera de esta cuenta, un aparato sin catalogo de
  /// productos diria «ya lo tienes» y se iria al almacen a cargar un camion con
  /// los pesos a cero — que es exactamente el fallo que este boton existe para
  /// evitar.
  bool get completo =>
      !sinSenal && !sinSesion && fallo == null && faltan.isEmpty;

  /// Se trajo algo, pero no todo. Es el estado del que hay que hablar.
  bool get aMedias => !completo && !sinSenal && !sinSesion;

  @override
  String toString() =>
      'LoQueSeTrajo(hora: $hora, faltan: $faltan, fallo: $fallo, '
      'sinSesion: $sinSesion, sinSenal: $sinSenal)';
}

/// EL GESTO: «cojo el día y me lo llevo».
///
/// No es un boton de refrescar. Es lo que hace un logistico de sucursal por la
/// mannana, donde hay senal, antes de meterse en el almacen a pasar el dia sin
/// cobertura: le da, ve que se carga, y se va sabiendo que lo tiene todo.
///
/// ## Lo que esta clase NO hace
///
///  * **No escribe otra bajada.** Llama a `CicloDeSincronizacion.ahora()`, que
///    es renovar → subir → bajar en ese orden y por las razones de
///    `docs/sincronizacion.md`.
///  * **No monta un segundo candado.** El de «un solo ciclo en vuelo» vive en
///    `ciclo.dart`; quien llame dos veces seguidas recibe el MISMO futuro y hay
///    un solo ciclo. Poner aqui un `if (corriendo) return` seria un candado
///    nuevo, y dos candados no son ningun candado.
///  * **No se cree lo que contesto el servidor.** Los numeros se cuentan en la
///    base local **despues** de bajar (`recuento.dart`).
class TraerElDia extends Notifier<LoQueSeTrajo?> {
  @override
  LoQueSeTrajo? build() => null;

  /// Trae el dia. Devuelve lo mismo que deja en el estado.
  Future<LoQueSeTrajo> ahora({String motivo = 'lo pidio la persona'}) async {
    // Lo anterior se borra ANTES de empezar: dejar los numeros de las 8:14
    // mientras corre el gesto de las 11:30 es ensenar una hora que ya no es.
    state = null;

    final reloj = ref.read(relojProvider);
    final recontador = ref.read(recontadorProvider);

    // SIN SENAL SE DICE ANTES DE INTENTARLO, no despues de cuarenta segundos de
    // rueda. La pista sirve para esto y solo para esto: si dijera que SI hay
    // red no se daria por buena —en Cuba el aparato ensena el wifi conectado y
    // no sale un paquete—, se intenta igual y quien decide es la peticion.
    if (!await ref.read(pistaDeRedProvider)()) {
      Registro.info('traer el dia: el aparato dice que no hay red, no se sale');
      final guardado = await recontador.ahora();
      return state = LoQueSeTrajo(
        hora: reloj(),
        recuento: guardado,
        // Lo que falta se dice TAMBIEN sin senal. La pregunta «¿que me llevo?»
        // es exactamente igual de valida sin cobertura, y es justo cuando mas se
        // hace: visto en el navegador el 15/09/2026, con el catalogo a cero la
        // tabla lo pintaba en verde con un 0 al lado porque aqui no se
        // calculaban las faltas. Un cero en verde se lee como un dato.
        faltan: Faltas.de(guardado),
        sinSenal: true,
      );
    }

    final resumen = await ref.read(cicloProvider).ahora(motivo: motivo);

    // Y AHORA se cuenta, en la base y no en la respuesta.
    final recuento = await recontador.ahora();
    final trajo = LoQueSeTrajo(
      hora: reloj(),
      recuento: recuento,
      // Sin sesion no se intento nada: listar las nueve colecciones como «no
      // estan» seria culpar a la red de algo que es de la puerta.
      faltan: resumen.sinSesion ? const <Falta>[] : Faltas.de(recuento),
      subidos: resumen.subidos,
      fallo: resumen.fallo,
      sinSesion: resumen.sinSesion,
    );

    Registro.info('traer el dia: $trajo');
    // El banner en calma tambien cuenta filas: que se refresque.
    ref.invalidate(loQueHayProvider);
    return state = trajo;
  }

  /// Vuelve al estado de calma, sin borrar nada de la base. Lo llama el cajon al
  /// cerrarse para que la proxima vez no se abra con el resultado de hace tres
  /// horas puesto como si fuera de ahora.
  void olvidar() => state = null;
}

final traerElDiaProvider = NotifierProvider<TraerElDia, LoQueSeTrajo?>(
  TraerElDia.new,
);

/// LO QUE HAY AHORA MISMO en el aparato, en calma.
///
/// Se vuelve a contar cada vez que se mueve una marca de frescura, que es lo
/// unico que cambia cuando entra una bajada — asi el banner dice la verdad
/// tambien despues de un ciclo que disparo el vigia y que nadie estaba mirando.
final loQueHayProvider = FutureProvider<RecuentoDeLoQueHay>((ref) async {
  ref.watch(frescuraGlobalProvider);
  return ref.watch(recontadorProvider).ahora();
});
