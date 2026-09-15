import 'package:drift/drift.dart';

import '../base/base.dart';
import '../frescura/frescura.dart';
import '../red/cliente_api.dart';
import '../registro/registro.dart';
import '../reloj.dart';

/// `GET /api/sync/cambios` — LA BAJADA DEL DIA.
///
/// Es lo que hace que las pantallas dejen de decir «no se ha descargado
/// todavia». Se llama nada mas entrar, cuando hay red, y despues de cada subida
/// de la cola.
///
/// **Escribe en la base local y nada mas.** Ninguna pantalla mira lo que
/// devuelve esto: todas miran la base (regla 2). Por eso lo unico que hace falta
/// comprobar aqui es que las filas queden puestas y que la `frescura` quede
/// marcada — de ahi sale la hora de la franja de estado.
///
/// El orden de las dos cosas importa: primero las filas y **despues** la marca,
/// las dos en la misma transaccion. Al reves, un corte en medio dejaria la marca
/// movida sin los datos detras, y ese trozo de tiempo no lo volveria a pedir
/// nadie (`sincronizacion.md` §1).
class Bajada {
  Bajada({
    required ClienteApi cliente,
    required BaseLocal base,
    required RegistroDeFrescura frescura,
    Reloj reloj = relojDelAparato,
  }) : _cliente = cliente,
       _base = base,
       _frescura = frescura,
       _reloj = reloj;

  final ClienteApi _cliente;
  final BaseLocal _base;
  final RegistroDeFrescura _frescura;
  final Reloj _reloj;

  /// Cuantas tandas se encadenan como mucho cuando el servidor dice `truncado`.
  ///
  /// Un tope y no un `while (truncado)`: si un dia el servidor devolviera
  /// `truncado` sin avanzar la marca, un bucle sin tope se comeria la bateria y
  /// la conexion del logistico en el patio del almacen y no acabaria nunca.
  static const maximoDeTandas = 8;

  /// Las colecciones que sirve `GET /api/sync/cambios`.
  ///
  /// `order_items` no viene como conjunto suyo —los renglones viajan DENTRO del
  /// pedido— pero se marca igual: la franja de estado mira las nueve de
  /// `Colecciones.todas` y una sin marcar deja la pantalla diciendo «sin
  /// descargar» con los datos ya puestos.
  static const colecciones = <String>[
    Colecciones.pedidos,
    Colecciones.rutas,
    Colecciones.clientes,
    Colecciones.productos,
    Colecciones.vehiculos,
    Colecciones.sucursales,
    Colecciones.ajustes,
  ];

  /// Baja lo que haya cambiado y lo deja en la base local.
  ///
  /// Lo que lance sale tal cual (`fallos.dart`): `SesionMuerta` manda a la
  /// pantalla de acceso, `FalloDeRed` se reintenta luego y **no** toca nada de lo
  /// que ya estaba bajado. Una bajada que falla nunca deja la base peor que
  /// antes: lo que ya habia sigue ahi y la marca no se mueve.
  Future<ResumenDeBajada> ciclo({String? sucursal}) async {
    var puestos = 0;
    var quitados = 0;
    var completa = false;
    var tandas = 0;

    for (var vuelta = 0; vuelta < maximoDeTandas; vuelta++) {
      final desde = await _frescura.desde(Colecciones.pedidos);

      final datos = await _cliente.pedir<Map<String, Object?>>(
        '/sync/cambios',
        params: <String, Object?>{
          if (desde != null) 'desde': desde,
          if (sucursal != null) 'sucursal': sucursal,
        },
      );

      tandas++;
      final hasta = datos['hasta'] as String?;
      completa = completa || datos['completa'] == true;
      final cambios = (datos['cambios'] as Map<Object?, Object?>?) ?? const {};

      final cuenta = await _aplicar(cambios, hasta: hasta, completa: completa);
      puestos += cuenta.puestos;
      quitados += cuenta.quitados;

      if (datos['truncado'] != true) break;

      // Sin marca nueva no hay por donde seguir: pedir otra vez desde el mismo
      // sitio devolveria lo mismo para siempre.
      if (hasta == null) {
        Registro.aviso('la bajada vino truncada y sin `hasta`; se para aqui');
        break;
      }
      Registro.info('la bajada venia truncada: otra tanda desde $hasta');
    }

    return ResumenDeBajada(
      puestos: puestos,
      quitados: quitados,
      completa: completa,
      tandas: tandas,
    );
  }

