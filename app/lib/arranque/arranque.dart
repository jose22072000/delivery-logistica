import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../nucleo/identidad/sesion.dart';
import '../nucleo/proveedores.dart';
import '../nucleo/red/fallos.dart';
import '../nucleo/registro/registro.dart';

/// Como queda la aplicacion despues de arrancar.
enum Arranque {
  /// Hay sesion y se puede trabajar.
  dentro,

  /// No hay sesion, o murio: a la pantalla de acceso.
  fuera,

  /// Hay sesion guardada pero no se pudo comprobar porque no hay red. **Se
  /// entra igual** (regla 1: para entrar hace falta conexion, una vez dentro
  /// no).
  dentroSinComprobar,
}

/// Abre la base, lee la sesion e intenta RENOVAR.
///
/// **No se comprueba el token de acceso por su cuenta.** Dura minutos, asi que
/// casi siempre estara caducado al abrir, y eso no significa que la sesion haya
/// muerto. Se intenta renovar, que hace las dos cosas a la vez: si el par sirve
/// devuelve uno nuevo, y si no, no sirve (`identidad.md`).
Future<Arranque> arrancar(Ref ref) async {
  // Las fechas en espanol. Va aqui y no en cada formato porque `DateFormat` con
  // un locale sin cargar lanza, y hacerlo al pintar seria descubrirlo en la
  // pantalla de alguien.
  await initializeDateFormatting('es');

  // Tocar la base la abre. Si en web cayo a memoria, aqui es donde se entera.
  await ref.read(baseProvider).cuantosPendientes();

  final almacen = ref.read(almacenSesionProvider);
  final Sesion? guardada = await almacen.leer();

  if (guardada == null) {
    // En web esto es lo normal: la sesion la lleva la cookie y quien decide es
    // el servidor en la primera peticion.
    return Arranque.fuera;
  }

  try {
    await ref.read(renovadorProvider).renovar(guardada);
    return Arranque.dentro;
  } on SesionMuerta {
    // El refresh ya no vale. Los tokens los borro el propio renovador.
    return Arranque.fuera;
  } on FalloDeRed {
    // Sin red al arrancar se entra con lo guardado. Borrar la sesion aqui seria
    // dejar a alguien fuera en la calle por una caida pasajera.
    Registro.aviso('arranque sin red: se entra con la sesion guardada');
    return Arranque.dentroSinComprobar;
  }
}
