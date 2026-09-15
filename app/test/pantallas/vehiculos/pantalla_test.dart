import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/vehiculos/vista/pantalla_vehiculos.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo_vehiculos.dart';

/// Lo que ve una persona cuando abre Vehiculos sin red.
///
/// El cartel no es decoracion: es lo que evita que alguien se ponga a dar de
/// alta camiones en la calle creyendo que se estan guardando.
void main() {
  Future<void> pintar(WidgetTester tester, ClienteApi cliente) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [clienteApiProvider.overrideWithValue(cliente)],
        // El `Scaffold` lo pone el armazon, no la pantalla (el contrato esta
        // en `lib/navegacion/pantalla_registrada.dart`). Montada a pelo no hay
        // ningun `Material` debajo y el buscador revienta al construirse.
        child: const MaterialApp(home: Scaffold(body: PantallaVehiculos())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin red lo dice, y dice que aquí no se guarda nada', (
    tester,
  ) async {
    final banco = Banco.sinRed();
    addTearDown(banco.cerrar);
    await pintar(tester, banco.contenedor.read(clienteApiProvider));

    expect(find.textContaining('Sin conexión.'), findsOneWidget);
    expect(
      find.textContaining('aquí no se guarda nada en el aparato'),
      findsOneWidget,
    );
    // Y NO el vacio de «no hay vehiculos», que diria otra cosa muy distinta.
    expect(find.text('Sin vehículos'), findsNothing);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('con red y sin flota: el vacío del pliego', (tester) async {
    final banco = Banco(
      (p) async => p.ruta.endsWith('/settings')
          ? RespuestaFalsa(200, const <String, Object?>{})
          : RespuestaFalsa(200, const <Object?>[]),
    );
    addTearDown(banco.cerrar);
    await pintar(tester, banco.contenedor.read(clienteApiProvider));

    expect(find.text('Sin vehículos'), findsOneWidget);
    expect(
      find.text('Agrega tu primer vehículo para asignarlo a rutas'),
      findsOneWidget,
    );
    expect(find.textContaining('Sin conexión.'), findsNothing);
  });

  testWidgets('con flota: la tarjeta con sus literales', (tester) async {
    final banco = Banco(
      (p) async => p.ruta.endsWith('/settings')
          ? RespuestaFalsa(200, const <String, Object?>{})
          : RespuestaFalsa(200, const <Object?>[
              <String, Object?>{
                'id': 'v1',
                'name': 'Camión #1',
                'plate': 'ABC-1234',
                'capacity': 2500,
                'status': 'in_use',
                'type': 'truck',
                '_count': <String, Object?>{'routes': 4, 'orders': 12},
                'routes': <Object?>[
                  <String, Object?>{'id': 'r1', 'routeCode': 'STG-0007'},
                ],
              },
            ]),
    );
    addTearDown(banco.cerrar);
    await pintar(tester, banco.contenedor.read(clienteApiProvider));

    expect(find.text('Camión #1'), findsOneWidget);
    expect(find.text('ABC-1234'), findsOneWidget);
    expect(find.text('En uso'), findsOneWidget);
    expect(find.text('2500 kg'), findsOneWidget);
    expect(find.text('12 órdenes asignadas'), findsOneWidget);
    // Sin nombre, la ruta activa se identifica por su codigo.
    expect(find.text('Ruta activa'), findsOneWidget);
    expect(find.text('STG-0007'), findsOneWidget);
    // Sin marcar para domicilio sale el boton, no el chip.
    expect(find.text('Usar para domicilio'), findsOneWidget);
    // `Marcar disponible` sólo aparece cuando esta en uso.
    expect(find.text('Marcar disponible'), findsOneWidget);
  });
}
