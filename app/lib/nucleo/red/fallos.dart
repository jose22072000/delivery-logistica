/// La regla 5, escrita en codigo.
///
/// | Lo que pasa        | Tipo          | Que hace la aplicacion                    |
/// |--------------------|---------------|-------------------------------------------|
/// | 200                | —             | dentro                                    |
/// | 401 (tras renovar) | `SesionMuerta`| limpia y a la pantalla de acceso          |
/// | 4xx que no es 401  | `Rechazo`     | se ensena el mensaje LITERAL del servidor |
/// | red, timeout, 5xx  | `FalloDeRed`  | CONSERVA los tokens y se reintenta luego  |
///
/// La linea que separa `SesionMuerta` de `FalloDeRed` es la que decide si un
/// logistico sigue trabajando o se queda fuera con el dia dentro. Borrar los
/// tokens por una caida pasajera obliga a entrar otra vez sin motivo, y en la
/// calle eso es quedarse sin aplicacion.
library;

sealed class FalloApi implements Exception {
  const FalloApi();

  /// El texto que se le ensena a la persona.
  String get mensaje;
}

/// Red caida, tiempo agotado, o el servidor devolvio 5xx.
///
/// **Los tokens se quedan.** Esto se reintenta luego, solo.
class FalloDeRed extends FalloApi {
  const FalloDeRed({this.detalle, this.codigo});

  /// El 5xx, si lo hubo. `null` significa que la peticion ni salio.
  final int? codigo;
  final String? detalle;

  @override
  String get mensaje => 'Sin conexión con el servidor.';

  @override
  String toString() => 'FalloDeRed(codigo: $codigo, detalle: $detalle)';
}

/// El servidor entendio la peticion y dijo que no.
///
/// `mensaje` es LITERAL y viene del servidor, en espanol
/// (`contratos-api.md`, apendice). Se pinta tal cual, sin envolver en «Ha
/// ocurrido un error»: «3 de los 8 pedidos ya están en otra ruta. Vuelve a
/// elegirlos.» le dice a alguien que hacer; «Ha ocurrido un error», no.
///
/// **Un `Rechazo` no se reintenta jamas.**
class Rechazo extends FalloApi {
  const Rechazo(this.codigo, this.mensaje, {this.marca, this.cuerpo});

  final int codigo;

  /// EL CUERPO ENTERO DE LA RESPUESTA, sin tocar. `null` si no vino ninguno.
  ///
  /// [mensaje] es lo que se pinta y basta casi siempre. Esto es para los pocos
  /// «no» que traen **una lista nombrada** al lado de la frase, y en los que la
  /// frase sola no le dice a nadie qué hacer:
  ///
  ///  * `POST /api/board/columns/{id}/route` contesta 409 con `descartados`, que
  ///    es quién se cayó de la zona y por qué. Sin esa lista, una columna de
  ///    doce que produce una ruta de nueve no tiene explicación, «que es la
  ///    manera más rápida de que el logístico deje de fiarse» (tablero.md §5.2).
  ///  * `DELETE /api/board/columns/{id}` contesta 409 con `pedidos`, el número
  ///    que decide si hay que vaciar dos tarjetas o mover ochenta.
  ///
  /// Se guarda crudo y no interpretado a propósito: quien lo lee sabe de qué
  /// endpoint viene y esta capa no.
  final Object? cuerpo;

  @override
  final String mensaje;

  /// LA MARCA QUE UNA MAQUINA PUEDE LEER, cuando el servidor la manda.
  ///
  /// El formato de la casa sigue siendo la frase en espanol, y esto no la
  /// sustituye: es para los pocos fallos donde el cliente tiene que **hacer
  /// algo distinto** segun cual sea, y el numero no basta para distinguirlos.
  ///
  /// El caso que la trajo: `/sync/subida` contesta 404 cuando el aparato no
  /// esta registrado, y el telefono respondia tirando su identificador y
  /// dandose de alta otra vez. Pero un 404 de Traefik durante un redespliegue
  /// —que ni siquiera es JSON— tambien es un 404, y hacia lo mismo. En
  /// produccion salieron **12 aparatos para un solo telefono**.
  ///
  /// `null` = el servidor no mando ninguna. Entonces **no se puede suponer
  /// cual es**, y quien decide algo destructivo con esto tiene que fallar
  /// cerrado.
  final String? marca;

  @override
  String toString() => 'Rechazo($codigo, $mensaje${marca == null ? '' : ', $marca'})';
}

/// La sesion murio: un 401 que sigue siendo 401 despues de renovar, o un
/// refresh que el servidor ya no acepta.
///
/// Es lo unico que manda a alguien a la pantalla de acceso.
class SesionMuerta extends FalloApi {
  const SesionMuerta([this.detalle]);

  final String? detalle;

  @override
  String get mensaje => 'La sesión terminó. Hay que entrar otra vez.';

  @override
  String toString() => 'SesionMuerta($detalle)';
}
