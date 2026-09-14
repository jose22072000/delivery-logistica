// El worker de Drift para la web. Se compila a `web/drift_worker.js`:
//
//   dart compile js -O4 -o web/drift_worker.js web/drift_worker.dart
//
// Es quien corre SQLite (sobre `sqlite3.wasm`) fuera del hilo de la interfaz y
// guarda el fichero en OPFS. Los DOS ficheros —este y el .wasm— son ficheros
// del despliegue: si falta uno, la aplicacion arranca y la base no.
import 'package:drift/wasm.dart';

void main() => WasmDatabase.workerMainForOpen();
