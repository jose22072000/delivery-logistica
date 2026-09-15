import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/acceso/vista/pantalla_acceso.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

void main() {
  late AlmacenEnMemoria almacen;

  setUp(() => almacen = AlmacenEnMemoria());

  /// Monta la pantalla suelta. El `Scaffold` lo pone aqui porque en la
  /// aplicacion lo pone el enrutador: la pantalla no lleva el suyo.
  Future<ProviderContainer> montar(
    WidgetTester tester,
    Future<RespuestaFalsa?> Function(PeticionVista) auth, {
    bool yaConfigurado = true,
  }) async {
    final base = baseDePrueba();
    addTearDown(base.close);
    // Por defecto, el aparato YA tiene sus datos: estas pruebas van de la
    // puerta, no de la primera configuracion. Con el aparato vacio el portero
    // se queda —correctamente— en «Configurando Reparto», y eso tiene su propia
    // prueba en `widget_test.dart`.
    if (yaConfigurado) await aparatoYaConfigurado(base);

    final contenedor = ProviderContainer(
      overrides: [
        baseProvider.overrideWithValue(base),
        almacenSesionProvider.overrideWithValue(almacen),
        dioAuthProvider.overrideWithValue(dioFalso(auth)),
        // La bajada del dia se dispara sola al entrar: contra el servidor falso
        // y sin esperas, para que no quede un temporizador colgado.
        clienteApiProvider.overrideWithValue(
          clienteFalso(
            (p) async => RespuestaFalsa(200, <String, Object?>{
              'hasta': '2026-09-15T08:00:00Z',
              'completa': true,
              'cambios': <String, Object?>{},
              'truncado': false,
              'sucursales': <Object?>[],
            }),
          ),
        ),
      ],
    );
    addTearDown(contenedor.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: contenedor,
        child: const MaterialApp(home: Scaffold(body: PantallaAcceso())),
      ),
    );
    return contenedor;
  }

  Future<void> escribirYEntrar(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).first, 'yasmani');
    await tester.enterText(find.byType(TextFormField).last, 'la-buena');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
  }

  testWidgets('pide usuario y contrasena, y no manda nada vacio', (
    tester,
  ) async {
    var peticiones = 0;
    await montar(tester, (p) async {
      peticiones++;
      return RespuestaFalsa(200, parDeTokens());
    });

    expect(find.text('Usuario o correo'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);

    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Escribe tu usuario.'), findsOneWidget);
    expect(find.text('Escribe tu contraseña.'), findsOneWidget);
    expect(peticiones, 0, reason: 'un formulario vacio no sale a la red');
  });

  testWidgets('entrando bien: se guarda el par y el portero deja pasar', (
    tester,
  ) async {
    late PeticionVista laPeticion;
    final contenedor = await montar(tester, (p) async {
      laPeticion = p;
      return RespuestaFalsa(200, parDeTokens(refresh: 'refresh-nuevo'));
    });

    await escribirYEntrar(tester);

    expect(laPeticion.ruta, '/token');
    expect((laPeticion.cuerpo! as Map)['identifier'], 'yasmani');

    // El par, guardado. `refresh_token` de la respuesta es el `refresh` de la
    // sesion: si esto se rompiera, la renovacion presentaria un token vacio y el
    // servidor lo leeria como robo.
    final guardada = await almacen.leer();
    expect(guardada, isNotNull);
    expect(guardada!.refresh, 'refresh-nuevo');
    expect(guardada.sucursalId, 'STG', reason: 'sale del token, no del cuerpo');

    expect(contenedor.read(porteroProvider).estado, EstadoDeAcceso.dentro);
  });

  testWidgets(
    'un aparato que NO puede guardar la sesion lo dice ANTES de la contrasena',
    (tester) async {
      // La promesa de debajo del boton —«una vez dentro puedes seguir
      // trabajando el dia entero sin senal»— solo es verdad si el aparato
      // guarda. El 15/09/2026 no la cumplia y no lo decia: la aplicacion
      // aterrizaba en este mismo formulario, mudo. O se cumple, o no se promete.
      almacen = AlmacenEnMemoria.queNoGuarda(
        'Este aparato no tiene dónde guardar la sesión.',
      );
      await montar(tester, (p) async => RespuestaFalsa(200, parDeTokens()));
      await tester.pumpAndSettle();

      expect(
        find.text('Este aparato no tiene dónde guardar la sesión.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('hará falta cada vez que abras la aplicación'),
        findsOneWidget,
      );
      expect(
        find.textContaining('puedes seguir trabajando el día entero sin señal'),
        findsNothing,
        reason: 'la promesa que no se cumple no se escribe',
      );
    },
  );

  testWidgets('entrar en un aparato que no guarda NO deja pasar en silencio', (
    tester,
  ) async {
    almacen = AlmacenEnMemoria.queNoGuarda();
    final contenedor = await montar(
      tester,
      (p) async => RespuestaFalsa(200, parDeTokens()),
    );

    await escribirYEntrar(tester);

    // Se queda en la puerta con el aviso puesto. Entrar aqui seria dejar a
    // alguien irse al almacen creyendo que manana abre la aplicacion y sigue
    // dentro.
    expect(
      contenedor.read(porteroProvider).estado,
      isNot(EstadoDeAcceso.dentro),
    );
    expect(find.byType(PantallaAcceso), findsOneWidget);
  });

  testWidgets('contrasena mal: se dice, y no se guarda nada', (tester) async {
    await montar(
      tester,
      (p) async => RespuestaFalsa(401, <String, Object?>{
        'error': 'invalid_credentials',
      }),
    );

    await escribirYEntrar(tester);

    expect(find.text('Usuario o contraseña incorrectos.'), findsOneWidget);
    expect(await almacen.leer(), isNull);
  });

  testWidgets('el 403 sin_sucursal se explica, y NO como un fallo tecnico', (
    tester,
  ) async {
    await montar(
      tester,
      (p) async => RespuestaFalsa(403, <String, Object?>{
        'error': 'sin_sucursal',
        'message':
            'La cuenta no está dada de alta en ninguna sucursal, o la '
            'sucursal pedida no es suya.',
      }),
    );

    await escribirYEntrar(tester);

    // El mensaje LITERAL del servidor, mas lo que hay que hacer. Lo segundo es
    // lo que distingue «llama a la oficina» de «vuelve a probar la contrasena».
    expect(
      find.textContaining('no está dada de alta en ninguna sucursal'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Pide en la oficina que te den de alta'),
      findsOneWidget,
    );
  });

  testWidgets('un 403 que NO es de auth no se cuenta como cuenta de baja', (
    tester,
  ) async {
    // Cloudflare contesta 403 con «error code: 1010» y sin JSON. Decirle a
    // alguien que su cuenta esta dada de baja por eso es mandarlo a la oficina a
    // preguntar por algo que no existe.
    await montar(tester, (p) async => RespuestaFalsa(403, 'error code: 1010'));

    await escribirYEntrar(tester);

    expect(
      find.textContaining('no dejó pasar la petición (403)'),
      findsOneWidget,
    );
    expect(find.textContaining('dada de baja'), findsNothing);
  });

  testWidgets('sin red: se dice que para entrar hace falta conexion', (
    tester,
  ) async {
    await montar(tester, (p) async => null); // la peticion ni sale

    await escribirYEntrar(tester);

    expect(find.textContaining('Sin conexión con el servidor'), findsOneWidget);
    expect(
      find.textContaining('Lo que ya estaba descargado sigue en el aparato'),
      findsOneWidget,
    );
  });
}
