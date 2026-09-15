// NINGUNA RUTA EMPIEZA POR `/api/`, porque la base del cliente YA lo lleva.
//
// `lib/nucleo/proveedores.dart` monta el `ClienteApi` con `baseUrl: Entorno.apiUrl`, que
// en produccion es `https://reparto.procovar.cloud/api`. Una ruta escrita como
// `'/api/board'` se pega detras de eso y sale `…/api/api/board`, que es un 404 — siempre,
// en todas las peticiones de esa pantalla.
//
// ESTO YA PASO. El Tablero entero iba con `/api/board…` en sus diez llamadas, asi que no
// funcionaba ni una: ni bajar el tablero, ni mover una tarjeta, ni armar la ruta de una
// columna. Y no lo cazo nadie porque **las pruebas del Tablero repetian la ruta mala**:
// el servidor falso contestaba a `/api/api/board` tan contento y todo salia verde. Una
// prueba que copia la direccion del codigo que prueba no comprueba la direccion.
//
// Por eso esta mira el CODIGO FUENTE y no el comportamiento: es la unica forma de cazar
// la proxima, que se escribira en una pantalla que todavia no existe.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ninguna ruta del cliente empieza por /api/ (la base ya lo trae)', () {
    // Las rutas viajan de dos formas: como primer argumento de una llamada al cliente
    // (`'/board'`) o como `ruta:` de un apunte de la cola. Las dos son cadenas literales,
    // asi que se buscan igual.
    final sospechosas = RegExp(r"""['"]/api/""");

    final fallos = <String>[];
    for (final fichero in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!fichero.path.endsWith('.dart')) continue;
      // La puerta de auth es el UNICO sitio donde `/api/` es correcto dentro de una
      // cadena: alli la base es `${Entorno.authUrl}/api/auth` y esa la monta
      // proveedores.dart a proposito. Se excluye el fichero, no la comprobacion.
      if (fichero.path.endsWith('nucleo/proveedores.dart')) continue;

      final lineas = fichero.readAsLinesSync();
      for (var i = 0; i < lineas.length; i++) {
        final linea = lineas[i];
        // Los comentarios documentan la ruta DEL SERVIDOR (`GET /api/board`), que si
        // lleva el prefijo. Lo que no puede llevarlo es el codigo.
        if (linea.trimLeft().startsWith('//')) continue;
        if (sospechosas.hasMatch(linea)) {
          fallos.add('${fichero.path}:${i + 1}  ${linea.trim()}');
        }
      }
    }

    expect(
      fallos,
      isEmpty,
      reason:
          'Estas rutas llevan `/api/` delante y la base del ClienteApi ya lo trae, '
          'asi que saldran como `…/api/api/…` y daran 404:\n${fallos.join('\n')}',
    );
  });
}
