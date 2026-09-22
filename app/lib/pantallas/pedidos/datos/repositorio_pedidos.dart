// El repositorio de Pedidos.
//
// **Lee de la base local y NUNCA de la red.** Esa es la regla que sostiene el
// dia sin conexion: la pantalla mira Drift, y si hay red el sincronizador
// escribe por detras y las consultas vuelven a emitir solas. No hay un camino
// alternativo «si hay internet pide al servidor», porque tener dos caminos es
// tener dos comportamientos y sólo uno probado.
//
// El `WHERE` es el MISMO de `../../../../docs/contratos-api.md`
// («Filtros compartidos de pedido»), traducido a Drift. Cualquier diferencia
// aqui sale como un numero distinto en la prueba de paridad contra la de Next.

import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import 'filtros_pedidos.dart';

/// Una linea del pre-despacho: cuanto hay que sacar del almacen de cada
/// producto.
class LineaPreDespacho {
  const LineaPreDespacho({
    required this.producto,
    required this.empaques,
    required this.unidades,
    this.pesoKg,
  });

  final String producto;
  final double empaques;

  /// Las unidades sueltas que hay dentro de esos empaques, **sacadas del
  /// catálogo**: `empaques × unitsPerPackage`.
  ///
  /// `null` cuando el catálogo no lo dice, igual que [pesoKg] y por el mismo
  /// motivo. **Y esto antes era `SUM(quantity)`**, que no es lo mismo: el
  /// 22/09/2026 la hoja decía «SERVILLETA PROSITO PACA 24P · 7 empaques · 4
  /// unidades» — cuatro unidades dentro de siete pacas—, y «SOPA DE POLLO CAJA
  /// 72 P · 15 empaques · 15 unidades». `quantity` unas veces trae unidades y
  /// otras repite los bultos; en la hoja con la que se saca del almacén eso es
  /// un número creíble y equivocado. Lo único que se sabe de verdad es lo que
  /// diga el catálogo, y si no lo dice se pinta `—`.
  final double? unidades;

  /// `null` cuando ninguna linea de ese producto tiene el peso resuelto. **No es
  /// cero**: cero se lee como «no pesa», y en la hoja de almacen eso es un error
  /// distinto. Por eso la columna pinta `—`.
  final double? pesoKg;
}

/// Los totales del bloque de pre-despacho.
class TotalesPreDespacho {
  const TotalesPreDespacho(
    this.lineas, {
    this.pedidos = 0,
    this.pesoDeLosPedidos = 0,
  });

  final List<LineaPreDespacho> lineas;

  /// Cuantos pedidos entraron en esta suma. Es el `<n> pedido(s)` de la cabecera
  /// de la hoja impresa.
  final int pedidos;

  /// El peso del CONJUNTO de pedidos, que es el `<n.n> kg` de la cabecera de la
  /// hoja. **No es la suma de [pesoKg] por producto**: la de Next imprime el
  /// peso de los pedidos, y un producto sin peso resuelto no suma nada ahi
  /// aunque el pedido si pese.
  final double pesoDeLosPedidos;

  int get productos => lineas.length;
  double get empaques => lineas.fold(0, (suma, linea) => suma + linea.empaques);

  /// UN TOTAL A MEDIAS ES PEOR QUE NINGUNO, y por eso los dos de abajo son
  /// nulos en cuanto falte UNA línea — 22/09/2026.
  ///
  /// La franja de la pantalla decía «10 producto(s) · 3185 empaques · **0.0
  /// kg**» mientras la hoja imprimible del mismo filtro decía «264 pedido(s) ·
  /// **24891.0 kg**». Los dos números eran ciertos cada uno en su definición
  /// —uno suma el peso resuelto por producto, el otro el de los pedidos— y
  /// juntos sólo pueden hacer una cosa: que quien carga el camión se crea que
  /// no pesa nada.
  ///
  /// Sumar lo que hay y callar lo que falta es la misma mentira con menos
  /// escándalo: 8 de 10 productos resueltos dan un peso que parece completo y
  /// se queda corto. Mejor `null`, que la pantalla pinta `—` y dice cuántos
  /// faltan.
  double? get unidades => _sumaCompleta((l) => l.unidades);
  double? get pesoKg => _sumaCompleta((l) => l.pesoKg);

