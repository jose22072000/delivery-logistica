import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/vista/pantalla_tablero.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

/// EL CABLE ENTRE EL AVISO Y LA PANTALLA, que no lo sujetaba nadie.
///
/// `la_web_avisa_si_no_subio_test.dart` prueba el PROVEEDOR: que
/// `loQueElServidorRechazoProvider` emite el motivo cuando llega un apunte
/// rechazado. Lo que no probaba nadie es que la franja del tablero esté
/// **suscrita** a él. La auditoría cambió el `ref.watch` de
/// `pantalla_tablero.dart` por `ref.read` y corrió la suite entera: 862
/// pruebas, todas verdes. Con `read` el aviso se lee UNA vez, al pintar, y
/// nunca se vuelve a mirar.
///
/// Y eso es exactamente el fallo original, el del `CLAUDE.md` §4-bis: el aviso
/// se calculaba donde no se enteraba de nada. El rechazo llega DESPUÉS, con la
/// pantalla ya abierta; si nadie la repinta, no sale nunca.
///
/// Por eso esta prueba monta primero y rechaza después, **sin volver a
/// montar**, que es el orden de la vida real (§3-ter). Sembrar el rechazo antes
/// de montar es justo el caso que un `read` resuelve bien, y con eso el verde
/// no significa nada.
///
/// Sobre el tiempo: nada de `await` sobre el primer valor de un stream de
/// Drift aquí dentro — el reloj del `tester` no avanza solo y la prueba se
/// cuelga en vez de fallar (§5). Se avanza a mano con `tester.pump(Duration…)`.
void main() {
  late BaseLocal base;
  late ServidorFalso servidor;

  setUp(() async {
    base = baseDePrueba();
    servidor = ServidorFalso(
      (p) async => RespuestaFalsa(200, const {
        'columnas': <Object?>[],
        'colocados': <Object?>[],
      }),
    );
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarPedido(base, id: 'p-cerca', operacion: 'SC06-1257');
  });

  tearDown(() => base.close());

  Widget montar() {
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba'))
      ..httpClientAdapter = servidor;
    return ProviderScope(
      overrides: [
        baseProvider.overrideWith((ref) => base),
        // SIN ESPERAS: con esperas de verdad el reintento del cliente cuelga el
        // `pumpAndSettle` en vez de fallar. Es la trampa del `CLAUDE.md` §5.
        clienteApiProvider.overrideWithValue(
          ClienteApi(dio: dio, esperas: const <Duration>[]),
        ),
        almacenSesionProvider.overrideWithValue(
          AlmacenEnMemoria(
            const Sesion(
              token: 't',
              refresh: 'r',
              sub: 'logistico',
              sucursalId: sucursalStg,
            ),
          ),
        ),
      ],
      // La pantalla no lleva `Scaffold`: lo pone el armazón.
      child: const MaterialApp(home: Scaffold(body: PantallaTablero())),
    );
  }

  /// Un apunte que el servidor rechazó con su motivo, como lo deja la subida.
  Future<void> elServidorRechazo(String motivo) async {
    final cola = ColaDeSalida(base);
    final clave = await cola.encolar(
      metodo: 'PUT',
      ruta: '/board/placements/p-cerca',
      cuerpo: const {'columnaId': 'c1', 'posicion': 1},
    );
    await cola.resolver(
      clave,
      ResultadoApunte(estado: EstadoResultado.rechazado, motivo: motivo),
    );
  }

  /// Avanza el reloj del `tester` hasta que el texto aparezca, o se rinde.
  ///
  /// El tope es corto a propósito: si el cable no está, esto tiene que terminar
  /// y fallar con un mensaje, no quedarse colgado diez minutos.
  Future<bool> esperarATexto(WidgetTester tester, Finder que) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (que.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Dos pasadas: el temporizador de cero lo crea el propio desmontaje de los
    // `Stream` de Drift, al final del primer fotograma.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets(
    'la web: el rechazo llega CON LA PANTALLA YA ABIERTA y la franja se '
    'repinta sola con el motivo',
    (tester) async {
      await Destino.comoSiFueraWeb(() async {
        await tester.binding.setSurfaceSize(const Size(1400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // 1. La pantalla se abre, y todavía no ha pasado nada.
        await tester.pumpWidget(montar());
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );

        final elAviso = find.textContaining('Ese pedido ya va en otra ruta');
        expect(
          elAviso,
          findsNothing,
          reason: 'todavía no se ha rechazado nada; avisar aquí es avisar '
              'siempre, y un aviso que sale siempre deja de leerse',
        );

        // 2. Se arrastra la tarjeta y el servidor dice que no. NADIE vuelve a
        //    montar, nadie recarga y nadie cambia de sucursal: es lo que pasa
        //    en un navegador con la pantalla delante.
        await elServidorRechazo('Ese pedido ya va en otra ruta');

        // 3. Y la franja tiene que enterarse ella sola.
        final salio = await esperarATexto(tester, elAviso);
        expect(
          salio,
          isTrue,
          reason:
              'LA FRANJA DEL TABLERO NO SE ENTERÓ DEL RECHAZO.\n'
              'El apunte está rechazado en la base y '
              '`loQueElServidorRechazoProvider` lo emite —eso ya lo prueba '
              '`la_web_avisa_si_no_subio_test.dart`—, pero la pantalla no se '
              'repintó. Es lo que pasa si ese `case` de '
              '`pantalla_tablero.dart` se lee con `ref.read` en vez de con '
              '`ref.watch`: el valor se mira UNA vez, al pintar, y el rechazo '
              'llega después.\n'
              'En la web no hay cola que lo guarde para luego: la tarjeta se ve '
              'movida en la pantalla, el servidor la rechazó, y no se entera '
              'nadie hasta que alguien recarga y la ve volver a su sitio.',
        );

        expect(
          find.textContaining('El servidor no aceptó el último cambio'),
          findsOneWidget,
          reason: 'con el motivo LITERAL del servidor delante: «ya va en otra '
              'ruta» le dice a alguien qué hacer, «no se pudo guardar» no',
        );

        await desmontar(tester);
      });
    },
  );
}
