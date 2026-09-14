import 'package:drift/drift.dart';

import '../../../nucleo/base/base.dart';

/// Lo que se le pide al informe. Sin valores por defecto: arranca sin rango y
/// sin vehiculo (pliego §7).
class FiltroDeInforme {
  const FiltroDeInforme({this.desde, this.hasta, this.vehiculoId});

  final DateTime? desde;
  final DateTime? hasta;
  final String? vehiculoId;

  bool get hayAlgoPuesto =>
      desde != null || hasta != null || vehiculoId != null;

  FiltroDeInforme copiar({
    DateTime? desde,
    DateTime? hasta,
    String? vehiculoId,
    bool quitarDesde = false,
    bool quitarHasta = false,
    bool quitarVehiculo = false,
  }) => FiltroDeInforme(
    desde: quitarDesde ? null : (desde ?? this.desde),
    hasta: quitarHasta ? null : (hasta ?? this.hasta),
    vehiculoId: quitarVehiculo ? null : (vehiculoId ?? this.vehiculoId),
  );

  @override
  bool operator ==(Object other) =>
      other is FiltroDeInforme &&
      other.desde == desde &&
      other.hasta == hasta &&
      other.vehiculoId == vehiculoId;

  @override
  int get hashCode => Object.hash(desde, hasta, vehiculoId);
}

/// Una fila de «Detalle de Órdenes».
class FilaDeInforme {
  const FilaDeInforme({
    required this.id,
    required this.cliente,
    required this.destino,
    required this.pesoKg,
    required this.importe,
    this.fecha,
    this.ruta,
    this.vehiculo,
    this.placa,
    this.kmDesdePartida,
  });

  final String id;
  final String cliente;
  final String destino;
  final double pesoKg;

  /// **Ingreso de un pedido = `price` si lo tiene, si no `pedidoCosto`.** Es el
  /// numero que mas facil se equivoca de todo el pliego, y por eso se calcula
  /// aqui y en ningun otro sitio.
  final double importe;

  final DateTime? fecha;
  final String? ruta;
  final String? vehiculo;
  final String? placa;
  final double? kmDesdePartida;
}

class ResumenDeInforme {
  const ResumenDeInforme({
    required this.totalOrdenes,
    required this.ingresos,
    required this.peso,
    required this.precioPromedio,
  });

  final int totalOrdenes;
  final double ingresos;
  final double peso;
  final double precioPromedio;
}

class FilaDeVehiculo {
  const FilaDeVehiculo({
    required this.nombre,
    required this.ordenes,
    required this.ingresos,
    required this.peso,
    this.placa,
  });

  final String nombre;
  final String? placa;
  final int ordenes;
  final double ingresos;
  final double peso;

  double get promedioPorOrden => ordenes == 0 ? 0 : ingresos / ordenes;
}

class Informe {
  const Informe({
    required this.filas,
    required this.resumen,
    required this.porVehiculo,
  });

  static const vacio = Informe(
    filas: <FilaDeInforme>[],
    resumen: ResumenDeInforme(
      totalOrdenes: 0,
      ingresos: 0,
      peso: 0,
      precioPromedio: 0,
    ),
    porVehiculo: <FilaDeVehiculo>[],
  );

  final List<FilaDeInforme> filas;
  final ResumenDeInforme resumen;

  /// **Solo los pedidos cuya ruta tiene vehiculo.** Lo dice el contrato, y sin
  /// esa condicion aparece una fila «sin vehiculo» que en la de Next no existe y
  /// descuadra la paridad.
  final List<FilaDeVehiculo> porVehiculo;
}

/// Los Informes, cuadrados **con lo que hay bajado en el aparato**.
///
/// Esta pantalla no es la del dia sin conexion y no pretende serlo: el informe
/// de verdad lo da `GET /api/reports`, sobre TODO lo que hay en el servidor.
/// Aqui solo puede salir lo que se haya bajado, y por eso la pantalla dice de
/// cuando son sus datos en vez de presentar un total como si fuera el bueno. Un
/// informe con la mitad de los pedidos no es un informe a medias: es un informe
/// equivocado.
class ConsultasInformes {
  ConsultasInformes(this._base);

  final BaseLocal _base;

