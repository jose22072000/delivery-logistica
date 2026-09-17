/// Descomprimir gzip, resuelto en tiempo de compilacion.
///
/// POR QUE HACE FALTA ESTA COSTURA: `dart:io` no existe en el navegador, y esta
/// aplicacion compila para web tambien. El paquete de mapa **no se usa en la
/// web** —alli siempre hay servidor detras (`CLAUDE.md` §1)— pero el codigo
/// tiene que COMPILAR en los cuatro destinos igual. Es el mismo patron que
/// `nucleo/base/conexion/`.
library;

export 'descomprimir_stub.dart'
    if (dart.library.io) 'descomprimir_nativo.dart';
