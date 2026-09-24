import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/arranque/arranque.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/entrada_por_accesos.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';

import 'apoyo/apoyo_accesos.dart';
import 'apoyo/apoyo_sesion.dart';
import 'apoyo/base_de_prueba.dart';
import 'apoyo/servidor_falso.dart';

/// UNA SESIÓN VIEJA EN `localStorage` NO PUEDE MATAR LA WEB, Y MENOS EN VERDE.
///
/// ## Lo que se vio en el navegador, con la cookie de Accesos VÁLIDA puesta
///
/// ```
/// [ 980ms] ERROR  POST  {AUTH_URL}/api/auth/refresh  -> ERR_CONNECTION_REFUSED
/// [1307ms] ERROR  GET   /api/eventos                 -> 401
/// [1377ms] ERROR  GET   /api/sync/cambios            -> 401
/// … y así cada 10 s, para siempre
/// ```
///
/// **Ni una sola llamada a `/api/me`.** Pedidos en «Cargando los pedidos…» para
/// siempre, la barra superior con una identidad fantasma y ningún error en
/// pantalla. Borrando el `localStorage` y recargando, todo al instante.
///
/// La cadena era ésta: `arrancar` miraba el almacén ANTES que la cookie, así que
/// un `reparto.sesion` viejo ganaba sobre una cookie buena; `renovar` fallaba
/// con un error de **red** y no con un 401, así que se caía en
/// [Arranque.dentroSinComprobar] —que es la regla del APARATO, «con sesión
/// guardada se entra»— y la web se quedaba dentro con un token muerto.
///
/// ## Las dos mitades, y las dos son §1
///
///  1. **La cookie manda.** En un navegador siempre se le puede preguntar al
///     servidor quién eres; el par guardado es el respaldo para cuando no hay
///     cookie, no al revés.
///  2. **En la web no existe «entrar sin comprobar».** Esa regla es del teléfono
///     que se va al patio de un almacén. Si aquí no se puede comprobar, se va a
///     la puerta.
///
/// Y la pareja obligatoria: **en la APK la regla del aparato sigue intacta**.
/// Sin esa mitad, «arreglar» esto mandando a todo el mundo a la puerta rompería
/// justo la razón de ser del proyecto.
void main() {
  late BaseLocal base;

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  /// El arranque de verdad, en el destino que se pida.
  ///
  /// [refreshVaMal] es el `ERR_CONNECTION_REFUSED` del informe: `auth` no
  /// contesta, así que renovar falla **por red**, no con un 401.
  ProviderContainer montar({
    required bool enWeb,
    Sesion? guardada,
    required Future<RespuestaFalsa?> Function(PeticionVista) apiMe,
    bool refreshVaMal = true,
  }) {
    final almacen = AlmacenEnMemoria(guardada);
    final caja = ProviderContainer.test(
      overrides: [
        trabajaSinConexionProvider.overrideWithValue(!enWeb),
        navegadorProvider.overrideWithValue(NavegadorFalso()),
        entradaPorAccesosProvider.overrideWithValue(
          entradaFalsa(NavegadorFalso(), apiMe),
        ),
        almacenSesionProvider.overrideWithValue(almacen),
        baseProvider.overrideWithValue(base),
        relojProvider.overrideWithValue(() => DateTime(2026, 9, 24, 8, 30)),
        dioAuthProvider.overrideWithValue(
          dioFalso(
            (p) async => refreshVaMal
                ? throw DioException.connectionError(
                    requestOptions: RequestOptions(),
                    reason: 'ERR_CONNECTION_REFUSED',
                  )
                : RespuestaFalsa(200, parDeTokens()),
          ),
        ),
      ],
    );
    addTearDown(caja.dispose);
    return caja;
  }

  /// Un `/api/me` que reconoce la cookie.
  Future<RespuestaFalsa?> laCookieVale(PeticionVista p) async =>
      RespuestaFalsa(200, respuestaDeApiMe(token: tokenDePrueba()));

  /// Un `/api/me` que dice que no hay cookie ninguna.
  Future<RespuestaFalsa?> sinCookie(PeticionVista p) async =>
      RespuestaFalsa(401, const <String, Object?>{});

  /// El par viejo de `localStorage`: de una prueba, o de la puerta de respaldo
  /// de hace un mes. Ya no vale para nada.
  const parViejo = Sesion(
    token: 't-muerto',
    refresh: 'r-muerto',
    sub: 'u-de-hace-un-mes',
  );

  // ---------------------------------------------------------------------------
  group('la web', () {
    test('con la cookie VÁLIDA y un par viejo guardado, manda la cookie — y el '
        'par se borra', () async {
      final caja = montar(enWeb: true, guardada: parViejo, apiMe: laCookieVale);

      final resultado = await arrancar(caja.read(_refProvider));

      expect(
        resultado.como,
        Arranque.dentro,
        reason:
            'la cookie es lo que el servidor reconoce. Con el par viejo '
            'mandando, la web se quedaba dentro con un token muerto y todo '
            'contestaba 401 sin decir una palabra',
      );
      expect(
        resultado.sesion?.sub,
        isNot('u-de-hace-un-mes'),
        reason: 'y se entra como quien dice la cookie, no como el par viejo',
      );
      expect(
        await caja.read(almacenSesionProvider).leer(),
        isNull,
        reason:
            'el par se BORRA. Si se queda, la carga siguiente vuelve a '
            'preferirlo y el ciclo sigue pidiendo `/api/auth/refresh` desde el '
            'navegador cada pocos minutos contra un par que no vale',
      );
    });

    test('con un par que no se puede comprobar y SIN cookie: a la puerta, no '
        'dentro a ciegas', () async {
      final caja = montar(enWeb: true, guardada: parViejo, apiMe: sinCookie);

      final resultado = await arrancar(caja.read(_refProvider));

      expect(
        resultado.como,
        Arranque.fuera,
        reason:
            '«con sesión guardada se entra aunque no se pueda comprobar» es la '
            'regla del APARATO: existe para el logístico que sale del almacén '
            'sin cobertura. En un navegador no hay nada que preparar y sí hay '
            '`/api/me` ahí mismo (§1)',
      );
      expect(
        await caja.read(almacenSesionProvider).leer(),
        isNull,
        reason: 'y sin borrarlo, la carga siguiente repite el intento entero',
      );
    });
  });

  // ---------------------------------------------------------------------------
  group('la APK, que es el otro mundo y no se toca', () {
    test('sin red al arrancar SE ENTRA con lo guardado, y el par se queda',
        () async {
      final caja = montar(
        enWeb: false,
        guardada: parViejo,
        // En el aparato esto no se llama nunca: si se llamara, la prueba lo
        // diría con un fallo aquí dentro.
        apiMe: (p) async => throw StateError('la APK no pregunta por la cookie'),
      );

      final resultado = await arrancar(caja.read(_refProvider));

      expect(
        resultado.como,
        Arranque.dentroSinComprobar,
        reason:
            'la regla de Jose, que manda: «para entrar hace falta conexión; '
            'una vez dentro, no». Mandar a esta persona a la puerta es '
            'mandarla a una pantalla que sin servidor tampoco funciona, con el '
            'trabajo del día dentro del teléfono',
      );
      expect(
        (await caja.read(almacenSesionProvider).leer())?.sub,
        'u-de-hace-un-mes',
        reason: 'y su par sigue entero: un fallo de red no mata una sesión',
      );
    });

    test('con red, se renueva y se entra como siempre', () async {
      final caja = montar(
        enWeb: false,
        guardada: parViejo,
        apiMe: (p) async => throw StateError('la APK no pregunta por la cookie'),
        refreshVaMal: false,
      );

      final resultado = await arrancar(caja.read(_refProvider));

      expect(resultado.como, Arranque.dentro);
    });
  });
}

/// Un `Ref` prestado del contenedor: `arrancar` lo pide, y así la prueba corre
/// el arranque de verdad en vez de una copia suya.
final _refProvider = Provider<Ref>((ref) => ref);