  /// Los almacenes, que NO vienen en `cambios`.
  ///
  /// Viven en Accesos y de ahi salen (`GET /api/almacenes`). Estan declarados en
  /// `faltan` a proposito —Accesos no da marca de cambio ni dice que borro, asi
  /// que no hay diferencias posibles— y por eso aqui se reemplaza la copia
  /// entera en vez de mezclarla. Desde el almacen se mide lo que se le cobra al
  /// cliente por el domicilio: uno viejo cobra mal cada entrega del dia.
  Future<int> almacenes() async {
    final datos = await _cliente.pedir<Map<String, Object?>>('/almacenes');
    final sucursales = (datos['sucursales'] as List<Object?>?) ?? const [];

    var puestos = 0;
    await _base.transaction(() async {
      await _base.delete(_base.warehouses).go();
      for (final cruda in sucursales.whereType<Map<Object?, Object?>>()) {
        final codigo = _texto(cruda['codigo']) ?? '';
        final lista = (cruda['almacenes'] as List<Object?>?) ?? const [];
        for (final a in lista.whereType<Map<Object?, Object?>>()) {
          final id = _texto(a['id']);
          if (id == null) continue; // sin id no hay fila que casar
          await _base
              .into(_base.warehouses)
              .insertOnConflictUpdate(
                WarehousesCompanion.insert(
                  id: id,
                  sucursalCodigo: codigo,
                  nombre: _texto(a['nombre']) ?? '',
                  direccion: Value(_texto(a['direccion'])),
                  lat: Value(_numero(a['latitud'])),
                  lng: Value(_numero(a['longitud'])),
                  principal: Value(a['principal'] == true),
                  activo: Value(a['activo'] != false),
                ),
              );
          puestos++;
        }
      }
      await _marcar(
        const [Colecciones.almacenes],
        hasta: null,
        completa: true,
      );
    });
    return puestos;
  }

  Future<_Cuenta> _aplicar(
    Map<Object?, Object?> cambios, {
    required String? hasta,
    required bool completa,
  }) async {
    var puestos = 0;
    var quitados = 0;

    await _base.transaction(() async {
      for (final coleccion in colecciones) {
        final conjunto = cambios[coleccion];
        if (conjunto is! Map<Object?, Object?>) continue;

        final filas = (conjunto['puestos'] as List<Object?>?) ?? const [];
        for (final fila in filas.whereType<Map<Object?, Object?>>()) {
          await _poner(coleccion, fila);
          puestos++;
        }

        final fuera = (conjunto['quitados'] as List<Object?>?) ?? const [];
        for (final id in fuera.whereType<String>()) {
          await _quitar(coleccion, id);
          quitados++;
        }
      }

      // La marca, DENTRO de la misma transaccion que las filas.
      await _marcar(
        <String>[...colecciones, Colecciones.renglones],
        hasta: hasta,
        completa: completa,
      );
    });

    return _Cuenta(puestos, quitados);
  }

  Future<void> _marcar(
    List<String> colecciones, {
    required String? hasta,
    required bool completa,
  }) async {
    final ahora = _reloj();
    for (final coleccion in colecciones) {
      await _frescura.marcar(
        coleccion,
        hasta: hasta,
        bajadaAt: ahora,
        completa: completa,
      );
    }
  }

