// SONDA: cuánto tarda y cuánto rodea el enrutado sin conexión, sobre el fichero
// de verdad.
//
// No es una prueba de la suite —no comprueba nada, imprime— y no corre sin el
// `.pmtiles` al lado. Existe porque el coste de esto es parte de su contrato:
// el enrutado se hace **en el hilo de la interfaz**, y un tramo que tarde medio
// segundo se ve como una aplicación colgada. Lo que garantiza la suite está en
// `calles_del_paquete_test.dart`; esto es para volver a medir cuando se toque el
// grafo o cambie el generador de teselas.
//
// Lo medido el 21/09/2026 en el portátil de Jose (i5-11400H), con
// `cuba-detallado.pmtiles` (60 MB, z15):
//
//     habana corto (2,9 km)   3,33 km  ×1,13    74 vértices   290 ms
//     habana medio (8,1 km)   9,49 km  ×1,17   154 vértices   130-170 ms
//     habana largo (10,7 km) 12,57 km  ×1,17   277 vértices   100-125 ms
//     habana–matanzas (81 km) 99,1 km  ×1,22   412 vértices   110-140 ms  (z11)
//     habana–camagüey (497)  528,9 km  ×1,06   798 vértices   135-165 ms  (z9)
//     habana corto OTRA VEZ    igual   igual   igual           39 ms
//     ruta de 8 paradas                        927 vértices   310-370 ms
//     la misma, ya calculada                                    0 ms
//
// **Los 290 ms del primero no son el coste del tramo, son el calentamiento de
// la máquina virtual**: el mismo tramo repetido al final, con otro enrutador y
// sin caché que valga, tarda 39 ms. Un tramo de ciudad son 40-60 ms, y por eso
// esto no necesita un isolate. Ojo al comparar: la suite corre en la VM de Dart
// con JIT, y la APK va compilada.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/mapa/calles_del_paquete.dart';
import 'package:reparto/mapa/pmtiles.dart';
import 'package:reparto/pantallas/rutas/datos/geo.dart';

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
  const camino =
      '/tmp/claude-1000/-mnt-datos-Work/7334aff6-02dc-47ca-ac43-1128133094d8/'
      'scratchpad/cuba-detallado.pmtiles';

  test('cuánto tarda y cuánto rodea el enrutado del paquete', () async {
    final f = File(camino);
    if (!f.existsSync()) {
      markTestSkipped('sin $camino no se mide nada');
      return;
    }
    final paquete = await PaqueteDeTeselas.abrir(_Fichero(f.openSync()));
    // ignore: avoid_print
    print('paquete z${paquete.cabecera.zMin}–z${paquete.cabecera.zMax}, '
        '${paquete.cabecera.entradas} teselas');

    Future<void> medir(String nombre, Punto a, Punto b) async {
      final reloj = Stopwatch()..start();
      final linea = await CallesDelPaquete(paquete).entre([a, b]);
      final ms = reloj.elapsedMilliseconds;
      if (linea == null) {
        // ignore: avoid_print
        print('$nombre: sin camino por calles, en $ms ms');
        return;
      }
      var largo = 0.0;
      for (var i = 0; i + 1 < linea.length; i++) {
        largo += haversineKm(linea[i], linea[i + 1]);
      }
      final recta = haversineKm(a, b);
      // ignore: avoid_print
      print('$nombre: ${linea.length} vértices · '
          '${largo.toStringAsFixed(2)} km contra ${recta.toStringAsFixed(2)} km '
          'en recta (×${(largo / recta).toStringAsFixed(2)}) · $ms ms');
    }

    const almacen = Punto(23.1136, -82.3666);
    await medir('habana corto', almacen, const Punto(23.1290, -82.3900));
    await medir('habana medio', almacen, const Punto(23.0600, -82.4200));
    await medir('habana largo', almacen, const Punto(23.0270, -82.3200));
    await medir('habana-matanzas', almacen, const Punto(23.0411, -81.5775));
    await medir('habana-camaguey', almacen, const Punto(21.3808, -77.9169));
    await medir('mar abierto', const Punto(23.50, -82.36), const Punto(23.60, -82.40));
    await medir('habana corto otra vez', almacen, const Punto(23.1290, -82.3900));

    // UNA RUTA ENTERA, como la pide el croquis: almacén y ocho paradas.
    final ruta = <Punto>[
      almacen,
      const Punto(23.1290, -82.3900),
      const Punto(23.1200, -82.3500),
      const Punto(23.1000, -82.4000),
      const Punto(23.0800, -82.3800),
      const Punto(23.0900, -82.3400),
      const Punto(23.1350, -82.3550),
      const Punto(23.1050, -82.3700),
      const Punto(23.1250, -82.4100),
    ];
    final enrutador = CallesDelPaquete(paquete);
    final reloj = Stopwatch()..start();
    final linea = await enrutador.entre(ruta);
    // ignore: avoid_print
    print('ruta de 8 paradas: ${linea?.length} vértices en '
        '${reloj.elapsedMilliseconds} ms');
    final otraVez = Stopwatch()..start();
    await enrutador.entre(ruta);
    // ignore: avoid_print
    print('la misma, ya calculada: ${otraVez.elapsedMilliseconds} ms');

    await paquete.cerrar();
  });
}
