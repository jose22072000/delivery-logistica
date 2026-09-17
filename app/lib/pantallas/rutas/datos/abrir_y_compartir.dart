// LOS TRES GESTOS QUE SALEN DE LA APLICACION: abrir un enlace, compartirlo y
// copiarlo.
//
// ## Por que una interfaz y no llamar a `launchUrl` desde el boton
//
// Porque si no, no hay forma de comprobar que el boton manda **lo que toca**.
// `launchUrl` y `SharePlus` hablan con el sistema operativo: dentro de un
// `flutter test` no hay sistema operativo, asi que o se pone una costura o esos
// botones se quedan sin una sola prueba — y un boton que manda mal el enlace
// falla en el telefono del chofer, a cien kilometros de aqui, y vuelve como «no
// me sale el mapa».
//
// Con esto, la prueba mete un [AbrirYCompartir] de mentira, pulsa, y **lee la
// cadena exacta** que se le entrego.
//
// ## Por que devuelven `bool` y no `void`
//
// Regla 4: si algo falla, la pantalla no se queda verde. Quien llama tiene que
// poder decir «no se pudo abrir Google Maps» con su motivo a la vista. Un
// `void` obliga a dar por bueno lo que no se sabe.
//
// ## Que necesita señal y que no
//
// Ninguno de los tres la necesita para **dispararse**: el cajon de compartir de
// Android sale sin datos, y copiar al portapapeles tampoco pide nada. Lo que
// necesita señal es lo que pasa DESPUES —Google Maps tiene que bajar el mapa,
// WhatsApp tiene que mandar el mensaje—, y eso ya no es de esta aplicacion. Por
// eso aqui no se pregunta por la conexion: preguntar seria adivinar, y
// `connectivity_plus` es una pista, nunca la verdad (`nucleo/red/salud.dart`).

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../nucleo/registro/registro.dart';

/// La costura con el aparato.
abstract interface class AbrirYCompartir {
  /// Abre [destino] fuera de la aplicacion. `false` = no se pudo.
  Future<bool> abrir(Uri destino);

  /// Saca el cajon de compartir del sistema. `false` = no se pudo sacar.
  Future<bool> compartir({required String texto, String? asunto});

  /// Deja [texto] en el portapapeles. `false` = no se pudo.
  Future<bool> copiar(String texto);
}

/// La de verdad: `url_launcher` y `share_plus`.
class ElAparato implements AbrirYCompartir {
  const ElAparato();

  @override
  Future<bool> abrir(Uri destino) async {
    try {
      // `externalApplication` y no `platformDefault`: en Android eso es lo que
      // hace que un enlace de `google.com/maps/dir` lo coja **la aplicacion de
      // Google Maps** en vez de una pestana del navegador. Es la diferencia
      // entre empezar a navegar y quedarse mirando un mapa.
      return await launchUrl(destino, mode: LaunchMode.externalApplication);
    } on Object catch (e) {
      Registro.aviso('no se pudo abrir $destino: $e');
      return false;
    }
  }

  @override
  Future<bool> compartir({required String texto, String? asunto}) async {
    try {
      // El resultado NO se mira para decidir si salio bien. `unavailable` no es
      // un fallo: significa «se compartio pero el sistema no cuenta que eligio
      // la persona», que es lo normal en Android. Y `dismissed` es que se
      // arrepintio, que tampoco es un fallo. Lo unico que es un fallo aqui es
      // que esto lance.
      await SharePlus.instance.share(ShareParams(text: texto, subject: asunto));
      return true;
    } on Object catch (e) {
      Registro.aviso('no se pudo compartir: $e');
      return false;
    }
  }

  @override
  Future<bool> copiar(String texto) async {
    try {
      await Clipboard.setData(ClipboardData(text: texto));
      return true;
    } on Object catch (e) {
      Registro.aviso('no se pudo copiar: $e');
      return false;
    }
  }
}

/// Por Riverpod, para que una prueba lo cambie con `overrideWithValue`.
final abrirYCompartirProvider = Provider<AbrirYCompartir>(
  (ref) => const ElAparato(),
);
