import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../registro/registro.dart';

/// EL CANAL EN VIVO DE LA WEB, por `EventSource`.
///
/// Se usa el del navegador y no una lectura en streaming a mano porque **el
/// navegador ya sabe reconectar**: si la conexion se cae, vuelve a abrirla sola
/// con su espera creciente. Escribir eso a mano es reescribir algo que ya
/// funciona, y peor.
///
/// `withCredentials` va puesto: en la web la sesion es la cookie del acceso
/// unico, no un token guardado (`docs/identidad.md`). Sin eso el servidor
/// contesta 401 y el canal no abre.
Stream<String> escucharEventos(
  String urlBase,
  Future<String?> Function() token,
) {
  final control = StreamController<String>();
  web.EventSource? fuente;

  control.onListen = () async {
    // EL TOKEN VA POR COOKIE, no por la direccion.
    //
    // `EventSource` no sabe mandar cabeceras, asi que no hay `Authorization`
    // posible. Quedaban dos formas y esta es la buena: el token en la URL
    // (`?token=…`) acaba escrito en el registro del servidor, en el del proxy y
    // en el historial del navegador, y ahi se queda; la cookie no sale en
    // ninguno de los tres.
    //
    // No es exposicion nueva: en la web el token ya vive en `localStorage`, o sea
    // que el JavaScript de esta pagina ya lo tiene. `SameSite=Strict` para que no
    // viaje desde otro sitio, y `Secure` porque esto sirve por https.
    //
    // Se llama `token` porque es el nombre que ya lee `auth.DelaPeticion` del
    // reparto — la misma puerta que usan la APK y la web, sin inventar otra.
    final t = await token();
    if (t == null || t.isEmpty) {
      Registro.info('canal de eventos: sin sesión todavía, no se abre');
      unawaited(control.close());
      return;
    }
    web.document.cookie =
        'token=$t; Path=/; Secure; SameSite=Strict';

    try {
      fuente = web.EventSource(
        '$urlBase/eventos',
        web.EventSourceInit(withCredentials: true),
      );
    } on Object catch (e) {
      // Que el canal no abra NO puede dejar a nadie sin sincronizar: queda el
      // temporizador, que es lo que habia antes de esto.
      Registro.aviso('no se pudo abrir el canal de eventos: $e');
      unawaited(control.close());
      return;
    }

    // El `cambio` es el unico que le dice algo a una pantalla. El `listo` del
    // principio y los latidos son del transporte: sirven para que el navegador
    // de la conexion por abierta y para que un proxy no la cierre por callada,
    // y no se reenvian.
    fuente!.addEventListener(
      'cambio',
      (web.Event e) {
        final datos = (e as web.MessageEvent).data.dartify();
        control.add(_tipoDe(datos));
      }.toJS,
    );

    fuente!.onerror = (web.Event _) {
      // ## Hay DOS errores distintos y se parecen en nada
      //
      // Un corte de red: `readyState` queda en `CONNECTING` y **el navegador
      // reconecta solo**, con su espera creciente. Ahi no hay nada que hacer.
      //
      // Un 401, o un `Content-Type` que no es `text/event-stream`: por la
      // especificacion de HTML el navegador hace *fail the connection* —
      // `readyState` pasa a `CLOSED` y **no reintenta nunca mas**. Sin
      // distinguirlo, el `StreamController` se quedaba abierto y muerto: no
      // emitia, no cerraba, nadie se enteraba, y la aplicacion caia al
      // temporizador en silencio. El comentario decia que reconectaba solo, y
      // para ese caso era mentira.
      if (fuente?.readyState == web.EventSource.CLOSED) {
        Registro.aviso(
          'canal de eventos cerrado por el navegador (401 o cabecera mala): se '
          'sigue con el temporizador',
        );
        unawaited(control.close());
        return;
      }
      Registro.info('canal de eventos: corte, el navegador reconecta solo');
    }.toJS;
  };

  control.onCancel = () {
    fuente?.close();
    fuente = null;
  };

  return control.stream;
}

bool get hayCanalDeEventos => true;

/// El tipo que viene dentro del `data`. Si no se entiende, se devuelve vacio y
/// quien escuche decidira —un aviso raro no puede tumbar la pantalla—.
String _tipoDe(Object? datos) {
  if (datos is! String) return '';
  try {
    final m = jsonDecode(datos);
    if (m is Map && m['tipo'] is String) return m['tipo'] as String;
  } on Object {
    // Un cuerpo que no es JSON es un aviso perdido, no un fallo.
  }
  return '';
}
