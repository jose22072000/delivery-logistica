import 'package:drift/native.dart';
import 'package:reparto/nucleo/base/base.dart';

/// Una `BaseLocal` en memoria, recien creada. El mismo Dart y el mismo SQL que
/// en el aparato: lo unico que cambia es donde vive el fichero.
BaseLocal baseDePrueba() => BaseLocal.con(NativeDatabase.memory());
