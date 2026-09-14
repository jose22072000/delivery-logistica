import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/navegacion/barra_lateral.dart';
import 'package:reparto/navegacion/franja_de_estado.dart';
import 'package:reparto/navegacion/pantalla_registrada.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';

import '../apoyo/base_de_prueba.dart';

/// Dos pantallas de mentira: el armazon se prueba solo, sin arrastrar el Panel
/// ni los Informes a un test de navegacion.
List<PantallaRegistrada> _dePrueba() => <PantallaRegistrada>[
  PantallaRegistrada(
    ruta: '/uno',
    titulo: 'Uno',
    icono: Icons.looks_one_outlined,
    enElMenu: true,
    construir: (contexto, estado) => const Text('cuerpo de uno'),
  ),
  PantallaRegistrada(
    ruta: '/dos',
    titulo: 'Dos',
    icono: Icons.looks_two_outlined,
    enElMenu: true,
    construir: (contexto, estado) => const Text('cuerpo de dos'),
  ),
  PantallaRegistrada(
    ruta: '/escondida',
    titulo: 'Escondida',
    construir: (contexto, estado) => const Text('cuerpo escondido'),
  ),
];

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> montar(WidgetTester tester, Size tamano) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 14, 8, 30)),
        ],
        child: RepartoApp(
          enrutador: crearEnrutador(pantallas: _dePrueba(), inicial: '/uno'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Desmontar antes de que acabe el cuerpo del test no es ceremonia: las
  /// consultas de Drift que alimentan la franja de estado sueltan un temporizador
  /// al cancelarse, y flutter_test comprueba que no queda ninguno ANTES de los
  /// `tearDown`. Sin esto, el primer test deja el temporizador y se lleva por
  /// delante a todos los demas.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Dos pasadas: la primera desmonta y crea el temporizador de cierre de
    // Drift, la segunda lo deja correr.
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  testWidgets('escritorio: la barra lateral esta fija y no hay boton de menu', (
    tester,
  ) async {
    await montar(tester, const Size(1440, 900));

    expect(find.byType(BarraLateral), findsOneWidget);
    expect(find.byTooltip('Menú'), findsNothing);
    expect(find.text('Uno'), findsWidgets); // titulo + entrada del menu
    expect(find.text('cuerpo de uno'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('movil: la barra se sale de la pantalla y la abre el boton', (
    tester,
  ) async {
    await montar(tester, const Size(390, 800));

    // Fuera de pantalla: el cajon no esta montado hasta que se abre.
    expect(find.byType(BarraLateral), findsNothing);
    expect(find.byTooltip('Menú'), findsOneWidget);

    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    expect(find.byType(BarraLateral), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('movil: al elegir una entrada navega Y el cajon se cierra solo', (
    tester,
  ) async {
    await montar(tester, const Size(390, 800));

    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dos'));
    await tester.pumpAndSettle();

    expect(find.text('cuerpo de dos'), findsOneWidget);
    // Si el cajon se quedara abierto taparia justo la pantalla a la que se
    // acaba de ir (§8.1).
    expect(find.byType(BarraLateral), findsNothing);
    await desmontar(tester);
  });

  testWidgets('la franja de estado esta arriba en las DOS anchuras', (
    tester,
  ) async {
    await montar(tester, const Size(1440, 900));
    expect(find.byType(FranjaDeEstado), findsOneWidget);
    // Base vacia = nunca se bajo nada. Eso se dice, no se calla.
    expect(find.text('Sin descargar todavía'), findsOneWidget);

    await montar(tester, const Size(390, 800));
    expect(find.byType(FranjaDeEstado), findsOneWidget);
    expect(find.text('Sin descargar todavía'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('lo que queda sin subir se ve arriba, con su numero', (
    tester,
  ) async {
    await base
        .into(base.apuntes)
        .insert(
          ApuntesCompanion.insert(
            clave: '01J8AAAA',
            hechoAt: DateTime(2026, 9, 14, 7),
            metodo: 'POST',
            ruta: '/api/routes',
            cuerpo: '{}',
          ),
        );

    await montar(tester, const Size(390, 800));
    expect(find.text('1 sin subir'), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('una pantalla fuera del menu se alcanza por URL', (tester) async {
    final enrutador = crearEnrutador(
      pantallas: _dePrueba(),
      inicial: '/escondida',
    );
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 14, 8, 30)),
        ],
        child: RepartoApp(enrutador: enrutador),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('cuerpo escondido'), findsOneWidget);
    // Esta y no sale en la barra lateral: es lo que hace Reportes.
    expect(
      find.descendant(
        of: find.byType(BarraLateral),
        matching: find.text('Escondida'),
      ),
      findsNothing,
    );
    await desmontar(tester);
  });
}
