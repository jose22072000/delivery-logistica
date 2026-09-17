// EL BLOQUE DEL MAPA: lo que se ve, lo que DICE que se esta viendo, y lo que
// sale del aparato cuando se pulsa.
//
// Jose, 17/09/2026: «El mapa, ¿por qué no me sale el mapa con la ruta, si
// teníamos hasta para compartir la ruta por WhatsApp?».
//
// Las tres cosas que se vigilan aqui son las tres que fallan lejos de esta
// oficina:
//
//  1. **Que la pantalla diga lo que ensena.** El croquis no lleva calles; quien
//     lo mire tiene que enterarse ahi, no comparandolo con Google Maps.
//  2. **Que la web y el aparato no digan lo mismo** (regla 1): la promesa de
//     «se ve igual sin señal» es de la APK; en un navegador cuenta algo que no
//     pasa nunca.
//  3. **Que los botones manden lo que toca.** Un enlace mal armado no falla
//     aqui: falla en el telefono del chofer.
//
// Nada de esto toca la red. El aparato va inyectado: es la razon de que
// `AbrirYCompartir` sea una interfaz y no un `launchUrl` suelto dentro del
// boton.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/datos/abrir_y_compartir.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';
import 'package:reparto/pantallas/rutas/vista/croquis_de_ruta.dart';
import 'package:reparto/pantallas/rutas/vista/detalle_ruta.dart';
import 'package:reparto/textos/textos.dart';
import 'package:reparto/pantallas/rutas/vista/mapa_de_la_ruta.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';
import 'rutas_a_mano.dart';

/// El aparato de mentira: apunta lo que se le pide y contesta lo que le digan.
class AparatoEspia implements AbrirYCompartir {
  AparatoEspia({this.abre = true, this.comparte = true, this.copia = true});

  bool abre;
  bool comparte;
  bool copia;

  final abiertos = <Uri>[];
  final compartidos = <({String texto, String? asunto})>[];
  final copiados = <String>[];

  @override
  Future<bool> abrir(Uri destino) async {
    abiertos.add(destino);
    return abre;
  }

  @override
  Future<bool> compartir({required String texto, String? asunto}) async {
    compartidos.add((texto: texto, asunto: asunto));
    return comparte;
  }

  @override
  Future<bool> copiar(String texto) async {
    copiados.add(texto);
    return copia;
  }
}

RutaConTodo laRutaDeSiempre({int cuantas = 3}) => rutaAMano(
  vehiculo: camionAMano(),
  paradas: [
    for (var i = 1; i <= cuantas; i++)
      paradaAMano(
        id: 'p$i',
        cliente: 'Cliente $i',
        lat: 21 + i / 100,
        lng: -77 - i / 100,
      ),
  ],
);

