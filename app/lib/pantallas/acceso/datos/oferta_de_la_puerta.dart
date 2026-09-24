import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/actualizacion/comprobador.dart';
import '../../../nucleo/actualizacion/version_publicada.dart';
import '../../../nucleo/proveedores.dart';
import '../../../nucleo/registro/registro.dart';

/// LAS DOS SALIDAS DE LA PUERTA: bajarse la aplicacion, e irse al portal.
///
/// Jose, 24/09/2026:
///
/// > «recuerda q tienes q poner en el login q puedan descargar la aplicacion y
/// > entrar a procovar.cloud […] recuerda q se pueden hacer las dos, para q
/// > puedan descargar la apk y instalarla»
///
/// ## QUIEN LAS VE, Y POR QUE NO LAS VEN LOS TRES (`CLAUDE.md` §1)
///
/// Son tres formas de la misma aplicacion y no se comportan igual. Aqui se nota
/// entero, porque la pregunta que contesta cada salida **sale de estar en un
/// navegador**:
///
///  * **La web SI, las dos.** Quien abre `reparto.procovar.cloud` en el
///    telefono es exactamente quien puede querer el APK, y quien esta en un
///    navegador esta a un clic del portal. Es el unico destino donde la
///    aplicacion NO esta instalada.
///  * **La APK NO, ninguna.** Ofrecerle bajarse el APK a quien ya lo tiene
///    abierto es el ejemplo de manual de lo que prohibe la §1. De la version
///    nueva ya se encarga otra cosa —`navegacion/aviso_de_version_nueva.dart`—
///    y esa si sabe que no se actualiza con cola pendiente. Y el portal son las
///    demas aplicaciones **web** de la casa: mandar a un navegador externo a
///    quien esta en la puerta de la unica aplicacion que trabaja sin senal es
///    sacarlo de lo unico que le va a funcionar en el patio de un almacen.
///  * **El escritorio NO, ninguna — decidido el 24/09/2026 y escrito aqui.**
///    Es el destino que no se decide solo, asi que se razona:
///      1. Lo que se ofrece es el APK de **Android**, que un Windows o un Linux
///         no puede instalar. Seria un boton de ~77 MB que no lleva a ninguna
///         parte, o sea justo lo que `CLAUDE.md` §4 llama descartar en
///         silencio, pero al reves: gastar la tarde de datos de alguien para
///         nada.
///      2. Y el paquete de escritorio tampoco se ofrece: alli la aplicacion ya
///         esta instalada, que es el mismo caso que la APK.
///      3. El portal, en escritorio, es abrir el navegador que esa persona
///         tiene al lado. No hace falta un boton en la puerta para eso, y en la
///         puerta de una aplicacion que trabaja sin senal sobra igual que en la
///         APK.
///
/// La linea que las separa es `Destino.trabajaSinConexion`
/// (`nucleo/plataforma.dart`): `false` **solo** en la web. La pantalla la lee
/// por provider, asi que la pareja de pruebas —sale en la web / no sale en el
/// aparato— se escribe sin compilar para web. El molde es
/// `test/la_web_no_se_prepara_test.dart`.
///
/// ## DE DONDE SALE LA URL: DEL ANUNCIO, NUNCA ESCRITA A MANO
///
/// `GET /api/version` ya dice que hay colgado y de donde se baja
/// (`docs/actualizaciones.md` §2). Escribir aqui un
/// `https://archivos.procovar.cloud/…` seria una direccion que caduca el dia
/// que se publique la siguiente version, y nadie se enteraria hasta que
/// alguien pulsara y no bajara nada.
///
/// Se reusa entero lo que ya existe: `VersionPublicada.deJson`,
/// `descargaPara(Plataforma.android)` y `ficheroPara(Plataforma.android)`.
///
/// **`Plataforma.android` fija, y no `Plataforma.deEsteAparato()`**: en la web
/// eso devuelve `ninguna` a proposito (la web no se instala), asi que preguntar
/// por este aparato dejaria la puerta sin descarga siempre. Lo que se ofrece en
/// la puerta de la web es el telefono de quien mira, no el cacharro desde el que
/// mira.
///
/// ## SI NO HAY ANUNCIO, NO SE PINTA UN ENLACE ROTO
///
/// Devuelve `null` —y la puerta entonces no ensena boton de descarga— en los
/// cuatro casos en los que no hay nada bueno que ofrecer:
///
///  1. no hubo red o el servidor no contesto;
///  2. `ultima` es `null`, que es lo normal mientras no haya nada colgado;
///  3. hay version pero `descargas` no trae `android`;
///  4. el cuerpo vino raro (un proxy por medio, por ejemplo).
///
/// No se pinta un boton apagado ni un «ahora mismo no se puede»: nadie llego a
/// esta pantalla a descargarse nada, llego a entrar a trabajar. Un cartel que
/// explica que algo que no habias pedido no esta disponible es ruido en la
/// puerta. El enlace del portal, que no depende de la api, se queda igual.
@immutable
class OfertaDeLaPuerta {
  const OfertaDeLaPuerta({
    required this.version,
    required this.enlace,
    this.bytes,
  });

