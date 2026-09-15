import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../registro/registro.dart';
import 'nombre.dart';

/// Android y escritorio: SQLite embebido (`sqlite3_flutter_libs`) sobre un
/// fichero en el directorio de la aplicacion.
///
/// Va en un ISOLATE APARTE a proposito: la pantalla de Pedidos consulta doce mil
/// filas con nueve filtros y eso, en el hilo de la interfaz, es la aplicacion
/// trabada mientras el logistico espera en el patio de un almacen.
///
/// [dueno] es el `sub` del token. **Un fichero por persona**: el porque, entero,
/// en `nombre.dart`.
QueryExecutor abrirConexion({String? dueno}) => driftDatabase(
  name: nombreDeLaBase(dueno),
  native: const DriftNativeOptions(),
);

/// Una copia por SU NOMBRE DE FICHERO, sin saber de quien es.
///
/// Hace falta para poder mirar las copias que hay en el aparato: el nombre del
/// fichero lleva la parte legible del `sub` recortada y una huella, asi que del
/// nombre no se puede volver al `sub` — hay que abrir la base y preguntarselo.
QueryExecutor abrirConexionDeFichero(String nombre) =>
    driftDatabase(name: nombre, native: const DriftNativeOptions());

/// En un fichero, lo guardado esta guardado.
bool get almacenamientoFragil => false;

/// Borra la copia de una persona, fichero incluido.
///
/// Es el gesto de **olvidar a alguien**, que es aparte y explicito a proposito
/// (`nombre.dart`): cerrar sesion cambia de copia, olvidar es lo que la borra.
/// Quien llama tiene que haber mirado antes si a esa persona le queda trabajo
/// sin subir.
Future<void> borrarLaCopia(String dueno) async {
  final carpeta = await getApplicationDocumentsDirectory();
  final base = '${carpeta.path}/${nombreDeLaBase(dueno)}.sqlite';
  // Los tres: SQLite deja el diario al lado y un `-wal` huerfano de una base
  // borrada es lo que hace que la siguiente con el mismo nombre no abra.
  for (final camino in <String>[base, '$base-wal', '$base-shm']) {
    final fichero = File(camino);
    if (fichero.existsSync()) await fichero.delete();
  }
}

/// Las copias que hay en este aparato, por el nombre de su fichero.
///
/// Se listan del DISCO y no de una lista guardada aparte: una lista aparte se
/// desincroniza con los ficheros —se borra una copia a mano, se restaura una
/// copia de seguridad— y entonces el gesto de olvidar a alguien deja de ver a la
/// persona que de verdad tiene datos ahi. El disco es la verdad.
Future<List<String>> copiasEnElAparato() async {
  try {
    final carpeta = await getApplicationDocumentsDirectory();
    return <String>[
      for (final f in carpeta.listSync().whereType<File>())
        if (_esUnaCopia(f.uri.pathSegments.last))
          f.uri.pathSegments.last.replaceAll('.sqlite', ''),
    ];
  } on Object catch (e) {
    Registro.aviso('no se pudieron listar las copias del aparato: $e');
    return const <String>[];
  }
}

/// `reparto-<algo>.sqlite`, y ni el diario ni la base neutra ni la de antes.
bool _esUnaCopia(String fichero) =>
    fichero.startsWith('reparto-') &&
    fichero.endsWith('.sqlite') &&
    fichero != '${nombreDeLaBase(null)}.sqlite';

/// ¿Quedo el fichero de la version de UNA SOLA BASE por aparato?
///
/// Se mira al arrancar para poder decirlo. Ver `nombreDeLaBaseDeAntes`.
Future<bool> hayBaseDeAntes() async {
  try {
    final carpeta = await getApplicationDocumentsDirectory();
    return File('${carpeta.path}/$nombreDeLaBaseDeAntes.sqlite').existsSync();
  } on Object catch (e) {
    Registro.aviso('no se pudo mirar si hay base de antes: $e');
    return false;
  }
}