  /// Cuántas líneas no tienen el peso resuelto. Es lo que convierte el `—` en
  /// algo que se puede arreglar: dice cuántos productos faltan por emparejar.
  int get sinPeso => lineas.where((l) => l.pesoKg == null).length;

  /// Cuántas no saben sus unidades por empaque.
  int get sinUnidades => lineas.where((l) => l.unidades == null).length;

  double? _sumaCompleta(double? Function(LineaPreDespacho) de) {
    if (lineas.isEmpty) return null;
    var suma = 0.0;
    for (final linea in lineas) {
      final valor = de(linea);
      if (valor == null) return null;
      suma += valor;
    }
    return suma;
  }
}

/// Una opcion de faceta con su conteo: `Camagüey` · `312`.
class OpcionFaceta {
  const OpcionFaceta(this.valor, this.pedidos);

  final String valor;
  final int pedidos;
}

/// Lo que llena los dos selectores de municipio y vendedor.
class Facetas {
  const Facetas({required this.municipios, required this.vendedores});

  static const vacias = Facetas(municipios: [], vendedores: []);

  final List<OpcionFaceta> municipios;
  final List<OpcionFaceta> vendedores;
}

/// Un renglon del pedido con el peso por empaque ya resuelto contra el catalogo.
class RenglonConPeso {
  const RenglonConPeso(this.renglon, this.kgPorEmpaque);

  final RenglonPedido renglon;

  /// `null` = **sin peso**, que en la ficha se dice con esas palabras.
  final double? kgPorEmpaque;

  /// Los empaques de la linea: sus `packs` y si no los trae sus `quantity`,
  /// nunca cero (`reglas-negocio.md` §12).
  double get empaques {
    final packs = renglon.packs;
    if (packs != null && packs > 0) return packs;
    return renglon.quantity;
  }

  double? get pesoLinea {
    final kg = kgPorEmpaque;
    return kg == null ? null : kg * empaques;
  }
}

/// El pedido con todo lo que la ficha necesita, en una sola lectura.
class DetallePedido {
  const DetallePedido({
    required this.pedido,
    required this.renglones,
    this.ruta,
    this.vehiculo,
    this.almacen,
  });

  final Pedido pedido;
  final List<RenglonConPeso> renglones;
  final Ruta? ruta;
  final Vehiculo? vehiculo;

  /// El almacen de partida, para el mapa `Recorrido` y su pie
  /// `Del almacén (<nombre>) al cliente.`
  final Almacen? almacen;
}

class ConsultasPedidos {
  ConsultasPedidos(this._base);

  final BaseLocal _base;

  /// Lo fija el servidor y el control de tamano esta deshabilitado en la
  /// pantalla. Se deja como constante para que la paginacion local de en el
  /// aparato exactamente las mismas paginas que la de Next.
  static const porPagina = 50;

  // --------------------------------------------------------------------------
  // El WHERE
  // --------------------------------------------------------------------------