  /// La version que hay colgada. Se ensena para que quien ya tenga una instalada
  /// sepa si esto le aporta algo.
  final String version;

  /// De donde se baja el APK. Sale de `descargas.android` del anuncio.
  final String enlace;

  /// CUANTO PESA, o `null` si el anuncio no lo dijo.
  ///
  /// Son ~77 MB. Con la conexion de alla, pulsar sin saberlo es la tarde de
  /// datos de alguien, y por eso el tamano va **en el boton** y no en la letra
  /// pequena de debajo. Sale del anuncio (`ficheros.android.bytes`) y no del
  /// `Content-Length`: Cloudflare lo quita de la respuesta completa, y el
  /// 22/09/2026 eso enseno «30 MB/?» a la hora de actualizar
  /// (`version_publicada.dart`, `FicheroPublicado`).
  final int? bytes;
}

/// EL PORTAL DE PROCOVAR: la entrada comun a todo lo demas.
///
/// No vive en `nucleo/red/entorno.dart` con las otras tres a proposito. Alli
/// estan los **servicios con los que esta aplicacion habla** —`api`, `sync`,
/// `auth`—, y a este no se le pide nada nunca: es una direccion que una persona
/// pulsa. Meterlo alli invitaria a que alguien le mandara una peticion.
///
/// La direccion es la que la propia api publica como Portal en `GET /api/apps`
/// («La entrada comun a todo lo demas», `docs/contratos-api.md`). No se lee de
/// ahi porque esa ruta pide sesion, y aqui todavia no hay ninguna — que es
/// justo el momento en el que hace falta el enlace.
///
/// Se puede cambiar en la compilacion, como las otras, para no dejar una
/// direccion de produccion clavada en el codigo.
const enlaceDelPortal = String.fromEnvironment(
  'PORTAL_URL',
  defaultValue: 'https://procovar.cloud',
);

/// QUE SE PUEDE OFRECER EN LA PUERTA, segun lo que anuncie el servidor.
///
/// `null` cuando no hay nada que ofrecer. Ver arriba los cuatro casos.
///
/// **No mira el destino.** La decision de si esto se ensena o no es de la
/// pantalla (`pantalla_acceso.dart`), y esta en un solo `if` a proposito: si la
/// decision estuviera tambien aqui, romper la de alla no rompería nada —las dos
/// callarian— y la pareja de pruebas dejaria de comprobar la linea. Como la
/// pantalla solo mira este provider en la web, en la APK y en el escritorio esto
/// no llega a construirse y **no sale ni una peticion**.
///
/// `FutureProvider` y no `Stream`: esto es UNA respuesta a una pregunta que no
/// cambia mientras alguien esta delante del formulario. El §3-ter de
/// `CLAUDE.md` prohibe el `Future` para lo que se llena cuando entra la bajada,
/// que es otra cosa.
final ofertaDeLaPuertaProvider = FutureProvider<OfertaDeLaPuerta?>((ref) async {
  // El cliente SIN reintentos, el mismo que mira la version al arrancar. Aqui
  // importa mas que en ningun sitio: alguien esta esperando para entrar a
  // trabajar y esto es un extra. Si no se sabe, no se ensena.
  final cliente = ref.watch(clienteVersionProvider);

  final Map<String, Object?> cuerpo;
  try {
    cuerpo = await cliente.pedir<Map<String, Object?>>(
      ComprobadorDeActualizacion.ruta,
    );
  } on Object catch (e) {
    // Sin red, un 4xx, un proxy por medio: no se sabe, y no saber no se cuenta.
    // Lo que NO puede pasar es que esto tumbe la puerta de nadie.
    Registro.info('no se pudo mirar que hay colgado para la puerta: $e');
    return null;
  }

  final publicada = VersionPublicada.deJson(cuerpo['ultima']);
  if (publicada == null) return null;

  // GUARDA: sin enlace no hay boton. Un boton que lleva a un 404 es peor que no
  // ofrecer nada, porque ademas hace que alguien pregunte.
  final enlace = publicada.descargaPara(Plataforma.android);
  if (enlace == null) return null;

  return OfertaDeLaPuerta(
    version: publicada.version,
    enlace: enlace,
    bytes: publicada.ficheroPara(Plataforma.android)?.bytes,
  );
});