  Stream<Informe> mirar(FiltroDeInforme filtro, {String? sucursalId}) {
    const sql = '''
SELECT o.id, o.customer_name, o.address, o.end_address, o.weight,
       o.price, o.pedido_costo, o.segment_km, o.created_at,
       COALESCE(r.route_code, r.name) AS ruta_nombre,
       v.name  AS vehiculo_nombre,
       v.plate AS vehiculo_placa
  FROM orders o
  LEFT JOIN routes   r ON r.id = o.route_id
  LEFT JOIN vehicles v ON v.id = r.vehicle_id
 WHERE (?1 IS NULL OR o.branch_id = ?1)
   AND (?2 IS NULL OR o.created_at >= ?2)
   AND (?3 IS NULL OR o.created_at <= ?3)
   AND (?4 IS NULL OR r.vehicle_id = ?4)
 ORDER BY o.created_at DESC
''';

    return _base
        .customSelect(
          sql,
          variables: [
            Variable<String>(sucursalId),
            Variable<DateTime>(filtro.desde),
            // `hasta` incluye el DIA ENTERO. Sin esto, pedir «hasta el 14» deja
            // fuera todo lo del 14, que es justo el dia que se queria mirar.
            Variable<DateTime>(finDelDia(filtro.hasta)),
            Variable<String>(filtro.vehiculoId),
          ],
          readsFrom: {_base.orders, _base.routes, _base.vehicles},
        )
        .watch()
        .map(armar);
  }

  /// Las 23:59:59.999 del dia de [dia]. Publica porque se prueba sola.
  static DateTime? finDelDia(DateTime? dia) => dia == null
      ? null
      : DateTime(dia.year, dia.month, dia.day, 23, 59, 59, 999);

  /// De filas crudas a informe. Separado de la consulta **a proposito**: asi las
  /// cuatro cifras y `Por Vehículo` se prueban con datos a mano, sin base.
  static Informe armar(List<QueryRow> crudas) {
    final filas = <FilaDeInforme>[];
    for (final f in crudas) {
      final precio = f.read<double?>('price');
      final costo = f.read<double?>('pedido_costo');
      filas.add(
        FilaDeInforme(
          id: f.read<String>('id'),
          cliente: f.read<String>('customer_name'),
          destino: f.read<String?>('end_address') ?? f.read<String>('address'),
          pesoKg: f.read<double>('weight'),
          importe: precio ?? costo ?? 0,
          fecha: f.read<DateTime?>('created_at'),
          ruta: f.read<String?>('ruta_nombre'),
          vehiculo: f.read<String?>('vehiculo_nombre'),
          placa: f.read<String?>('vehiculo_placa'),
          kmDesdePartida: f.read<double?>('segment_km'),
        ),
      );
    }
    return Informe(
      filas: filas,
      resumen: resumir(filas),
      porVehiculo: agruparPorVehiculo(filas),
    );
  }

  static ResumenDeInforme resumir(List<FilaDeInforme> filas) {
    var ingresos = 0.0;
    var peso = 0.0;
    for (final f in filas) {
      ingresos += f.importe;
      peso += f.pesoKg;
    }
    return ResumenDeInforme(
      totalOrdenes: filas.length,
      ingresos: ingresos,
      peso: peso,
      // Sin ordenes el promedio es 0, no una division por cero ni un `NaN` que
      // se pinta como «NaN» en la tarjeta.
      precioPromedio: filas.isEmpty ? 0 : ingresos / filas.length,
    );
  }

  static List<FilaDeVehiculo> agruparPorVehiculo(List<FilaDeInforme> filas) {
    final porNombre = <String, FilaDeVehiculo>{};
    for (final f in filas) {
      final nombre = f.vehiculo;
      if (nombre == null) continue; // sin vehiculo no entra (contrato §9)
      final previo = porNombre[nombre];
      porNombre[nombre] = FilaDeVehiculo(
        nombre: nombre,
        placa: f.placa ?? previo?.placa,
        ordenes: (previo?.ordenes ?? 0) + 1,
        ingresos: (previo?.ingresos ?? 0) + f.importe,
        peso: (previo?.peso ?? 0) + f.pesoKg,
      );
    }
    final lista = porNombre.values.toList()
      // De mas a menos ingreso: `Top vehículos` son las 3 primeras de aqui.
      ..sort((a, b) => b.ingresos.compareTo(a.ingresos));
    return lista;
  }
}
