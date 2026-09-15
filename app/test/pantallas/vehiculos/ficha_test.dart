import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/vehiculos/datos/costo_km.dart';
import 'package:reparto/pantallas/vehiculos/datos/vehiculo_api.dart';
import 'package:reparto/pantallas/vehiculos/vista/ficha_vehiculo.dart';

/// Los defectos exactos, el ayudante del costo por km y el eje de la edicion:
/// **abrir una ficha y guardar sin tocar nada tiene que dejarla igual**.
void main() {
  const tipos = [
    TipoDeVehiculo(nombre: 'truck', costoKmUsd: 1.65),
    TipoDeVehiculo(nombre: 'furgoneta', costoKmUsd: 0.9),
  ];

  testWidgets('la ficha vacía trae los defectos del pliego', (tester) async {
    DatosVehiculo? salida;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FichaVehiculo(
            tipos: tipos,
            cupRate: 320,
            guardando: false,
            alGuardar: (datos) => salida = datos,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nuevo Vehículo'), findsOneWidget);
    // Sin nombre, `Agregar Vehículo` esta deshabilitado: el servidor
    // contestaria en ingles y eso no se le ensena a nadie.
    final boton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Agregar Vehículo'),
    );
    expect(boton.onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Ej: Camión #1, Furgoneta Azul'),
      'Camión #1',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Agregar Vehículo'));
    await tester.pumpAndSettle();

    expect(salida!.nombre, 'Camión #1');
    expect(salida!.tipo, 'truck');
    expect(salida!.capacidad, 1000);
    expect(salida!.estado, 'available');
    expect(salida!.usarParaDomicilio, isFalse);
  });

  testWidgets('guardar sin tocar nada deja la ficha igual', (tester) async {
    const original = VehiculoDeLaApi(
      id: 'v1',
      nombre: 'Camión #3',
      capacidad: 2500,
      estado: 'maintenance',
      tipo: 'furgoneta',
      placa: 'ABC-1234',
      costoKmUsd: 1.2,
      notas: 'Le falla el freno de mano',
      usarParaDomicilio: true,
    );

    DatosVehiculo? salida;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FichaVehiculo(
            vehiculo: original,
            tipos: tipos,
            cupRate: 320,
            guardando: false,
            alGuardar: (datos) => salida = datos,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Editar Vehículo'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Actualizar'));
    await tester.pumpAndSettle();

    // Ni un campo cambiado. Es el eje del guion de pruebas: una edicion que
    // «arregla» algo por su cuenta se descubre semanas despues, cuando el costo
    // por km ya no es el que alguien puso.
    expect(salida!.nombre, 'Camión #3');
    expect(salida!.tipo, 'furgoneta');
    expect(salida!.placa, 'ABC-1234');
    expect(salida!.capacidad, 2500);
    expect(salida!.estado, 'maintenance');
    expect(salida!.costoKmUsd, 1.2);
    expect(salida!.notas, 'Le falla el freno de mano');
    expect(salida!.usarParaDomicilio, isTrue);
  });

  testWidgets('elegir un tipo hereda su costo/km', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FichaVehiculo(
            tipos: tipos,
            cupRate: 320,
            guardando: false,
            alGuardar: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('truck · \$1.65/km'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('furgoneta · \$0.9/km').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '0.9'), findsOneWidget);
  });

  testWidgets('un tipo HEREDADO se pinta, no deja el desplegable en blanco', (
    tester,
  ) async {
    // `truck` no esta en el catalogo: es justo el caso de produccion, donde los
    // vehiculos lo traen por defecto y ajustes no lo tiene.
    const heredado = VehiculoDeLaApi(
      id: 'v1',
      nombre: 'Camión #1',
      capacidad: 1000,
      estado: 'available',
      tipo: 'truck',
    );

    DatosVehiculo? salida;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FichaVehiculo(
            vehiculo: heredado,
            // El catalogo NO tiene `truck`: es el caso de produccion.
            tipos: const [TipoDeVehiculo(nombre: 'furgoneta', costoKmUsd: 0.9)],
            cupRate: 320,
            guardando: false,
            alGuardar: (datos) => salida = datos,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('truck'),
      findsOneWidget,
      reason:
          'El desplegable de Tipo se abrio EN BLANCO con un tipo heredado. En '
          'blanco parece que el vehiculo no tiene tipo cuando si lo tiene, y '
          'nadie puede saberlo mirando.',
    );

    // Y guardar sin tocar nada no se lo come.
    await tester.tap(find.widgetWithText(FilledButton, 'Actualizar'));
    await tester.pumpAndSettle();
    expect(salida!.tipo, 'truck');
  });

  testWidgets('el ayudante RELLENA el campo, con 2 decimales', (tester) async {
    // Pantalla alta: en 800×600 el pie del cajon tapa el ayudante y el toque no
    // llega.
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FichaVehiculo(
            tipos: tipos,
            cupRate: 320,
            guardando: false,
            alGuardar: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('¿No sabes el costo por km?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'El camionero cobra (CUP)'),
      '180000',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'hasta ___ km (ida)'),
      '72',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Calcular'));
    await tester.pumpAndSettle();

    // 180000 / (2 × 72 × 320) = 3.90625 → 3.91, los 2 decimales del Excel.
    // NI un paso de mas —`Usar este costo`, que se olvidaba y dejaba el
    // vehiculo sin costo por km— NI los 4 decimales de antes.
    expect(
      find.widgetWithText(TextField, '3.91'),
      findsOneWidget,
      reason:
          'El ayudante no relleno el campo del costo por km, o lo relleno con '
          'una precision que nadie tecleó.',
    );
    expect(find.text('Usar este costo'), findsNothing);
    expect(find.text('3.9063'), findsNothing);
  });

  test('el ayudante: 180000 CUP hasta 72 km con la tasa 320', () {
    // 180000 / (2 × 72 × 320) = 3.90625 $/km.
    expect(
      CostoPorKm.calcular(cobroCup: 180000, km: 72),
      closeTo(3.90625, 0.00001),
    );
    // La tasa por defecto es 320, la de la casa.
    expect(CostoPorKm.tasaPorDefecto, 320);
    // Y con otra tasa sale otra cosa: la tasa es un dato, no una constante.
    expect(
      CostoPorKm.calcular(cobroCup: 180000, km: 72, tasa: 400),
      closeTo(3.125, 0.00001),
    );
  });

  test('el ayudante no inventa un número cuando falta un dato', () {
    // Sin km no hay division posible. Devolver 0 seria decir que el viaje es
    // gratis.
    expect(CostoPorKm.calcular(cobroCup: 180000, km: null), isNull);
    expect(CostoPorKm.calcular(cobroCup: null, km: 72), isNull);
    expect(CostoPorKm.calcular(cobroCup: 180000, km: 0), isNull);
    expect(CostoPorKm.calcular(cobroCup: 180000, km: 72, tasa: 0), isNull);
  });

  test('`in_use` e `in_route` se leen igual: En uso', () {
    const enUso = VehiculoDeLaApi(
      id: 'v1',
      nombre: 'a',
      capacidad: 1000,
      estado: 'in_use',
    );
    const enRuta = VehiculoDeLaApi(
      id: 'v2',
      nombre: 'b',
      capacidad: 1000,
      estado: 'in_route',
    );
    expect(enUso.etiquetaEstado, 'En uso');
    expect(enRuta.etiquetaEstado, 'En uso');
  });

  test('la búsqueda del encabezado mira nombre y placa, nada más', () {
    const v = VehiculoDeLaApi(
      id: 'v1',
      nombre: 'Camión #1',
      capacidad: 1000,
      estado: 'available',
      placa: 'ABC-1234',
      notas: 'reparado en Holguín',
    );
    expect(v.cuadraCon('camión'), isTrue);
    expect(v.cuadraCon('abc'), isTrue);
    expect(v.cuadraCon('holguín'), isFalse);
    expect(v.cuadraCon(''), isTrue);
  });
}
