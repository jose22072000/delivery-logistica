import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/tema.dart';
import 'package:reparto/navegacion/franja_de_estado.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/sincro/bajada.dart';
import 'package:reparto/nucleo/sincro/ciclo.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';

import '../apoyo/base_de_prueba.dart';

/// LO QUE ESTÁ EN ESTE APARATO Y NO VA A SUBIR SOLO **SE DICE**.
///
/// ## El agujero que cierra
///
/// `Huerfanos.mirar()` estaba escrito, probado y **no lo llamaba nadie en
/// `lib/`**: el único que tocaba `huerfanosProvider` era el ciclo, y sólo para
/// `volverAEncolar`, que hoy únicamente sabe reconstruir las zonas del tablero.
/// El comentario de `huerfanos.dart` decía que los demás «se cuentan y se
/// dicen»; contar se contaba, decirse no se decía.
///
/// O sea: una ruta armada sin señal cuyo apunte se perdió existía en el
/// teléfono, no existía arriba, no la subía nadie **y no salía en ninguna
/// pantalla**. Ni en «N sin subir» —no le queda apunte—, ni en la bandeja
/// —nadie la rechazó—, ni en el Panel. El repartidor la veía en su aparato y la
/// daba por hecha.
///
/// ## Y la otra mitad: que NO salga cuando no toca
///
/// Un aviso que sale siempre deja de leerse, y entonces tampoco se lee el día
/// que importa (`CLAUDE.md` §3-quinquies, y ya pasó una vez). Por eso cada
/// prueba de aquí va en pareja: lo normal —una ruta con su apunte esperando— no
/// puede encender nada.
///
/// ## Sobre el tiempo
///
/// Nada de `await` sobre el primer valor de un stream de Drift aquí dentro: el
/// reloj del `tester` no avanza solo y la prueba **se cuelga en vez de
/// fallar** (§5). Se siembra dentro del cuerpo —nunca en el `setUp`— y se avanza
/// a mano con `tester.pump(Duration…)`.
void main() {
  late BaseLocal base;

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  ProviderContainer? contenedor;

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [baseProvider.overrideWith((ref) => base)],
        child: MaterialApp(
          theme: temaDeReparto(),
          home: const Scaffold(body: FranjaDeEstado()),
        ),
      ),
    );
    await tester.pump();
    contenedor = ProviderScope.containerOf(
      tester.element(find.byType(FranjaDeEstado)),
    );
  }

  /// Avanza el reloj del `tester` hasta que el texto salga, o se rinde.
  ///
  /// El tope es corto a propósito: si el cable no está, esto tiene que terminar
  /// y fallar con un mensaje, no quedarse colgado diez minutos.
  Future<bool> saleEl(WidgetTester tester, Finder que) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (que.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Una ruta armada en este aparato, con su `local-…`.
  ///
  /// Se inserta por Drift y no con SQL a pelo **a proposito**: es lo que hace
  /// `acciones_rutas.armar`, y es lo unico que anuncia el cambio de tabla. Con
  /// un `customStatement` la fila aparece y nadie se entera — que es una trampa
  /// de la prueba, no del codigo.
  Future<void> unaRutaDeAqui([String id = 'local-9f3a2b7c']) => base
      .into(base.routes)
      .insert(RoutesCompanion.insert(id: id, status: const Value('planned')));

  final elAviso = find.textContaining('Sólo en este aparato');

  // ---------------------------------------------------------------------------
  group('trabajo huérfano', () {
    testWidgets('una RUTA sin ningún apunte que la suba SE NOMBRA, y aparece '
        'con la pantalla ya abierta', (tester) async {
      await montar(tester);

      expect(
        elAviso,
        findsNothing,
        reason: 'todavía no hay nada colgado; avisar aquí es avisar siempre',
      );

      // Y AHORA aparece, SIN QUE NADIE VUELVA A MONTAR NADA. La ruta está en
      // el aparato y no le queda ningún apunte que la suba: es lo que se ve
      // cuando el suyo se pierde, o cuando lo descartan desde la bandeja con
      // la aplicación abierta (eso va en la tercera prueba de este grupo).
      await unaRutaDeAqui();

      expect(
        await saleEl(tester, elAviso),
        isTrue,
        reason:
            'LA FRANJA NO SE ENTERÓ. La ruta está en el aparato, no está '
            'arriba y no le queda ningún apunte que la suba: es la zona '
            '«Vista» del 16/09/2026 otra vez. Si esto no sale, el repartidor '
            'la ve en su pantalla y la da por hecha.',
      );
      expect(
        find.text('Sólo en este aparato: 1 ruta'),
        findsOneWidget,
        reason:
            'se NOMBRA lo que es: «1 cosa colgada» no le dice a nadie dónde '
            'mirar',
      );
      // Y NO sale como «sin subir», que es justo por lo que no se veía: la cola
      // está vacía.
      expect(find.textContaining('sin subir'), findsNothing);

      await desmontar(tester);
    });

    testWidgets('LO NORMAL NO AVISA: una ruta con su apunte esperando no '
        'enciende nada', (tester) async {
      await montar(tester);

      await unaRutaDeAqui();
      await ColaDeSalida(base).encolar(
        metodo: 'POST',
        ruta: '/routes',
        cuerpo: const <String, Object?>{},
        provisional: 'local-9f3a2b7c',
      );

      // Se le da el mismo tiempo que al caso bueno: si con esto sale, sale
      // siempre, y un aviso que sale siempre deja de leerse.
      expect(
        await saleEl(tester, elAviso),
        isFalse,
        reason:
            'una ruta recién armada sin señal está legítimamente pendiente: va '
            'a subir sola en cuanto haya red. Avisar aquí es avisar en cada '
            'gesto (§3-quinquies)',
      );

      await desmontar(tester);
    });

    testWidgets('una ZONA DEL TABLERO huérfana también, y sin esperar al tic '
        'siguiente del ciclo', (tester) async {
      // Las tablas del Tablero no son de Drift: las crea la propia pantalla, y
      // `tableUpdates` no las conoce por objeto. Se vigilan POR NOMBRE, y lo
      // que las anuncia es `EsquemaTablero.avisarDeCambio` —un `notifyUpdates`
      // a mano— que es justo lo que corre después de cada escritura de verdad
      // del tablero. Sin eso, una zona colgada no salía hasta que el ciclo
      // volviera a pasar, minutos después.
      await montar(tester);

      await EsquemaTablero.asegurar(base);
      await base.customStatement(
        "INSERT INTO ${EsquemaTablero.columnas} "
        '(id, branch_id, nombre, posicion, nacio_aqui) '
        "VALUES ('z-vista', 'suc-stg', 'Vista', 1, 1)",
      );
      // El aviso que da el tablero de verdad al escribir.
      EsquemaTablero.avisarDeCambio(base);

      expect(
        await saleEl(tester, elAviso),
        isTrue,
        reason:
            'la zona está en el aparato con su marca de «sólo existe aquí» y '
            'sin ningún apunte que la suba: es la zona «Vista» del 16/09/2026',
      );
      expect(find.text('Sólo en este aparato: 1 zona del tablero'), findsOneWidget);

      await desmontar(tester);
    });

    test('los nombres de las tablas del Tablero son los mismos a los dos lados',
        () {
      // §3-bis: `nucleo/` no puede importar `pantallas/`, así que los nombres
      // están escritos dos veces. Dos copias que se separen dejan el aviso sin
      // enterarse de nada, en verde. Se atan con una prueba, no con un
      // comentario.
      expect(tablaDeZonasDelTablero, EsquemaTablero.columnas);
      expect(tablaDeTarjetasDelTablero, EsquemaTablero.colocaciones);
    });

    testWidgets('y en cuanto se le quita el apunte, lo dice', (tester) async {
      await montar(tester);

      final cola = ColaDeSalida(base);
      await unaRutaDeAqui();
      final clave = await cola.encolar(
        metodo: 'POST',
        ruta: '/routes',
        cuerpo: const <String, Object?>{},
        provisional: 'local-9f3a2b7c',
      );
      expect(await saleEl(tester, elAviso), isFalse);

      // El servidor dice que no y alguien lo descarta desde la bandeja. **Ese
      // gesto es el que deja la ruta huérfana**: el apunte se va y no queda
      // nada que la suba. Hasta hoy no lo decía nadie.
      await cola.resolver(
        clave,
        const ResultadoApunte(
          estado: EstadoResultado.rechazado,
          motivo: 'Ese camión ya va en otra ruta',
        ),
      );
      await cola.descartar(clave);

      expect(
        await saleEl(tester, elAviso),
        isTrue,
        reason:
            'descartar el apunte deja la ruta sin nada que la suba: es el '
            'caso exacto de `huerfanos.dart`',
      );

      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  group('la bajada que volvió a medias', () {
    /// Un ciclo que bajó y se quedó a medias, como lo devuelve `bajada.dart`.
    ResumenDelCiclo aMedias(String? quedoPor, {int tandas = 3}) =>
        ResumenDelCiclo(
          pasos: const [PasoDelCiclo.bajar],
          bajada: ResumenDeBajada(
            puestos: 2000,
            quitados: 0,
            completa: false,
            tandas: tandas,
            quedoPor: quedoPor,
          ),
        );

    testWidgets('un ciclo que NADIE estaba mirando lo dice, con el motivo '
        'literal del servidor', (tester) async {
      await montar(tester);

      const motivo =
          'se llegó al tope de 20 tandas y el servidor seguía diciendo que '
          'queda más';
      expect(find.textContaining(motivo), findsNothing);

      // El vigía dispara un ciclo por su cuenta y vuelve con 2.000 clientes de
      // 8.034. Hasta hoy eso era un `Registro.fallo` en un log y nada más:
      // `quedoPor` lo leía UN sitio, la configuración inicial.
      contenedor!.read(alAcabarElCicloProvider)(aMedias(motivo));

      expect(
        await saleEl(tester, find.textContaining(motivo)),
        isTrue,
        reason:
            'el motivo va LITERAL: nombra lo que se quedó fuera, que es lo '
            'único con lo que alguien puede hacer algo. «No terminó» no sirve '
            'para nada (`CLAUDE.md` §3)',
      );

      await desmontar(tester);
    });

    testWidgets('una bajada ENTERA no dice nada', (tester) async {
      await montar(tester);

      contenedor!.read(alAcabarElCicloProvider)(aMedias(null));

      expect(
        await saleEl(tester, find.textContaining('Faltan datos por bajar')),
        isFalse,
        reason:
            'la bajada buena es el caso de siempre: avisar aquí sería avisar '
            'en cada vuelta del vigía',
      );

      await desmontar(tester);
    });

    testWidgets('y una vuelta que NI LLEGÓ A BAJAR no borra el aviso de '
        'antes', (tester) async {
      await montar(tester);

      const motivo = 'el servidor dijo que quedaba más y no avanzó ni la marca';
      contenedor!.read(alAcabarElCicloProvider)(aMedias(motivo));
      expect(await saleEl(tester, find.textContaining(motivo)), isTrue);

      // Se va la red: el ciclo muere al renovar y vuelve con la bajada a cero
      // tandas. Al aparato le SIGUEN faltando esos clientes.
      contenedor!.read(alAcabarElCicloProvider)(aMedias(null, tandas: 0));
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.textContaining(motivo),
        findsOneWidget,
        reason:
            'creerse el `quedoPor` nulo de una vuelta que ni bajó apagaría un '
            'aviso que sigue siendo verdad',
      );

      await desmontar(tester);
    });
  });
}