void main() {
  late AparatoEspia aparato;

  setUp(() => aparato = AparatoEspia());

  Future<void> pintar(
    WidgetTester tester,
    RutaConTodo ruta, {
    required bool enElAparato,
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // El destino se pone por provider y no compilando para web: es lo que
          // deja ejercitar las dos mitades de la regla 1 en la misma suite.
          trabajaSinConexionProvider.overrideWithValue(enElAparato),
          abrirYCompartirProvider.overrideWithValue(aparato),
          // EL PATIO DEL ALMACEN, por defecto: ni teselas ni OSRM. Ademas de ser
          // el caso que mas importa, es lo que garantiza que **de esta maquina
          // no sale una peticion**.
          fondoDeCallesProvider.overrideWithValue(const SinCalles()),
          recorridoPorCallesProvider.overrideWithValue(
            const SinCallesQueSeguir(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: MapaDeLaRuta(ruta: ruta),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // ───────────────────────────────────────────────────────────────────────────
  group('la pantalla dice lo que esta ensenando', () {
    testWidgets('en la APK, sin calles, cuenta que sale del aparato', (
      tester,
    ) async {
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);

      expect(
        find.textContaining(TextosDelMapa.croquisEnElAparato),
        findsOneWidget,
      );
      expect(find.textContaining(TextosDelMapa.croquisEnLaWeb), findsNothing);
    });

    testWidgets('en la web NO se le promete nada sobre la señal', (
      tester,
    ) async {
      // Quien abre un navegador tiene internet, siempre. Contarle que algo «se
      // ve igual sin señal» es explicarle algo que en su caso no pasa nunca, y
      // eso es justo lo que se saca de la web.
      await pintar(tester, laRutaDeSiempre(), enElAparato: false);

      expect(find.textContaining(TextosDelMapa.croquisEnLaWeb), findsOneWidget);
      expect(
        find.textContaining(TextosDelMapa.croquisEnElAparato),
        findsNothing,
      );
      expect(find.textContaining('Sin señal'), findsNothing);
    });

    testWidgets('sin el recorrido por carretera se dice que es aproximado', (
      tester,
    ) async {
      // Lo peor que podria hacer esta pantalla es dibujar una linea recta entre
      // dos paradas y dejar que se lea como «por aquí va la carretera».
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);

      expect(
        find.textContaining(TextosDelMapa.recorridoAproximado),
        findsOneWidget,
      );
      expect(
        find.textContaining(TextosDelMapa.recorridoPorCarretera),
        findsNothing,
      );
    });

    testWidgets('la frase dice lo que cambia, y NADA MÁS', (tester) async {
      // Jose, 17/09/2026: «sin tanto texto». Antes la frase llevaba pegado un
      // «las paradas van numeradas en su orden de visita; para navegar por la
      // calle: Abrir en Google Maps», que es justo lo que ya dicen la leyenda y
      // el botón que están a dos dedos. El patrón no escribe ni una línea
      // debajo del mapa.
      //
      // Lo que SÍ se sigue diciendo es lo que cambia el diagnóstico: si son
      // calles o croquis, y si el recorrido es el de verdad o una línea recta.
      // Sin eso, una recta se lee como la ruta buena.
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);

      expect(TextosDelMapa.siempre, isEmpty);
      expect(find.textContaining('Abrir en Google Maps.'), findsNothing);
      // Una de las dos, según haya contestado el servicio de calles o no: lo
      // que no puede pasar es que no diga ninguna.
      expect(
        find
                .textContaining(TextosDelMapa.recorridoPorCarretera)
                .evaluate()
                .length +
            find
                .textContaining(TextosDelMapa.recorridoAproximado)
                .evaluate()
                .length,
        1,
      );
    });
  });

  group('la frase se arma de trozos, y cada estado tiene el suyo', () {
    // Los cuatro cruces, en seco: es donde se ve que ninguna combinacion se
    // queda sin frase ni dice dos cosas a la vez.
    for (final enElAparato in [true, false]) {
      for (final conCalles in [true, false]) {
        for (final porCarretera in [true, false]) {
          test(
            'aparato=$enElAparato calles=$conCalles carretera=$porCarretera',
            () {
              final frase = TextosDelMapa.queSeEstaViendo(
                (conCalles: conCalles, recorridoPorCarretera: porCarretera),
                enElAparato: enElAparato,
              );

              // CON TODO BIEN, NI UNA PALABRA. Jose, 17/09/2026: «hay varios
              // botones que están cortados; podríamos quitar ese texto y que
              // quepan ahí sin necesidad de tener scroll en esa vista». Y es
              // que la frase describía lo que ya se ve.
              if (conCalles && porCarretera) {
                expect(
                  frase,
                  isEmpty,
                  reason:
                      'con calles y recorrido de verdad no hay nada que '
                      'avisar: la frase sobra y empuja los botones fuera',
                );
                return;
              }
              // En los otros tres SÍ se dice, porque cambian el diagnóstico:
              // una línea recta no son los kilómetros del camión, y un croquis
              // no son las calles.
              expect(
                frase,
                contains(
                  porCarretera
                      ? TextosDelMapa.recorridoPorCarretera
                      : TextosDelMapa.recorridoAproximado,
                ),
              );
              if (conCalles) {
                // Con las calles puestas no hay nada que explicar sobre la
                // cobertura, y no se explica.
                expect(frase, contains(TextosDelMapa.conCalles));
                expect(frase, isNot(contains('Sin señal')));
                expect(frase, isNot(contains('no cargó')));
              } else {
                expect(
                  frase,
                  contains(
                    enElAparato
                        ? TextosDelMapa.croquisEnElAparato
                        : TextosDelMapa.croquisEnLaWeb,
                  ),
                );
              }
            },
          );
        }
      }
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('nunca un cuadro gris', () {
    testWidgets('con coordenadas se dibuja el croquis', (tester) async {
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);

      expect(find.byKey(CroquisDeRuta.clave), findsOneWidget);
      expect(find.byKey(claveDeSinRecorrido), findsNothing);
    });

    testWidgets('sin ninguna coordenada sale un recuadro que lo DICE', (
      tester,
    ) async {
      final ruta = rutaAMano(
        origenLat: null,
        origenLng: null,
        paradas: [
          paradaAMano(id: 'p1', cliente: 'Ana'),
          paradaAMano(id: 'p2', cliente: 'Beto'),
        ],
      );
      await pintar(tester, ruta, enElAparato: true);

      expect(find.byKey(CroquisDeRuta.clave), findsNothing);
      expect(find.byKey(claveDeSinRecorrido), findsOneWidget);
      expect(find.textContaining('ninguna de las 2 paradas'), findsOneWidget);
    });

    testWidgets('sin paradas lo dice con sus palabras, no con un hueco', (
      tester,
    ) async {
      await pintar(
        tester,
        rutaAMano(origenLat: null, origenLng: null, paradas: []),
        enElAparato: true,
      );

      expect(find.byKey(claveDeSinRecorrido), findsOneWidget);
      expect(find.textContaining('todavía no tiene paradas'), findsOneWidget);
    });

    testWidgets('sin almacen pero con paradas, se dibuja igual y se avisa', (
      tester,
    ) async {
      final ruta = rutaAMano(
        origenLat: null,
        origenLng: null,
        paradas: [paradaAMano(id: 'p1', cliente: 'Ana', lat: 21.1, lng: -77.1)],
      );
      await pintar(tester, ruta, enElAparato: true);

      // El dibujo sale —es lo que hay— y el motivo de que no haya enlace
      // tambien: son dos cosas distintas y fallan por separado.
      expect(find.byKey(CroquisDeRuta.clave), findsOneWidget);
      expect(find.textContaining('almacén de salida'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(claveDeAbrirEnGoogleMaps))
            .onPressed,
        isNull,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('lo que sale del aparato al pulsar', () {
    testWidgets('«Abrir en Google Maps» manda las paradas EN ORDEN', (
      tester,
    ) async {
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);
      await tester.tap(find.byKey(claveDeAbrirEnGoogleMaps));
      await tester.pump();

      expect(aparato.abiertos, hasLength(1));
      final partes = aparato.abiertos.single.queryParameters;
      expect(partes['waypoints'], '21.01,-77.01|21.02,-77.02|21.03,-77.03');
      expect(partes['origin'], '21.38,-77.91');
      expect(partes['destination'], '21.38,-77.91');
    });

    testWidgets('WhatsApp recibe el mensaje, y acaba en el enlace', (
      tester,
    ) async {
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);
      await tester.tap(find.byKey(claveDeWhatsApp));
      await tester.pump();

      final destino = aparato.abiertos.single;
      expect(destino.host, 'wa.me');
      final mensaje = destino.queryParameters['text']!;
      expect(mensaje, startsWith('Ruta RT-001'));
      expect(mensaje, contains('3 paradas'));
      expect(mensaje, contains('Camión 1 (P-001)'));
      expect(
        mensaje.split('\n').last,
        startsWith('https://www.google.com/maps'),
      );
    });

    testWidgets('«Compartir» saca el cajon del sistema con texto y asunto', (
      tester,
    ) async {
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);
      await tester.tap(find.byKey(claveDeCompartir));
      await tester.pump();

      expect(aparato.compartidos, hasLength(1));
      expect(aparato.compartidos.single.asunto, 'Ruta RT-001');
      expect(
        aparato.compartidos.single.texto,
        contains('https://www.google.com/maps'),
      );
      // Y no se abre nada por su cuenta: compartir es compartir.
      expect(aparato.abiertos, isEmpty);
    });

    testWidgets('«Copiar» deja el mensaje entero, no solo el enlace', (
      tester,
    ) async {
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);
      await tester.tap(find.byKey(claveDeCopiar));
      await tester.pump();

      expect(aparato.copiados.single, startsWith('Ruta RT-001'));
      expect(aparato.copiados.single, contains('https://www.google.com/maps'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('si falla, la pantalla NO se queda verde', () {
    testWidgets('no se pudo abrir Google Maps: se dice, y con el motivo', (
      tester,
    ) async {
      aparato.abre = false;
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);
      await tester.tap(find.byKey(claveDeAbrirEnGoogleMaps));
      await tester.pump();

      expect(find.text(TextosDelMapa.noSeAbrio), findsOneWidget);
    });

    testWidgets('no se pudo compartir: se dice y se ofrece copiar', (
      tester,
    ) async {
      aparato.comparte = false;
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);
      await tester.tap(find.byKey(claveDeCompartir));
      await tester.pump();

      expect(find.text(TextosDelMapa.noSeCompartio), findsOneWidget);
    });

    testWidgets('cuando SI se abre, no sale ningun aviso', (tester) async {
      // La pareja de la de arriba: un aviso que sale siempre deja de leerse, y
      // entonces tampoco se lee el dia que importa (`CLAUDE.md` §3-quinquies).
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);
      await tester.tap(find.byKey(claveDeAbrirEnGoogleMaps));
      await tester.pump();

      expect(find.text(TextosDelMapa.noSeAbrio), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('lo que no cabe en el enlace se dice en la pantalla', () {
    testWidgets('con 30 paradas, el aviso esta a la vista', (tester) async {
      await pintar(tester, laRutaDeSiempre(cuantas: 30), enElAparato: true);

      expect(find.byKey(claveDeLoQueQuedaFuera), findsOneWidget);
      expect(find.textContaining('5 paradas quedan fuera'), findsOneWidget);
    });

    testWidgets('con 3 paradas no hay aviso que estorbe', (tester) async {
      await pintar(tester, laRutaDeSiempre(), enElAparato: true);

      expect(find.byKey(claveDeLoQueQuedaFuera), findsNothing);
    });

    testWidgets('y el chofer se entera tambien por WhatsApp', (tester) async {
      await pintar(tester, laRutaDeSiempre(cuantas: 30), enElAparato: true);
      await tester.tap(find.byKey(claveDeWhatsApp));
      await tester.pump();

      expect(
        aparato.abiertos.single.queryParameters['text'],
        contains('5 paradas quedan fuera'),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // QUE NO SE CORTE POR ABAJO
  //
  // Jose, 17/09/2026: «me corta parte de abajo, esto hasta del mapa, no solo de
  // la última card, no puedo ver el final». Es un fallo del original, no un
  // patron que copiar, y tiene dos causas que dependen de este widget:
  //
  //  1. **un hijo sin alto propio** dentro de algo que se desplaza se come la
  //     pantalla;
  //  2. **un gesto de arrastre** dentro del mapa le gana el arrastre a la lista,
  //     y entonces arrastrar sobre el mapa deja de desplazar.
  //
  // Las dos se comprueban A TAMANO DE TELEFONO. A 1200×1600 cabe todo y esto no
  // se ve nunca: la prueba pasaria en verde con el fallo dentro.
  // ───────────────────────────────────────────────────────────────────────────
  group('a tamaño de teléfono, el detalle llega hasta el final', () {
    const telefono = Size(390, 844);

    /// Una lista con el mapa dentro y **un ultimo renglon al final**, que es la
    /// forma que tiene el detalle de la ruta. La lista de verdad vive en
    /// `detalle_ruta.dart` y hoy no se puede tocar; cuando quede libre, esta
    /// misma prueba se apunta a la pantalla entera.
    Future<void> comoElDetalle(WidgetTester tester) async {
      tester.view.physicalSize = telefono;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trabajaSinConexionProvider.overrideWithValue(true),
            abrirYCompartirProvider.overrideWithValue(aparato),
            fondoDeCallesProvider.overrideWithValue(const SinCalles()),
            recorridoPorCallesProvider.overrideWithValue(
              const SinCallesQueSeguir(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 48),
                children: [
                  const SizedBox(height: 300, child: Placeholder()),
                  MapaDeLaRuta(ruta: laRutaDeSiempre(cuantas: 6)),
                  const SizedBox(height: 300, child: Placeholder()),
                  const Text('el último renglón del detalle'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('el mapa tiene alto PROPIO y con techo', (tester) async {
      await comoElDetalle(tester);

      final alto = tester.getSize(find.byKey(CroquisDeRuta.clave)).height;
      expect(alto, altoDelMapa(390 - 24));
      // Y sobre todo: no se come la pantalla. Un hijo sin alto propio dentro de
      // una lista es exactamente como se corta esto.
      expect(alto, lessThan(telefono.height / 2));
    });

    testWidgets('el techo aguanta una pantalla ancha', (tester) async {
      // A 1400 px de ancho, sin techo el mapa mediria 875 px de alto el solo y
      // empujaria las acciones y las paradas por debajo del borde.
      expect(altoDelMapa(1400), 320);
      expect(altoDelMapa(200), 190);
    });

    testWidgets('arrastrar SOBRE EL MAPA sigue desplazando la lista', (
      tester,
    ) async {
      await comoElDetalle(tester);

      final antes = tester.getTopLeft(find.byKey(CroquisDeRuta.clave)).dy;
      // El arrastre empieza justo encima del mapa. Si el mapa tuviera un
      // reconocedor de arrastre o de pellizco, se quedaria el gesto y la lista
      // no se moveria ni un pixel.
      await tester.drag(find.byKey(CroquisDeRuta.clave), const Offset(0, -200));
      await tester.pump();

      expect(
        tester.getTopLeft(find.byKey(CroquisDeRuta.clave)).dy,
        lessThan(antes),
        reason: 'el mapa se quedó el arrastre y la lista no se movió',
      );
    });

    testWidgets('se llega al último renglón desplazando, no está solo en el árbol', (
      tester,
    ) async {
      await comoElDetalle(tester);

      final ultimo = find.text('el último renglón del detalle');
      // Un widget fuera de pantalla TAMBIEN existe en el arbol: comprobar que
      // esta seria comprobar nada. Lo que hay que comprobar es que se llega.
      await tester.scrollUntilVisible(ultimo, 200, scrollable: find.byType(Scrollable));
      await tester.pump();

      expect(ultimo, findsOneWidget);
      final caja = tester.getRect(ultimo);
      expect(caja.bottom, lessThanOrEqualTo(telefono.height));
      expect(caja.top, greaterThanOrEqualTo(0));
    });

    testWidgets('y también se llega a los cuatro botones', (tester) async {
      await comoElDetalle(tester);

      await tester.scrollUntilVisible(
        find.byKey(claveDeCopiar),
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.pump();

      final caja = tester.getRect(find.byKey(claveDeCopiar));
      expect(caja.bottom, lessThanOrEqualTo(telefono.height));
      // Y se puede pulsar de verdad, que es lo que no se podia en el original.
      await tester.tap(find.byKey(claveDeCopiar));
      await tester.pump();
      expect(aparato.copiados, hasLength(1));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Y QUE ESTE DE VERDAD EN EL DETALLE
  //
  // Todo lo de arriba prueba el bloque suelto. Esto prueba lo otro, que es lo
  // que Jose ve: que al abrir una ruta **sale el mapa**, y que desde ahi se
  // llega hasta el final de la pantalla en un telefono.
  //
  // Sin esta, quitar `MapaDeLaRuta` de la lista de `detalle_ruta.dart` dejaria
  // las 83 pruebas de arriba en verde y la pantalla sin mapa — que es
  // exactamente el fallo del que salio este encargo.
  // ───────────────────────────────────────────────────────────────────────────
  group('el mapa está dentro del detalle de la ruta', () {
    late BaseLocal base;
    final ahora = DateTime(2026, 9, 14, 16, 5);
    const telefono = Size(390, 844);

    setUp(() => base = baseDePrueba());
    tearDown(() => base.close());

    Future<void> abrirElDetalle(WidgetTester tester) async {
      // SE SIEMBRA AQUI DENTRO, no en el `setUp`: el `setUp` corre fuera del
      // reloj falso del `tester` y lo que Drift deja empezado alli no avanza
      // dentro — la prueba se cuelga en vez de fallar (`CLAUDE.md` §5).
      await sembrarCatalogo(base);
      await base
          .into(base.routes)
          .insert(
            RoutesCompanion.insert(
              id: 'R1',
              routeCode: const Value('RT-001'),
              branchId: const Value('B1'),
              originLat: const Value(21.38),
              originLng: const Value(-77.91),
            ),
          );
      for (var i = 1; i <= 4; i++) {
        await sembrarPedido(
          base,
          id: 'o$i',
          cliente: 'Cliente $i',
          ultimaRutaId: 'R1',
          orden: i,
          endLat: 21.3 + i / 100,
          endLng: -77.9 - i / 100,
        );
        await sembrarRenglon(
          base,
          id: 'r$i',
          pedidoId: 'o$i',
          producto: 'Arroz',
          unidades: 10,
          empaques: 2,
        );
      }

      tester.view.physicalSize = telefono;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseProvider.overrideWithValue(base),
            relojProvider.overrideWithValue(() => ahora),
            fondoDeCallesProvider.overrideWithValue(const SinCalles()),
            recorridoPorCallesProvider.overrideWithValue(
              const SinCallesQueSeguir(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: delegacionesDeIdioma,
            supportedLocales: idiomas,
            home: const Scaffold(body: DetalleDeRuta(rutaId: 'R1')),
          ),
        ),
      );
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> desmontar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('al abrir una ruta SALE el mapa', (tester) async {
      await abrirElDetalle(tester);

      expect(find.byKey(CroquisDeRuta.clave), findsOneWidget);
      expect(find.byKey(claveDeAbrirEnGoogleMaps), findsOneWidget);

      await desmontar(tester);
    });

    testWidgets('en un teléfono se llega hasta la última tarjeta', (
      tester,
    ) async {
      await abrirElDetalle(tester);

      // `Carga total` es lo ultimo del detalle. Que exista en el arbol no
      // demuestra nada —un widget fuera de pantalla tambien existe—: hay que
      // **llegar** y que quepa dentro de la ventana.
      final ultima = find.text('Carga total');
      await tester.scrollUntilVisible(
        ultima,
        200,
        scrollable: find.ancestor(
          of: find.byKey(CroquisDeRuta.clave),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pump();

      final caja = tester.getRect(ultima);
      expect(caja.bottom, lessThanOrEqualTo(telefono.height));
      expect(caja.top, greaterThanOrEqualTo(0));

      await desmontar(tester);
    });

    testWidgets('y por debajo queda aire, no la barra del sistema', (
      tester,
    ) async {
      await abrirElDetalle(tester);

      // La lista se busca **como antepasada del mapa** y no por `byType().first`:
      // asi ademas queda dicho que el mapa va DENTRO de lo que se desplaza. Con
      // `first` la prueba cogia cualquier `ListView` del arbol, y con varias
      // pruebas corriendo a la vez no siempre era la misma.
      final lista = tester.widget<ListView>(
        find.ancestor(
          of: find.byKey(CroquisDeRuta.clave),
          matching: find.byType(ListView),
        ),
      );
      expect((lista.padding! as EdgeInsets).bottom, rellenoAlFinalDelDetalle);
      expect(rellenoAlFinalDelDetalle, greaterThanOrEqualTo(48));

      await desmontar(tester);
    });
  });
}
