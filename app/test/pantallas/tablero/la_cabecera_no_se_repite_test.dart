// LA CABECERA DEL TABLERO NO REPITE EL NOMBRE DEL SITIO.
//
// Jose, 25/09/2026: «explicame ese santigao de cuba desde santiago de cuba […]
// explicame q es esa mierda por q sale ahi».
//
// Y tenía razón en que no decía nada. En Accesos el almacén se llama como el
// sitio —los nombres de abajo están copiados de la tabla `Almacen` el mismo
// día—, así que en SEIS de las ocho sucursales la línea se leía dos veces:
// «Santiago de Cuba · desde Santiago de Cuba».
//
// El «desde» no sobra: los kilómetros de cada tarjeta, y el domicilio que se
// cobra con ellos, se miden desde ESE almacén. Cuando la sucursal tiene más de
// uno, saber cuál se está usando es lo único que lo explica. Lo que sobra es
// decirlo cuando el almacén se llama igual que la sucursal.
//
// SE COMPARA SIN TILDES A PROPÓSITO: la sucursal es «Camagüey» y su almacén,
// «Camaguey». Dos escrituras del mismo sitio no son dos sitios.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

void main() {
  /// Lo que se lee arriba, pasando por el widget de verdad y no por la función
  /// suelta: lo que importa es lo que ve quien trabaja.
  Future<String> loQueSeLee(
    WidgetTester tester,
    String sucursal,
    String almacen,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CabeceraDelTablero(sucursal, almacen)),
      ),
    );
    return (tester.widget<Text>(find.byType(Text)).data)!;
  }

  group('los ocho nombres de verdad, copiados de Accesos', () {
    // Las seis que se repetían.
    const seRepiten = <(String, String)>[
      ('Camagüey', 'Camaguey'),
      ('Guantánamo', 'Guantanamo'),
      ('Holguín', 'Holguin'),
      ('Las Tunas', 'Las Tunas'),
      ('Sancti Spíritus', 'Sancti Spiritus'),
      ('Santiago de Cuba', 'Santiago de Cuba'),
    ];

    for (final (sucursal, almacen) in seRepiten) {
      testWidgets('$sucursal sale una sola vez', (tester) async {
        expect(await loQueSeLee(tester, sucursal, almacen), sucursal);
      });
    }

    // Las dos que SÍ decían algo, y lo siguen diciendo.
    testWidgets('Granma sigue diciendo que mide desde Bayamo', (tester) async {
      expect(
        await loQueSeLee(tester, 'Granma', 'Bayamo (Granma)'),
        'Granma · desde Bayamo (Granma)',
        reason:
            'el almacén nombra la ciudad, que es justo lo que hacía falta '
            'saber: los km salen de ahí',
      );
    });

    testWidgets('La Habana también', (tester) async {
      expect(
        await loQueSeLee(tester, 'La Habana', 'Almacén Habana'),
        'La Habana · desde Almacén Habana',
      );
    });
  });

  group('los casos de al lado', () {
    testWidgets('un segundo almacén del mismo sitio SÍ se nombra', (
      tester,
    ) async {
      expect(
        await loQueSeLee(tester, 'Santiago de Cuba', 'Nave 2 (Sueño)'),
        'Santiago de Cuba · desde Nave 2 (Sueño)',
        reason:
            'con dos almacenes, cuál se usa deja de ser evidente y es lo que '
            'decide los kilómetros de cada tarjeta',
      );
    });

    testWidgets('sin almacén todavía, sólo la sucursal', (tester) async {
      expect(await loQueSeLee(tester, 'Holguín', ''), 'Holguín');
    });

    testWidgets('el nombre contenido en el otro tampoco se repite', (
      tester,
    ) async {
      expect(
        await loQueSeLee(tester, 'Santiago de Cuba', 'Santiago'),
        'Santiago de Cuba',
      );
    });
  });
}
