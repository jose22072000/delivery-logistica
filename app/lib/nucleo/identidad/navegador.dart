export 'navegador_stub.dart' if (dart.library.js_interop) 'navegador_web.dart';

/// IRSE DE LA APLICACION, de verdad.
///
/// El login unico no es una peticion: es **mandar el navegador a otro sitio** y
/// que vuelva. Eso no lo puede hacer `go_router` —su enrutador vive dentro de
/// esta pagina— ni una llamada con Dio, que traeria el HTML de Accesos en vez de
/// ensenarselo a nadie.
///
/// Esta pieza existe con nombre y por provider por dos motivos, y los dos son de
/// los que se pagan tarde:
///
///  1. **Se puede probar.** Una prueba pone el suyo y comprueba **a donde** se
///     mando a la persona. Con `window.location` escrito dentro del widget no
///     hay forma de saberlo sin abrir un navegador de verdad.
///  2. **Compila en los tres destinos.** `package:web` no existe en Android ni
///     en el escritorio; la importacion condicional deja alli el
///     [NavegadorQuieto], que no va a ningun sitio — y esta bien que no vaya:
///     alli se entra con usuario y contrasena (`docs/identidad.md`).
abstract interface class Navegador {
  /// Manda el navegador a [destino]. **Se pierde el estado de la pagina**: es
  /// una navegacion de verdad, no un cambio de pantalla.
  void irA(String destino);

  /// La direccion con la que se cargo esta pagina. En los destinos que no son
  /// web es la del proceso y no dice nada, que es justo lo que hace falta.
  Uri get direccionAlCargar;
}

/// El que no va a ningun sitio: APK y escritorio.
///
/// No lanza a proposito. Si algun dia una pantalla llamara aqui por error, lo
/// peor que puede pasar es que no pase nada; lanzar tumbaria la aplicacion de
/// quien esta en el patio de un almacen por una puerta que alli no se usa.
class NavegadorQuieto implements Navegador {
  const NavegadorQuieto();

  @override
  void irA(String destino) {}

  @override
  Uri get direccionAlCargar => Uri.base;
}
