import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/diseno/colores.dart';
import 'package:reparto/diseno/insignia.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/sincronizacion/datos/panel_sincronizacion.dart';
import 'package:reparto/pantallas/sincronizacion/registro.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo_sincronizacion.dart';

/// La pantalla del sincronizador, montada de verdad sobre el armazon.
void main() {
  setUpAll(() => initializeDateFormatting('es'));

  final ahora = DateTime(2026, 9, 14, 10, 42);

  late BaseLocal base;
  late SincroFalso servidor;

  setUp(() {
    base = baseDePrueba();
    servidor = SincroFalso(estadoJson());
  });
  tearDown(() => base.close());

  Future<void> sucursal(String id, String nombre) => base
      .into(base.branches)
      .insert(
        BranchesCompanion.insert(
          id: id,
          name: nombre,
          lat: 21.38,
          lng: -77.91,
          externalId: const Value('CAM'),
        ),
      );

  Future<ProviderContainer> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => ahora),
          clienteSyncProvider.overrideWithValue(clienteDePrueba(servidor)),
        ],
        child: RepartoApp(
          enrutador: crearEnrutador(
            pantallas: [registrarSincronizacion()],
            inicial: '/sync',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(RepartoApp)));
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  Insignia insigniaDe(WidgetTester tester, String texto) => tester
      .widgetList<Insignia>(find.byType(Insignia))
      .firstWhere((i) => i.texto == texto);

  final panelDeLosDiez = estadoJson(
    aparatos: [
      // El que nunca subió, primero: así lo ordena el servidor.
      aparatoJson(
        aparato: 'ap-palma',
        persona: 'María',
        sucursal: 'b-palma',
        nombre: 'Teléfono de Palma',
        pendientes: 12,
      ),
      aparatoJson(
        aparato: 'ap-tunas',
        persona: 'Pedro',
        sucursal: 'b-tunas',
        nombre: 'Teléfono de Las Tunas',
        subida: '2026-09-11T08:00:00Z',
        horasSinSubir: 74,
        pendientes: 5,
        rechazados: 1,
      ),
      aparatoJson(
        aparato: 'ap-camaguey',
        persona: 'Luis',
        sucursal: 'b-camaguey',
        nombre: 'Teléfono de Camagüey',
        subida: '2026-09-14T10:41:00Z',
        horasSinSubir: 0,
      ),
    ],
    bandeja: [
      rechazoJson(
        rechazo: 'r1',
        motivo: '3 de los 8 pedidos ya están en otra ruta. Vuelve a elegirlos.',
      ),
    ],
    sinAtender: [
      <String, Object?>{'sucursal': 'b-palma', 'sin_atender': 1},
    ],
  );

  testWidgets('«nunca ha subido» NO se pinta como «hace 0 horas»', (
    tester,
  ) async {
    servidor.cuerpo = panelDeLosDiez;
    await montar(tester);

    // Otro texto...
    expect(find.text(TextosDeSincronizacion.nunca), findsWidgets);
    expect(find.text('Hace menos de una hora'), findsOneWidget);

    // ...y otro COLOR. Esto es lo que se ve de reojo, sin leer.
    final nunca = insigniaDe(tester, TextosDeSincronizacion.nunca);
    final alDia = insigniaDe(tester, 'Hace menos de una hora');
    expect(nunca.color, Colores.rojo);
    expect(alDia.color, Colores.verde);
    expect(nunca.color, isNot(alDia.color));
    expect(nunca.fondo, isNot(alDia.fondo));

    // El de tres días tampoco se lee igual que el de una hora.
    expect(insigniaDe(tester, 'Hace 3 días').color, Colores.rojo);

    await desmontar(tester);
  });

  testWidgets('el que nunca subió sale ARRIBA, no al final de la lista', (
    tester,
  ) async {
    servidor.cuerpo = panelDeLosDiez;
    await montar(tester);

    final arriba = tester.getTopLeft(find.text('Teléfono de Palma')).dy;
    final medio = tester.getTopLeft(find.text('Teléfono de Las Tunas')).dy;
    final abajo = tester.getTopLeft(find.text('Teléfono de Camagüey')).dy;
    expect(arriba, lessThan(medio));
    expect(medio, lessThan(abajo));

    await desmontar(tester);
  });

  testWidgets('los rechazados salen con su motivo y su hora', (tester) async {
    servidor.cuerpo = panelDeLosDiez;
    await montar(tester);

    // El motivo LITERAL del servidor: es lo único que le dice a alguien qué
    // hacer. No se descarta en silencio.
    expect(
      find.text('3 de los 8 pedidos ya están en otra ruta. Vuelve a elegirlos.'),
      findsOneWidget,
    );
    // Las dos horas: la del aparato (`hecho`) y la del servidor (`rechazado`).
    expect(find.textContaining('hecho 14/9/2026'), findsOneWidget);
    expect(find.textContaining('rechazado 14/9/2026'), findsOneWidget);
    // Y a quién hay que llamar.
    expect(find.textContaining('María'), findsWidgets);
    expect(find.text('POST /api/routes/local-9f3a/results'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('sin conexión dice que NO PUEDE SABERLO; no finge datos', (
    tester,
  ) async {
    servidor.cuerpo = null;
    await montar(tester);

    expect(find.text(TextosDeSincronizacion.sinConexion), findsOneWidget);

    // Y ni una fila: una tabla vacía se leería como «están todos al día», que
    // es lo contrario de «no lo sé».
    expect(find.byType(Insignia), findsNothing);
    expect(find.text('Teléfono de Palma'), findsNothing);
    expect(find.textContaining('Hace'), findsNothing);
    expect(find.textContaining('Leído del servidor'), findsNothing);

    await desmontar(tester);
  });

  testWidgets('al perder la red, la lectura vieja NO se queda en pantalla', (
    tester,
  ) async {
    servidor.cuerpo = panelDeLosDiez;
    await montar(tester);
    expect(find.text('Teléfono de Palma'), findsOneWidget);
    expect(find.textContaining('Leído del servidor a las 10:42'), findsWidgets);

    // Se cae la red y se pulsa `Actualizar`.
    servidor.cuerpo = null;
    await tester.tap(find.text('Actualizar'));
    await tester.pumpAndSettle();

    expect(find.text(TextosDeSincronizacion.sinConexion), findsOneWidget);
    // Lo de antes se fue: enseñarlo diría «Palma sigue así» sin haberlo podido
    // comprobar.
    expect(find.text('Teléfono de Palma'), findsNothing);
    expect(find.byType(Insignia), findsNothing);

    await desmontar(tester);
  });

  testWidgets('el alcance por sucursal lo cierra el servidor, no la pantalla', (
    tester,
  ) async {
    servidor.cuerpo = panelDeLosDiez;
    final contenedor = await montar(tester);

    // Sin sucursal mirada no se estrecha nada: el alcance sale de quién
    // pregunta.
    expect(servidor.pedidas.first.queryParameters, isEmpty);

    // Y lo que el servidor manda se pinta ENTERO: la pantalla no filtra por su
    // cuenta. Si filtrara aquí, el día que el servidor mandara de más nadie se
    // enteraría de que el alcance está roto.
    expect(find.byType(Insignia), findsNWidgets(3));

    contenedor.read(sucursalMiradaProvider.notifier).mirar('b-palma');
    await tester.pumpAndSettle();

    // Al mirar una sucursal se vuelve a preguntar, con ella en la dirección.
    expect(servidor.pedidas.last.queryParameters['sucursal'], 'b-palma');

    await desmontar(tester);
  });

  testWidgets('la sucursal sale por su nombre si está bajada', (tester) async {
    // Dos, para que la barra superior enseñe `Todas las sucursales` y no el
    // nombre de la única: así lo que se encuentre abajo es la fila y no la
    // barra.
    await sucursal('b-camaguey', 'Camagüey');
    await sucursal('b-palma', 'Palma');
    servidor.cuerpo = panelDeLosDiez;
    await montar(tester);

    expect(find.text('Camagüey'), findsOneWidget);
    // La que no está bajada no deja la fila sin sucursal: sale por su id corto.
    expect(find.text('b-tunas'), findsOneWidget);

    await desmontar(tester);
  });

  testWidgets('sin ningún aparato dado de alta lo dice con esas palabras', (
    tester,
  ) async {
    servidor.cuerpo = estadoJson();
    await montar(tester);

    expect(find.text(TextosDeSincronizacion.sinAparatos), findsOneWidget);
    expect(find.text(TextosDeSincronizacion.bandejaVacia), findsOneWidget);

    await desmontar(tester);
  });
}
