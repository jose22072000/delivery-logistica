// EL FICHERO DEL MAPA, LEÍDO POR VARIOS A LA VEZ.
//
// Esto es lo que tenía el mapa de Jose en blanco el 21/09/2026, con Cuba
// descargada y el avión puesto: **una sola tesela arriba a la izquierda y el
// resto del recuadro vacío**. No era el dibujo ni el paquete: era que el mapa
// pide todas las teselas de la vista de golpe —y desde ese mismo día el
// enrutador por calles lee el mismo fichero a la vez para armar su grafo—, y un
// `RandomAccessFile` tiene UNA sola posición. Colocarse y leer son dos pasos con
// un `await` en medio: la segunda lectura movía la posición mientras la primera
// esperaba, y la primera leía desde donde no era.
//
// Lo peor de ese fallo es que **no falla**: devuelve otros bytes. Por eso la
// tesela no salía rota, salía en blanco, y la pantalla no tenía nada que decir.
//
// Y no lo cazaba ninguna prueba porque en las pruebas —y en la web— el paquete
// se lee de memoria, donde no hay posición que compartir. Sólo existe en el
// aparato, así que la prueba tiene que abrir un fichero DE VERDAD.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/mapa/carpeta_en_disco_nativo.dart';

void main() {
  test('veinte lecturas a la vez devuelven cada una LO SUYO', () async {
    // Un fichero donde cada bloque de 64 bytes lleva escrito su número: si una
    // lectura se lleva la posición de otra, lo que sale es el número del vecino
    // y se ve exactamente cuál pisó a cuál.
    const bloques = 20;
    const tamano = 64;
    final bytes = Uint8List(bloques * tamano);
    for (var i = 0; i < bloques; i++) {
      bytes.fillRange(i * tamano, (i + 1) * tamano, i + 1);
    }

    final carpeta = await Directory.systemTemp.createTemp('mapa-lecturas');
    addTearDown(() => carpeta.delete(recursive: true));
    await File('${carpeta.path}/paquete.bin').writeAsBytes(bytes);

    final rangos = await CarpetaEnDisco(carpeta).porRangos('paquete.bin');
    addTearDown(rangos.cerrar);

    // TODAS a la vez y sin `await` entre medias: es como las pide el mapa.
    final leidas = await Future.wait([
      for (var i = 0; i < bloques; i++) rangos.leer(i * tamano, tamano),
    ]);

    for (var i = 0; i < bloques; i++) {
      final quien = leidas[i].first;
      expect(
        quien,
        i + 1,
        reason:
            'LECTURAS QUE SE PISAN: el bloque $i devolvió los bytes del bloque '
            '${quien - 1}. En el teléfono eso es una tesela que se lee desde '
            'donde no es, no decodifica y deja el recuadro en blanco: el mapa '
            'sale a trozos y nadie dice por qué.',
      );
      expect(
        leidas[i].every((b) => b == i + 1),
        isTrue,
        reason: 'el bloque $i salió mezclado con otro',
      );
    }
  });

  test('una lectura que se pasa del final no deja la cola muerta', () async {
    // Si el turno se quedara en un futuro con error, TODAS las siguientes
    // fallarían y el mapa se quedaría en blanco hasta reiniciar. El error es de
    // quien pidió esa lectura, no de las que vienen detrás.
    final carpeta = await Directory.systemTemp.createTemp('mapa-lecturas');
    addTearDown(() => carpeta.delete(recursive: true));
    await File('${carpeta.path}/paquete.bin')
        .writeAsBytes(Uint8List.fromList(List.filled(32, 7)));

    final rangos = await CarpetaEnDisco(carpeta).porRangos('paquete.bin');
    addTearDown(rangos.cerrar);

    await expectLater(rangos.leer(0, 1000), throwsA(anything));

    final buena = await rangos.leer(0, 8);
    expect(
      buena.every((b) => b == 7),
      isTrue,
      reason:
          'LA COLA SE QUEDÓ MUERTA: una lectura que falló se llevó por delante '
          'las siguientes, así que el mapa no vuelve a pintar hasta reiniciar.',
    );
  });
}
