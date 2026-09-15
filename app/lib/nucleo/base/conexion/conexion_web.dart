import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

import '../../registro/registro.dart';
import 'nombre.dart';

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
/// [dueno] es el `sub` del token. **Una base por persona**, igual que en la APK:
/// el porque, entero, en `nombre.dart`.
QueryExecutor abrirConexion({String? dueno}) => LazyDatabase(() async {
  final resultado = await WasmDatabase.open(
    databaseName: nombreDeLaBase(dueno),
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );

  if (resultado.missingFeatures.isNotEmpty) {
    Registro.aviso('almacenamiento degradado: ${resultado.missingFeatures}');
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

/// En web NO se borra el fichero, porque no hay fichero: la base vive en OPFS o
/// en IndexedDB y drift no expone un borrado por nombre en esta version. Quien
/// olvida a alguien (`BaseLocal.olvidar`) ya ha vaciado sus tablas una por una
/// antes de llegar aqui, que es lo que de verdad quita los datos; lo que queda
/// es una base vacia con su nombre, y eso no dice nada de nadie.
Future<void> borrarLaCopia(String dueno) async {}

/// En web no se abren copias ajenas: no hay carpeta que listar, asi que esto no
/// llega a llamarse nunca. Existe para que la interfaz sea la misma en los tres
/// destinos.
QueryExecutor abrirConexionDeFichero(String nombre) =>
    throw UnsupportedError('En web no se abren las copias de otras personas.');

/// En web no hay carpeta que listar: cada navegador guarda lo suyo y drift no
/// expone un listado por nombre. Quien olvida a alguien en web lo hace estando
/// dentro de su propia sesion.
Future<List<String>> copiasEnElAparato() async => const <String>[];

/// En web no hubo nunca un fichero suelto que mirar.
Future<bool> hayBaseDeAntes() async => false;
