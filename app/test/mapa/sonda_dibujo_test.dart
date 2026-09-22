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
    final f = File('$base/mapa/cuba-completo-260922.pmtiles');
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
    final f = File('$base/mapa/cuba-detallado-260922.pmtiles');
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

  test('la Ciénaga de Zapata sale de color de ciénaga, no de prado', () async {
    // LA SONDA DEL HUMEDAL. Lo que el 21/09/2026 salió mal y ninguna prueba
    // podía ver: la clase `humedal` caía en el `_ =>` del pintor y la mancha más
    // grande de Cuba se pintaba del color de la hierba.
    //
    // `colores_del_suelo_test.dart` ata la decisión —de qué color sale cada
    // clase— y eso es lo que corre siempre. Esto de aquí es la otra mitad y
    // necesita el paquete de verdad al lado: que ese color **llegue al lienzo**
    // sobre la Ciénaga, o sea que el generador la esté mandando y que el pintor
    // la esté pintando. Las dos cosas a la vez no las dice ninguna de las otras.
    final f = File('$base/mapa/cuba-detallado-260922.pmtiles');
    if (!f.existsSync()) {
      markTestSkipped('sin el paquete nuevo al lado');
      return;
    }
    final fondo = FondoDelPaquete(
      await PaqueteDeTeselas.abrir(_Fichero(f.openSync())),
    );

    // La Ciénaga de Zapata, en la rejilla de z11: lon -81,3 / lat 22,35.
    final imagen = await fondo.tesela(11, 561, 893);
    expect(imagen, isNotNull, reason: 'el paquete no devolvió la tesela');

    final datos = await imagen!.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = datos!.buffer.asUint8List();
    var deCienaga = 0;
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      if (bytes[i] == 0xCC && bytes[i + 1] == 0xE3 && bytes[i + 2] == 0xDB) {
        deCienaga++;
      }
    }
    // ignore: avoid_print
    print('píxeles de humedal en la tesela de la Ciénaga: $deCienaga de 65536');

    final png = await imagen.toByteData(format: ui.ImageByteFormat.png);
    File('$base/cienaga-z11.png').writeAsBytesSync(png!.buffer.asUint8List());

    expect(
      deCienaga,
      greaterThan(2000),
      reason:
          'la Ciénaga de Zapata no sale del color del humedal: o el generador no '
          'la manda, o el pintor no la conoce y volvió a caer en el `_ =>`',
    );
  });
}
