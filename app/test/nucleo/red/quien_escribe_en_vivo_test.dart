// EL ÚNICO SITIO DONDE SE DECIDE QUIÉN ESCRIBE EN VIVO.
//
// `escrituraEnVivoProvider` es la bisagra entera: con él puesto, Rutas y el
// Tablero mandan cada gesto al servidor y esperan; sin él, escriben en local y
// encolan. Las pruebas de las dos pantallas inyectan la pieza a mano —así se
// ejercitan los dos mundos sin compilar para web— y por eso **ninguna de ellas
// cazaría esta línea puesta a `null`**: la web volvería a no escribir nada y
// todo seguiría en verde, que es exactamente como se llegó al 22/09/2026.
//
// Por eso esta prueba está sola y mira sólo esto.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';

void main() {
  test('en la web SÍ hay escritura en vivo', () async {
    await Destino.comoSiFueraWeb(() async {
      final contenedor = ProviderContainer.test();
      expect(
        contenedor.read(escrituraEnVivoProvider),
        isNotNull,
        reason:
            'sin esto la web vuelve a encolar sobre una base en memoria que '
            'muere al recargar, y la cola sale por `/sync`, que contesta 401 '
            'porque en un navegador no hay aparato que dar de alta',
      );
    });
  });

  test('en la APK y en el escritorio NO la hay', () {
    final contenedor = ProviderContainer.test();
    expect(
      contenedor.read(escrituraEnVivoProvider),
      isNull,
      reason:
          'allí se arma la ruta en el patio de un almacén, sin señal: esperar '
          'al servidor sería no poder cerrar ninguna ruta',
    );
  });

  test('lo decide `trabajaSinConexion` y nada más', () {
    // La capacidad con nombre, no un `kIsWeb` repartido: el día que aparezca un
    // cuarto destino —una PWA instalada, un kiosco— se cambia en un solo sitio.
    final contenedor = ProviderContainer.test(
      overrides: [trabajaSinConexionProvider.overrideWithValue(false)],
    );
    expect(contenedor.read(escrituraEnVivoProvider), isNotNull);

    final otro = ProviderContainer.test(
      overrides: [trabajaSinConexionProvider.overrideWithValue(true)],
    );
    expect(otro.read(escrituraEnVivoProvider), isNull);
  });
}