  /// Traduce los 9 filtros a SQL. Es la pieza que hay que mirar cuando un total
  /// no cuadra con el de Next.
  ///
  /// [sucursalId] no es un filtro de la pantalla: es el ALCANCE, y viene del
  /// selector de la barra superior. Va aqui y no en la pantalla para que no se
  /// pueda olvidar en una consulta.
  Expression<bool> donde(FiltrosPedidos f, {String? sucursalId}) {
    final o = _base.orders;
    // Se parte de «todo cuadra» y cada filtro puesto va estrechando. Asi el
    // caso de «ningun filtro» es el mismo camino que los demas y no una rama
    // aparte que nadie prueba.
    Expression<bool> todo = const Constant(true);

    void anadir(Expression<bool> mas) => todo = todo & mas;

    if (sucursalId != null && sucursalId.isNotEmpty) {
      anadir(o.branchId.equals(sucursalId));
    }

    final q = f.q.trim().toLowerCase();
    if (q.isNotEmpty) {
      // El mismo juego de campos que el servidor, incluido el texto de los
      // productos: quien busca «arroz» espera el pedido que lleva arroz, no sólo
      // el cliente que se apellida asi.
      final enElPedido =
          o.customerName.lower().contains(q) |
          o.operationNumber.lower().contains(q) |
          o.endAddress.lower().contains(q) |
          o.address.lower().contains(q) |
          o.municipio.lower().contains(q) |
          o.vendedor.lower().contains(q);

      final enLosProductos = o.id.isInQuery(
        _base.selectOnly(_base.orderItems)
          ..addColumns([_base.orderItems.orderId])
          ..where(_base.orderItems.description.lower().contains(q)),
      );

      anadir(enElPedido | enLosProductos);
    }

    switch (f.archivado) {
      case ArchivadoFiltro.cualquiera:
        break;
      case ArchivadoFiltro.no:
        anadir(o.archivado.equals(false));
      case ArchivadoFiltro.si:
        anadir(o.archivado.equals(true));
    }

    switch (f.cotizado) {
      case CotizadoFiltro.cualquiera:
        break;
      case CotizadoFiltro.conPrecio:
        anadir(o.pedidoCosto.isNotNull());
      case CotizadoFiltro.sinCotizar:
        anadir(o.pedidoCosto.isNull());
    }

    if (f.municipio.isNotEmpty) anadir(o.municipio.equals(f.municipio));
    if (f.vendedor.isNotEmpty) anadir(o.vendedor.equals(f.vendedor));

    switch (f.factura) {
      case FacturaFiltro.cualquiera:
        break;
      case FacturaFiltro.conFactura:
        // `con_factura` admite lo que cambio: se carga con las lineas de la
        // factura, no con las del pedido.
        anadir(
          o.facturaEstado.isIn([EstadoFactura.igual, EstadoFactura.cambiado]),
        );
      case FacturaFiltro.cuadra:
        anadir(o.facturaEstado.equals(EstadoFactura.igual));
      case FacturaFiltro.sinCotejar:
        // NULL no es `sin_factura`: NULL es «el cotejo no ha pasado por aqui».
        anadir(o.facturaEstado.isNull());
    }

    switch (f.reparto) {
      case RepartoFiltro.cualquiera:
        break;
      case RepartoFiltro.sinEntregar:
        anadir(
          o.routeId.isNull() &
              o.deliveredAt.isNull() &
              (o.resultado.isNull() |
                  o.resultado.equals(ResultadoParada.entregado).not()),
        );
      case RepartoFiltro.enDespacho:
        anadir(_enRutaCon(EstadoRuta.planificada));
      case RepartoFiltro.enRuta:
        anadir(_enRutaCon(EstadoRuta.enCurso));
      case RepartoFiltro.entregado:
        // Manda `resultado` de la parada. El `deliveredAt` entra tambien porque
        // los pedidos viejos del espejo lo tienen puesto sin resultado.
        anadir(
          o.resultado.equals(ResultadoParada.entregado) |
              o.deliveredAt.isNotNull(),
        );
      case RepartoFiltro.devuelto:
        anadir(
          o.resultado.isIn([
            ResultadoParada.devuelto,
            ResultadoParada.cancelado,
          ]),
        );
    }

    final rango = _rangoDeFechas(f);
    if (rango != null) {
      final (desde, hasta) = rango;
      // El mismo OR del servidor: un pedido sin `orderDate` se acota por la
      // fecha en que se copio, o desapareceria de todos los rangos.
      anadir(
        (o.orderDate.isBiggerOrEqualValue(desde) &
                o.orderDate.isSmallerOrEqualValue(hasta)) |
            (o.orderDate.isNull() &
                o.createdAt.isBiggerOrEqualValue(desde) &
                o.createdAt.isSmallerOrEqualValue(hasta)),
      );
    }

    return todo;
  }

  /// `en_despacho` / `en_ruta`: el pedido esta ocupado por una ruta que esta en
  /// ese estado. Va como subconsulta y no como join para que el `WHERE` sirva
  /// igual en la lista, en el conteo y en el pre-despacho.
  Expression<bool> _enRutaCon(String estadoRuta) {
    final o = _base.orders;
    return o.routeId.isNotNull() &
        o.routeId.isInQuery(
          _base.selectOnly(_base.routes)
            ..addColumns([_base.routes.id])
            ..where(_base.routes.status.equals(estadoRuta)),
        );
  }

  /// `hasta` incluye el dia entero. Sin esto, filtrar «del 3 al 3» no devuelve
  /// nada y parece que no hubo pedidos ese dia.
  (DateTime, DateTime)? _rangoDeFechas(FiltrosPedidos f) {
    final desde = f.desde;
    final hasta = f.hasta;
    if (desde == null && hasta == null) return null;
    final inicio = desde == null
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime(desde.year, desde.month, desde.day);
    final fin = hasta == null
        ? DateTime(9999)
        : DateTime(hasta.year, hasta.month, hasta.day, 23, 59, 59, 999);
    return (inicio, fin);
  }

