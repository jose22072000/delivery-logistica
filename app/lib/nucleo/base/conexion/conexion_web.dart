import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

import '../../registro/registro.dart';

bool _fragil = false;

/// Si es `true`, al recargar la pestana SE PIERDE TODO.
///
/// Pasa en Safari en ventana privada y con las cookies de terceros a cero. La
/// aplicacion lo DICE —aviso permanente en la barra— en vez de esconderlo:
/// alguien trabajando sobre una base que se evapora al cerrar la pestana tiene
/// que saberlo antes, no despues.
bool get almacenamientoFragil => _fragil;

/// Web: SQLite de verdad, compilado a WebAssembly, en un worker y guardado en
/// OPFS. Si el navegador no da OPFS cae a IndexedDB, que tambien persiste.
///
/// `sqlite3.wasm` y `drift_worker.js` son FICHEROS DEL DESPLIEGUE: si falta uno,
/// la aplicacion arranca y la base no. Va en la lista de comprobacion.
QueryExecutor abrirConexion() => LazyDatabase(() async {
  final resultado = await WasmDatabase.open(
    databaseName: 'reparto',
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );

  if (resultado.missingFeatures.isNotEmpty) {
    Registro.aviso(
      'almacenamiento degradado: ${resultado.missingFeatures}',
    );
  }
  _fragil =
      resultado.chosenImplementation == WasmStorageImplementation.inMemory;
  if (_fragil) {
    Registro.aviso(
      'la base cayo a memoria: al cerrar la pestana se pierde lo que no se haya subido',
    );
  }

  return resultado.resolvedExecutor;
});
