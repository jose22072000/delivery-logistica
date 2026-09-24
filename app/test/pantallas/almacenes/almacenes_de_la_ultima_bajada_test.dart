// «LOS ALMACENES SON LOS DE LA ÚLTIMA VEZ QUE HUBO RED» — que se diga, y dónde.
//
// El aparato enseña la copia de la última bajada como si fuera la de ahora. Los
// almacenes van en `faltan` a propósito —Accesos no da marca de cambio ni dice
// qué borró— y esa decisión NO se toca; lo único que se puede hacer es decirlo,
// con la fecha. Desde el almacén se mide lo que se le cobra al cliente por el
// domicilio: uno retirado cobra mal cada entrega del día y no se ve hasta
// cuadrar la caja.
//
// Las pruebas van EN PAREJA (§3-quinquies): una que el aviso SALE en el aparato
// y su gemela de que NO SALE en la web. Sin la segunda, un aviso puesto sin
// condición pasaría las dos mitades del trabajo y volvería a meter en un
// navegador el aparato de no tener señal, que es lo que Jose ha tenido que
// repetir tres veces.
//
// Y se monta con la base VACÍA sembrando DESPUÉS (§3-ter): sembrar en el
// `setUp` es justo el caso que un `Future` resuelve bien, y este aviso tiene que
// aparecer solo cuando la bajada entra con la pantalla ya abierta.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/almacenes/vista/pantalla_almacenes.dart';
import 'package:reparto/pantallas/rutas/vista/asistente_nueva_ruta.dart';
import 'package:reparto/idioma.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo_almacenes.dart';

/// Cuándo se bajó la copia y qué hora es ahora: seis días, o sea viejo de
/// verdad. La fecha va con patrón numérico, así que no depende del idioma.
final bajadaAt = DateTime(2026, 9, 15, 8);
final ahora = DateTime(2026, 9, 21, 9);
const fechaEnPantalla = '15/9/2026, 8:00';
const elAviso = 'los de la última vez que hubo red';

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Los `Stream` de Drift dejan un temporizador de cero al cerrarse: se desmonta
/// dentro de la prueba para que se apague aquí y no después.
Future<void> desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

/// LA BAJADA, que llega por detrás con la pantalla ya delante. Es lo que hace el
/// ciclo: reemplaza la copia entera y marca la frescura.
Future<void> llegaLaBajada(BaseLocal base, {int cuantos = 2}) async {
  await llegaronLosAlmacenes(base, cuantos: cuantos);
  await llegaLaMarca(base);
}

/// Las filas de la copia, sin la marca de frescura todavía.
Future<void> llegaronLosAlmacenes(BaseLocal base, {int cuantos = 2}) async {
  for (var i = 0; i < cuantos; i++) {
    await base
        .into(base.warehouses)
        .insertOnConflictUpdate(
          WarehousesCompanion.insert(
            id: 'W$i',
            sucursalCodigo: 'CAM',
            nombre: 'Almacén $i',
            lat: const Value(21.38),
            lng: const Value(-77.91),
            principal: Value(i == 0),
          ),
        );
  }
}

/// LA MARCA: de cuándo es la copia. Es lo que este aviso lee, y lo que llega con
/// la pantalla ya delante.
Future<void> llegaLaMarca(BaseLocal base) async {
  await base
      .into(base.frescura)
      .insertOnConflictUpdate(
        FrescuraCompanion.insert(
          coleccion: Colecciones.almacenes,
          bajadaAt: Value(bajadaAt),
          completa: const Value(true),
        ),
      );
}

