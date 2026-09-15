import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/identidad/sesion.dart';
import '../../../nucleo/proveedores.dart';
import '../datos/servicio_acceso.dart';

final servicioAccesoProvider = Provider<ServicioDeAcceso>(
  (ref) => ServicioDeAcceso(
    auth: ref.watch(dioAuthProvider),
    almacen: ref.watch(almacenSesionProvider),
  ),
);

/// Cómo va el intento de entrar. Lo mira sólo la pantalla de acceso.
sealed class EstadoDelFormulario {
  const EstadoDelFormulario();
}

class EnReposo extends EstadoDelFormulario {
  const EnReposo();
}

class Entrando extends EstadoDelFormulario {
  const Entrando();
}

class NoEntro extends EstadoDelFormulario {
  const NoEntro(this.fallo);

  final FalloDeAcceso fallo;
}

/// El formulario de acceso.
///
/// **No decide a dónde se va**: eso lo hace el portero. Esto sólo pide el par de
/// tokens y dice si salió o no; quien entró se lo cuenta al portero, que es
/// quien mueve la aplicación de sitio. Con las dos cosas juntas, cada pantalla
/// que quisiera comprobar la sesión tendría su propia versión de la regla.
class Formulario extends Notifier<EstadoDelFormulario> {
  @override
  EstadoDelFormulario build() => const EnReposo();

  /// Devuelve la sesión si se entró, o `null` si no. El fallo queda en el
  /// estado, para pintarlo.
  Future<Sesion?> entrar({
    required String usuario,
    required String contrasena,
  }) async {
    if (state is Entrando) return null; // doble pulsación: una sola petición
    state = const Entrando();
    try {
      final sesion = await ref
          .read(servicioAccesoProvider)
          .entrar(usuario: usuario.trim(), contrasena: contrasena);
      state = const EnReposo();
      return sesion;
    } on FalloDeAcceso catch (fallo) {
      state = NoEntro(fallo);
      return null;
    }
  }
}

final formularioProvider = NotifierProvider<Formulario, EstadoDelFormulario>(
  Formulario.new,
);
