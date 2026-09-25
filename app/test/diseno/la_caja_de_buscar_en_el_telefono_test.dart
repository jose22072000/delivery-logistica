// EN UN TELÉFONO LA CAJA DE BUSCAR OCUPA TODO EL ANCHO, y el `ancho` que le
// pase la pantalla no cuenta.
//
// Los 220 px por defecto son un número de escritorio: allí la caja convive en
// una fila con los desplegables y tiene que dejarles sitio. En un móvil de 390
// va sola en su fila, y esos 220 dejaban **unos 150 px muertos** a su derecha.
// Eso es lo que hacía que Pedidos, Clientes y Rutas no se parecieran al Tablero
// —que pasa `ancho: null` y la pinta entera—, y de lo que se quejó Jose el
// 25/09/2026: «los filtros… mal ubicados, regados, sin uniformidad».
//
// Esto se prueba APARTE de `barra_de_filtros_test.dart` a propósito: aquella
// monta una caja de mentira y comprueba la BARRA; ésta monta la
// `CajaDeBusqueda` de verdad y comprueba la CAJA. Sin esta prueba se podía
// invertir la condición —volver a los 220 clavados en el teléfono— con las
// 1.656 pruebas del proyecto en verde. Lo comprobó el auditor el mismo día.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reparto/diseno/caja_de_busqueda.dart';

/// Monta la caja a un ancho de pantalla concreto, que es lo único que decide.
Future<double> anchoDeLaCaja(
  WidgetTester tester, {
  required double pantalla,
  double? ancho = 220,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(pantalla, 800);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // `Align` y no una `Column` con `stretch`: hace falta que las
        // restricciones lleguen SUELTAS, como en el `Wrap` de las barras de
        // filtros de verdad. Con restricciones apretadas el `SizedBox` de 220
        // no puede hacer nada y la prueba mediría el ancho de la pantalla,
        // no el de la caja.
        body: Align(
          alignment: Alignment.topLeft,
          child: CajaDeBusqueda(valor: '', ancho: ancho, alBuscar: (_) {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return tester.getSize(find.byType(TextField)).width;
}

void main() {
  testWidgets('a 390 px la caja se estira entera y no se queda en 220', (
    tester,
  ) async {
    final medida = await anchoDeLaCaja(tester, pantalla: 390);

    expect(
      medida,
      390,
      reason:
          'la caja se quedó en $medida px de los 390 de la pantalla. Los 220 '
          'son un número de escritorio: en el teléfono dejan ~150 px muertos a '
          'su derecha, que es el desorden del que se quejó Jose el 25/09/2026.',
    );
  });

  testWidgets('a 1200 px sí respeta los 220 que le pide la pantalla', (
    tester,
  ) async {
    // La otra mitad de la pareja: el arreglo del teléfono NO puede llevarse por
    // delante el escritorio, donde la caja comparte fila con los desplegables y
    // los 220 son lo correcto. Sin esta mitad, «siempre a todo el ancho» también
    // pasaría, y en un monitor la caja de buscar mediría metro y medio.
    final medida = await anchoDeLaCaja(tester, pantalla: 1200);

    expect(
      medida,
      220,
      reason:
          'en pantalla grande la caja midió $medida px en vez de los 220 que le '
          'pide la pantalla: el arreglo del móvil se comió el escritorio.',
    );
  });

  testWidgets('con `ancho: null` manda el padre en las dos pantallas', (
    tester,
  ) async {
    expect(await anchoDeLaCaja(tester, pantalla: 390, ancho: null), 390);
    expect(await anchoDeLaCaja(tester, pantalla: 1200, ancho: null), 1200);
  });
}
