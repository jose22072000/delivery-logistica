import '../../../diseno/numeros.dart';
import '../../../nucleo/sincro/ciclo.dart';

/// EN QUE ESTADO ESTA EL APARATO, y por tanto que toca ahora.
///
/// **Uno solo, no dos botones.** Antes el Panel ensenaba «Traer el día» y
/// «Entregar el día» a la vez, siempre, y le dejaba al logistico decidir cual de
/// los dos le servia. Eso es trabajo que puede hacer la pantalla: en el patio
/// del almacen sin cobertura no hay nada que decidir, y con veintitres apuntes
/// dentro del telefono tampoco.
///
/// El orden de la lista **es el orden de prioridad**, y no es arbitrario: lo
/// unico que se puede perder es el trabajo hecho. Los datos bajados se vuelven a
/// bajar; una parada marcada a las cuatro de la tarde que nunca subio, no.
enum QueToca {
  /// Bajando. Se dice por donde va.
  trayendo,

  /// Subiendo. Se dice por donde va.
  enviando,

  /// **Sin senal.** No se ofrece un boton que no puede funcionar: se dice el
  /// estado y de que hora son los datos, que es lo que hace falta saber ahi.
  sinConexion,

  /// Hay trabajo dentro del telefono. **Manda sobre todo lo demas.**
  hayQueEnviar,

  /// Todo entregado y con senal: lo que toca es traer el dia.
  alDia,
}

abstract final class TextosDelDia {
  /// El titulo de la pieza en cada estado.
  static String titulo(QueToca toca, {int sinSubir = 0}) => switch (toca) {
    QueToca.trayendo => 'Trayendo datos...',
    QueToca.enviando => 'Enviando datos...',
    QueToca.sinConexion => 'Trabajando sin conexión',
    QueToca.hayQueEnviar => 'Tienes trabajo sin enviar',
    QueToca.alDia => 'Traer el día',
  };

  /// El texto del boton. `null` = **no hay boton**, que es el caso de no tener
  /// senal: ofrecer uno que va a fallar es peor que no ofrecer ninguno.
  static String? boton(QueToca toca, {int sinSubir = 0}) => switch (toca) {
    QueToca.trayendo => 'Trayendo datos...',
    QueToca.enviando => 'Enviando datos...',
    QueToca.sinConexion => null,
    QueToca.hayQueEnviar => 'Enviar datos (${Numeros.entero(sinSubir)})',
    QueToca.alDia => 'Traer el día',
  };

  static String explicacion(QueToca toca) => switch (toca) {
    QueToca.trayendo ||
    QueToca.enviando => 'No cierres la pantalla hasta que acabe.',
    // Se nombra la falta de conexión Y lo que pasa con lo que ya está hecho. Lo
    // segundo es lo que de verdad quita el miedo: quien ve «6 sin subir» lo que
    // quiere saber es si eso se va a perder.
    QueToca.sinConexion =>
      'No hay conexión con el servidor. Puedes seguir trabajando: todo se '
          'guarda aquí y sube solo cuando vuelva la señal.',
    QueToca.hayQueEnviar =>
      'Hasta que no suba, sólo está en este aparato. Es lo único que se puede '
          'perder.',
    QueToca.alDia =>
      'Cárgalo donde haya señal y llévatelo: el día entero se trabaja sin '
          'conexión.',
  };

  /// POR DONDE VA, con el verbo del paso que toca.
  static String porDondeVa(AvanceDelCiclo? avance) {
    if (avance == null) return 'Empezando...';
    return switch (avance.paso) {
      PasoDelCiclo.renovar => 'Comprobando la sesión...',
      PasoDelCiclo.subir => 'Subiendo lo que hiciste...',
      PasoDelCiclo.bajar when avance.coleccion == null =>
        'Pidiendo los cambios...',
      PasoDelCiclo.bajar => '${_coleccion(avance.coleccion!)}...',
    };
  }

