import '../../../nucleo/base/base.dart';

/// El punto desde el que se mide la cercania: el almacen principal de la
/// sucursal (§3 «De donde sale la distancia»).
class AlmacenOrigen {
  const AlmacenOrigen({
    required this.id,
    required this.nombre,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String nombre;
  final double lat;
  final double lng;
}

/// La sucursal no tiene ningun almacen con coordenadas: **no hay tablero**.
///
/// No se ordena por un punto inventado ni por las coordenadas de la sucursal,
/// que no son el sitio del que sale la mercancia. El mensaje es literal, el
/// mismo que devuelve el servidor con su 409.
class SinAlmacenConCoordenadas implements Exception {
  const SinAlmacenConCoordenadas(this.sucursal);

  final String sucursal;

  String get mensaje => '$sucursal no tiene ningún almacén con coordenadas';

  @override
  String toString() => mensaje;
}

/// Todavia no se ha elegido sucursal. **No se ensena «todo»**, que es lo que
/// pareceria razonable y seria lo peor: un tablero con las diez mezcladas
/// ordenaria los pedidos de Holguin por su distancia al almacen de Santiago.
class FaltaElegirSucursal implements Exception {
  const FaltaElegirSucursal();

  String get mensaje => 'Elige una sucursal para ver su tablero';

  @override
  String toString() => mensaje;
}

/// El servidor —o la base local, que aqui manda igual— dijo que no, con un
/// motivo que se le puede ensenar a una persona tal cual.
class RechazoDelTablero implements Exception {
  const RechazoDelTablero(
    this.mensaje, {
    this.pedidos,
    this.detalles = const <String>[],
  });

  final String mensaje;

  /// Cuantos pedidos hay dentro, cuando el motivo es ese (§7.6).
  final int? pedidos;

  /// Quien se cayo y POR QUE, NOMBRADOS. Una columna de doce que produce una
  /// ruta de nueve sin explicacion es la manera mas rapida de que el logistico
  /// deje de fiarse del tablero (§5.2).
  final List<String> detalles;

  @override
  String toString() => mensaje;
}

/// Una columna del tablero, con sus totales.
///
/// Los totales los da la base y NO la suma de lo pintado: la pantalla pagina y
/// el camion no. Con 60 pedidos puestos, sumar lo que se ve en el movil da el
/// peso de los 20 primeros y el aviso de que no cabe no apareceria nunca.
class ColumnaTablero {
  const ColumnaTablero({
    required this.id,
    required this.branchId,
    required this.nombre,
    required this.posicion,
    required this.pedidos,
    required this.pesoKg,
    required this.costoUsd,
    this.vehiculoId,
    this.vehiculoNombre,
    this.vehiculoMatricula,
    this.vehiculoCapacidad,
    this.sinSubir = false,
    this.rechazada = false,
  });

  final String id;
  final String branchId;
  final String nombre;
  final int posicion;
  final String? vehiculoId;
  final String? vehiculoNombre;
  final String? vehiculoMatricula;
  final double? vehiculoCapacidad;
  final int pedidos;
  final double pesoKg;
  final double costoUsd;

  /// Le queda algo por subir: la propia zona, o un cambio suyo.
  final bool sinSubir;

  /// El servidor dijo que no a algo de esta zona y espera a que alguien decida.
  final bool rechazada;

  /// `null` **no es `false`**: sin camion previsto todavia no se sabe si cabe, y
  /// pintar «cabe» cuando nadie ha dicho en que va es peor que no pintar nada
  /// (§7.3).
  bool? get excedeCamion {
    final capacidad = vehiculoCapacidad;
    if (capacidad == null) return null;
    return pesoKg > capacidad;
  }

  /// ¿Le falta llegar arriba?
  ///
  /// **Sale de la cola, no del id**, y ese cambio es del 16/09/2026. Antes era
  /// `id.startsWith('local-')`, que dejo de significar nada el dia que el aparato
  /// empezo a poner el id definitivo —un UUIDv7— al crear la zona, este o no
  /// este arriba.
  ///
  /// Y el prefijo nunca supo contar la otra mitad: una zona que subio y que
  /// despues se renombro sin senal tambien tiene trabajo sin subir, y con el id
  /// de verdad puesto se daba por entregada.
  bool get faltaPorSubir => sinSubir || rechazada;
}

/// Por que una tarjeta dejo de servir. **Se marca, no se esconde** (§7.2).
enum MarcaTarjeta {
  /// PEDIDO lo dio de baja con la tarjeta puesta.
  archivado('Archivado en PEDIDO', grave: true),

  /// Se lo llevo otra ruta: el Super Admin, o el armador de siempre desde otro
  /// aparato.
  enOtraRuta('Ya va en otra ruta', grave: true),

  /// `factura_estado` NULL. **No es «cuadra»**: es «no se sabe». Con un NULL
  /// colado se armo una ruta sin facturar el 2/09.
  sinCotejar('Sin cotejar', grave: true),

  /// No hay nada que llevar: hoy no sale.
  sinFactura('Sin factura', grave: true),

  /// Se facturo distinto de como se pidio. Se reparte igual —lo que sube al
  /// camion son las lineas de la factura— pero **el peso de la columna ya no es
  /// el que era**, y ese es el aviso que importa.
  cambiado('Cambió en la factura', grave: false);

  const MarcaTarjeta(this.texto, {required this.grave});

  final String texto;

  /// En rojo lo que hoy NO sale; en ambar lo que sale distinto.
  final bool grave;
}

/// Lo comun a las dos mitades: una tarjeta de pedido.
class TarjetaPedido {
  const TarjetaPedido({
    required this.pedidoId,
    required this.customerName,
    required this.address,
    required this.weight,
    required this.kmAlAlmacen,
    required this.mismoCliente,
    this.operationNumber,
    this.customerPhone,
    this.pedidoCosto,
    this.municipio,
    this.vendedor,
    this.orderDate,
    this.facturaEstado,
    this.archivado = false,
    this.rutaId,
    this.resultado,
  });

  final String pedidoId;
  final String? operationNumber;
  final String customerName;
  final String? customerPhone;
  final String address;
  final double weight;
  final double? pedidoCosto;
  final String? municipio;
  final String? vendedor;
  final DateTime? orderDate;
  final String? facturaEstado;
  final bool archivado;
  final String? rutaId;
  final String? resultado;
  final double kmAlAlmacen;

  /// Cuantos pedidos hay hoy de este mismo cliente. **No se funden las
  /// tarjetas**: X-2992 y X-2992-2 son dos pedidos, con sus renglones, su peso
  /// y su costo de domicilio cada uno; juntarlos porque coincide el cliente es
  /// repetir el error de julio —dos facturas, un solo bulto cargado—. Lo unico
  /// que hace la pantalla es decirlo, para que el logistico los meta en la
  /// misma columna a proposito y no por casualidad (§7.1).
  final int mismoCliente;

  /// Las marcas, de la mas grave a la menos. Una tarjeta puede llevar varias:
  /// un pedido archivado y sin facturar es las dos cosas.
  List<MarcaTarjeta> get marcas => <MarcaTarjeta>[
    if (archivado) MarcaTarjeta.archivado,
    if (rutaId != null) MarcaTarjeta.enOtraRuta,
    if (facturaEstado == null) MarcaTarjeta.sinCotejar,
    if (facturaEstado == EstadoFactura.sinFactura) MarcaTarjeta.sinFactura,
    if (facturaEstado == EstadoFactura.cambiado) MarcaTarjeta.cambiado,
  ];

  /// ¿Se puede repartir hoy? Es la pregunta del armador (§5.2), no la de si se
  /// ensena: lo que no se puede repartir se ensena igual, marcado.
  bool get repartible => marcas.every((m) => !m.grave);
}

/// Una tarjeta YA COLOCADA, con la columna y el sitio en el que esta.
class TarjetaColocada {
  const TarjetaColocada({
    required this.pedido,
    required this.columnaId,
    required this.posicion,
    this.colocadoAt,
  });

  final TarjetaPedido pedido;
  final String columnaId;

  /// El orden de visita que propone el logistico, el que conoce las calles.
  final int posicion;
  final DateTime? colocadoAt;
}

/// Los contadores de arriba. **Tres y no uno**: «lo archivaron en PEDIDO», «se
/// lo llevo otra ruta» y «no esta facturado» se arreglan de maneras distintas, y
/// un numero unico obligaria a abrir las doce columnas para saber cual es.
class AvisosTablero {
  const AvisosTablero({
    this.archivados = 0,
    this.enOtraRuta = 0,
    this.sinFactura = 0,
    this.cambiados = 0,
    this.colocados = 0,
  });

  final int archivados;
  final int enOtraRuta;
  final int sinFactura;
  final int cambiados;
  final int colocados;

  bool get hayAlguno =>
      archivados > 0 || enOtraRuta > 0 || sinFactura > 0 || cambiados > 0;
}

/// Un pedido que estaba puesto y ya no existe en PEDIDO (§7.5). Se avisa UNA
/// vez, con lo que se sabia de el antes de que se fuera.
class PedidoDesaparecido {
  const PedidoDesaparecido({
    required this.pedidoId,
    this.operationNumber,
    this.customerName,
    this.columna,
  });

  final String pedidoId;
  final String? operationNumber;
  final String? customerName;
  final String? columna;
}

/// La mitad izquierda: los pedidos sin colocar, ordenados por cercania.
class MitadIzquierda {
  const MitadIzquierda({required this.pedidos, required this.total});

  final List<TarjetaPedido> pedidos;

  /// Cuantos hay de verdad con estos filtros. `pedidos.length` es lo que cabe.
  final int total;

  bool get truncada => total > pedidos.length;
}

/// El tablero entero, tal y como se pinta.
class Tablero {
  const Tablero({
    required this.sucursalId,
    required this.sucursalNombre,
    required this.almacen,
    required this.columnas,
    required this.colocados,
    required this.avisos,
    required this.sinColocar,
    required this.desaparecidos,
    this.vistoAt,
  }) : problema = null;

  /// EL TABLERO QUE NO SE PUEDE PINTAR, y por que.
  ///
  /// Son dos situaciones **normales**, no averias: que el Super Admin todavia
  /// no haya elegido sucursal y que la sucursal no tenga ningun almacen con
  /// coordenadas. Van como un tablero vacio con su motivo, y no como una
  /// excepcion, porque una excepcion se reintenta sola —eso hace Riverpod— y
  /// reintentar «elige una sucursal» cada pocos segundos, para siempre, no
  /// arregla nada y calienta el telefono.
  const Tablero.imposible(
    this.problema, {
    this.sucursalId = '',
    this.sucursalNombre = '',
  }) : almacen = const AlmacenOrigen(id: '', nombre: '', lat: 0, lng: 0),
       columnas = const <ColumnaTablero>[],
       colocados = const <TarjetaColocada>[],
       avisos = const AvisosTablero(),
       sinColocar = const MitadIzquierda(pedidos: <TarjetaPedido>[], total: 0),
       desaparecidos = const <PedidoDesaparecido>[],
       vistoAt = null;

  /// `null` cuando el tablero se puede pintar.
  final String? problema;

  final String sucursalId;
  final String sucursalNombre;
  final AlmacenOrigen almacen;

  final List<ColumnaTablero> columnas;
  final List<TarjetaColocada> colocados;
  final AvisosTablero avisos;
  final MitadIzquierda sinColocar;
  final List<PedidoDesaparecido> desaparecidos;

  /// De cuando son estos datos. Es lo que se ensena arriba con todas las
  /// letras: un tablero que parece vivo y lleva seis horas congelado es peor
  /// que uno que avisa.
  final DateTime? vistoAt;

  List<TarjetaColocada> deColumna(String columnaId) =>
      colocados.where((t) => t.columnaId == columnaId).toList(growable: false);
}
