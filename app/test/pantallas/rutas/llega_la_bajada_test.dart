// EL GEMELO DEL DE PEDIDOS, PARA RUTAS.
//
// `rutasDescargadasProvider` era un `FutureProvider`: una sola respuesta, la del
// instante en que la pantalla se pinta. En la web la base nace vacía en cada
// carga de la página, así que esa única respuesta era siempre «no se descargó»
// y la pantalla se quedaba clavada en «Esta pantalla no se ha descargado
// todavía» aunque las rutas llegaran un segundo después.
//
// Se arregló pasándolo a `Stream`, **y el arreglo se quedó sin red**: el auditor
// lo devolvió a `FutureProvider` y las 785 pruebas siguieron verdes. El motivo
// es que las dos pruebas que montan `PantallaRutas` escriben la marca de
// frescura en el `setUp`, ANTES de montar — que es justo el caso que un
// `FutureProvider` resuelve bien. El caso de la web no lo probaba nadie.
//
// Ésta lo prueba: monta con la base vacía y deja que la bajada llegue con la
// pantalla delante, sin volver a montarla, que es lo que pasa en un navegador
// donde nadie recarga.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/frescura/reloj_de_datos.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/vista/pantalla_rutas.dart';
import 'package:reparto/textos/textos.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late BaseLocal base;
  final ahora = DateTime(2026, 9, 14, 16, 5);

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> pintar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
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
          home: const Scaffold(body: PantallaRutas()),
        ),
      ),
    );
    await asentar(tester);
  }

  testWidgets(
    'la bajada llega con la pantalla ya abierta: el cartel de «sin descargar» '
    'se va solo y salen las rutas, sin recargar',
    (tester) async {
      await pintar(tester);
      expect(
        find.text(SinDescargar.textoDeLaPantallaVacia),
        findsOneWidget,
        reason: 'con la base vacía y sin marca, esto es lo correcto',
      );

      // Llega la bajada. Nadie recarga: es el ciclo, por detrás.
      await sembrarCatalogo(base);
      await sembrarRuta(
        base,
        id: 'R1',
        codigo: 'RT-LA-NUEVA',
        creada: DateTime(2026, 9, 10),
      );
      await RegistroDeFrescura(
        base,
        reloj: () => ahora,
      ).marcar(Colecciones.rutas, hasta: null, bajadaAt: ahora);
      await asentar(tester);

      expect(
        find.text(SinDescargar.textoDeLaPantallaVacia),
        findsNothing,
        reason:
            'las rutas ya están aquí: dejar el cartel puesto es acusar al '
            'servidor de algo que no pasa',
      );
      expect(
        find.text('RT-LA-NUEVA'),
        findsOneWidget,
        reason: 'y la ruta que bajó se ve',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets(
    'en la WEB, mientras baja, dice «Cargando» y NO acusa de que no se ha '
    'descargado',
    (tester) async {
      // Esta pantalla se quedó fuera de la pasada que separó los tres casos, y
      // lo dejó dicho quien la hizo. Sin esto, la web enseña «Esta pantalla no
      // se ha descargado todavía. Con conexión baja sola» durante el primer
      // segundo de CADA carga —su base nace vacía— y eso es un diagnóstico
      // falso, y además en el idioma del aparato.
      await Destino.comoSiFueraWeb(() async {
        await pintar(tester);

        expect(
          find.text(SinDescargar.textoDeLaPantallaVacia),
          findsNothing,
          reason:
              'en un navegador no hay nada que «bajar solo»: está bajando ahora '
              'mismo y todavía no se ha mirado nada que acusar',
        );
        expect(find.textContaining('Cargando'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
      });
    },
  );
}
