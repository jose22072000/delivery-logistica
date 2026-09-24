import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:sqlite3/common.dart' show InMemoryFileSystem;
import 'package:sqlite3/wasm.dart' show WasmSqlite3;


bool _fragil = false;

/// Si es `true`, al recargar la pestana SE PIERDE TODO.
///
/// Pasa en Safari en ventana privada y con las cookies de terceros a cero. La
/// aplicacion lo DICE —aviso permanente en la barra— en vez de esconderlo:
/// alguien trabajando sobre una base que se evapora al cerrar la pestana tiene
/// que saberlo antes, no despues.
bool get almacenamientoFragil => _fragil;

/// Web: SQLite de verdad, compilado a WebAssembly, **y en memoria a proposito**.
///
/// ## La web NO guarda copia. Lee del servidor — 16/09/2026
///
/// Hasta hoy esto abria la base en OPFS —o en IndexedDB— y por tanto guardaba
/// una copia que sobrevivia a cerrar la pestana. Esa copia es lo que rompio el
/// tablero de la web: guardo una cola de salida, la cola se atasco, el tablero
/// **se nego a bajar durante hora y media** para no pisar lo que no habia
/// subido, y la pantalla enseñaba una foto de las 16:13 mientras el telefono
/// subia zonas que no aparecian. Refrescar no hacia nada.
///
/// Palabras de Jose, que lo dijo cinco veces:
///
/// > «el desktop y las apks tienen su propia base de datos para trabajar sin
/// > conexion; la web siempre esta con conexion porque esta en el servidor»
/// > «la web debe leer todo desde el servidor, desde la base de datos, no desde
/// > su base de datos copia»
///
/// Asi que en memoria. Cada carga de la pagina arranca vacia y se llena de lo
/// que diga el servidor, que es la unica verdad que hay. No queda nada entre
/// visitas: ni cola que se atasque, ni foto vieja que enseñar, ni dos versiones
/// de lo mismo.
///
/// **Drift se queda como el MOTOR DE CONSULTAS, no como almacen.** Las siete
/// pantallas filtran, ordenan y agrupan con las mismas reglas en las tres formas
/// de la aplicacion, y tener dos caminos de lectura seria tener dos verdades —que
/// es exactamente el fallo que se esta quitando, por el otro lado.
///
/// `sqlite3.wasm` sigue siendo un FICHERO DEL DESPLIEGUE: si falta, la
/// aplicacion arranca y la base no. El worker de Drift ya NO hace falta —sin
/// almacenamiento que compartir entre pestanas no hay nada que coordinar— y el
/// 24/09/2026 se fue ENTERO: `web/drift_worker.dart`, su `.js` compilado, el
/// `.map` y el `.deps` (760 KB que la imagen servia a cada navegador), y la
/// guarda del `deploy/Dockerfile.app` que hacia fallar el build si no estaba.
/// Se comprobo antes de quitarlo: en `lib` no queda un `WasmDatabase.open` ni
/// un `driftWorkerUri`, y el `main.dart.js` compilado no lo nombra.
///
/// [dueno] se ignora aqui. Una base por persona tiene sentido donde la copia
/// PERSISTE y dos personas comparten el aparato (`nombre.dart`); en una pestana
/// que se vacia al cerrarse no hay nada de la anterior que separar.
QueryExecutor abrirConexion({String? dueno}) => LazyDatabase(() async {
  final sqlite3 = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  sqlite3.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
  // `false`: aqui la memoria es la DECISION, no una degradacion. El aviso de
  // «se pierde lo que no se haya subido» era para la APK, y en la web no hay
  // nada que perder porque nada espera a subir.
  _fragil = false;
  return WasmDatabase.inMemory(sqlite3);
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
