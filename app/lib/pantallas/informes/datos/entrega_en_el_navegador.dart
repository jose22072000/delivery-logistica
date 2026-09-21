// LA WEB: lo descarga el navegador.
//
// Aqui no hay ni carpeta que elegir ni cajon que sacar: un navegador entrega un
// fichero de una sola forma, un `Blob` con su enlace y un clic. Donde acabe el
// fichero lo decide el navegador, asi que **no se le promete a nadie una ruta**
// —decir «guardado en Descargas» seria adivinar—: se dice que se descargo, con
// su nombre, que es lo que la persona va a buscar.
//
// `package:web` y no `dart:html`, como todo lo de este proyecto.

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../../nucleo/registro/registro.dart';
import 'entrega_del_excel.dart';

EntregaDeFichero crearEntrega() => const EntregaEnElNavegador();

class EntregaEnElNavegador implements EntregaDeFichero {
  const EntregaEnElNavegador();

  @override
  Future<Entregado> entregar({
    required Uint8List bytes,
    required String nombre,
    required String tipoMime,
  }) async {
    String? url;
    try {
      final blob = web.Blob(
        <JSAny>[bytes.toJS].toJS,
        web.BlobPropertyBag(type: tipoMime),
      );
      url = web.URL.createObjectURL(blob);
      final enlace = web.document.createElement('a') as web.HTMLAnchorElement
        ..href = url
        ..download = nombre
        // Fuera de la vista: es un enlace de usar y tirar, no algo que
        // tenga que salir en la pagina.
        ..style.display = 'none';
      web.document.body?.appendChild(enlace);
      enlace.click();
      enlace.remove();
      return Entregado.hecho('Se descargó $nombre');
    } on Object catch (e) {
      Registro.fallo('el navegador no dejo descargar $nombre: $e');
      return Entregado.noSePudo('El navegador no pudo descargar el Excel: $e');
    } finally {
      if (url != null) _soltarMasTarde(url);
    }
  }

  /// Suelta el `Blob`, **pero no en el mismo instante del clic**.
  ///
  /// Se suelta porque un `createObjectURL` sin soltar deja los bytes del libro
  /// en memoria hasta que se recargue la pagina, y esta pantalla se usa muchas
  /// veces seguidas. Y se espera porque en Firefox y en Safari la descarga
  /// arranca DESPUES del clic: soltar la URL a la vez la cancela, y lo que se
  /// ve es un boton que no hace nada.
  void _soltarMasTarde(String url) {
    Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
  }
}
