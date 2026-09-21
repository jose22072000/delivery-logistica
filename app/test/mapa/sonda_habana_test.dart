// SONDA: abre el fichero de VERDAD y pregunta qué hay sobre La Habana.
//
// No es una prueba de la suite: no corre sin el `.pmtiles` al lado, y por eso se salta
// sola si no está. Existe porque el 21/09/2026 el teléfono, sin señal y con el paquete
// bajado, decía «Mapa de calles» y dibujaba una hoja en blanco.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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

({int x, int y}) _teselaDe(double lat, double lng, int z) {
  final n = 1 << z;
  final x = ((lng + 180) / 360 * n).floor();
  final r = lat * math.pi / 180;
  final y = ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n)
      .floor();
  return (x: x, y: y);
}

void main() {
  const camino =
      '/tmp/claude-1000/-mnt-datos-Work/7334aff6-02dc-47ca-ac43-1128133094d8/scratchpad/cuba-detallado.pmtiles';

  test('qué trae una tesela sobre La Habana', () async {
    final f = File(camino);
    if (!f.existsSync()) {
      // ignore: avoid_print
      print('sin fichero, no se sonda');
      return;
    }
    final paquete = await PaqueteDeTeselas.abrir(_Fichero(f.openSync()));

    // La Habana Vieja, y de paso el almacén de la ruta.
    for (final z in [10, 12, 13, 14]) {
      final t = _teselaDe(23.11, -82.37, z);
      final crudo = await paquete.tesela(z, t.x, t.y);
      if (crudo == null) {
        // ignore: avoid_print
        print('z$z (${t.x},${t.y}): NO HAY TESELA');
        continue;
      }
      final capas = leerTeselaVectorial(crudo);
      final resumen = <String, int>{};
      for (final c in capas) {
        resumen[c.nombre] = c.rasgos.length;
      }
      // ignore: avoid_print
      print('z$z (${t.x},${t.y}): ${crudo.length} bytes · $resumen');
      // Y las clases de las carreteras, que es lo que decide si se pinta.
      final vias = capas.where((c) => c.nombre == 'carretera');
      if (vias.isNotEmpty) {
        final clases = <String, int>{};
        for (final r in vias.first.rasgos) {
          final cl = '${r.clase}';
          clases[cl] = (clases[cl] ?? 0) + 1;
        }
        // ignore: avoid_print
        print('   clases: $clases');
        // ignore: avoid_print
        final primera = vias.first.rasgos.first;
        // ignore: avoid_print
        print(
          '   extension=${vias.first.extension} · partes=${primera.partes.length}'
          ' · primeros puntos=${primera.partes.first.take(3)}',
        );
      }
    }
  });
}
