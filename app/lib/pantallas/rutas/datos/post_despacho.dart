// La cuenta del post-despacho: **lo que tiene que quedar en el camion**.
//
// Calcada de `../../../../docs/reglas-negocio.md` §12. Es Dart puro —ni Drift ni
// Flutter dentro— porque es una resta que decide si falta mercancia, y eso se
// prueba con numeros y no abriendo un PDF. El mismo resultado alimenta la vista
// previa en vivo `Queda en el camión` del cierre y, cuando exista
// `lib/impresion/`, la hoja impresa.

/// Una parada tal y como la ve la cuenta: quien es y como acabo.
class ParadaDelCierre {
  const ParadaDelCierre({
    required this.pedidoId,
    required this.cliente,
    required this.lineas,
    this.resultado,
    this.nota,
  });

  final String pedidoId;
  final String cliente;
  final List<LineaDeParada> lineas;

  /// `entregado` | `devuelto` | `cancelado` | **`null` = nadie la marco**.
  final String? resultado;
  final String? nota;
}

/// Una linea de mercancia de una parada.
class LineaDeParada {
  const LineaDeParada(this.producto, this.empaques);

  final String producto;

  /// Los empaques con los que se carga y se cuenta un camion: sus `packs`, y si
  /// la linea no los trae, sus `quantity`. **Nunca cero**: cero seria mentira.
  final double empaques;
}

/// Una linea de la hoja: cuanto salio, cuanto se entrego y cuanto queda.
class LineaPostDespacho {
  const LineaPostDespacho({
    required this.producto,
    required this.salio,
    required this.entregado,
    required this.queda,
  });

  final String producto;
  final double salio;
  final double entregado;
  final double queda;
}

/// El resultado de la cuenta.
class HojaPostDespacho {
  const HojaPostDespacho({
    required this.lineas,
    required this.entregadas,
    required this.devueltas,
    required this.canceladas,
    required this.sinMarcar,
    required this.pendientes,
  });

  /// Sólo las que tienen `queda > 0`: en la hoja del almacen lo entregado entero
  /// no se cuenta, estorba.
  final List<LineaPostDespacho> lineas;

  final int entregadas;
  final int devueltas;
  final int canceladas;

  /// Las que nadie marco. Salen aparte **para que se vea que falta marcarlas**.
  final int sinMarcar;

  /// Toda parada que no sea `entregado`, en el orden en que llegaron.
  final List<ParadaDelCierre> pendientes;
}

/// **REGLA CLAVE: lo que QUEDA es todo lo que no se entrego** — lo devuelto, lo
/// cancelado y, sobre todo, lo que nadie marco.
///
/// Que lo sin marcar cuente como que sigue arriba es a proposito: dar por
/// entregada una parada que nadie toco es exactamente como se pierde mercancia
/// sin que salte nada.
HojaPostDespacho armarPostDespacho(List<ParadaDelCierre> paradas) {
  final salio = <String, double>{};
  final entregado = <String, double>{};
  final queda = <String, double>{};

  var entregadas = 0;
  var devueltas = 0;
  var canceladas = 0;
  var sinMarcar = 0;
  final pendientes = <ParadaDelCierre>[];

  for (final parada in paradas) {
    final seEntrego = parada.resultado == 'entregado';
    switch (parada.resultado) {
      case 'entregado':
        entregadas++;
      case 'devuelto':
        devueltas++;
      case 'cancelado':
        canceladas++;
      default:
        // `null` y cualquier valor desconocido cuentan como sin marcar: lo que
        // no se reconoce no se da por bueno.
        sinMarcar++;
    }
    if (!seEntrego) pendientes.add(parada);

    for (final linea in parada.lineas) {
      final producto = linea.producto.trim();
      if (producto.isEmpty) continue; // una linea sin nombre no se saca
      salio[producto] = (salio[producto] ?? 0) + linea.empaques;
      if (seEntrego) {
        entregado[producto] = (entregado[producto] ?? 0) + linea.empaques;
      } else {
        queda[producto] = (queda[producto] ?? 0) + linea.empaques;
      }
    }
  }

  final lineas = <LineaPostDespacho>[
    for (final producto in salio.keys)
      if ((queda[producto] ?? 0) > 0)
        LineaPostDespacho(
          producto: producto,
          salio: salio[producto] ?? 0,
          entregado: entregado[producto] ?? 0,
          queda: queda[producto] ?? 0,
        ),
  ];

  // Lo que mas queda primero: es por donde se empieza a contar al bajar el
  // camion. A igualdad, por nombre, para que dos hojas del mismo dia salgan
  // iguales.
  lineas.sort((a, b) {
    final porQueda = b.queda.compareTo(a.queda);
    return porQueda != 0 ? porQueda : a.producto.compareTo(b.producto);
  });

  return HojaPostDespacho(
    lineas: lineas,
    entregadas: entregadas,
    devueltas: devueltas,
    canceladas: canceladas,
    sinMarcar: sinMarcar,
    pendientes: pendientes,
  );
}
