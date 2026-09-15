import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../arranque/arranque.dart';
import '../nucleo/identidad/sesion.dart';
import '../nucleo/proveedores.dart';
import '../nucleo/registro/registro.dart';
import '../pantallas/acceso/estado/estado_acceso.dart';
import 'estado_navegacion.dart';

/// Las tres situaciones en las que puede estar alguien delante de la aplicación.
enum EstadoDeAcceso {
  /// Todavía no se sabe: se está mirando lo guardado. Dura lo que tarde una
  /// renovación, o lo que tarde la red en rendirse.
  comprobando,

  /// Hay sesión. Al Panel.
  dentro,

  /// No hay sesión, o murió. A la pantalla de acceso.
  fuera,
}

/// EL PORTERO. Sin sesión, a la pantalla de acceso; con sesión, al Panel.
///
/// Es un `ChangeNotifier` porque es lo que `GoRouter` sabe escuchar
/// (`refreshListenable`): al cambiar el estado, el enrutador vuelve a pasar por
/// `redirigir` y la persona aterriza donde toca **sin que ninguna pantalla tenga
/// que llamar a `context.go`**.
///
/// ## La regla de Jose, que manda
///
/// > Para entrar hace falta conexión. Una vez dentro, no.
///
/// Al arrancar **sin red y con sesión guardada SE ENTRA** ([Arranque.
/// dentroSinComprobar]). Mandar a esa persona al acceso sería mandarla a una
/// pantalla que sin servidor tampoco funciona, con el trabajo del día dentro del
/// teléfono. Sólo un 401 mata la sesión; un fallo de red la conserva
/// (`docs/identidad.md`, regla 3).
class Portero extends ChangeNotifier {
  Portero(this._ref);

  final Ref _ref;

  EstadoDeAcceso get estado => _estado;
  EstadoDeAcceso _estado = EstadoDeAcceso.comprobando;

  /// Quién entró. Sale del token guardado, así que se sabe sin red.
  Sesion? get sesion => _sesion;
  Sesion? _sesion;

  /// `true` cuando se entró con lo guardado sin poder comprobarlo por falta de
  /// red. No cambia lo que se puede hacer: se dice para poder pintarlo.
  bool get sinComprobar => _sinComprobar;
  bool _sinComprobar = false;

  /// Lo que hace la aplicación al abrirse: abre la base, lee la sesión e intenta
  /// RENOVAR. No se comprueba el token de acceso por su cuenta — dura quince
  /// minutos, así que casi siempre estará caducado al abrir, y eso no significa
  /// que la sesión haya muerto.
  Future<void> comprobar() async {
    try {
      final resultado = await arrancar(_ref);
      _sesion = await _ref.read(almacenSesionProvider).leer();
      _poner(
        switch (resultado) {
          Arranque.fuera => EstadoDeAcceso.fuera,
          Arranque.dentro => EstadoDeAcceso.dentro,
          Arranque.dentroSinComprobar => EstadoDeAcceso.dentro,
        },
        sinComprobar: resultado == Arranque.dentroSinComprobar,
      );
    } on Object catch (e, pila) {
      // Un arranque que revienta NO puede dejar la aplicación en la pantalla de
      // esperar para siempre. Se va al acceso, que es la única pantalla que
      // funciona sin nada montado.
      Registro.fallo('el arranque falló: $e', e, pila);
      _poner(EstadoDeAcceso.fuera);
      return;
    }
    if (_estado == EstadoDeAcceso.dentro) _descargarElDia();
  }

  /// Acaba de entrar con usuario y contraseña. El par ya está guardado.
  void entro(Sesion sesion) {
    _sesion = sesion;
    _poner(EstadoDeAcceso.dentro);
    _descargarElDia();
  }

  /// La sesión murió (un 401 que sigue siendo 401 después de renovar). Es lo
  /// único que echa a nadie fuera.
  void murio() {
    _sesion = null;
    _poner(EstadoDeAcceso.fuera);
  }

  /// Salir a mano. Revoca en auth si hay red, borra el par y **borra lo local**:
  /// en el aparato quedan los clientes con sus direcciones y los pedidos del
  /// día, y si el teléfono cambia de manos eso no puede seguir ahí (regla 8).
  Future<void> salir() async {
    final quien = _sesion;
    _sesion = null;
    _poner(EstadoDeAcceso.fuera);
    try {
      await _ref.read(servicioAccesoProvider).salir(quien);
      await _ref.read(baseProvider).borrarTodoLoDelDominio();
    } on Object catch (e) {
      Registro.aviso('salida con incidencias: $e');
    }
  }

  /// La bajada del día, en cuanto se entra. **En segundo plano**: la pantalla no
  /// espera a que acabe, porque con la conexión de allá eso es un minuto mirando
  /// un giro, y lo que hay que ver es el Panel.
  void _descargarElDia() {
    final enVuelo = _ref.read(enVueloProvider.notifier)..empieza();
    Future<void>(() async {
      try {
        final resumen = await _ref.read(bajadaProvider).ciclo();
        Registro.info('bajada del día: $resumen');
        await _ref.read(bajadaProvider).almacenes();
      } on Object catch (e) {
        // Que falle no echa a nadie fuera ni borra nada: lo que ya estaba
        // bajado sigue en la base y la franja de estado dirá de cuándo es. Un
        // 401 lo trata el interceptor, que es quien sabe renovar.
        Registro.aviso('no se pudo bajar el día: $e');
      } finally {
        enVuelo.termina();
      }
    });
  }

  void _poner(EstadoDeAcceso nuevo, {bool sinComprobar = false}) {
    if (_estado == nuevo && _sinComprobar == sinComprobar) return;
    _estado = nuevo;
    _sinComprobar = sinComprobar;
    notifyListeners();
  }
}

final porteroProvider = Provider<Portero>((ref) {
  final portero = Portero(ref);
  ref.onDispose(portero.dispose);
  return portero;
});

/// La ruta de la pantalla de acceso. Vive aquí y no en su `registro.dart` para
/// que el portero no tenga que importar la pantalla.
const rutaDeAcceso = '/acceso';

/// La pantalla de esperar mientras se comprueba lo guardado.
///
/// Existe para que no se vea la pantalla de acceso durante un segundo antes de
/// entrar: quien tiene sesión guardada no tiene por qué ver nunca un formulario
/// de contraseña, y ese parpadeo enseña a escribir la contraseña por reflejo.
const rutaDeArranque = '/arranque';

/// EL REDIRECTOR. Una sola función, sin estado, para poder probarla suelta.
String? redirigir(String rutaActual, EstadoDeAcceso estado, String inicio) =>
    switch (estado) {
      EstadoDeAcceso.comprobando =>
        rutaActual == rutaDeArranque ? null : rutaDeArranque,
      EstadoDeAcceso.fuera => rutaActual == rutaDeAcceso ? null : rutaDeAcceso,
      EstadoDeAcceso.dentro =>
        (rutaActual == rutaDeAcceso || rutaActual == rutaDeArranque)
            ? inicio
            : null,
    };

/// Lo que consume `rutas.dart`.
String? porteroDeRutas(GoRouterState estado, Portero portero, String inicio) =>
    redirigir(estado.matchedLocation, portero.estado, inicio);
