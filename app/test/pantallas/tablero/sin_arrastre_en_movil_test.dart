import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/vista/kit.dart';
import 'package:reparto/pantallas/tablero/vista/tarjeta.dart';

/// LA PAREJA DEL ARRASTRE: en el movil no, en el escritorio si.
///
/// Palabras de Jose, 16/09/2026: «el drag and drop en el movil no... eso lo
/// puedes quitar de ahi». Y el 14: «recuerda q para movil es con boton para
/// mover entre tablas».
///
/// El motivo es fisico. En un telefono la mitad de «sin colocar» y las columnas
/// **no caben a la vez**: son dos pestanas, y no se puede arrastrar algo a un
/// sitio que no esta en pantalla. Lo unico que conseguia el arrastre alli era
/// comerse el desplazamiento de la lista.
///
/// Las dos mitades juntas son las que fijan la linea:
///
///  * solo «en movil no se arrastra» se cumpliria igual si alguien borrara el
///    arrastre entero, y en escritorio, donde SI se ven las dos mitades a la
///    vez, es el gesto natural;
///  * solo «en escritorio si» se cumpliria igual si alguien quitara el umbral, y
///    el telefono volveria a levantar tarjetas sin querer.
void main() {
  const pedido = TarjetaPedido(
    pedidoId: 'p-1',
    customerName: 'Yasmani Pérez',
    address: 'Calle 5 nº 12',
    weight: 12.5,
    kmAlAlmacen: 3.2,
    mismoCliente: 0,
    operationNumber: 'X-2992',
  );

  Future<void> montarA(WidgetTester tester, double ancho) async {
    tester.view.physicalSize = Size(ancho, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: temaDeReparto(),
        home: const Scaffold(
          body: SizedBox(
            width: 320,
            child: TarjetaDePedido(pedido: pedido, columnaId: 'col-1'),
          ),
        ),
      ),
    );
  }

  testWidgets('en un TELEFONO la tarjeta no se puede arrastrar', (tester) async {
    await montarA(tester, anchoDeDosMitades - 1);

    expect(
      find.byType(LongPressDraggable<TarjetaArrastrada>),
      findsNothing,
      reason:
          'en el movil las columnas no se ven a la vez que «sin colocar»: '
          'arrastrar solo se come el desplazamiento de la lista',
    );
    // Y la tarjeta sigue ahi, entera: lo que se quita es el gesto, no el pedido.
    expect(find.text('Yasmani Pérez'), findsOneWidget);
  });

  testWidgets('en ESCRITORIO si se arrastra, con pulsacion larga', (
    tester,
  ) async {
    await montarA(tester, anchoDeDosMitades + 1);

    expect(
      find.byType(LongPressDraggable<TarjetaArrastrada>),
      findsOneWidget,
      reason:
          'con las dos mitades a la vista arrastrar es el gesto natural y no '
          'se puede perder',
    );
  });
}
