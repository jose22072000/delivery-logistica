/// QUE SE PUEDE HACER AHORA MISMO CON EL DIA: traer, enviar, o ninguna.
///
/// Las tres reglas son de Jose, 16/09/2026, y valen para los dos botones de la
/// franja y para la tarjeta del Panel:
///
/// > «si no hay conexion pues no puedes ni traer ni enviar datos al servidor por
/// > q para eso es y en caso de q no alla q traer nada del dia pues ese boton se
/// > desabilita y solo se deja enviar en caso de q si alla q traer se desabilida
/// > el de enviar para no subir nada sin tener todo lo actual y despues si se
/// > podra una ves todo actualizado»
///
/// ## Por que un boton apagado y no uno que falla
///
/// Un boton que se pulsa y no hace nada ensena a desconfiar de todos los
/// botones. Apagarlo **con el motivo escrito al lado** dice dos cosas a la vez:
/// que ahora no se puede y que hay que hacer antes. Esa es la unica forma de que
/// el orden se aprenda sin que nadie lo explique.
///
/// ## Traer antes de enviar
///
/// Es la regla que mas se nota y la que Jose pidio dos veces. Enviar con el
/// aparato desfasado sube decisiones tomadas sobre datos viejos: un pedido que
/// aqui sale libre y en el servidor ya entro en otra ruta. El apunte no se
/// pierde —se queda en la cola— pero vuelve rechazado, y el rechazo se ve horas
/// despues y lejos de donde se decidio.
///
/// **Esto NO cambia el orden del ciclo automatico**, que sigue siendo renovar →
/// subir → bajar (`sincro/ciclo.dart`) y tiene sus motivos: bajar con la cola
/// pendiente pisaria lo recien hecho, y con una ventana de senal de treinta
/// segundos lo primero que tiene que salir es el trabajo. Lo que se ordena aqui
/// son los gestos A MANO, que es otra cosa: quien los pulsa esta mirando la
/// pantalla y puede esperar a que acabe el primero.
library;

/// Si un gesto se puede hacer, y si no, por que no.
class Gesto {
  const Gesto.si() : motivo = null;
  const Gesto.no(this.motivo);

  /// `null` cuando se puede.
  final String? motivo;

  bool get sePuede => motivo == null;
}

/// Los dos gestos del dia, resueltos juntos porque las reglas se cruzan.
class QueSePuede {
  const QueSePuede({required this.traer, required this.enviar});

  final Gesto traer;
  final Gesto enviar;
}

/// Resuelve los dos botones. No toca nada: dice lo que se puede.
///
/// [hayQueTraer] sale de la frescura de los datos, no de preguntarle al
/// servidor: el aparato no puede saber si hay algo nuevo sin bajarlo, asi que lo
/// que se mira es si lo que tiene es de ahora o de hace rato.
QueSePuede quePuedeHacerse({
  required bool hayConexion,
  required bool hayQueTraer,
}) {
  if (!hayConexion) {
    // Los dos gestos son contra el servidor. Sin conexion no hay ninguno, y
    // decirlo en los dos botones evita que alguien pulse dos veces cada uno
    // buscando cual de los dos falla.
    const sinRed = Gesto.no('Sin conexión con el servidor');
    return const QueSePuede(traer: sinRed, enviar: sinRed);
  }

  if (hayQueTraer) {
    return const QueSePuede(
      traer: Gesto.si(),
      enviar: Gesto.no(
        'Trae el día primero: no se envía nada sin tener lo de ahora',
      ),
    );
  }

  // Con los datos al día, enviar SIEMPRE se puede, haya pendientes o no. Con
  // cero es el gesto de «asegúrate», y quien acaba de cerrar una ruta lo busca:
  // apagarlo ahí fue justo el hueco que se encontró el 16/09.
  return const QueSePuede(
    traer: Gesto.no('Los datos ya son de ahora mismo'),
    enviar: Gesto.si(),
  );
}
