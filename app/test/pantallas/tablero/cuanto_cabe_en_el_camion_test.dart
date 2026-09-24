// LA COLUMNA DICE CUÁNTO LLEVA **Y CUÁNTO CABE**.
//
// Medido en producción el 22/09/2026: la zona ponía «200 kg · 0,00 USD · Camión:
// Vehiculo HAB» y los 1.000 kg de capacidad de ese camión no salían por ninguna
// parte. Así no hay forma de saber que te estás pasando hasta que el camión está
// en el almacén, y para entonces la ruta ya se armó. El paso 3 del asistente de
// rutas sí lo dice («0.0 / 1000 kg»), y es la misma pregunta.
//
// El aviso de «no cabe» ya estaba y se queda: son dos cosas distintas —el tope y
// haberlo pasado— y quitar una para poner la otra deja el mismo hueco del otro
// lado.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/vista/columna.dart';

void main() {
  ColumnaTablero zona({double? capacidad, double peso = 200}) => ColumnaTablero(
    id: 'z1',
    branchId: 'b-hab',
    nombre: 'Vista',
    posicion: 1,
    pedidos: 3,
    pesoKg: peso,
    costoUsd: 0,
    vehiculoId: capacidad == null ? null : 'v1',
    vehiculoNombre: capacidad == null ? null : 'Vehiculo HAB',
    vehiculoCapacidad: capacidad,
  );

  Future<void> pintar(WidgetTester tester, ColumnaTablero columna) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            monedaEfectivaProvider.overrideWithValue('USD'),
            tasaDeLaMiradaProvider.overrideWithValue(
              const TasaDeLaMirada.no('sin tasa en las pruebas'),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 600,
                child: ColumnaDelTablero(
                  columna: columna,
                  tarjetas: const [],
                  alSoltar: (_, _) {},
                  alPulsarTarjeta: (_) {},
                  alAbrirMenu: () {},
                  alSoltarColumna: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('con camión previsto se ve el peso Y la capacidad', (
    tester,
  ) async {
    await pintar(tester, zona(capacidad: 1000));

    expect(
      find.textContaining('200 kg / 1.000 kg'),
      findsOneWidget,
      reason:
          'el peso solo no dice nada: hay que poder ver que te quedan 800 kg',
    );
    expect(find.text('Camión: Vehiculo HAB'), findsOneWidget);
  });

  testWidgets('sin camión previsto NO se promete un tope que nadie puso', (
    tester,
  ) async {
    await pintar(tester, zona());

    expect(find.textContaining('200 kg'), findsOneWidget);
    expect(
      find.textContaining('/'),
      findsNothing,
      reason: 'un «/ —» se lee como un tope, y aquí todavía no hay camión',
    );
  });

  testWidgets('pasarse sigue avisando, y con la capacidad delante', (
    tester,
  ) async {
    await pintar(tester, zona(capacidad: 1000, peso: 1210));

    expect(find.textContaining('1.210 kg / 1.000 kg'), findsOneWidget);
    expect(find.text('no cabe'), findsOneWidget);
  });
}
