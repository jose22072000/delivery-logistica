/// Los datos que entran en las dos hojas impresas. Dart puro a proposito: aqui
/// no entra `pdf` ni Flutter, para que la cuenta del post-despacho se pueda
/// probar sin abrir un PDF y para que la vista previa en vivo del cierre de ruta
/// («Queda en el camion») coma exactamente lo mismo que el papel.
///
/// Pliego: `../docs/pantallas.md` §10 y `../docs/reglas-negocio.md` §12.
library;

/// Una linea del pre-despacho: lo que hay que sacar del almacen de un producto.
class LineaPreDespacho {
  const LineaPreDespacho({
    required this.producto,
    required this.formatos,
    required this.unidades,
    required this.pesoKg,
  });

  final String producto;

  /// Empaques. En la hoja la columna se llama `Empaques`, pero el dato viene
  /// de Next con el nombre `formatos`: se conserva para que al cruzar las dos
  /// hojas no haya que ir traduciendo nombres de campo.
  final num formatos;
  final num unidades;
  final num pesoKg;
}

/// La hoja con la que alguien baja al almacen a sacar mercancia.
class HojaPreDespacho {
  const HojaPreDespacho({
    required this.sucursal,
    required this.vehiculo,
    required this.pedidos,
    required this.pesoKg,
    required this.lineas,
    this.dia,
  });

  final String sucursal;
  final String vehiculo;

  /// El dia de los pedidos, `AAAA-MM-DD`, si se filtro por uno. Va tal cual: es
  /// lo que escribe la de Next y se compara caracter a caracter.
  final String? dia;

  final int pedidos;
  final num pesoKg;

  /// Ya vienen ordenadas de mas a menos empaques; esta hoja no las reordena.
  final List<LineaPreDespacho> lineas;
}

/// Una linea del post-despacho: de un producto, lo que salio, lo entregado y lo
/// que tiene que seguir arriba.
class LineaPostDespacho {
  LineaPostDespacho({
    required this.producto,
    this.salio = 0,
    this.entregado = 0,
    this.queda = 0,
  });

  final String producto;

  /// Lo que se cargo: empaques de todas las paradas de la ruta.
  num salio;

  /// Lo de las paradas marcadas como entregadas.
  num entregado;

  /// Lo que tiene que seguir en el camion: lo devuelto, lo cancelado y lo que
  /// nadie marco. Invariante: `salio == entregado + queda`.
  num queda;
}

/// Un producto de una parada que no se entrego, con su numero.
class ProductoDeParada {
  const ProductoDeParada({required this.producto, required this.formatos});

  final String producto;
  final num formatos;
}

/// Una parada que no se entrego: hace falta saber DE QUIEN es lo que vuelve,
/// porque «faltan nueve cajas» no sirve para reclamar.
class ParadaPendiente {
  const ParadaPendiente({
    required this.cliente,
    required this.resultado,
    required this.nota,
    required this.productos,
  });

  final String cliente;

  /// `devuelto`, `cancelado`, o `null` si nadie la marco.
  final String? resultado;
  final String? nota;
  final List<ProductoDeParada> productos;
}

/// La cuenta de lo que tiene que quedar en el camion al volver.
class HojaPostDespacho {
  const HojaPostDespacho({
    required this.ruta,
    required this.sucursal,
    required this.vehiculo,
    required this.entregadas,
    required this.devueltas,
    required this.canceladas,
    required this.sinMarcar,
    required this.lineas,
    required this.pendientes,
    this.salida,
    this.regreso,
  });

  final String ruta;
  final String sucursal;
  final String vehiculo;

  /// Cuando salio y cuando volvio, si se sabe. Textos ya formados: la hoja los
  /// escribe tal cual, igual que la de Next.
  final String? salida;
  final String? regreso;

  final int entregadas;
  final int devueltas;
  final int canceladas;
  final int sinMarcar;

  /// Todas las lineas, ya ordenadas. El papel filtra las de `queda <= 0`;
  /// la lista entera se guarda porque el cierre de ruta la usa para otra cosa.
  final List<LineaPostDespacho> lineas;

  final List<ParadaPendiente> pendientes;

  /// Lo unico que se imprime en la tabla: un producto entregado entero no hay
  /// que contarlo al bajar, y si sale alarga la hoja y esconde las tres lineas
  /// que importan. El umbral `0.0001` es el de la de Next, no `> 0`: con
  /// empaques fraccionados un resto de coma flotante no puede ensuciar la hoja.
  List<LineaPostDespacho> get lineasConResto =>
      lineas.where((l) => l.queda > 0.0001).toList(growable: false);
}

/// Los totales del pie de cada tabla, apartados del dibujo para poder probarlos
/// sin abrir un PDF: es la fila con la que se cuadra el camion.
class TotalesPreDespacho {
  const TotalesPreDespacho({
    required this.formatos,
    required this.unidades,
    required this.pesoKg,
  });

  /// El peso NO se suma de las lineas: la hoja de Next imprime `d.pesoKg`, el
  /// del conjunto de pedidos, que no tiene por que coincidir con la suma de los
  /// pesos por producto. Se copia ese criterio para que las dos hojas cuadren.
  factory TotalesPreDespacho.de(HojaPreDespacho h) => TotalesPreDespacho(
    formatos: h.lineas.fold<num>(0, (t, l) => t + l.formatos),
    unidades: h.lineas.fold<num>(0, (t, l) => t + l.unidades),
    pesoKg: h.pesoKg,
  );

  final num formatos;
  final num unidades;
  final num pesoKg;
}

/// El pie del post-despacho suma **las filas mostradas**, no todas: si sumara
/// todas, el total no cuadraria con lo que se ve encima.
class TotalesPostDespacho {
  const TotalesPostDespacho({
    required this.salio,
    required this.entregado,
    required this.queda,
  });

  factory TotalesPostDespacho.de(HojaPostDespacho h) {
    final filas = h.lineasConResto;
    return TotalesPostDespacho(
      salio: filas.fold<num>(0, (t, l) => t + l.salio),
      entregado: filas.fold<num>(0, (t, l) => t + l.entregado),
      queda: filas.fold<num>(0, (t, l) => t + l.queda),
    );
  }

  final num salio;
  final num entregado;
  final num queda;
}