  // --------------------------------------------------------------------------
  // Lectura
  // --------------------------------------------------------------------------

  /// Cuantos pedidos cuadran. Es el `<total> pedidos` de la cabecera y el que se
  /// compara contra el de Next.
  Stream<int> contar(FiltrosPedidos f, {String? sucursalId}) {
    final cuenta = _base.orders.id.count();
    final consulta = _base.selectOnly(_base.orders)
      ..addColumns([cuenta])
      ..where(donde(f, sucursalId: sucursalId));
    return consulta.watchSingle().map((fila) => fila.read(cuenta) ?? 0);
  }

  /// La pagina, en el orden del SERVIDOR (`orderDate desc nulls last`, luego
  /// `createdAt desc`). El orden que elige la persona se aplica despues, sobre
  /// esta lista y nada mas: ver [ordenarPagina].
  Stream<List<Pedido>> pagina(FiltrosPedidos f, {String? sucursalId}) {
    final consulta = _base.select(_base.orders)
      ..where((_) => donde(f, sucursalId: sucursalId))
      // SQLite pone los NULL al final en DESC, que es exactamente el
      // `nulls last` del servidor.
      ..orderBy([
        (o) => OrderingTerm.desc(o.orderDate),
        (o) => OrderingTerm.desc(o.createdAt),
      ])
      ..limit(porPagina, offset: (f.pagina - 1) * porPagina);
    return consulta.watch();
  }

  /// Los renglones de unos pedidos, con el peso por empaque resuelto contra el
  /// catalogo de productos.
  Future<Map<String, List<RenglonConPeso>>> renglonesDe(
    List<String> pedidoIds,
  ) async {
    if (pedidoIds.isEmpty) return const {};
    final consulta = _base.select(_base.orderItems).join([
      leftOuterJoin(
        _base.products,
        _base.products.id.equalsExp(_base.orderItems.productId),
      ),
    ])..where(_base.orderItems.orderId.isIn(pedidoIds));
    consulta.orderBy([OrderingTerm.asc(_base.orderItems.linea)]);

    final filas = await consulta.get();
    final porPedido = <String, List<RenglonConPeso>>{};
    for (final fila in filas) {
      final renglon = fila.readTable(_base.orderItems);
      final producto = fila.readTableOrNull(_base.products);
      porPedido
          .putIfAbsent(renglon.orderId, () => <RenglonConPeso>[])
          .add(RenglonConPeso(renglon, producto?.weight));
    }
    return porPedido;
  }

  /// El pre-despacho de LO FILTRADO, sumado en SQL.
  ///
  /// **Sin tope.** El servidor corta en 5000 porque ahi estan los pedidos de
  /// ocho sucursales; en el aparato sólo esta la suya, asi que sumarlos todos es
  /// barato y no hay motivo para negarle el numero a nadie (PLAN.md §7.2).
  Future<TotalesPreDespacho> preDespachoDeLoFiltrado(
    FiltrosPedidos f, {
    String? sucursalId,
  }) => _preDespacho(donde(f, sucursalId: sucursalId));

  /// El pre-despacho de LO MARCADO a mano.
  Future<TotalesPreDespacho> preDespachoDe(List<String> pedidoIds) {
    if (pedidoIds.isEmpty) return Future.value(const TotalesPreDespacho([]));
    return _preDespacho(_base.orders.id.isIn(pedidoIds));
  }

  /// **Los empaques de una linea: sus `packs`, y si no los trae, sus
  /// `quantity`.** Nunca cero.
  ///
  /// Esto es la MISMA regla que [RenglonConPeso.empaques], que `armarPostDespacho`
  /// y que `reglas-negocio.md` §12, y no estaba aqui: el pre-despacho sumaba
  /// `SUM(packs)` a secas, asi que un producto cuya linea viene sin empaques
  /// contaba **0** y **la hoja del almacen salia corta** — se cargan menos cajas
  /// de las que hay que cargar, y eso no se descubre hasta que el camion ya se
  /// fue. Un cero ahi no es un dato: es una mentira con forma de numero.
  ///
  /// `CASE WHEN packs > 0` cubre tambien el `packs` nulo: en SQL una condicion
  /// nula no es cierta, asi que cae al `ELSE` igual que el `> 0` de Dart.
  Expression<double> get _empaquesDeLaLinea => CaseWhenExpression<double>(
    cases: <CaseWhen<bool, double>>[
      CaseWhen(
        _base.orderItems.packs.isBiggerThanValue(0),
        then: _base.orderItems.packs,
      ),
    ],
    orElse: _base.orderItems.quantity,
  );

