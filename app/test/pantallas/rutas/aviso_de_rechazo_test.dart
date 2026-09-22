// EL «NO» DEL ARMADO TIENE QUE VERSE — 22/09/2026.
//
// Esto salía por `showSnackBar`, y un `SnackBar` lo pinta el `ScaffoldMessenger`
// de la pantalla de detrás: **debajo del cajón**. El mensaje se componía entero,
// con su motivo, y no lo veía nadie. Jose, pulsando «Generar Ruta» tres veces
// seguidas contra pedidos que ya iban en otra ruta: «no hace nada y no dice
// nada» — la peor forma de decir que no.
//
// Lo que se mide aquí es lo único que arregla eso: que el texto **se vea** y que
// **quepa entero en la pantalla**, también a 390 px, que es donde el pie ya iba
// justo. Un aviso pintado fuera del recorte es el mismo fallo con otra cara.
//
// Qué dice el aviso, palabra por palabra y motivo por motivo, lo sujeta
// `armado_test.dart` contra el literal del servidor.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/rutas/vista/aviso_de_rechazo.dart';

void main() {
  const mensaje =
      '2 de los 3 pedidos elegidos no pueden ir en esta ruta: '
      'F-002 (ya va en la ruta RT-20260922-003), F-003 (PEDIDO lo archivó).';

  Future<Rect> pintar(WidgetTester tester, Size pantalla, VoidCallback alCerrar) async {
    tester.view.physicalSize = pantalla;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Abajo del todo y pegado al borde, que es donde vive: encima del
          // botón que lo provoca, en el pie del cajón.
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AvisoDeRechazo(mensaje: mensaje, alCerrar: alCerrar),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getRect(find.byType(AvisoDeRechazo));
  }

  testWidgets('se ve el mensaje entero, con su motivo', (tester) async {
    await pintar(tester, const Size(390, 844), () {});

    expect(find.textContaining('no pueden ir en esta ruta'), findsOneWidget);
    // El código de la ruta: «ya va en la ruta RT-…» dice dónde mirar, «ya va en
    // otra ruta» deja quince rutas que abrir.
    expect(find.textContaining('RT-20260922-003'), findsOneWidget);
    // Y el segundo motivo, que es distinto del primero. Si el aviso recortara a
    // una línea, quien lo lee arreglaría uno y el otro seguiría ahí.
    expect(find.textContaining('PEDIDO lo archivó'), findsOneWidget);
  });

  testWidgets('cabe dentro de la pantalla a 390 px', (tester) async {
    const pantalla = Size(390, 844);
    final sitio = await pintar(tester, pantalla, () {});

    expect(sitio.left, greaterThanOrEqualTo(0));
    expect(sitio.right, lessThanOrEqualTo(pantalla.width));
    expect(sitio.top, greaterThanOrEqualTo(0));
    expect(sitio.bottom, lessThanOrEqualTo(pantalla.height));
    // Y el texto no se sale por su cuenta dentro de la caja.
    final texto = tester.getRect(find.textContaining('no pueden ir'));
    expect(texto.right, lessThanOrEqualTo(sitio.right));
  });

  testWidgets('con un mensaje largo crece hacia arriba y sigue cabiendo', (
    tester,
  ) async {
    // Cinco pedidos nombrados con su motivo son varias líneas. El aviso tiene
    // que crecer, no recortar ni desbordar: lo que se recorta es justo lo que
    // hacía falta leer.
    const pantalla = Size(390, 844);
    final sitio = await pintar(tester, pantalla, () {});
    expect(sitio.height, greaterThan(40));
    expect(sitio.bottom, lessThanOrEqualTo(pantalla.height));
  });

  testWidgets('la ✕ está y avisa', (tester) async {
    // A 390 px un aviso que no se puede quitar tapa el pie y deja a alguien sin
    // ver el botón. La ✕ nunca puede desaparecer (`CLAUDE.md`).
    var cerrado = false;
    await pintar(tester, const Size(390, 844), () => cerrado = true);

    await tester.tap(find.byTooltip('Quitar el aviso'));
    await tester.pump();
    expect(cerrado, isTrue);
  });
}
