import '../../navegacion/pantalla_registrada.dart';
import '../../navegacion/portero.dart';
import 'vista/pantalla_acceso.dart';

/// La pantalla de acceso, registrada como todas las demás.
///
/// Dos diferencias con las siete del menú, y las dos tienen motivo:
///
///  * **`enElMenu: false`** — no se llega a ella desde la barra lateral. Se llega
///    porque el portero manda, o porque se pulsó «Salir».
///  * **`conArmazon: false`** — no lleva barra lateral, ni barra superior, ni
///    franja de estado. Las tres salen de la sesión y de la base local, que es
///    justo lo que todavía no hay cuando alguien está mirando esta pantalla: un
///    menú de siete pantallas a las que no se puede ir, un selector de sucursal
///    vacío y un «sin descargar» son tres formas de decir que la aplicación está
///    rota antes de haber entrado.
PantallaRegistrada registrarAcceso() => PantallaRegistrada(
  ruta: rutaDeAcceso,
  titulo: 'Entrar',
  enElMenu: false,
  conArmazon: false,
  construir: (contexto, estado) => const PantallaAcceso(),
);
