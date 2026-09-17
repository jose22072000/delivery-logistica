import 'dart:io' show gzip;
import 'dart:typed_data';

/// Android, Windows y Linux: el gzip que trae Dart.
Uint8List descomprimirGzip(Uint8List crudo) =>
    Uint8List.fromList(gzip.decode(crudo));
