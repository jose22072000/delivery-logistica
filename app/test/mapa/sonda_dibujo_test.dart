// SONDA: dibuja una tesela de verdad y la guarda en PNG para mirarla.
//
// No es una prueba de la suite: se salta sola sin el `.pmtiles` al lado. Existe porque el
// 21/09/2026 el teléfono decía «Mapa de calles» y enseñaba una hoja en blanco, y los datos
// estaban bien: 573 carreteras en la tesela de La Habana, con sus clases.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/mapa/fondo_del_paquete.dart';
import 'package:reparto/mapa/pmtiles.dart';

class _Fichero implements LeerPorRangos {
  _Fichero(this._f);
  final RandomAccessFile _f;
  @override
  Future<Uint8List> leer(int desde, int largo) async {
    await _f.setPosition(desde);
    return _f.read(largo);
  }

  @override
  Future<void> cerrar() async => _f.close();
}

void main() {
  const base =
      '/tmp/claude-1000/-mnt-datos-Work/7334aff6-02dc-47ca-ac43-1128133094d8/scratchpad';

  test('dibuja La Habana y guarda el PNG', () async {
    final f = File('$base/cuba-completo.pmtiles');
    if (!f.existsSync()) return;
    final fondo = FondoDelPaquete(
      await PaqueteDeTeselas.abrir(_Fichero(f.openSync())),
    );

    // La misma tesela que la sonda de datos: 573 carreteras dentro.
    final imagen = await fondo.tesela(14, 4443, 7110);
    expect(imagen, isNotNull, reason: 'el paquete no devolvió imagen');

    final datos = await imagen!.toByteData(format: ui.ImageByteFormat.png);
    File('$base/tesela-habana.png')
        .writeAsBytesSync(datos!.buffer.asUint8List());
    // ignore: avoid_print
    print('tesela ${imagen.width}×${imagen.height} guardada');
  });

  test('y la misma con las capas nuevas: suelo, manzanas y tren', () async {
    // El paquete del 21/09/2026, el que lleva `suelo`, `edificio` y `tren`. Es
    // el que hay que mirar con los ojos: lo que Jose pidió es que se parezca al
    // mapa con conexión, y eso no lo dice ningún assert.
    final f = File('$base/cuba-detallado-260921.pmtiles');
    if (!f.existsSync()) {
      markTestSkipped('sin el paquete nuevo al lado');
      return;
    }
    final fondo = FondoDelPaquete(
      await PaqueteDeTeselas.abrir(_Fichero(f.openSync())),
    );

    for (final donde in const [
      (z: 14, x: 4443, y: 7110, nombre: 'habana-z14'),
      (z: 15, x: 8887, y: 14221, nombre: 'habana-z15'),
      (z: 12, x: 1110, y: 1777, nombre: 'habana-z12'),
    ]) {
      final imagen = await fondo.tesela(donde.z, donde.x, donde.y);
      if (imagen == null) {
        // ignore: avoid_print
        print('${donde.nombre}: sin tesela');
        continue;
      }
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      File('$base/nueva-${donde.nombre}.png')
          .writeAsBytesSync(datos!.buffer.asUint8List());
      // ignore: avoid_print
      print('${donde.nombre}: ${imagen.width}×${imagen.height} guardada');
    }
  });
}
