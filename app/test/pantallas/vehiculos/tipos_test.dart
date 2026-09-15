// LOS TIPOS DE VEHICULO, QUE SON LOS QUE COTIZAN EL DOMICILIO.
//
// Dos fallos que juntos cerraban el camino:
//
//  1. `+ Crear tipo nuevo…` sólo hacia `setState`. El tipo se elegia, se veia en
//     el desplegable y se perdia al cerrar la ficha — **sin un solo error**. Es
//     el mismo fallo que ya paso en delivery y que cuenta
//     `docs/esquema-cambios.md`.
//  2. El cajon de «Tipos de vehículo» sólo enseñaba los que hay en ajustes, asi
//     que `truck` —el tipo por defecto de TODO vehiculo nuevo— no aparecia en
//     ninguna lista donde ponerle su costo por km.
//
// Resultado en produccion: `vehicle_types.costo_km_usd` en NULL en los cinco
// tipos. Y ese numero es el que cotiza el domicilio que se le cobra al cliente.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/vehiculos/datos/vehiculo_api.dart';
import 'package:reparto/pantallas/vehiculos/vista/pantalla_vehiculos.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo_vehiculos.dart';

void main() {
  /// Un servidor falso **con memoria**: `PUT /settings` cambia lo que
  /// `GET /settings` contesta despues. Sin esa memoria no se puede comprobar lo
  /// unico que importa aqui, que es si el tipo SIGUE ESTANDO al volver a mirar.
  ({Banco banco, List<Map<String, Object?>> tipos}) montarServidor({
    List<Map<String, Object?>> tipos = const [],
    List<Map<String, Object?>> vehiculos = const [],
  }) {
    final guardados = [...tipos];
    final banco = Banco((p) async {
      if (p.ruta.endsWith('/settings')) {
        if (p.metodo == 'PUT') {
          final cuerpo = p.cuerpo! as Map<String, Object?>;
          guardados
            ..clear()
            ..addAll(
              (cuerpo['tiposVehiculo']! as List<Object?>)
                  .cast<Map<String, Object?>>(),
            );
          return RespuestaFalsa(200, <String, Object?>{
            'tiposVehiculo': guardados,
          });
        }
        return RespuestaFalsa(200, <String, Object?>{
          'tiposVehiculo': guardados,
          'cupRate': 320,
        });
      }
      return RespuestaFalsa(200, vehiculos);
    });
    return (banco: banco, tipos: guardados);
  }

  Future<void> pintar(WidgetTester tester, Banco banco) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(banco.base),
          clienteApiProvider.overrideWithValue(
            banco.contenedor.read(clienteApiProvider),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: PantallaVehiculos())),
      ),
    );
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  // ---------------------------------------------------------------------------
  // 1. El cajon de Tipos siembra los que YA usan los vehiculos
  // ---------------------------------------------------------------------------

  testWidgets('el cajon de Tipos enseña `truck` aunque no esté en ajustes', (
    tester,
  ) async {
    final montaje = montarServidor(
      // Ajustes VACIO de tipos, que es lo que hay en produccion.
      vehiculos: const [
        <String, Object?>{
          'id': 'v1',
          'name': 'Camión #1',
          'type': 'truck',
          'capacity': 1000,
          'status': 'available',
        },
      ],
    );
    addTearDown(montaje.banco.cerrar);
    await pintar(tester, montaje.banco);

    await tester.tap(find.text('Tipos de vehículo'));
    await tester.pumpAndSettle();

    // El cajon abierto, con una fila para `truck` y su hueco de costo/km.
    expect(find.text('Tipos de vehículo'), findsWidgets);
    expect(
      find.widgetWithText(TextField, 'truck'),
      findsOneWidget,
      reason:
          'El cajon de Tipos no enseña `truck`, que es el tipo por defecto de '
          'todo vehiculo nuevo y el que usan los vehiculos que ya existen. Sin '
          'esa fila no hay NINGUNA lista donde ponerle su costo por km, y ese '
          'costo es el que cotiza el domicilio que se le cobra al cliente.',
    );
    expect(find.text('Sin tipos. Agrega el primero.'), findsNothing);

    // Y se le puede poner el costo y guardar: eso es lo que arregla los NULL.
    await tester.enterText(
      find.widgetWithText(TextField, 'truck').first,
      'truck',
    );
    final costo = find.widgetWithText(TextField, 'Costo/km (USD)');
    await tester.enterText(costo, '1.65');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(montaje.tipos, [
      <String, Object?>{'nombre': 'truck', 'costoKmUsd': 1.65},
    ]);

    await desmontar(tester);
  });

  testWidgets('el tipo que ya tiene costo lo trae puesto', (tester) async {
    final montaje = montarServidor(
      vehiculos: const [
        <String, Object?>{
          'id': 'v1',
          'name': 'Camión #1',
          'type': 'truck',
          'capacity': 1000,
          'status': 'available',
          'costoKmUsd': 2.5,
        },
      ],
    );
    addTearDown(montaje.banco.cerrar);
    await pintar(tester, montaje.banco);

    await tester.tap(find.text('Tipos de vehículo'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '2.5'), findsOneWidget);

    await desmontar(tester);
  });

  // ---------------------------------------------------------------------------
  // 2. `+ Crear tipo nuevo…` GUARDA
  // ---------------------------------------------------------------------------

  testWidgets('se crea un tipo nuevo y SIGUE AHÍ al reabrir', (tester) async {
    final montaje = montarServidor(
      tipos: [
        <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 0.9},
      ],
    );
    addTearDown(montaje.banco.cerrar);
    await pintar(tester, montaje.banco);

    // --- Se crea desde la ficha del vehiculo ---------------------------------
    // Hay dos botones con ese texto —el de la cabecera y el del vacio— y los
    // dos abren la misma ficha.
    await tester.tap(
      find.widgetWithText(FilledButton, 'Agregar Vehículo').first,
    );
    await tester.pumpAndSettle();

    // El desplegable de `Tipo`, no el de `Estado del vehículo`.
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Tipo'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ Crear tipo nuevo…').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre del tipo'),
      'Rastra',
    );
    // El `Costo por km (USD)` DEL TIPO, que en el arbol va justo debajo del
    // desplegable; el del vehiculo viene mas abajo.
    await tester.enterText(
      find.widgetWithText(TextField, 'Costo por km (USD)').first,
      '3.25',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Crear tipo'));
    await tester.pumpAndSettle();

    // SALIO AL SERVIDOR. Esto es lo que antes no pasaba: el tipo vivia en un
    // `setState` y se perdia al cerrar la ficha, sin un solo error.
    expect(
      montaje.banco.servidor.cuantas('PUT', '/settings'),
      1,
      reason:
          '`Crear tipo` no mando nada al servidor: el tipo sólo existe en la '
          'pantalla y se pierde al cerrarla, sin un solo error. Es el fallo '
          'que ya paso en delivery (docs/esquema-cambios.md).',
    );
    expect(montaje.tipos, [
      <String, Object?>{'nombre': 'furgoneta', 'costoKmUsd': 0.9},
      <String, Object?>{'nombre': 'Rastra', 'costoKmUsd': 3.25},
    ]);
    // Y queda elegido, con su costo heredado en el campo del vehiculo.
    expect(find.widgetWithText(TextField, '3.25'), findsOneWidget);

    // --- Se cierra la ficha y se abre el cajon de Tipos ----------------------
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tipos de vehículo'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextField, 'Rastra'),
      findsOneWidget,
      reason:
          'El tipo recien creado no está en el catalogo al volver a mirar: se '
          'guardó sólo en la pantalla.',
    );

    await desmontar(tester);
  });

  // ---------------------------------------------------------------------------
  // 3. La mezcla, sin montar nada
  // ---------------------------------------------------------------------------

  group('los tipos que se enseñan', () {
    const deAjustes = [TipoDeVehiculo(nombre: 'furgoneta', costoKmUsd: 0.9)];

    test('son los de ajustes MAS los que usan los vehiculos', () {
      final tipos = TipoDeVehiculo.paraElCajon(
        deAjustes: deAjustes,
        vehiculos: const [
          VehiculoDeLaApi(
            id: 'v1',
            nombre: 'a',
            capacidad: 1000,
            estado: 'available',
            tipo: 'truck',
            costoKmUsd: 1.65,
          ),
          VehiculoDeLaApi(
            id: 'v2',
            nombre: 'b',
            capacidad: 1000,
            estado: 'available',
            tipo: 'furgoneta',
          ),
        ],
      );
      // `furgoneta` NO se repite: ya estaba en ajustes.
      expect(tipos.map((t) => t.nombre).toList(), ['furgoneta', 'truck']);
      // El costo sembrado sale de un vehiculo de ese tipo que ya lo tenga.
      expect(tipos.last.costoKmUsd, 1.65);
      // Y el de ajustes se respeta, no se pisa con el del vehiculo.
      expect(tipos.first.costoKmUsd, 0.9);
    });

    test('sin costo en ningun vehiculo se deja VACIO, no en cero', () {
      final tipos = TipoDeVehiculo.paraElCajon(
        deAjustes: const [],
        vehiculos: const [
          VehiculoDeLaApi(
            id: 'v1',
            nombre: 'a',
            capacidad: 1000,
            estado: 'available',
            tipo: 'truck',
          ),
        ],
      );
      // Un cero guardado se lee como «el kilometro es gratis» — un numero
      // creible y equivocado. Un hueco se ve y se rellena.
      expect(tipos.single.nombre, 'truck');
      expect(tipos.single.costoKmUsd, isNull);
    });

    test('un vehiculo sin tipo no siembra nada', () {
      expect(
        TipoDeVehiculo.paraElCajon(
          deAjustes: deAjustes,
          vehiculos: const [
            VehiculoDeLaApi(
              id: 'v1',
              nombre: 'a',
              capacidad: 1000,
              estado: 'available',
            ),
            VehiculoDeLaApi(
              id: 'v2',
              nombre: 'b',
              capacidad: 1000,
              estado: 'available',
              tipo: '  ',
            ),
          ],
        ).map((t) => t.nombre).toList(),
        ['furgoneta'],
      );
    });
  });
}
