import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// Android: SQLite embebido en el APK (`sqlite3_flutter_libs`) sobre un fichero
/// en el directorio de la aplicacion.
///
/// Va en un ISOLATE APARTE a proposito: la pantalla de Pedidos consulta doce mil
/// filas con nueve filtros y eso, en el hilo de la interfaz, es la aplicacion
/// trabada mientras el logistico espera en el patio de un almacen.
QueryExecutor abrirConexion() =>
    driftDatabase(name: 'reparto', native: const DriftNativeOptions());

/// En un fichero, lo guardado esta guardado.
bool get almacenamientoFragil => false;
