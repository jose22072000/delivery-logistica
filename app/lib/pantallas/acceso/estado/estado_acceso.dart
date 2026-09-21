import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/identidad/almacen_sesion.dart';
import '../../../nucleo/identidad/entrada_por_accesos.dart';
import '../../../nucleo/proveedores.dart';
import '../datos/servicio_acceso.dart';

final servicioAccesoProvider = Provider<ServicioDeAcceso>(
  (ref) => ServicioDeAcceso(
    auth: ref.watch(dioAuthProvider),
    almacen: ref.watch(almacenSesionProvider),
    // La puerta de la WEB, y sólo en la web: allí cerrar sesión es pasar por
    // Accesos para que retire la cookie. En la APK y en el escritorio va `null`
    // y todo sigue exactamente igual que hasta hoy.
    porAccesos: ref.watch(entraPorAccesosProvider)
        ? ref.watch(entradaPorAccesosProvider)
        : null,
  ),
);

/// ¿Este aparato puede guardar la sesión y volver a leerla?
///
/// Lo mira la pantalla de acceso **antes** de pedir la contraseña, porque la
/// promesa que hay escrita debajo del botón —«una vez dentro puedes seguir
/// trabajando el día entero sin señal»— sólo es verdad si la respuesta es que
/// sí. O se cumple, o no se promete (`nucleo/identidad/almacen_sesion.dart`).
///
/// `FutureProvider` y no algo que se dispare solo: es una ida y vuelta al
/// almacén del sistema y se hace cuando alguien la mira, una vez por arranque.
final saludDelAlmacenProvider = FutureProvider<SaludDelAlmacen>(
  (ref) => ref.watch(almacenSesionProvider).comprobar(),
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

  /// Devuelve el acceso si se entró, o `null` si no. El fallo queda en el
  /// estado, para pintarlo.
  Future<Acceso?> entrar({
    required String usuario,
    required String contrasena,
  }) async {
    if (state is Entrando) return null; // doble pulsación: una sola petición
    state = const Entrando();
    try {
      final acceso = await ref
          .read(servicioAccesoProvider)
          .entrar(usuario: usuario.trim(), contrasena: contrasena);
      state = const EnReposo();
      return acceso;
    } on FalloDeAcceso catch (fallo) {
      state = NoEntro(fallo);
      return null;
    }
  }
}

final formularioProvider = NotifierProvider<Formulario, EstadoDelFormulario>(
  Formulario.new,
);
