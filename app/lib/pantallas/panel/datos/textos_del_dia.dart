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
    QueToca.sinConexion =>
      'Puedes seguir trabajando: todo se guarda aquí y sube cuando vuelva la '
          'señal.',
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
