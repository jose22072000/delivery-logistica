import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// EL PERMISO DE RED TIENE QUE ESTAR EN EL MANIFIESTO DE `main`.
///
/// Flutter crea el proyecto con `INTERNET` declarado sólo en `src/debug/` y
/// `src/profile/`, porque lo que necesita red en esos dos modos es la recarga en
/// caliente. El de `main` —el único que entra en un `--release`— se queda sin él.
///
/// El 16/09/2026 se instaló la release en un Galaxy A16 con wifi de cinco rayas
/// y no se podía entrar: «Sin conexión con el servidor. Comprueba la señal». Era
/// verdad que no había conexión, pero no por la señal: la aplicación no tenía
/// permiso para abrir un socket. En debug el permiso SÍ está, así que probando
/// como se prueba siempre eso no se ve nunca, y la APK de las diez tabletas
/// habría salido muerta.
///
/// Esta prueba corre en cada `./comprobar.sh`. Cuesta milisegundos y tapa un
/// fallo que sólo se ve con un teléfono en la mano.
void main() {
  test('el manifiesto de release declara INTERNET y ACCESS_NETWORK_STATE', () {
    final manifiesto = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    for (final permiso in ['INTERNET', 'ACCESS_NETWORK_STATE']) {
      expect(
        manifiesto,
        contains('android.permission.$permiso'),
        reason:
            'sin $permiso en el manifiesto de `main`, la APK de release no '
            'puede hablar con el servidor y lo cuenta como falta de señal',
      );
    }
  });
}
