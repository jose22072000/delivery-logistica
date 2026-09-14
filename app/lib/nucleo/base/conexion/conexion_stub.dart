import 'package:drift/drift.dart';

/// Nunca se compila: existe para que el `export` condicional tenga una rama por
/// defecto. Si esto llega a ejecutarse es que el destino no es ni `dart:io` ni
/// web, y entonces no hay base local posible.
QueryExecutor abrirConexion() =>
    throw UnsupportedError('Este destino no tiene base local.');

/// Ver `conexion_web.dart`: en los destinos nativos el almacenamiento nunca es
/// fragil, porque es un fichero.
bool get almacenamientoFragil => false;
