import '../pantallas/almacenes/registro.dart';
import '../pantallas/clientes/registro.dart';
import '../pantallas/vehiculos/registro.dart';
import '../pantallas/informes/registro.dart';
import '../pantallas/panel/registro.dart';
import '../pantallas/pedidos/registro.dart';
import '../pantallas/rutas/registro.dart';
import '../pantallas/tablero/registro.dart';
import 'pantalla_registrada.dart';

/// EL REGISTRO. Una linea por pantalla, en el orden en que salen en el menu.
///
/// Este es el unico fichero que un agente de pantalla toca fuera de su carpeta,
/// y toca **una sola linea**: sustituye su `_pendiente(...)` por la llamada a su
/// `registrarX()` y anade el import. El contrato entero esta explicado en
/// `pantalla_registrada.dart`.
///
/// Ya estan las siete mas el tablero: no queda ninguna por montar.
List<PantallaRegistrada> pantallasDeLaAplicacion() => <PantallaRegistrada>[
  registrarPanel(),

  // DECISION A CONFIRMAR CON JOSE: el tablero es una pantalla NUEVA
  // (`docs/tablero.md`, 14/09/2026) y por eso no esta en las 6 entradas del
  // pliego §8.1, que describe la de Next. Se pone en el menu porque es la
  // pantalla del dia del logistico y sin entrada no se llega a ella; si se
  // decide lo contrario, es cambiar `enElMenu` a false.
  registrarTablero(),

  registrarRutas(),
  registrarPedidos(),
  registrarClientes(),
  registrarVehiculos(),
  registrarAlmacenes(),

  // Reportes NO va en el menu (pliego §8.1): se llega por URL y desde las
  // acciones rapidas del Panel.
  registrarInformes(),
];

// Ya NO hay `_pendiente(...)`: con Rutas y Pedidos montadas no queda ninguna
// pantalla sin escribir, y un hueco que no se usa es codigo muerto que hace
// pensar que todavia falta algo. Si hiciera falta otra vez, esta en el historial.