  Future<TotalesPreDespacho> _preDespacho(Expression<bool> filtro) async {
    final producto = _base.orderItems.description;
    final empaques = _empaquesDeLaLinea.sum();
    // Las unidades salen del catálogo, igual que el peso: `empaques × unidades
    // por empaque`. Ver `LineaPreDespacho.unidades` para lo que costó.
    final unidades =
        (_empaquesDeLaLinea * _base.products.unitsPerPackage).sum();
    // El peso de la linea sale del catalogo: `kg por empaque × empaques`. Si el
    // producto no esta emparejado, `SUM` se salta la linea y el total queda
    // `null`, que la pantalla pinta `—` y no `0`. Los empaques son los mismos de
    // arriba, con su respaldo: si aqui se usara `packs` a secas, una linea sin
    // empaques contaria en la columna `Empaques` y no en la de `kg`, y las dos
    // columnas de la misma fila dejarian de hablar del mismo bulto.
    final peso = (_empaquesDeLaLinea * _base.products.weight).sum();

    final consulta =
        _base.selectOnly(_base.orderItems).join([
            innerJoin(
              _base.orders,
              _base.orders.id.equalsExp(_base.orderItems.orderId),
            ),
            leftOuterJoin(
              _base.products,
              _base.products.id.equalsExp(_base.orderItems.productId),
            ),
          ])
          ..addColumns([producto, empaques, unidades, peso])
          // Una linea sin nombre no se puede sacar del almacen: se salta, igual
          // que en el servidor.
          ..where(filtro & producto.trim().equals('').not())
          ..groupBy([producto])
          ..orderBy([OrderingTerm.desc(empaques)]);

    final filas = await consulta.get();
    final (cuantos, kilos) = await _cabeceraDeLaHoja(filtro);
    return TotalesPreDespacho(
      [
        for (final fila in filas)
          LineaPreDespacho(
            producto: fila.read(producto) ?? '',
            empaques: fila.read(empaques) ?? 0,
            unidades: fila.read(unidades),
            pesoKg: fila.read(peso),
          ),
      ],
      pedidos: cuantos,
      pesoDeLosPedidos: kilos,
    );
  }

  /// Cuantos pedidos y cuantos kilos entran en la hoja. Es la esquina derecha
  /// del papel (`pantallas.md` §10.1) y va aparte de la suma por producto
  /// porque cuenta PEDIDOS, no lineas: sumarlo en la misma consulta lo
  /// multiplicaria por el numero de renglones de cada pedido.
  Future<(int, double)> _cabeceraDeLaHoja(Expression<bool> filtro) async {
    final cuantos = _base.orders.id.count();
    final kilos = _base.orders.weight.sum();
    final consulta = _base.selectOnly(_base.orders)
      ..addColumns([cuantos, kilos])
      ..where(filtro);
    final fila = await consulta.getSingle();
    return (fila.read(cuantos) ?? 0, fila.read(kilos) ?? 0);
  }

  /// Los municipios y vendedores con su conteo, para los dos selectores.
  ///
  /// Se calculan en local, como todo lo demas: pedirlas a `/api/orders/facetas`
  /// dejaria dos selectores vacios en cuanto no hubiera red.
  Future<Facetas> facetas({String? sucursalId}) async {
    Future<List<OpcionFaceta>> agrupar(GeneratedColumn<String> columna) async {
      final cuenta = _base.orders.id.count();
      final consulta = _base.selectOnly(_base.orders)
        ..addColumns([columna, cuenta])
        ..where(
          columna.isNotNull() &
              columna.equals('').not() &
              (sucursalId == null || sucursalId.isEmpty
                  ? const Constant(true)
                  : _base.orders.branchId.equals(sucursalId)),
        )
        ..groupBy([columna])
        ..orderBy([OrderingTerm.asc(columna)]);
      final filas = await consulta.get();
      return [
        for (final fila in filas)
          OpcionFaceta(fila.read(columna) ?? '', fila.read(cuenta) ?? 0),
      ];
    }

    return Facetas(
      municipios: await agrupar(_base.orders.municipio),
      vendedores: await agrupar(_base.orders.vendedor),
    );
  }

