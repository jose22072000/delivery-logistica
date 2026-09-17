// RUTAS ARMADAS A MANO, sin Drift.
//
// `Ruta` y `Pedido` son `DataClass` de Drift, pero su constructor solo exige
// siete campos: se pueden montar en memoria. Y hacerlo asi es lo correcto para
// lo que prueban el croquis, el enlace y el bloque del mapa, por dos motivos:
//
//  * ninguno de los tres consulta la base. Meter una base de verdad para
//    probarlos seria probar Drift;
//  * dentro de un `testWidgets` el reloj lo manda el `tester`, y lo que Drift
//    deja empezado no avanza solo. Las dos trampas del §5 del `CLAUDE.md` —el
//    `await` sobre un stream y el sembrado en el `setUp`— **cuelgan la prueba en
//    vez de fallarla**, que es lo peor que puede hacer una prueba. Sin base no
//    hay ninguna de las dos.
//
// Lo que SI toca la base es `recorridoDe`, y por eso esa tiene su propia prueba
// con `baseDePrueba()`.

import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';

Pedido paradaAMano({
  required String id,
  required String cliente,
  double? lat,
  double? lng,
  double? precio,
  String tramo = Tramo.ida,
  String? resultado,
}) => Pedido(
  id: id,
  customerName: cliente,
  address: 'Calle $id',
  endLat: lat,
  endLng: lng,
  price: precio,
  weight: 10,
  status: EstadoPedido.pendiente,
  tripLeg: tramo,
  resultado: resultado,
  archivado: false,
);

RutaConTodo rutaAMano({
  required List<Pedido> paradas,
  String id = 'R1',
  String? codigo = 'RT-001',
  String? nombre,
  double? origenLat = 21.38,
  double? origenLng = -77.91,
  double km = 42.5,
  DateTime? fecha,
  Vehiculo? vehiculo,
  Sucursal? sucursal,
}) => RutaConTodo(
  ruta: Ruta(
    id: id,
    routeCode: codigo,
    name: nombre,
    status: EstadoRuta.planificada,
    originLat: origenLat,
    originLng: origenLng,
    totalDistance: km,
    totalWeight: 100,
    totalPrice: 250,
    deliveryDate: fecha ?? DateTime(2026, 9, 14),
    optimized: true,
  ),
  paradas: paradas,
  vehiculo: vehiculo,
  sucursal: sucursal,
);

Vehiculo camionAMano({
  String nombre = 'Camión 1',
  String? matricula = 'P-001',
}) => Vehiculo(
  id: 'V1',
  name: nombre,
  plate: matricula,
  capacity: 1000,
  usarParaDomicilio: true,
  status: EstadoVehiculo.disponible,
);
