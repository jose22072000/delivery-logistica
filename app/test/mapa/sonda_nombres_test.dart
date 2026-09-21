// SONDA: los nombres de calle sobre teselas de VERDAD, y lo que cuestan.
//
// No es una prueba de la suite —se salta sola sin el `.pmtiles` al lado— y
// existe por dos razones que ninguna prueba de unidad cubre:
//
//  1. **Mirarlo con los ojos.** Un reparto de rótulos puede cumplir todas las
//     guardas y verse amontonado igual. Se escriben los PNG y se abren.
//  2. **Lo que cuesta.** Esto corre al rasterizar CADA tesela en el teléfono del
//     repartidor, que no es esta máquina. Si rotular dispara el tiempo hay que
//     recortar por zoom, y para saberlo hay que medirlo sobre La Habana, que es
//     la tesela más cargada de Cuba (573 carreteras).

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/mapa/fondo_del_paquete.dart';
import 'package:reparto/mapa/mvt.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  const base =
      '/tmp/claude-1000/-mnt-datos-Work/7334aff6-02dc-47ca-ac43-1128133094d8/scratchpad';
  const fichero = '$base/cuba-detallado.pmtiles';

  // La Habana Vieja y el Vedado, en la rejilla del z14 y del z15.
  const teselas = [
    (z: 14, x: 4443, y: 7110),
    (z: 15, x: 8886, y: 14220),
    (z: 15, x: 8887, y: 14221),
    // Por encima del paquete: se amplía el antepasado del z15.
    (z: 17, x: 35547, y: 56882),
  ];

  test('los nombres de calle sobre La Habana: PNG y milisegundos', () async {
    final f = File(fichero);
    if (!f.existsSync()) {
      markTestSkipped('no está $fichero: la sonda necesita el paquete de verdad');
      return;
    }
    final paquete = await PaqueteDeTeselas.abrir(_Fichero(f.openSync()));

    for (final t in teselas) {
      // Un fondo nuevo por tesela: la caché de `FondoDelPaquete` mediría cero.
      final fondo = FondoDelPaquete(paquete);
      final reloj = Stopwatch()..start();
      final imagen = await fondo.tesela(t.z, t.x, t.y);
      reloj.stop();
      if (imagen == null) {
        // ignore: avoid_print
        print('z${t.z}/${t.x}/${t.y}: el paquete no la tiene');
        continue;
      }

      // Lo que cuestan los nombres, aparte: repartirlos y escribirlos. Se hace
      // sobre la MISMA tesela ya decodificada para no medir el descifrado.
      final crudo = await paquete.tesela(
        t.z > paquete.cabecera.zMax ? paquete.cabecera.zMax : t.z,
        t.x >> (t.z - (t.z > paquete.cabecera.zMax ? paquete.cabecera.zMax : t.z)),
        t.y >> (t.z - (t.z > paquete.cabecera.zMax ? paquete.cabecera.zMax : t.z)),
      );
      final capas = leerTeselaVectorial(crudo!);
      final salto = t.z - (t.z > paquete.cabecera.zMax ? paquete.cabecera.zMax : t.z);
      final aumento = (1 << salto).toDouble();
      final dentroX = t.x - ((t.x >> salto) << salto);
      final dentroY = t.y - ((t.y >> salto) << salto);

      final relojNombres = Stopwatch()..start();
      final rotulos = rotulosDeCalleDeLaTesela(
        capas,
        t.z,
        aumento: aumento,
        dentroX: dentroX,
        dentroY: dentroY,
      );
      // Y escribirlos, que es la otra mitad del coste.
      final grabadora = ui.PictureRecorder();
      final lienzo = ui.Canvas(grabadora);
      for (final r in rotulos) {
        final pintor = TextPainter(
          text: TextSpan(text: r.texto, style: const TextStyle(fontSize: 8)),
          textDirection: TextDirection.ltr,
        )..layout();
        lienzo.save();
        lienzo.translate(r.centro.dx, r.centro.dy);
        lienzo.rotate(r.angulo);
        pintor.paint(lienzo, Offset(-pintor.width / 2, -pintor.height / 2));
        lienzo.restore();
      }
      grabadora.endRecording().toImageSync(256, 256);
      relojNombres.stop();

      final cuantasVias = capas
          .where((c) => c.nombre == 'carretera')
          .fold(0, (a, c) => a + c.rasgos.length);

      // ignore: avoid_print
      print(
        'z${t.z}/${t.x}/${t.y}: $cuantasVias vías, ${rotulos.length} rótulos · '
        'tesela entera ${reloj.elapsedMicroseconds / 1000} ms · '
        'nombres ${relojNombres.elapsedMicroseconds / 1000} ms',
      );

      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      File('$base/nombres-z${t.z}-${t.x}-${t.y}.png')
          .writeAsBytesSync(datos!.buffer.asUint8List());
    }
  });
}