  /// La ficha del pedido, entera y en una lectura.
  Future<DetallePedido?> detalle(String pedidoId) async {
    final pedido = await (_base.select(
      _base.orders,
    )..where((o) => o.id.equals(pedidoId))).getSingleOrNull();
    if (pedido == null) return null;

    final renglones = (await renglonesDe([pedidoId]))[pedidoId] ?? const [];

    final rutaId = pedido.routeId ?? pedido.ultimaRutaId;
    final ruta = rutaId == null
        ? null
        : await (_base.select(
            _base.routes,
          )..where((r) => r.id.equals(rutaId))).getSingleOrNull();

    final vehiculoId = pedido.vehicleId ?? ruta?.vehicleId;
    final vehiculo = vehiculoId == null
        ? null
        : await (_base.select(
            _base.vehicles,
          )..where((v) => v.id.equals(vehiculoId))).getSingleOrNull();

    final almacen = await almacenPrincipal(pedido.sucursalCodigo);

    return DetallePedido(
      pedido: pedido,
      renglones: renglones,
      ruta: ruta,
      vehiculo: vehiculo,
      almacen: almacen,
    );
  }

  /// El almacen principal de una sucursal: el punto desde el que se mide todo.
  Future<Almacen?> almacenPrincipal(String? sucursalCodigo) async {
    final consulta = _base.select(_base.warehouses)
      ..where(
        (a) => sucursalCodigo == null
            ? a.activo.equals(true)
            : a.sucursalCodigo.equals(sucursalCodigo) & a.activo.equals(true),
      )
      ..orderBy([
        (a) => OrderingTerm.desc(a.principal),
        (a) => OrderingTerm.asc(a.nombre),
      ])
      ..limit(1);
    final filas = await consulta.get();
    return filas.isEmpty ? null : filas.first;
  }
}

/// El orden que elige la persona, aplicado **sólo a la pagina visible**.
///
/// Es una funcion pura y por eso se prueba sin base y sin widget: se le dan 50
/// pedidos y se comprueba que salen en el orden que toca, y que la lista que
/// entra no es la de la consulta entera.
List<Pedido> ordenarPagina(List<Pedido> pagina, OrdenLocal orden) {
  final copia = [...pagina];

  /// «Sin valor» se va SIEMPRE al final, suba o baje el orden. Y eso hay que
  /// decidirlo antes de invertir la comparacion: si se ordenara al reves
  /// intercambiando los argumentos, los nulos se irian al principio en uno de
  /// los dos sentidos y «sin cotizar» se leeria como «lo mas barato».
  int porNumero(double? a, double? b, {required bool descendente}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return descendente ? b.compareTo(a) : a.compareTo(b);
  }

  int porFecha(Pedido a, Pedido b, {required bool descendente}) {
    final fa = a.orderDate ?? a.createdAt;
    final fb = b.orderDate ?? b.createdAt;
    if (fa == null && fb == null) return 0;
    // Sin fecha no se sabe cuando fue, asi que no puede encabezar ni «lo mas
    // nuevo» ni «lo mas viejo».
    if (fa == null) return 1;
    if (fb == null) return -1;
    return descendente ? fb.compareTo(fa) : fa.compareTo(fb);
  }

  switch (orden) {
    case OrdenLocal.recientes:
      copia.sort((a, b) => porFecha(a, b, descendente: true));
    case OrdenLocal.antiguos:
      copia.sort((a, b) => porFecha(a, b, descendente: false));
    case OrdenLocal.precioDesc:
      copia.sort(
        (a, b) => porNumero(a.pedidoCosto, b.pedidoCosto, descendente: true),
      );
    case OrdenLocal.precioAsc:
      copia.sort(
        (a, b) => porNumero(a.pedidoCosto, b.pedidoCosto, descendente: false),
      );
    case OrdenLocal.distanciaDesc:
      copia.sort(
        (a, b) => porNumero(
          a.deliveryDistanceKm,
          b.deliveryDistanceKm,
          descendente: true,
        ),
      );
    case OrdenLocal.pesoDesc:
      copia.sort((a, b) => porNumero(a.weight, b.weight, descendente: true));
  }
  return copia;
}
