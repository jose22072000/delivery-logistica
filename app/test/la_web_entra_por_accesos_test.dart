import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/app.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/entrada_por_accesos.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/acceso/datos/servicio_acceso.dart';
import 'package:reparto/pantallas/acceso/vista/pantalla_acceso.dart';

import 'apoyo/apoyo_accesos.dart';
import 'apoyo/apoyo_sesion.dart';
import 'apoyo/base_de_prueba.dart';
import 'apoyo/servidor_falso.dart';

/// LA WEB ENTRA SOLA POR ACCESOS. LA APK PIDE LA CONTRASEÑA. Las dos cosas.
///
/// `docs/identidad.md` lo dice en una tabla de dos filas, y las dos filas hacen
/// falta:
///
/// | Cliente | Como | Que guarda |
/// |---|---|---|
/// | **Web** | Login unico de auth: redireccion y vuelta con sesion | Cookie |
/// | **APK** | Usuario y contrasena contra el endpoint de token | El par |
///
/// ## Por que van EN PAREJA (`CLAUDE.md` §3-quinquies)
///
/// Cada cosa se comprueba dos veces —**en web pasa** y **en aparato NO pasa**—
/// porque una sola mitad se cumple igual con el codigo roto del otro lado:
///
///  * solo «la web entra sola» se cumple igual si alguien le quita el formulario
///    a la APK, y entonces **el logistico no puede entrar en el patio de un
///    almacen**, que es la razon de ser del proyecto;
///  * solo «la APK pide la contrasena» se cumple igual si el login unico no se
///    llegara a escribir nunca, que es de donde venimos.
///
/// La mutacion que las valida: `Destino.trabajaSinConexion` clavado a `true`
/// tiene que caerse todo lo de web, y clavado a `false` todo lo de aparato.
void main() {
  setUpAll(() => initializeDateFormatting('es'));

  /// Monta la aplicacion de verdad en el destino que se pida.
  ///
  /// [enWeb] es lo UNICO que cambia entre las dos mitades. Todo lo demas —la
  /// base, el servidor falso, la direccion de la pagina— es identico a
  /// proposito: si cambiara algo mas, la prueba no estaria midiendo la puerta.
  Future<NavegadorFalso> montar(
    WidgetTester tester, {
    required bool enWeb,
    required Future<RespuestaFalsa?> Function(PeticionVista) apiMe,
    String direccion = 'https://ejemplo.test/',
    bool conRueda = false,
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final base = baseDePrueba();
    addTearDown(base.close);
    await aparatoYaConfigurado(base);

    final navegador = NavegadorFalso(direccion: direccion);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // LA UNICA DIFERENCIA ENTRE LAS DOS MITADES.
          trabajaSinConexionProvider.overrideWithValue(!enWeb),
          navegadorProvider.overrideWithValue(navegador),
          entradaPorAccesosProvider.overrideWithValue(
            entradaFalsa(navegador, apiMe),
          ),
          // SIN PAR GUARDADO en los dos lados: en la web porque alli la sesion
          // es la cookie, y en el aparato porque es lo que ve quien todavia no
          // ha entrado.
          almacenSesionProvider.overrideWithValue(AlmacenEnMemoria()),
          baseProvider.overrideWithValue(base),
          relojProvider.overrideWithValue(() => DateTime(2026, 9, 15, 8, 30)),
          dioAuthProvider.overrideWithValue(
            dioFalso((p) async => RespuestaFalsa(200, parDeTokens())),
          ),
          clienteApiProvider.overrideWithValue(
            clienteFalso(
              (p) async => RespuestaFalsa(200, <String, Object?>{
                'hasta': '2026-09-15T08:00:00Z',
                'completa': true,
                'truncado': false,
                'cambios': <String, Object?>{},
                'sucursales': <Object?>[],
              }),
            ),
          ),
        ],
        child: const RepartoApp(),
      ),
    );
    if (conRueda) {
      // `pumpAndSettle` NO vale con la rueda de «entrando» delante: no para
      // nunca y la prueba se cuelga en vez de fallar (`CLAUDE.md` §5). Se
      // bombea a mano lo justo para que el arranque termine.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    } else {
      await tester.pumpAndSettle();
    }
    return navegador;
  }

  /// Desmontar aqui y no en un `tearDown`: las consultas de Drift sueltan un
  /// temporizador al cancelarse y flutter_test lo comprueba ANTES de los
  /// `tearDown`.
  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  Future<RespuestaFalsa?> conSesionDeAccesos(PeticionVista p) async =>
      RespuestaFalsa(200, respuestaDeApiMe(token: tokenDePrueba(sub: 'u-7')));

  Future<RespuestaFalsa?> sinSesionDeAccesos(PeticionVista p) async =>
      RespuestaFalsa(401, <String, Object?>{'user': null});

  // ---------------------------------------------------------------------------
  // 1 · CON SESION DE ACCESOS
  // ---------------------------------------------------------------------------

  group('1 · quien ya entro en Accesos', () {
    testWidgets('en WEB entra SIN ESCRIBIR NADA', (tester) async {
      final navegador = await montar(
        tester,
        enWeb: true,
        apiMe: conSesionDeAccesos,
      );

      expect(
        find.byType(PantallaAcceso),
        findsNothing,
        reason:
            'quien ya entro en Accesos no tiene por que ver un formulario de '
            'contrasena: la sesion la lleva la cookie y el servidor ya dijo '
            'quien es',
      );
      expect(find.text('Panel'), findsWidgets);
      expect(
        navegador.ultimo,
        isNull,
        reason: 'con sesion no hay que ir a ninguna parte',
      );
      await desmontar(tester);
    });

    testWidgets('en APARATO sigue saliendo el formulario, igual que hoy', (
      tester,
    ) async {
      // MISMO servidor, misma respuesta. En el aparato **ni se pregunta**: alli
      // se entra con usuario y contrasena porque quien entra se va al patio de
      // un almacen y necesita el par guardado para el dia entero sin senal.
      final navegador = await montar(
        tester,
        enWeb: false,
        apiMe: conSesionDeAccesos,
      );

      expect(find.byType(PantallaAcceso), findsOneWidget);
      expect(find.text('Usuario o correo'), findsOneWidget);
      expect(find.text('Contraseña'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Entrar'), findsOneWidget);
      expect(
        navegador.ultimo,
        isNull,
        reason: 'la APK no manda a nadie a ningun navegador',
      );
      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // 2 · SIN SESION
  // ---------------------------------------------------------------------------

  group('2 · quien no ha entrado en Accesos', () {
    testWidgets('en WEB se va sola al login unico, sin formulario', (
      tester,
    ) async {
      final navegador = await montar(
        tester,
        enWeb: true,
        apiMe: sinSesionDeAccesos,
        conRueda: true,
      );

      expect(navegador.ultimo, '$baseApiDePrueba/auth/entrar');
      expect(
        find.text('Contraseña'),
        findsNothing,
        reason:
            'ensenar media pantalla de contrasena antes de irse ensena a '
            'rellenarla por reflejo',
      );
      expect(find.text('Entrando con tu cuenta de Procovar…'), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('en APARATO no se va a ninguna parte: se pide la contrasena', (
      tester,
    ) async {
      final navegador = await montar(
        tester,
        enWeb: false,
        apiMe: sinSesionDeAccesos,
      );

      expect(navegador.ultimo, isNull);
      expect(find.text('Contraseña'), findsOneWidget);
      expect(find.text('Entrando con tu cuenta de Procovar…'), findsNothing);
      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // 3 · EL LOGIN UNICO FALLO
  // ---------------------------------------------------------------------------

  group('3 · cuando Accesos falla, se dice y se deja entrar igual', () {
    testWidgets('en WEB: el motivo, el boton de reintentar y el formulario', (
      tester,
    ) async {
      // Asi vuelve el servidor cuando algo se tuerce: `/acceso?sso=<motivo>`
      // (`api/internal/api/auth_web.go`). **Y aqui NO se redirige otra vez**: si
      // se hiciera, el navegador reboraria entre las dos paginas para siempre y
      // nadie podria entrar ni enterarse de por que.
      final navegador = await montar(
        tester,
        enWeb: true,
        apiMe: sinSesionDeAccesos,
        direccion: 'https://ejemplo.test/acceso?sso=nodisponible',
      );

      expect(
        navegador.ultimo,
        isNull,
        reason: 'venimos rebotados de alli: volver a mandar seria un bucle',
      );
      expect(find.byType(PantallaAcceso), findsOneWidget);
      expect(
        find.text('No se pudo entrar con tu cuenta de Procovar.'),
        findsOneWidget,
      );
      expect(
        find.text(EntradaPorAccesos.textoDelMotivo('nodisponible')),
        findsOneWidget,
        reason: 'el motivo literal, que es lo que dice a quien avisar',
      );
      expect(find.text('Volver a intentarlo'), findsOneWidget);
      // LA PUERTA DE RESPALDO. Si Accesos esta caido, la oficina tiene que poder
      // repartir igual: aqui es donde esto se separa del patron de Next, que
      // solo ofrece volver a intentarlo.
      expect(find.text('Contraseña'), findsOneWidget);
      await desmontar(tester);
    });

    testWidgets('en APARATO ese aviso no existe: alli no hay login unico', (
      tester,
    ) async {
      final navegador = await montar(
        tester,
        enWeb: false,
        apiMe: sinSesionDeAccesos,
        direccion: 'https://ejemplo.test/acceso?sso=nodisponible',
      );

      expect(navegador.ultimo, isNull);
      expect(
        find.text('No se pudo entrar con tu cuenta de Procovar.'),
        findsNothing,
        reason:
            'contarle a quien entra en un telefono que el login unico fallo es '
            'explicarle algo que en su caso no pasa nunca',
      );
      expect(find.text('Contraseña'), findsOneWidget);
      await desmontar(tester);
    });
  });

  // ---------------------------------------------------------------------------
  // 4 · SALIR
  // ---------------------------------------------------------------------------

  group('4 · cerrar sesion', () {
    test('en WEB pasa por el servidor, que es el unico que borra la cookie', () async {
      // El JavaScript de la pagina no puede leer ni borrar una cookie
      // `httpOnly`. Sin esto, quien pulsaba «cerrar sesion» volvia a entrar sin
      // mas y creia que habia salido — y eso importa justo en el ordenador
      // compartido, que es donde se le da al boton.
      final navegador = NavegadorFalso();
      final almacen = AlmacenEnMemoria(sesionDePrueba());
      final servicio = ServicioDeAcceso(
        auth: dioFalso((p) async => RespuestaFalsa(200)),
        almacen: almacen,
        porAccesos: entradaFalsa(navegador, (p) async => null),
      );

      await servicio.salir(
        Sesion.deLaCookie(token: tokenDePrueba(), usuario: const {'id': 'u-1'}),
      );

      expect(navegador.ultimo, '$baseApiDePrueba/auth/logout');
      expect(
        await almacen.leer(),
        isNull,
        reason: 'y lo guardado tambien se va: es la otra mitad del cierre',
      );
    });

    test('en APARATO se revoca el par y NO se va a ningun navegador', () async {
      final navegador = NavegadorFalso();
      final vistas = <PeticionVista>[];
      final almacen = AlmacenEnMemoria(sesionDePrueba());
      final servicio = ServicioDeAcceso(
        auth: dioFalso((p) async {
          vistas.add(p);
          return RespuestaFalsa(200);
        }),
        almacen: almacen,
        // `null`, que es lo que le pasa el cableado fuera de la web.
        porAccesos: null,
      );

      await servicio.salir(sesionDePrueba(refresh: 'refresh-viejo'));

      expect(vistas.map((p) => p.ruta), contains('/logout'));
      expect(navegador.ultimo, isNull);
      expect(await almacen.leer(), isNull);
    });
  });
}
