// Lo que Rutas ESCRIBE. Es el corazon del proyecto.
//
// Las cinco acciones —armar, iniciar, completar, eliminar y cerrar parada por
// parada— hacen siempre lo mismo y en este orden:
//
//   1. se comprueba **en el aparato** lo que se puede comprobar, con los mensajes
//      LITERALES del servidor, para que un rechazo local y uno remoto se lean
//      igual;
//   2. se escribe en la base local y se pinta como hecho;
//   3. se encola el apunte con la **hora del aparato** y se sube por detras.
//
// No hay un «modo sin conexion»: esto es lo que pasa siempre, tenga red o no.
// Quien tenga senal todo el dia simplemente vera subir la cola a medida que
// trabaja. El caso que manda es el otro: el patio del almacen, donde no hay
// senal, es donde se cierra la ruta.

import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/cola/cola_salida.dart';
import '../../../nucleo/cola/provisionales.dart';
import '../../../nucleo/registro/registro.dart';
import '../../../nucleo/reloj.dart';
import 'geo.dart';

/// Un «no» dicho por el aparato, con el MISMO texto que diria el servidor.
///
/// Se comprueba aqui lo que se puede para que el rechazo tardio —el que llega
/// horas despues, al subir, y sale en la bandeja— sea la excepcion y no lo
/// normal. Y con el mismo texto para que nadie tenga que aprender dos idiomas de
/// error.
class RechazoLocal implements Exception {
  const RechazoLocal(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Como acabo una parada, tal y como sale del cierre.
class MarcaDeParada {
  const MarcaDeParada({
    required this.pedidoId,
    required this.resultado,
    this.nota,
  });

  final String pedidoId;

  /// `entregado` | `devuelto` | `cancelado`.
  final String resultado;
  final String? nota;

  bool get seEntrego => resultado == ResultadoParada.entregado;

  Map<String, Object?> aJson() => <String, Object?>{
    'orderId': pedidoId,
    'resultado': resultado,
    'nota': nota,
  };
}

class AccionesDeRuta {
  AccionesDeRuta(
    this._base,
    this._cola, {
    Reloj reloj = relojDelAparato,
    String sufijoAparato = 'LOC',
  }) : _reloj = reloj,
       _sufijo = sufijoAparato;

  final BaseLocal _base;
  final ColaDeSalida _cola;
  final Reloj _reloj;

  /// El sufijo que distingue los codigos de ruta generados sin conexion. Sin el,
  /// dos sucursales sin red el mismo dia generan `RT-20260914-001` las dos.
  final String _sufijo;

  /// El maximo que acepta el servidor para la nota de una parada.
  static const topeDeNota = 500;

  // ---------------------------------------------------------------------------
  // Armar
  // ---------------------------------------------------------------------------

  /// Arma una ruta con pedidos que ya existen. Devuelve el id de la ruta, que
  /// sin conexion es un `local-…`.
  ///
  /// El orden de visita, los km, el peso y el precio se calculan **en el
  /// aparato** (`geo.dart`, calcado de `reglas-negocio.md` §1): si los pusiera el
  /// servidor, no se podria armar una ruta sin red, que es la mitad del dia.
  Future<String> armar({
    required String? vehiculoId,
    required List<String> pedidoIds,
    required double? origenLat,
    required double? origenLng,
    String? nombre,
    String? origenDireccion,
    String? sucursalId,
    DateTime? fechaDeEntrega,
  }) async {
    // Las validaciones van en el ORDEN ESTRICTO del servidor: si dos fallan a la
    // vez, la persona tiene que leer el mismo mensaje en los dos sitios.
    if (origenLat == null || origenLng == null) {
      throw const RechazoLocal(
        'Las coordenadas del punto de partida son requeridas',
      );
    }
    if (vehiculoId == null || vehiculoId.isEmpty) {
      throw const RechazoLocal('Se requiere un vehículo para crear la ruta');
    }
    if (pedidoIds.isEmpty) {
      throw const RechazoLocal(
        'Una ruta se arma eligiendo pedidos ya existentes. Manda `orderIds`.',
      );
    }

    final pedidos = await _pedidosArmables(pedidoIds, sucursalId);

    if (pedidos.isEmpty) {
      throw const RechazoLocal('Los pedidos seleccionados ya no están disponibles');
    }
    if (pedidos.length < pedidoIds.length) {
      final faltan = pedidoIds.length - pedidos.length;
      throw RechazoLocal(
        '$faltan de los ${pedidoIds.length} pedidos ya están en otra ruta. '
        'Vuelve a elegirlos.',
      );
    }

    final noFacturados = [
      for (final p in pedidos)
        if (p.facturaEstado != EstadoFactura.igual) p,
    ];
    if (noFacturados.isNotEmpty) {
      throw RechazoLocal(_mensajeDeFactura(noFacturados));
    }

    final pesoTotal = pedidos.fold<double>(0, (suma, p) => suma + p.weight);
    final vehiculo = await (_base.select(
      _base.vehicles,
    )..where((v) => v.id.equals(vehiculoId))).getSingleOrNull();
    // Si el vehiculo no esta en el aparato NO se valida capacidad y la ruta se
    // crea igual: es lo que hace el servidor, y negarla aqui dejaria sin armar
    // rutas a quien todavia no ha bajado su flota.
    if (vehiculo != null && pesoTotal > vehiculo.capacity) {
      throw RechazoLocal(
        'Peso total (${pesoTotal.toStringAsFixed(1)} kg) supera la capacidad '
        'del vehículo (${_sinDecimalesSobrantes(vehiculo.capacity)} kg)',
      );
    }

    final origen = Punto(origenLat, origenLng);
    final paradas = [
      for (final p in pedidos)
        if (p.endLat != null && p.endLng != null)
          Parada(p.id, p.endLat!, p.endLng!),
    ];
    final orden = vecinoMasCercano(origen, paradas);
    final porId = {for (final p in pedidos) p.id: p};
    final ordenadas = [
      for (final id in orden)
        Parada(id, porId[id]!.endLat!, porId[id]!.endLng!),
    ];

    final rutaId = Provisionales.nuevoId();
    final codigo = await _codigoDeRuta();
    final ahora = _reloj();
    final sucursalDeLaRuta = sucursalId ?? pedidos.first.branchId;

    await _base.transaction(() async {
      await _base
          .into(_base.routes)
          .insert(
            RoutesCompanion.insert(
              id: rutaId,
              name: Value(nombre),
              routeCode: Value(codigo),
              status: const Value(EstadoRuta.planificada),
              originAddress: Value(origenDireccion),
              originLat: Value(origenLat),
              originLng: Value(origenLng),
              totalDistance: Value(kmDelCircuito(origen, ordenadas)),
              totalWeight: Value(pesoTotal),
              totalPrice: Value(
                pedidos.fold<double>(0, (suma, p) => suma + (p.pedidoCosto ?? 0)),
              ),
              deliveryDate: Value(fechaDeEntrega),
              vehicleId: Value(vehiculoId),
              branchId: Value(sucursalDeLaRuta),
              optimized: const Value(true),
              createdAt: Value(ahora),
              updatedAt: Value(ahora),
            ),
          );

      for (var i = 0; i < orden.length; i++) {
        final pedido = porId[orden[i]]!;
        await (_base.update(
          _base.orders,
        )..where((o) => o.id.equals(pedido.id))).write(
          OrdersCompanion(
            routeId: Value(rutaId),
            ultimaRutaId: Value(rutaId),
            stopOrder: Value(i + 1),
            tripLeg: const Value(Tramo.ida),
            // `segmentKm` es la distancia RADIAL desde el origen, no la del
            // tramo del recorrido. Es raro y es a proposito: es lo que guarda el
            // servidor y con lo que se compara la paridad.
            segmentKm: Value(
              haversineKm(origen, Punto(pedido.endLat!, pedido.endLng!)),
            ),
            price: Value(pedido.pedidoCosto ?? 0),
            vehicleId: Value(vehiculoId),
            updatedAt: Value(ahora),
          ),
        );
      }
    });

    await _cola.encolar(
      metodo: 'POST',
      ruta: '/routes',
      // El cuerpo lleva `orderIds` en el ORDEN CALCULADO aqui. El servidor
      // recalcula el suyo, pero mandarlo ordenado deja constancia de lo que el
      // aparato decidio cuando no habia con quien consultarlo.
      cuerpo: <String, Object?>{
        'name': ?nombre,
        'branchId': sucursalDeLaRuta,
        'vehicleId': vehiculoId,
        if (fechaDeEntrega != null)
          'deliveryDate': fechaDeEntrega.toIso8601String(),
        'originAddress': origenDireccion,
        'originLat': origenLat,
        'originLng': origenLng,
        'orderIds': orden,
      },
      // La bisagra: cuando esto suba, el id de verdad sustituye a `local-…` en
      // la cola y en las filas locales. Sin esto, el cierre de la tarde se iria
      // a `/routes/local-9f3a/results` y se perderia justo despues de subir.
      provisional: rutaId,
    );

    return rutaId;
  }

  /// Los pedidos que de verdad se pueden meter, con las mismas condiciones que
  /// la consulta del servidor.
  Future<List<Pedido>> _pedidosArmables(
    List<String> ids,
    String? sucursalId,
  ) async {
    final consulta = _base.select(_base.orders)
      ..where(
        (o) =>
            o.id.isIn(ids) &
            o.source.equals(Procedencia.pedido) &
            o.routeId.isNull() &
            o.endLat.isNotNull() &
            o.endLng.isNotNull() &
            (sucursalId == null || sucursalId.isEmpty
                ? const Constant(true)
                : o.branchId.equals(sucursalId)),
      );
    return consulta.get();
  }

  /// El mensaje compuesto de los no facturados, letra a letra como el servidor:
  /// los 5 primeros con su motivo y, si hay mas, ` y <n> más.`
  String _mensajeDeFactura(List<Pedido> noFacturados) {
    String motivo(Pedido p) => switch (p.facturaEstado) {
      EstadoFactura.cambiado => 'cambió en la factura',
      EstadoFactura.sinFactura => 'sin facturar',
      // NULL y cualquier otro valor: sin cotejar.
      _ => 'sin cotejar',
    };

    final n = noFacturados.length;
    final detalle = noFacturados
        .take(5)
        .map((p) => '${p.operationNumber ?? p.customerName} (${motivo(p)})')
        .join(', ');
    final cola = n > 5 ? ' y ${n - 5} más.' : '.';
    return 'En una ruta sólo entra lo facturado y que cuadre. '
        '$n no cumplen: $detalle$cola';
  }

  /// `RT-YYYYMMDD-NNN-<aparato>`.
  ///
  /// El formato es el de `generateRouteCode()` mas el sufijo del aparato
  /// (PLAN.md §3.2): el `NNN` sale de contar lo que hay **en este aparato**, asi
  /// que sin el sufijo dos sucursales sin red generarian el mismo codigo el mismo
  /// dia. **Al aplicarse en el servidor manda el del servidor** y la fila local se
  /// reescribe con la respuesta.
  Future<String> _codigoDeRuta() async {
    final hoy = _reloj().toUtc();
    final fecha =
        '${hoy.year.toString().padLeft(4, '0')}'
        '${hoy.month.toString().padLeft(2, '0')}'
        '${hoy.day.toString().padLeft(2, '0')}';
    final prefijo = 'RT-$fecha-';

    final cuenta = _base.routes.id.count();
    final fila =
        await (_base.selectOnly(_base.routes)
              ..addColumns([cuenta])
              ..where(_base.routes.routeCode.like('$prefijo%')))
            .getSingle();
    final siguiente = (fila.read(cuenta) ?? 0) + 1;
    return '$prefijo${siguiente.toString().padLeft(3, '0')}-$_sufijo';
  }

  // ---------------------------------------------------------------------------
  // Estado de la ruta
  // ---------------------------------------------------------------------------

  /// `Iniciar ruta`. Marca el vehiculo como ocupado, igual que el servidor.
  Future<void> iniciar(String rutaId) async {
    final ahora = _reloj();
    final ruta = await _ruta(rutaId);
    if (ruta == null) throw const RechazoLocal('No encontrada');

    await _base.transaction(() async {
      await (_base.update(_base.routes)..where((r) => r.id.equals(rutaId)))
          .write(
            OrdersDeRuta.enCurso(
              ahora: ahora,
              yaEmpezada: ruta.startedAt != null,
            ),
          );
      await _ocuparVehiculo(ruta.vehicleId, EstadoVehiculo.enUso);
    });

    await _cola.encolar(
      metodo: 'PATCH',
      ruta: '/routes/$rutaId',
      cuerpo: <String, Object?>{'status': EstadoRuta.enCurso},
    );
  }

  /// `Marcar como completada`. Libera el vehiculo.
  ///
  /// Ojo: completar NO cierra la ruta. El camion vuelve despues, y por eso el
  /// boton `Cierre` sigue disponible en `completed`.
  Future<void> completar(String rutaId) async {
    final ahora = _reloj();
    final ruta = await _ruta(rutaId);
    if (ruta == null) throw const RechazoLocal('No encontrada');

    await _base.transaction(() async {
      await (_base.update(_base.routes)..where((r) => r.id.equals(rutaId)))
          .write(
            RoutesCompanion(
              status: const Value(EstadoRuta.completada),
              finishedAt: Value(ahora),
              updatedAt: Value(ahora),
            ),
          );
      await _ocuparVehiculo(ruta.vehicleId, EstadoVehiculo.disponible);
    });

    await _cola.encolar(
      metodo: 'PATCH',
      ruta: '/routes/$rutaId',
      cuerpo: <String, Object?>{'status': EstadoRuta.completada},
    );
  }

  /// `Eliminar`, sólo rutas no completadas.
  ///
  /// **No borra pedidos**: les suelta la ruta y los devuelve a la lista de
  /// disponibles. `ultimaRutaId` se conserva, o el pedido desapareceria de la
  /// hoja de lo que bajo del camion.
  Future<void> eliminar(String rutaId) async {
    final ruta = await _ruta(rutaId);
    if (ruta == null) throw const RechazoLocal('No encontrada');
    if (ruta.status == EstadoRuta.completada) {
      throw const RechazoLocal('No encontrada');
    }

    await _base.transaction(() async {
      await (_base.update(_base.orders)..where((o) => o.routeId.equals(rutaId)))
          .write(
            const OrdersCompanion(
              routeId: Value(null),
              stopOrder: Value(null),
              segmentKm: Value(null),
              tripLeg: Value(Tramo.ida),
            ),
          );
      await _ocuparVehiculo(ruta.vehicleId, EstadoVehiculo.disponible);
      await (_base.delete(_base.routes)..where((r) => r.id.equals(rutaId))).go();
    });

    await _cola.encolar(
      metodo: 'DELETE',
      ruta: '/routes/$rutaId',
      cuerpo: const <String, Object?>{},
    );
  }

  Future<Ruta?> _ruta(String rutaId) => (_base.select(
    _base.routes,
  )..where((r) => r.id.equals(rutaId))).getSingleOrNull();

  Future<void> _ocuparVehiculo(String? vehiculoId, String estado) async {
    if (vehiculoId == null) return;
    await (_base.update(_base.vehicles)
          ..where((v) => v.id.equals(vehiculoId)))
        .write(VehiclesCompanion(status: Value(estado)));
  }

  // ---------------------------------------------------------------------------
  // El cierre parada por parada — el caso de uso principal
  // ---------------------------------------------------------------------------

  /// Guarda el cierre: se escribe en la base local **con la hora del aparato** y
  /// se encola un solo apunte hacia `POST /api/routes/<id>/results`.
  ///
  /// Se pinta como hecho sin esperar al servidor. Esto pasa en el patio del
  /// almacen, donde no hay senal: esperar una respuesta seria no poder cerrar
  /// ninguna ruta.
  ///
  /// Devuelve la `clave` del apunte, que es con lo que se le sigue la pista.
  Future<String> cerrar(String rutaId, List<MarcaDeParada> marcas) async {
    if (marcas.isEmpty) throw const RechazoLocal('No vino ningún resultado');

    // El universo valido es `ultimaRutaId`, NO `routeId`: asi se puede corregir
    // el resultado de un pedido que ya se marco como devuelto y por tanto solto
    // su ruta.
    final paradas = await (_base.select(
      _base.orders,
    )..where((o) => o.ultimaRutaId.equals(rutaId))).get();
    final deLaRuta = {for (final p in paradas) p.id};

    final validas = <MarcaDeParada>[];
    for (final marca in marcas) {
      if (!deLaRuta.contains(marca.pedidoId)) {
        // El mismo motivo literal del servidor. No aborta el resto: lo que se
        // puede guardar se guarda.
        Registro.aviso(
          'cierre de $rutaId: ${marca.pedidoId} — ese pedido no va en esta ruta',
        );
        continue;
      }
      if (!const [
        ResultadoParada.entregado,
        ResultadoParada.devuelto,
        ResultadoParada.cancelado,
      ].contains(marca.resultado)) {
        Registro.aviso(
          "cierre de $rutaId: resultado '${marca.resultado}' desconocido",
        );
        continue;
      }
      validas.add(marca);
    }
    if (validas.isEmpty) throw const RechazoLocal('No vino ningún resultado');

    // LA HORA DEL APARATO. Lo que se marca a las cuatro en el patio queda como
    // las cuatro aunque suba a las siete (regla 7).
    final ahora = _reloj();

    final limpias = <MarcaDeParada>[];
    await _base.transaction(() async {
      for (final marca in validas) {
        final nota = _notaLimpia(marca.nota);
        limpias.add(
          MarcaDeParada(
            pedidoId: marca.pedidoId,
            resultado: marca.resultado,
            nota: nota,
          ),
        );
        await (_base.update(
          _base.orders,
        )..where((o) => o.id.equals(marca.pedidoId))).write(
          OrdersCompanion(
            resultado: Value(marca.resultado),
            resultadoAt: Value(ahora),
            resultadoNota: Value(nota),
            deliveredAt: Value(marca.seEntrego ? ahora : null),
            status: Value(
              marca.seEntrego ? EstadoPedido.entregado : EstadoPedido.pendiente,
            ),
            // Lo que NO se entrega suelta su `routeId` y vuelve a la lista de
            // disponibles para la ruta de manana. `ultimaRutaId` y `stopOrder`
            // no se tocan NUNCA: son lo que ata el pedido a la hoja de cierre.
            routeId: marca.seEntrego ? const Value.absent() : const Value(null),
            updatedAt: Value(ahora),
          ),
        );
      }
    });

    return _cola.encolar(
      metodo: 'POST',
      ruta: '/routes/$rutaId/results',
      cuerpo: <String, Object?>{
        'resultados': [for (final m in limpias) m.aJson()],
      },
    );
  }

  /// La nota, recortada como la recorta el servidor: sin espacios sobrantes,
  /// maximo 500 caracteres, y vacia es `null` y no `''`.
  static String? _notaLimpia(String? cruda) {
    final texto = cruda?.trim() ?? '';
    if (texto.isEmpty) return null;
    return texto.length <= topeDeNota
        ? texto
        : texto.substring(0, topeDeNota);
  }

  /// La capacidad va en el mensaje **sin formatear**, igual que el servidor:
  /// `1000` y no `1000.0`.
  static String _sinDecimalesSobrantes(double valor) =>
      valor == valor.roundToDouble()
      ? valor.round().toString()
      : valor.toString();
}

/// Los dos companions del cambio de estado, juntos para que el «sólo si aun es
/// null» de `startedAt` no se pierda en medio de un metodo.
abstract final class OrdersDeRuta {
  static RoutesCompanion enCurso({
    required DateTime ahora,
    required bool yaEmpezada,
  }) => RoutesCompanion(
    status: const Value(EstadoRuta.enCurso),
    // `startedAt` sólo se pone la primera vez: volver a iniciar una ruta no
    // reescribe a que hora salio el camion, que es con lo que se mide la
    // duracion.
    startedAt: yaEmpezada ? const Value.absent() : Value(ahora),
    finishedAt: const Value(null),
    updatedAt: Value(ahora),
  );
}
