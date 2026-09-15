/// La conexion a SQLite, resuelta en tiempo de compilacion.
///
/// Es la pieza que hace verdad «el mismo Dart y el mismo SQL en Android y en
/// web»: arriba de esta linea nadie sabe en que destino corre.
library;

export 'conexion_stub.dart'
    if (dart.library.io) 'conexion_nativa.dart'
    if (dart.library.js_interop) 'conexion_web.dart';
export 'nombre.dart';
