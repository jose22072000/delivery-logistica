// LOS FICHEROS DE LA WEB.
//
// El paquete de mapa no existe en el navegador (`CLAUDE.md` §1), pero el código
// **tiene que compilar igual en los cuatro destinos**: la web se construye del
// mismo `lib/`. Por eso hay un `_stub` por cada trozo que usa `dart:io`.
//
// Esta prueba los importa a propósito —son los que se eligen cuando NO hay
// `dart:library.io`— para que el analizador y el compilador los miren de verdad.
// Sin ella, una firma que no cuadra en el stub no se descubre hasta el
// `flutter build web`, que es cuatro minutos más tarde y en otra máquina.
//
// Y comprueba lo otro: que **fallan con voz**. Devolver bytes vacíos o una
// carpeta de mentira dejaría una pantalla de descargas que no descarga nunca y
// no dice por qué — que es exactamente el aparato de sin-conexión colándose en
// la web, lo que Jose ha tenido que pedir que se quite tres veces.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/mapa/carpeta_en_disco_stub.dart';
import 'package:reparto/mapa/descomprimir_stub.dart';

void main() {
  test('en la web no se descomprime ningún paquete, y se dice', () {
    expect(
      () => descomprimirGzip(Uint8List(10)),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'el motivo',
          allOf(contains('web'), contains('APK')),
        ),
      ),
    );
  });

  test('en la web no hay carpeta de mapa, y se dice', () {
    expect(
      abrirLaCarpetaDelMapa,
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'el motivo',
          contains('escritorio'),
        ),
      ),
    );
  });
}