void main() {
  // ---------------------------------------------------------------------------
  // La pantalla de Almacenes
  // ---------------------------------------------------------------------------
  group('en la pantalla de Almacenes', () {
    late Banco banco;

    setUp(() {
      // Accesos contesta: la pantalla está en su estado normal, con su lista en
      // vivo. Justo por eso hace falta el aviso — lo que se ve aquí no es lo que
      // el aparato usará para medir el domicilio en la calle.
      banco = Banco(
        (_) async => RespuestaFalsa(200, const <String, Object?>{
          'sucursales': [
            {
              'codigo': 'CAM',
              'nombre': 'Camagüey',
              'almacenes': [
                {'id': 'W0', 'nombre': 'Almacén 0', 'principal': true},
              ],
            },
          ],
        }),
      );
    });

    tearDown(() => banco.cerrar());

    Future<void> pintar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(banco.base),
            relojProvider.overrideWithValue(() => ahora),
            clienteApiProvider.overrideWithValue(
              banco.contenedor.read(clienteApiProvider),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: PantallaAlmacenes())),
        ),
      );
      await asentar(tester);
    }

    testWidgets('EN EL APARATO: la bajada llega con la pantalla abierta y el '
        'aviso sale solo, con su fecha', (tester) async {
      await pintar(tester);
      expect(
        find.textContaining(elAviso),
        findsNothing,
        reason:
            'con la base vacía no hay copia de la que hablar: decirlo ahí '
            'sería inventarse una fecha',
      );

      // Nadie recarga: es el ciclo, por detrás.
      await llegaLaBajada(banco.base);
      await asentar(tester);

      expect(find.textContaining(elAviso), findsOneWidget);
      expect(
        find.textContaining(fechaEnPantalla),
        findsOneWidget,
        reason: 'sin la fecha el aviso no se puede usar para decidir nada',
      );
      // Y dice QUÉ SE ROMPE, que es la mitad que hace que alguien actúe.
      expect(find.textContaining('se cobra mal'), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('con la copia VACÍA no se habla de la copia', (tester) async {
      // Bajada hecha y CERO almacenes dentro. «Los almacenes son los de la
      // última vez que hubo red» encima de una lista que no existe no avisa de
      // nada: no hay ninguno que pueda estar de más. Lo que hay que decir ahí es
      // otra cosa —«la última bajada tampoco trajo ninguno»— y lo dice el vacío
      // de la pantalla, que además sabe qué se rompe sin almacenes.
      await pintar(tester);
      await llegaLaMarca(banco.base);
      await asentar(tester);

      expect(find.textContaining(elAviso), findsNothing);

      // Y en cuanto la copia tiene algo, el aviso sí sale: la guarda separa los
      // dos casos, no apaga el aviso.
      await llegaronLosAlmacenes(banco.base);
      await asentar(tester);
      expect(find.textContaining(elAviso), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('EN LA WEB: no sale, porque allí no hay copia que envejecer', (
      tester,
    ) async {
      await Destino.comoSiFueraWeb(() async {
        await pintar(tester);
        await llegaLaBajada(banco.base);
        await asentar(tester);

        expect(
          find.textContaining(elAviso),
          findsNothing,
          reason:
              'la web lee del servidor: contarle a quien está en la oficina '
              'que sus almacenes son los del lunes es un problema que en su '
              'caso no existe (regla 1)',
        );
        // Y la pantalla SÍ está pintada: lo que falta es el aviso, no todo.
        expect(find.text('Almacenes'), findsOneWidget);

        await desmontar(tester);
      });
    });
  });

  // ---------------------------------------------------------------------------
  // El paso donde se elige el punto de partida
  // ---------------------------------------------------------------------------
  group('donde se elige el punto de partida', () {
    late BaseLocal base;

    setUp(() async {
      base = await baseConUnaSucursal();
      // LAS FILAS SÍ VAN AQUÍ, Y ES A LA FUERZA. La lista del paso 2 sale de
      // `almacenesProvider(codigo)`, que es un `FutureProvider`: una sola
      // respuesta, la del instante en que se pinta. Si las filas llegaran
      // después, el asistente se quedaría clavado en «Esta sucursal no tiene
      // ningún almacén con ubicación» para siempre — es el §3-ter otra vez, en
      // `pantallas/rutas/estado/proveedores_rutas.dart`, y NO es de este
      // cambio: queda anotado para quien tenga ese fichero.
      //
      // Lo que sí llega con la pantalla delante es LA MARCA, que es justo lo que
      // este aviso lee y lo que tiene que hacerlo aparecer solo.
      await llegaronLosAlmacenes(base);
    });

    tearDown(() => base.close());

    Future<void> pintar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (contexto, _) => Scaffold(
              body: Builder(
                builder: (interior) => TextButton(
                  onPressed: () => showGeneralDialog<void>(
                    context: interior,
                    pageBuilder: (_, _, _) => const AsistenteNuevaRuta(),
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/warehouses',
            builder: (contexto, _) => const Scaffold(body: Text('almacenes')),
          ),
          GoRoute(
            path: '/vehicles',
            builder: (contexto, _) => const Scaffold(body: Text('vehículos')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(base),
            relojProvider.overrideWithValue(() => ahora),
          ],
          child: MaterialApp.router(
            localizationsDelegates: delegacionesDeIdioma,
            supportedLocales: idiomas,
            routerConfig: router,
          ),
        ),
      );
      await asentar(tester);
      await tester.tap(find.text('abrir'));
      await asentar(tester);
    }

    /// Deja el asistente en el paso 2, el del punto de partida.
    ///
    /// Con sucursal y salida ya resueltas el asistente arranca en el paso 3 —es
    /// su atajo— así que se vuelve al 2 por la barra de pasos, que es lo que
    /// hace quien quiere repasar de dónde sale el camión.
    Future<void> alPuntoDePartida(WidgetTester tester) async {
      await tester.tap(find.byKey(AsistenteNuevaRuta.claveDelTramo(2)));
      await asentar(tester);
    }

    testWidgets('EN EL APARATO: el aviso sale sobre el selector de almacén', (
      tester,
    ) async {
      await pintar(tester);
      await alPuntoDePartida(tester);

      // El paso 2 es el del punto de partida. Se busca por su clave y no por el
      // título del desplegable: ese título vive en un `Tooltip`, no en un `Text`.
      expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(2)), findsOneWidget);
      expect(
        find.textContaining(elAviso),
        findsNothing,
        reason:
            'todavía no hay marca: sin saber de cuándo es la copia, el aviso '
            'se estaría inventando la fecha',
      );

      // Llega la marca de la bajada. Nadie recarga ni vuelve a abrir nada.
      await llegaLaMarca(base);
      await asentar(tester);

      expect(find.textContaining(elAviso), findsOneWidget);
      expect(find.textContaining(fechaEnPantalla), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('EN LA WEB: el mismo paso, sin el aviso', (tester) async {
      await Destino.comoSiFueraWeb(() async {
        await pintar(tester);
        await llegaLaMarca(base);
        await alPuntoDePartida(tester);

        // El paso está delante: no es que no se haya llegado.
        expect(find.byKey(AsistenteNuevaRuta.claveDelPaso(2)), findsOneWidget);
        expect(
          find.textContaining(elAviso),
          findsNothing,
          reason:
              'la web siempre está en vivo: ahí los almacenes son los de '
              'ahora y no los de la última vez que hubo red',
        );

        await desmontar(tester);
      });
    });
  });
}

/// Una sucursal sola, para que el paso 1 del asistente se autocomplete y no
/// estorbe. Los almacenes NO se siembran aquí: llegan después, con la pantalla
/// delante, que es de lo que va esta prueba.
Future<BaseLocal> baseConUnaSucursal() async {
  final base = baseDePrueba();
  await base
      .into(base.branches)
      .insert(
        BranchesCompanion.insert(
          id: 'B1',
          name: 'Camagüey',
          lat: 21.38,
          lng: -77.91,
          externalId: const Value('CAM'),
        ),
      );
  return base;
}