  Future<void> _poner(String coleccion, Map<Object?, Object?> j) async {
    switch (coleccion) {
      case Colecciones.pedidos:
        await _pedido(j);
      case Colecciones.rutas:
        await _base
            .into(_base.routes)
            .insertOnConflictUpdate(
              RoutesCompanion.insert(
                id: _texto(j['id'])!,
                name: Value(_texto(j['name'])),
                routeCode: Value(_texto(j['routeCode'])),
                status: Value(_texto(j['status']) ?? EstadoRuta.planificada),
                originLat: Value(_numero(j['originLat'])),
                originLng: Value(_numero(j['originLng'])),
                totalDistance: Value(_numero(j['totalDistance']) ?? 0),
                totalWeight: Value(_numero(j['totalWeight']) ?? 0),
                vehicleId: Value(_texto(j['vehicleId'])),
                branchId: Value(_texto(j['branchId'])),
                updatedAt: Value(_fecha(j['updatedAt'])),
              ),
            );
      case Colecciones.clientes:
        await _base
            .into(_base.customers)
            .insertOnConflictUpdate(
              CustomersCompanion.insert(
                id: _texto(j['id'])!,
                name: _texto(j['name']) ?? '',
                phone: Value(_texto(j['phone'])),
                address: Value(_texto(j['address'])),
                municipio: Value(_texto(j['municipio'])),
                zona: Value(_texto(j['zona'])),
                codigo: Value(_texto(j['codigo'])),
                vendedor: Value(_texto(j['vendedor'])),
                lat: _numero(j['lat']) ?? 0,
                lng: _numero(j['lng']) ?? 0,
                sucursalCodigo: Value(_texto(j['sucursalCodigo'])),
                syncedAt: Value(_fecha(j['syncedAt'])),
              ),
            );
      case Colecciones.productos:
        await _base
            .into(_base.products)
            .insertOnConflictUpdate(
              ProductsCompanion.insert(
                id: _texto(j['id'])!,
                name: _texto(j['name']) ?? '',
                weight: Value(_numero(j['weight']) ?? 0),
                category: Value(_texto(j['category'])),
                sku: Value(_texto(j['sku'])),
                sucursalCodigo: Value(_texto(j['sucursalCodigo'])),
                price: Value(_numero(j['price'])),
                stock: Value(_numero(j['stock'])),
                unit: Value(_texto(j['unit'])),
                updatedAt: Value(_fecha(j['updatedAt'])),
              ),
            );
      case Colecciones.vehiculos:
        await _base
            .into(_base.vehicles)
            .insertOnConflictUpdate(
              VehiclesCompanion.insert(
                id: _texto(j['id'])!,
                name: _texto(j['name']) ?? '',
                plate: Value(_texto(j['plate'])),
                capacity: Value(_numero(j['capacity']) ?? 1000),
                status: Value(_texto(j['status']) ?? EstadoVehiculo.disponible),
                branchId: Value(_texto(j['branchId'])),
                updatedAt: Value(_fecha(j['updatedAt'])),
              ),
            );
      case Colecciones.sucursales:
        await _base
            .into(_base.branches)
            .insertOnConflictUpdate(
              BranchesCompanion.insert(
                id: _texto(j['id'])!,
                name: _texto(j['name']) ?? '',
                address: Value(_texto(j['address'])),
                lat: _numero(j['lat']) ?? 0,
                lng: _numero(j['lng']) ?? 0,
                externalId: Value(_texto(j['externalId'])),
                originConfigured: Value(j['originConfigured'] == true),
                updatedAt: Value(_fecha(j['updatedAt'])),
              ),
            );
      case Colecciones.ajustes:
        // UNA sola fila, como en el servidor: dos filas de ajustes es media
        // aplicacion mirando una y media mirando la otra.
        await _base
            .into(_base.settings)
            .insertOnConflictUpdate(
              SettingsCompanion.insert(
                id: const Value(1),
                currency: Value(_texto(j['currency']) ?? 'USD'),
                cupRate: Value(_numero(j['cupRate']) ?? 320),
                cupRateUpdatedAt: Value(_fecha(j['cupRateUpdatedAt'])),
                catalogoTraidoAt: Value(_fecha(j['catalogoTraidoAt'])),
                updatedAt: Value(_fecha(j['updatedAt'])),
              ),
            );
    }
  }

