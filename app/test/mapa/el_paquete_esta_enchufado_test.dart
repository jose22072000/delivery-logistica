// EL CABLEADO, que es lo que nadie prueba y lo que llega al teléfono roto.
//
// Escrito el 21/09/2026 en la auditoría final, después de romper a propósito el
// `recorridoConPaqueteProvider` para que devolviera siempre el de la red —o sea,
// con el mapa de Cuba descargado y **sin usarlo jamás**— y ver que las 72
// pruebas de `test/mapa` seguían en verde. Todas probaban las piezas; ninguna
// probaba que estuvieran conectadas.
//
// Y es exactamente el fallo que Jose ve y nosotros no: en el teléfono, con el
// avión puesto, las calles no salen y la ruta va en línea recta, mientras aquí
// todo dice que funciona. La pieza está bien hecha y no la llama nadie.
//
// Por eso esto no mira lo que devuelven: mira **de qué clase son**. Es la única
// pregunta que distingue «el paquete está enchufado» de «el paquete existe».

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/mapa/calles_del_paquete.dart';
import 'package:reparto/mapa/fondo_del_paquete.dart';
import 'package:reparto/mapa/pmtiles.dart';
import 'package:reparto/mapa/proveedores_de_mapa.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';

Future<PaqueteDeTeselas> _muestra() async => PaqueteDeTeselas.abrir(
  RangosEnMemoria(
    await File('test/mapa/muestra/cuba-muestra.pmtiles').readAsBytes(),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> conPaquete(PaqueteDeTeselas? paquete) async {
    final caja = ProviderContainer(
      overrides: [paqueteAbiertoProvider.overrideWith((ref) async => paquete)],
    );
    addTearDown(caja.dispose);
    // Hay que esperar al futuro: los dos proveedores miran `.value`, que hasta
    // que el futuro no resuelve es `null` — y `null` es justo el caso contrario
    // al que se quiere probar.
    await caja.read(paqueteAbiertoProvider.future);
    return caja;
  }

  group('con el mapa de Cuba descargado', () {
    test('las CALLES del croquis salen del paquete, no de la red', () async {
      final caja = await conPaquete(await _muestra());

      expect(
        caja.read(fondoConPaqueteProvider),
        isA<FondoDelPaquete>(),
        reason:
            'EL PAQUETE NO ESTÁ ENCHUFADO AL FONDO: hay mapa descargado y el '
            'croquis sigue pidiéndole las teselas a OpenStreetMap, así que sin '
            'señal no sale ni una calle.',
      );
    });

    test(
      'el RECORRIDO va por las calles del paquete, no en línea recta',
      () async {
        final caja = await conPaquete(await _muestra());

        expect(
          caja.read(recorridoConPaqueteProvider),
          isA<CallesDelPaquete>(),
          reason:
              'EL PAQUETE NO ESTÁ ENCHUFADO AL RECORRIDO: hay mapa descargado y la '
              'ruta se sigue pidiendo a OSRM, que sin señal no contesta. Es lo que '
              'vio Jose el 21/09/2026: «la ruta no es lógica, son rectas».',
        );
      },
    );
  });

  group('sin mapa descargado', () {
    test('el fondo es el de la red', () async {
      final caja = await conPaquete(null);
      expect(caja.read(fondoConPaqueteProvider), isA<CallesDeOsm>());
    });

    test('el recorrido es el de la red', () async {
      final caja = await conPaquete(null);
      expect(caja.read(recorridoConPaqueteProvider), isA<CallesDeOsrm>());
    });
  });
}
