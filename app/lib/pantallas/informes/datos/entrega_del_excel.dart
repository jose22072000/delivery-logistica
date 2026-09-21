// ENTREGAR EL FICHERO. **Los tres destinos no entregan igual, y eso es la
// regla, no un detalle de implementacion** (CLAUDE.md §1).
//
//  * **APK de Android** — no hay «carpeta de descargas» a la que mandar a
//    nadie. El fichero se escribe donde la aplicacion puede escribir y se saca
//    el cajon de compartir del sistema: WhatsApp, Telegram, correo, Archivos.
//    Es lo que de verdad pasa en el patio de un almacen.
//  * **Escritorio (Linux, Windows)** — se GUARDA, en la carpeta de descargas
//    de la persona, y se dice donde. Compartir ficheros no existe en Linux:
//    `share_plus` lanza `UnimplementedError('Sharing files not supported on
//    Linux')` a la cara (`share_plus_linux.dart`). Por eso el fichero se
//    escribe PRIMERO y compartir es lo de despues: si el cajon no sale, el
//    Excel ya esta en el disco y se dice su ruta.
//  * **Web** — lo descarga el navegador, que es lo unico que un navegador sabe
//    hacer con un fichero. Ni carpeta, ni cajon, ni ruta que enseñar.
//
// ## Por que una interfaz y no llamar al sistema desde el boton
//
// Por lo mismo que `rutas/datos/abrir_y_compartir.dart`: escribir en disco y
// sacar el cajon de compartir hablan con el sistema operativo, y dentro de un
// `flutter test` no hay sistema operativo. Sin costura, el unico boton nuevo de
// esta pantalla se queda sin una sola prueba — y lo que falla es el Excel de
// quien cuadra caja, a cien kilometros de aqui.
//
// ## Por que devuelve un resultado con mensaje y no `void`
//
// Regla 4: nada falla en silencio. Un `void` obliga a dar por bueno lo que no
// se sabe. Aqui vuelve **lo que se le va a decir a la persona**, con el motivo
// literal cuando no se pudo — «No se pudo guardar» no le dice a nadie que
// hacer; «no hay espacio en el disco» si.

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'entrega_en_el_aparato.dart'
    if (dart.library.js_interop) 'entrega_en_el_navegador.dart'
    as destino;

/// Como acabo el intento de entregar el fichero.
class Entregado {
  const Entregado.hecho(this.mensaje) : salioBien = true;

  /// [mensaje] lleva el motivo LITERAL, no un «no se pudo» a secas.
  const Entregado.noSePudo(this.mensaje) : salioBien = false;

  final bool salioBien;

  /// Lo que se le enseña a la persona. Nunca vacio.
  final String mensaje;
}

/// La costura con el aparato.
abstract interface class EntregaDeFichero {
  /// Pone [bytes] en manos de quien lo pidio, con el nombre [nombre].
  ///
  /// **No lanza**: un fallo vuelve como [Entregado.noSePudo] con su motivo.
  Future<Entregado> entregar({
    required Uint8List bytes,
    required String nombre,
    required String tipoMime,
  });
}

/// Por Riverpod, para que una prueba lo cambie con `overrideWithValue` y lea
/// exactamente los bytes y el nombre que se le entregaron.
final entregaDeFicheroProvider = Provider<EntregaDeFichero>(
  (ref) => destino.crearEntrega(),
);
