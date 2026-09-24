import 'package:drift/drift.dart';
import 'package:reparto/nucleo/base/base.dart';

/// El almacen principal de Santiago, con coordenadas reales. Es el punto desde
/// el que se miden todas las distancias de estas pruebas.
const almacenLat = 20.0247;
const almacenLng = -75.8219;

/// Siembra una sucursal (`STG`) con su almacen principal.
Future<void> sembrarSucursal(
  BaseLocal base, {
  String id = 'b-stg',
  String codigo = 'STG',
  bool conAlmacen = true,
  bool activo = true,
  double lat = almacenLat,
  double lng = almacenLng,
}) async {
  await base
      .into(base.branches)
      .insert(
        BranchesCompanion.insert(
          id: id,
          name: 'Santiago',
          lat: lat,
          lng: lng,
          externalId: Value(codigo),
        ),
      );
  if (!conAlmacen) return;
  await base
      .into(base.warehouses)
      .insert(
        WarehousesCompanion.insert(
          id: 'w-1',
          sucursalCodigo: codigo,
          nombre: 'Almacén central',
          lat: Value(lat),
          lng: Value(lng),
          principal: const Value(true),
          activo: Value(activo),
        ),
      );
}

Future<void> sembrarCliente(
  BaseLocal base, {
  required String id,
  required String nombre,
  required double lat,
  required double lng,
  String? codigo,
  String? municipio,
  String? zona,
  String? vendedor,
  String? telefono,
  String? direccion,
  String? sucursalCodigo = 'STG',
  String? source = 'pedido',
}) => base
    .into(base.customers)
    .insert(
      CustomersCompanion.insert(
        id: id,
        name: nombre,
        lat: lat,
        lng: lng,
        codigo: Value(codigo),
        municipio: Value(municipio),
        zona: Value(zona),
        vendedor: Value(vendedor),
        phone: Value(telefono),
        address: Value(direccion),
        sucursalCodigo: Value(sucursalCodigo),
        source: Value(source),
      ),
    );

/// Deja constancia de que la coleccion SE BAJO. Sin esta fila la pantalla no
/// dice «no hay clientes», dice «no se ha descargado» — y son cosas distintas.
Future<void> marcarBajada(
  BaseLocal base,
  DateTime cuando, {
  List<String> colecciones = const [Colecciones.clientes],
}) async {
  for (final coleccion in colecciones) {
    await base
        .into(base.frescura)
        .insertOnConflictUpdate(
          FrescuraCompanion.insert(
            coleccion: coleccion,
            bajadaAt: Value(cuando),
            hasta: const Value('2026-09-14T08:00:00Z'),
          ),
        );
  }
}
