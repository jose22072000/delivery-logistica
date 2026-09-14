import 'package:reparto/nucleo/reloj.dart';

/// Un reloj que va donde le digan.
///
/// Hace falta porque las piezas que se prueban aqui dependen de la hora del
/// APARATO, y el aparato es justo lo que no se puede controlar: el reloj de un
/// telefono se cambia a mano, se va con la bateria y salta de zona horaria. La
/// prueba tiene que poder reproducir eso.
class RelojFalso {
  RelojFalso(this.ahora);

  DateTime ahora;

  /// La lista de horas que va a devolver, en orden. Cuando se acaba, repite la
  /// ultima. Sirve para simular un reloj que salta hacia atras.
  List<DateTime>? guion;
  int _paso = 0;

  Reloj get leer => () {
    final g = guion;
    if (g == null || g.isEmpty) return ahora;
    final valor = g[_paso.clamp(0, g.length - 1)];
    _paso++;
    return valor;
  };

  void avanzar(Duration cuanto) => ahora = ahora.add(cuanto);
}
