import 'almacen_sesion.dart';

/// Sin sitio donde guardar.
///
/// Se devuelve un almacen en memoria para que la aplicacion **arranque** —sin
/// el no habria ni pantalla de acceso— pero declarado como lo que es: un sitio
/// que pierde la sesion al cerrar. La pantalla de acceso lo dice en vez de
/// prometer un dia entero sin senal que este destino no puede cumplir.
AlmacenDeSesion abrirAlmacenDeSesion() => AlmacenEnMemoria(
  null,
  const SaludDelAlmacen.rota('Este aparato no tiene dónde guardar la sesión.'),
);
