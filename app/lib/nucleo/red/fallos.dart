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
  const Rechazo(this.codigo, this.mensaje);

  final int codigo;

  @override
  final String mensaje;

  @override
  String toString() => 'Rechazo($codigo, $mensaje)';
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