  /// «datos de las 8:14» — en minuscula porque va detras de otra cosa tantas
  /// veces como sola.
  static String datosDeLas(DateTime? cuando) => cuando == null
      ? 'sin datos todavía'
      : 'datos de las ${cuando.hour}:'
            '${cuando.minute.toString().padLeft(2, '0')}';

  static String sinSubir(int cuantos) =>
      cuantos == 1 ? '1 sin subir' : '${Numeros.entero(cuantos)} sin subir';

  /// La linea de estado del aparato: de cuando son los datos y que queda dentro.
  static String deQueHoraYQueQueda(DateTime? cuando, int pendientes) =>
      <String>[
        datosDeLas(cuando),
        if (pendientes > 0) sinSubir(pendientes),
      ].join(' · ');

  static String _coleccion(String clave) => switch (clave) {
    'orders' => 'Pedidos',
    'order_items' => 'Líneas de pedido',
    'routes' => 'Rutas',
    'customers' => 'Clientes',
    'products' => 'Productos',
    'vehicles' => 'Vehículos',
    'branches' => 'Sucursales',
    'warehouses' => 'Almacenes',
    'settings' => 'Ajustes',
    _ => clave,
  };
}

/// QUE TOCA AHORA MISMO, en una funcion suelta y probable.
///
/// Esta fuera del widget a proposito: es **una regla**, no pintura. La misma
/// razon por la que `haySesionParaSincronizar` vive suelta en el portero. Una
/// regla metida en un `build` sólo se puede comprobar montando media
/// aplicacion, y lo que hay que comprobar aqui es el ORDEN de cuatro
/// condiciones — que es justo donde estuvo el fallo.
///
/// [vaMal] no es «el aparato cree que no hay wifi»: es que las peticiones no
/// estan llegando, medido (`nucleo/red/salud.dart`).
QueToca queTocaAhora({
  required bool enVuelo,
  required PasoDelCiclo? paso,
  required bool vaMal,
  required int pendientes,
}) {
  // SIN CONEXION MANDA, TAMBIEN MIENTRAS SE INTENTA. Y este orden es el
  // arreglo, no un detalle.
  //
  // Antes `enVuelo` iba primero, asi que la comprobacion de la red **no se
  // llegaba a mirar nunca** mientras habia un intento en marcha. Visto en un
  // Galaxy A16 el 16/09/2026, con el wifi puesto y sin salida a internet: la
  // tarjeta se quedo mas de un minuto diciendo «Enviando datos... Subiendo lo
  // que hiciste...» sin subir absolutamente nada, y sin nombrar la conexion ni
  // una vez. Palabras de Jose: «tienes q notificar q estas sin conexion ok la
  // aplicacion tiene q informar eso».
  //
  // No es que se viera raro: es que la pantalla estaba diciendo una cosa que
  // no era verdad, en el unico sitio donde alguien mira para saber si su
  // trabajo salio del telefono. Y dura mucho, porque el cliente reintenta con
  // esperas crecientes antes de rendirse — o sea que el minuto de mentira es
  // el caso NORMAL, no el raro.
  //
  // `vaMal` no es «el aparato cree que no hay wifi»: es que las peticiones no
  // estan llegando, medido (`red/salud.dart`). Un ciclo en vuelo con la red
  // caida no es progreso, es un reintento condenado, y decirlo es lo unico
  // honesto. Al empezar `vaMal` todavia es false y se dice «Enviando datos»,
  // que entonces SI es verdad; en cuanto empieza a fallar, cambia.
  if (vaMal) return QueToca.sinConexion;
  if (enVuelo) {
    // Mientras el ciclo esta en el paso de subir se dice «enviando», porque es
    // lo que esta pasando. Los tres pasos son el mismo ciclo.
    return paso == PasoDelCiclo.subir ? QueToca.enviando : QueToca.trayendo;
  }
  if (pendientes > 0) return QueToca.hayQueEnviar;
  return QueToca.alDia;
}
