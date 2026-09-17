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
Stream<String> escucharEventos(String urlBase) {
  final control = StreamController<String>();
  web.EventSource? fuente;

  control.onListen = () {
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
      // `EventSource` reconecta solo. Esto se anota y ya: cerrar el stream aqui
      // dejaria la pantalla sin canal para siempre por un corte de dos segundos.
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
