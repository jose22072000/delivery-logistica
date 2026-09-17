// FOTOS DE LA PANTALLA, PARA MIRARLAS.
//
// **Esto no es una prueba y no corre con la suite**: no acaba en `_test.dart`,
// así que `flutter test` no lo recoge. Se lanza a mano y escribe PNG en
// `capturas/`, al lado de los que ya había:
//
//   flutter test test/capturas/capturas_rutas.dart --update-goldens
//
// Para qué. Jose, 17/09/2026: «¿dónde lo probaste?, porque no te vi en el
// navegador probándolo». Tenía razón: hasta ahora lo único que había eran
// medidas —152 contra 216 píxeles—, y una medida no es ver la pantalla. Esto
// dibuja el árbol de verdad, con las tipografías de verdad de
// `assets/google_fonts`, y deja la imagen en el repo.
//
// Lo que NO es: no sustituye a levantar la aplicación contra la API. No hay
// red, no hay sesión y no hay servidor; es el dibujo de la pantalla con unos
// datos puestos a mano.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/lista_rutas.dart';
import 'package:reparto/textos/textos.dart';

import '../apoyo/base_de_prueba.dart';
import '../pantallas/pedidos/sembrar.dart';

/// LAS TIPOGRAFIAS DE LA APLICACION, cargadas a mano.
///
/// Sin esto un `flutter test` dibuja cada letra como un rectangulo negro (la
/// fuente `Ahem`), y la foto no serviria para mirar nada. Se cargan las mismas
/// que van en el `pubspec`.
Future<void> cargarTipografias() async {
  for (final familia in const {
    'HankenGrotesk': [
      'assets/google_fonts/HankenGrotesk-Regular.ttf',
      'assets/google_fonts/HankenGrotesk-SemiBold.ttf',
      'assets/google_fonts/HankenGrotesk-Bold.ttf',
    ],
    'JetBrainsMono': [
      'assets/google_fonts/JetBrainsMono-Regular.ttf',
      'assets/google_fonts/JetBrainsMono-Medium.ttf',
      'assets/google_fonts/JetBrainsMono-SemiBold.ttf',
    ],
    'BricolageGrotesque': [
      'assets/google_fonts/BricolageGrotesque-Medium.ttf',
      'assets/google_fonts/BricolageGrotesque-SemiBold.ttf',
      'assets/google_fonts/BricolageGrotesque-Bold.ttf',
      'assets/google_fonts/BricolageGrotesque-ExtraBold.ttf',
    ],
  }.entries) {
    final cargador = FontLoader(familia.key);
    for (final camino in familia.value) {
      final fichero = File(camino);
      if (!fichero.existsSync()) continue;
      cargador.addFont(
        Future.value(ByteData.sublistView(fichero.readAsBytesSync())),
      );
    }
    await cargador.load();
  }
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUpAll(cargarTipografias);
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Tres rutas como las de verdad: una con la direccion corta, otra con una
  /// direccion larguisima —la que hacia que la tarjeta creciera— y otra sin
  /// vehiculo.
  Future<void> sembrarLasTres() async {
    await sembrarCatalogo(base);
    await RegistroDeFrescura(
      base,
      reloj: () => ahora,
    ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);

    final rutas = <(String, String, String?, String?, double, double)>[
      (
        'R1',
        'RT-20260914-001',
        'V1',
        'Reparto La Caridad, Camagüey',
        68.0,
        5212.78,
      ),
      (
        'R2',
        'RT-20260914-002',
        'V2',
        '2da Paralela entre Simón Reyes y Beneficencia, Reparto La Caridad, '
            'Camagüey, esquina al almacén viejo',
        33.6,
        238.30,
      ),
      ('R3', 'RT-20260914-003', null, null, 4.5, 0),
    ];
    for (final (id, codigo, vehiculo, direccion, km, importe) in rutas) {
      await sembrarRuta(
        base,
        id: id,
        codigo: codigo,
        estado: EstadoRuta.enCurso,
        vehiculoId: vehiculo,
        creada: ahora,
      );
      await (base.update(base.routes)..where((r) => r.id.equals(id))).write(
        RoutesCompanion(
          originAddress: Value(direccion),
          totalDistance: Value(km),
          totalPrice: Value(importe),
          deliveryDate: Value(ahora),
        ),
      );
    }
    // Paradas: 2, 3 y ninguna, para que se vea el singular, el plural y el cero.
    for (final (ruta, cuantas) in const [('R1', 2), ('R2', 3)]) {
      for (var i = 0; i < cuantas; i++) {
        await sembrarPedido(
          base,
          id: '$ruta-p$i',
          cliente: 'Cliente $i de $ruta',
          rutaId: ruta,
          orden: i + 1,
        );
      }
    }
  }

  Future<void> foto(
    WidgetTester tester, {
    required Size tamano,
    required String nombre,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MaterialApp(
          localizationsDelegates: delegacionesDeIdioma,
          supportedLocales: idiomas,
          theme: temaDeReparto(),
          home: const Scaffold(
            body: SafeArea(
              child: ListaDeRutas(deLaPestana: PestanaRutas.enCurso),
            ),
          ),
        ),
      ),
    );
    await asentar(tester);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../../capturas/$nombre.png'),
    );
  }

  testWidgets('la lista de rutas en un teléfono', (tester) async {
    await sembrarLasTres();
    await foto(
      tester,
      tamano: const Size(390, 844),
      nombre: '390-rutas-lista',
    );
  });

  testWidgets('la lista de rutas en escritorio', (tester) async {
    await sembrarLasTres();
    await foto(
      tester,
      tamano: const Size(520, 900),
      nombre: '520-rutas-lista',
    );
  });
}