  /// Un pedido con SUS RENGLONES, que viajan dentro.
  ///
  /// Los renglones se reemplazan enteros y no se mezclan: si la factura de
  /// PEDIDO quito una linea, mezclar la dejaria puesta y el despacho cargaria
  /// mercancia que ya no va (`sincronizacion.md` §1).
  Future<void> _pedido(Map<Object?, Object?> j) async {
    final id = _texto(j['id']);
    if (id == null) return;

    await _base
        .into(_base.orders)
        .insertOnConflictUpdate(
          OrdersCompanion.insert(
            id: id,
            operationNumber: Value(_texto(j['operationNumber'])),
            customerName: _texto(j['customerName']) ?? '',
            customerPhone: Value(_texto(j['customerPhone'])),
            address: _texto(j['address']) ?? '',
            endAddress: Value(_texto(j['endAddress'])),
            endLat: Value(_numero(j['endLat'])),
            endLng: Value(_numero(j['endLng'])),
            lat: Value(_numero(j['lat'])),
            lng: Value(_numero(j['lng'])),
            weight: Value(_numero(j['weight']) ?? 1),
            status: Value(_texto(j['status']) ?? EstadoPedido.pendiente),
            tripLeg: Value(_texto(j['tripLeg']) ?? Tramo.ida),
            notes: Value(_texto(j['notes'])),
            routeId: Value(_texto(j['routeId'])),
            ultimaRutaId: Value(_texto(j['ultimaRutaId'])),
            vehicleId: Value(_texto(j['vehicleId'])),
            price: Value(_numero(j['price'])),
            segmentKm: Value(_numero(j['segmentKm'])),
            deliveryPrice: Value(_numero(j['deliveryPrice'])),
            deliveryDistanceKm: Value(_numero(j['deliveryDistanceKm'])),
            branchId: Value(_texto(j['branchId'])),
            source: Value(_texto(j['source'])),
            externalId: Value(_texto(j['externalId'])),
            orderDate: Value(_fecha(j['orderDate'])),
            estado: Value(_texto(j['estado'])),
            archivado: Value(j['archivado'] == true),
            fechaComprometida: Value(_fecha(j['fechaComprometida'])),
            requiereDomicilio: Value(j['requiereDomicilio'] as bool?),
            pedidoCosto: Value(_numero(j['pedidoCosto'])),
            municipio: Value(_texto(j['municipio'])),
            vendedor: Value(_texto(j['vendedor'])),
            sucursalCodigo: Value(_texto(j['sucursalCodigo'])),
            facturaEstado: Value(_texto(j['facturaEstado'])),
            facturaNumero: Value(_texto(j['facturaNumero'])),
            facturaDomicilio: Value(_numero(j['facturaDomicilio'])),
            stopOrder: Value(_entero(j['stopOrder'])),
            deliveredAt: Value(_fecha(j['deliveredAt'])),
            resultado: Value(_texto(j['resultado'])),
            resultadoNota: Value(_texto(j['resultadoNota'])),
            updatedAt: Value(_fecha(j['updatedAt'])),
          ),
        );

    final renglones = (j['items'] as List<Object?>?) ?? const [];
    await (_base.delete(
      _base.orderItems,
    )..where((r) => r.orderId.equals(id))).go();
    for (final r in renglones.whereType<Map<Object?, Object?>>()) {
      final renglonId = _texto(r['id']);
      if (renglonId == null) continue;
      await _base
          .into(_base.orderItems)
          .insertOnConflictUpdate(
            OrderItemsCompanion.insert(
              id: renglonId,
              orderId: id,
              linea: _entero(r['linea']) ?? 1,
              description: _texto(r['description']) ?? '',
              quantity: _numero(r['quantity']) ?? 0,
              packs: Value(_numero(r['packs'])),
              productId: Value(_texto(r['productId'])),
              updatedAt: Value(_fecha(r['updatedAt'])),
            ),
          );
    }
  }

  Future<void> _quitar(String coleccion, String id) async {
    switch (coleccion) {
      case Colecciones.pedidos:
        // Los renglones primero: se borran a mano y no por cascada, porque la
        // tabla local no declara la clave ajena y un renglon huerfano sale luego
        // en el post-despacho de un pedido que ya no existe.
        await (_base.delete(
          _base.orderItems,
        )..where((r) => r.orderId.equals(id))).go();
        await (_base.delete(
          _base.orders,
        )..where((p) => p.id.equals(id))).go();
      case Colecciones.rutas:
        await (_base.delete(
          _base.routes,
        )..where((r) => r.id.equals(id))).go();
      case Colecciones.clientes:
        await (_base.delete(
          _base.customers,
        )..where((c) => c.id.equals(id))).go();
      case Colecciones.productos:
        await (_base.delete(
          _base.products,
        )..where((p) => p.id.equals(id))).go();
      case Colecciones.vehiculos:
        await (_base.delete(
          _base.vehicles,
        )..where((v) => v.id.equals(id))).go();
      case Colecciones.sucursales:
        await (_base.delete(
          _base.branches,
        )..where((s) => s.id.equals(id))).go();
    }
  }

  static String? _texto(Object? v) => switch (v) {
    final String s => s,
    _ => null,
  };

  static double? _numero(Object? v) => switch (v) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  static int? _entero(Object? v) => switch (v) {
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };

  /// Las fechas llegan en texto ISO. Una que no se entienda se guarda como
  /// `null` y no revienta la bajada: quedarse sin el dia entero por una marca
  /// rara es mucho peor que quedarse sin una fecha.
  static DateTime? _fecha(Object? v) {
    final texto = _texto(v);
    if (texto == null || texto.isEmpty) return null;
    return DateTime.tryParse(texto)?.toLocal();
  }
}

class ResumenDeBajada {
  const ResumenDeBajada({
    required this.puestos,
    required this.quitados,
    required this.completa,
    required this.tandas,
  });

  static const nada = ResumenDeBajada(
    puestos: 0,
    quitados: 0,
    completa: false,
    tandas: 0,
  );

  final int puestos;
  final int quitados;
  final bool completa;
  final int tandas;

  @override
  String toString() =>
      'ResumenDeBajada(puestos: $puestos, quitados: $quitados, '
      'completa: $completa, tandas: $tandas)';
}

class _Cuenta {
  const _Cuenta(this.puestos, this.quitados);

  final int puestos;
  final int quitados;
}
