// EL LECTOR DEL PAQUETE, contra un fichero que escribió el generador de Go.
//
// ESTO ES LO QUE HACE QUE LA PRUEBA VALGA. Un lector probado sólo contra
// ficheros que él mismo escribe no comprueba el formato: comprueba que es
// consistente consigo mismo, y dos errores que se compensan salen verdes. La
// muestra de `test/mapa/muestra/cuba-muestra.pmtiles` la escribió
// `herramientas/mapa-cuba` a partir del `.osm.pbf` de Cuba de Geofabrik
// (16/09/2026) y la lee esto.
//
// Y **no se baja nada**: el fichero está en el repositorio, son 80 kB. Ni una
// petición a Geofabrik, ni a OpenStreetMap, ni a Procovar.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/mapa/mvt.dart';
import 'package:reparto/mapa/pmtiles.dart';

/// Lo que dijo el generador al sacarla. Se copia aquí a mano a propósito: si un
/// día alguien regenera la muestra y no toca esto, la prueba lo dice.
const bytesDeLaMuestra = 91082;
const teselasDeLaMuestra = 16;

Future<Uint8List> _muestra() async =>
    File('test/mapa/muestra/cuba-muestra.pmtiles').readAsBytes();

void main() {
  test('la muestra es la que dice el generador', () async {
    final bytes = await _muestra();
    expect(
      bytes.length,
      bytesDeLaMuestra,
      reason:
          'la muestra cambió de tamaño: si se regeneró, hay que actualizar los '
          'números de esta prueba y volver a mirar que todo lo de abajo cuadra',
    );
  });

  test('se abre y la cabecera dice lo que el generador escribió', () async {
    final paquete = await PaqueteDeTeselas.abrir(
      RangosEnMemoria(await _muestra()),
    );
    expect(paquete.cabecera.entradas, teselasDeLaMuestra);
    expect(paquete.cabecera.zMin, 0);
    expect(paquete.cabecera.zMax, 6);
    // El recuadro de Cuba, tal y como salió del .pbf. Que el signo de la
    // longitud esté bien es lo que separa Cuba de un punto en China.
    expect(paquete.cabecera.minLon, closeTo(-84.95, 0.01));
    expect(paquete.cabecera.maxLon, closeTo(-74.13, 0.01));
    expect(paquete.cabecera.minLat, closeTo(19.83, 0.01));
    expect(paquete.cabecera.maxLat, closeTo(23.28, 0.01));
  });

  test('la atribución de OpenStreetMap viaja DENTRO del fichero', () async {
    final paquete = await PaqueteDeTeselas.abrir(
      RangosEnMemoria(await _muestra()),
    );
    final meta = await paquete.metadatos();
    expect(
      '${meta['attribution']}',
      contains('OpenStreetMap'),
      reason:
          'la licencia la exige donde se enseñe el mapa, también sin conexión: '
          'metida en el fichero no se pierde aunque cambie la pantalla',
    );
  });

  test('una tesela sale, y es una tesela vectorial de verdad', () async {
    final paquete = await PaqueteDeTeselas.abrir(
      RangosEnMemoria(await _muestra()),
    );
    // z0 es la única tesela del nivel 0 y el generador dijo que trae costa.
    final crudo = await paquete.tesela(0, 0, 0);
    expect(crudo, isNotNull, reason: 'la 0/0/0 está en el paquete');

    final capas = leerTeselaVectorial(crudo!);
    expect(capas, isNotEmpty);
    final costa = capas.firstWhere((c) => c.nombre == 'costa');
    expect(
      costa.rasgos.length,
      501,
      reason: 'es lo que contó el generador al escribirla',
    );
    expect(costa.extension, 4096);
    // Las coordenadas van en unidades de tesela, dentro del cuadro (con el
    // margen que deja el recorte).
    for (final r in costa.rasgos.take(20)) {
      for (final parte in r.partes) {
        for (final p in parte) {
          expect(p.dx, inInclusiveRange(-4096, 8192));
          expect(p.dy, inInclusiveRange(-4096, 8192));
        }
      }
    }
  });

  test('un nombre con tilde llega entero', () async {
    final paquete = await PaqueteDeTeselas.abrir(
      RangosEnMemoria(await _muestra()),
    );
    final nombres = <String>{};
    for (var x = 0; x < 64; x++) {
      for (var y = 0; y < 64; y++) {
        final crudo = await paquete.tesela(6, x, y);
        if (crudo == null) continue;
        for (final capa in leerTeselaVectorial(crudo)) {
          if (capa.nombre != 'poblacion') continue;
          for (final r in capa.rasgos) {
            if (r.nombre != null) nombres.add(r.nombre!);
          }
        }
      }
    }
    expect(nombres, isNotEmpty, reason: 'la muestra trae núcleos con nombre');
    // Si el UTF-8 se leyera byte a byte, «Camagüey» saldría como «CamagÃ¼ey» y
    // ningún nombre tendría un carácter fuera del ASCII.
    expect(
      nombres.any((n) => n.codeUnits.any((c) => c > 127)),
      isTrue,
      reason:
          'ningún nombre tiene tildes ni eñes: el UTF-8 se está leyendo byte a '
          'byte y los nombres de aquí salen partidos',
    );
  });

  test('una tesela que no está devuelve null, no la de al lado', () async {
    final paquete = await PaqueteDeTeselas.abrir(
      RangosEnMemoria(await _muestra()),
    );
    // Fuera del recuadro de Cuba: en la muestra no hay nada ahí.
    expect(await paquete.tesela(6, 0, 0), isNull);
    // Por encima del zoom del paquete: el lector no inventa.
    expect(await paquete.tesela(12, 1200, 1700), isNull);
  });

  test('la curva de Hilbert es la de la especificación', () {
    // Los mismos números que comprueba el generador de Go
    // (`mapa_cuba_test.go`). Si los dos lados no coinciden, el paquete se
    // escribe bien y se lee de otro sitio — y eso se ve como un mapa raro, no
    // como un error.
    expect(idDeTesela(0, 0, 0), 0);
    expect(idDeTesela(1, 0, 0), 1);
    expect(idDeTesela(1, 0, 1), 2);
    expect(idDeTesela(1, 1, 1), 3);
    expect(idDeTesela(1, 1, 0), 4);
    expect(idDeTesela(2, 0, 0), 5);
    expect(idDeTesela(3, 0, 0), 21);
  });

  group('lo que NO es un paquete se dice, no se lee a medias', () {
    test('un fichero a medio bajar', () async {
      final trozo = Uint8List.sublistView(await _muestra(), 0, 60);
      expect(
        () => PaqueteDeTeselas.abrir(RangosEnMemoria(trozo)),
        throwsA(isA<PaqueteIlegible>()),
      );
    });

    test('otra cosa cualquiera', () async {
      final otro = Uint8List.fromList(
        List.generate(200, (i) => 'no soy un mapa'.codeUnitAt(i % 14)),
      );
      expect(
        () => PaqueteDeTeselas.abrir(RangosEnMemoria(otro)),
        throwsA(isA<PaqueteIlegible>()),
      );
    });

    test('un paquete sin una sola tesela', () async {
      // Se copia la muestra y se le pone a cero el número de entradas: se abre
      // sin un solo error y dejaría el mapa en blanco para siempre.
      final trucada = Uint8List.fromList(await _muestra());
      ByteData.sublistView(trucada).setUint64(80, 0, Endian.little);
      expect(
        () => PaqueteDeTeselas.abrir(RangosEnMemoria(trucada)),
        throwsA(isA<PaqueteIlegible>()),
        reason: 'una respuesta vacía no es una respuesta buena (CLAUDE.md §3)',
      );
    });

    test('un paquete de teselas de imagen', () async {
      final trucada = Uint8List.fromList(await _muestra());
      trucada[99] = 2; // 2 = PNG
      expect(
        () => PaqueteDeTeselas.abrir(RangosEnMemoria(trucada)),
        throwsA(isA<PaqueteIlegible>()),
      );
    });
  });

  test('unos bytes que no son MVT devuelven cero capas y no lanzan', () {
    // Esto corre dentro del repintado del mapa: una excepción aquí deja la
    // pantalla en negro en vez de dejar el croquis debajo.
    expect(
      leerTeselaVectorial(Uint8List.fromList(List.filled(300, 0xFF))),
      isEmpty,
    );
    expect(leerTeselaVectorial(Uint8List(0)), isEmpty);
  });
}
