import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/diseno/cajon.dart';
import 'package:reparto/navegacion/rutas.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/pantallas/panel/registro.dart';
import 'package:reparto/pantallas/sincronizacion/vista/fila_de_rechazo.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';
import '../traer_el_dia/apoyo_traer_el_dia.dart';

/// EL BOTON DE ENTREGAR EL DIA en la pantalla, a las dos anchuras.
void main() {
  setUpAll(() => initializeDateFormatting('es'));

  late BaseLocal base;
  late RelojFalso reloj;
  late ColaDeSalida cola;

  setUp(() {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime(2026, 9, 15, 17, 40));
    cola = ColaDeSalida(base, reloj: reloj.leer);
  });

  tearDown(() => base.close());

  Future<void> encolar(int cuantos) async {
    for (var i = 1; i <= cuantos; i++) {
      await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes/r-$i/results',
        cuerpo: <String, Object?>{'resultado': 'entregado'},
      );
    }
  }

  Future<RespuestaFalsa?> Function(PeticionVista) servidorQueAcepta({
    Set<String> rechazarRutas = const <String>{},
  }) {
    return (p) async {
      if (!p.ruta.endsWith('/subida')) return servidorQueTraeElDia(p);
      final cuerpo = p.cuerpo! as Map<String, Object?>;
      final apuntes = (cuerpo['apuntes']! as List<Object?>)
          .cast<Map<String, Object?>>();
      return RespuestaFalsa(200, <String, Object?>{
        'resultados': [
          for (final a in apuntes)
            if (rechazarRutas.contains(a['ruta']))
              <String, Object?>{
                'clave': a['clave'],
                'estado': 'rechazado',
                'motivo':
                    '3 de los 8 pedidos ya están en otra ruta. Vuelve a '
                    'elegirlos.',
              }
            else
              <String, Object?>{'clave': a['clave'], 'estado': 'aplicado'},
        ],
      });
    };
  }

  Future<ProviderContainer> montar(
    WidgetTester tester, {
    required Future<RespuestaFalsa?> Function(PeticionVista) responder,
    double ancho = 1440,
    double alto = 1000,
    bool hayPista = true,
  }) async {
    tester.view.physicalSize = Size(ancho, alto);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final caja = montarTraerElDia(
      base: base,
      reloj: reloj.leer,
      responder: responder,
      hayPista: hayPista,
    );
    addTearDown(caja.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: caja,
        child: RepartoApp(
          enrutador: crearEnrutador(
            pantallas: [registrarPanel()],
            inicial: '/dashboard',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return caja;
  }

  /// Sin `pumpAndSettle`: mientras corre hay una rueda girando y un cronometro
  /// por segundos, y con eso delante `pumpAndSettle` no vuelve nunca.
  Future<void> dejarCorrer(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  testWidgets('con trabajo dentro, la pieza dice ENVIAR y cuantos', (
    tester,
  ) async {
    await encolar(23);
    await montar(tester, responder: servidorQueAcepta());

    // **Una sola pieza**, no dos botones: con veintitres apuntes dentro del
    // telefono no hay nada que elegir, y lo que se puede perder es eso.
    expect(find.text('Tienes trabajo sin enviar'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Enviar datos (23)'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Traer el día'),
      findsNothing,
      reason: 'traer el dia no es lo que toca ahora y no se ofrece',
    );
    await desmontar(tester);

    await montar(tester, responder: servidorQueAcepta(), ancho: 390, alto: 800);
    expect(
      find.widgetWithText(FilledButton, 'Enviar datos (23)'),
      findsOneWidget,
      reason: 'la misma pieza, en el mismo sitio, en el telefono del almacen',
    );
    await desmontar(tester);
  });

  testWidgets('sin nada dentro, lo que toca es TRAER', (tester) async {
    await montar(tester, responder: servidorQueAcepta());

    expect(find.text('Traer el día'), findsWidgets);
    expect(
      find.textContaining('Enviar datos'),
      findsNothing,
      reason:
          'un boton de enviar sin nada que enviar ensena a desconfiar del '
          'que si hace algo',
    );
    await desmontar(tester);
  });

  testWidgets('CON LA CONEXION MALA no se ofrece un boton que va a fallar', (
    tester,
  ) async {
    await encolar(23);
    final caja = await montar(tester, responder: servidorQueAcepta());

    // El estado NO sale de `connectivity_plus`: sale de si las peticiones estan
    // llegando. Con una conexion inestable el aparato CREE que esta conectado, y
    // eso es lo que deja al logistico mirando una rueda sin saber si va a
    // funcionar.
    darLaConexionPorMala(caja);
    await tester.pumpAndSettle();

    expect(find.text('Trabajando sin conexión'), findsOneWidget);
    expect(
      find.byType(FilledButton),
      findsNothing,
      reason:
          'en el patio del almacen no hay nada que elegir: se dice el '
          'estado y de que hora son los datos',
    );
    // Y se dice lo unico que hace falta saber ahi: de cuando son los datos y
    // que queda dentro.
    expect(find.textContaining('23 sin subir'), findsWidgets);
    await desmontar(tester);
  });

  testWidgets('se le da, sube, y al acabar dice CUANTOS subieron', (
    tester,
  ) async {
    await encolar(23);
    await montar(tester, responder: servidorQueAcepta());

    await tester.tap(find.widgetWithText(FilledButton, 'Enviar datos (23)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Cajon, tambien en escritorio.
    expect(find.byType(Cajon), findsOneWidget);
    await dejarCorrer(tester);

    expect(find.text('Subieron 23 apuntes'), findsWidgets);
    expect(find.text('Todo entregado'), findsWidgets);
    await desmontar(tester);
  });

  testWidgets('un rechazo NO deja el dia entregado, y se ve con su motivo', (
    tester,
  ) async {
    await encolar(3);
    await montar(
      tester,
      responder: servidorQueAcepta(rechazarRutas: {'/api/routes/r-2/results'}),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Enviar datos (3)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await dejarCorrer(tester);

    expect(
      find.text('1 rechazado esperando a que alguien decida'),
      findsWidgets,
    );
    // El motivo LITERAL del servidor, en la misma pieza que usa la pantalla de
    // Sincronizacion.
    expect(find.byType(FilaDeRechazo), findsOneWidget);
    expect(
      find.textContaining('ya están en otra ruta'),
      findsOneWidget,
      reason:
          'un apunte rechazado que desaparece en silencio es trabajo '
          'perdido que nadie sabe que perdio',
    );
    await desmontar(tester);
  });

  testWidgets('se cae la subida: dice cuantos quedan y no se pone verde', (
    tester,
  ) async {
    await encolar(23);
    await montar(
      tester,
      responder: (p) async {
        if (p.ruta.endsWith('/subida')) return null;
        return servidorQueTraeElDia(p);
      },
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Enviar datos (23)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await dejarCorrer(tester);

    expect(find.text('Quedan 23 sin subir'), findsWidgets);
    expect(find.text('Todo entregado'), findsNothing);
    expect(
      find.textContaining('lo que no subió sigue entero'),
      findsOneWidget,
      reason: 'y se dice que hacer y que nada se ha perdido',
    );
    await desmontar(tester);
  });
}
