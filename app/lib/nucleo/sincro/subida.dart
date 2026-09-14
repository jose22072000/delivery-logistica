import '../cola/apunte.dart';
import '../cola/cola_salida.dart';
import '../red/cliente_api.dart';
import '../registro/registro.dart';

/// `POST /sync/subida` — la cola del aparato, en el orden en que se hizo.
///
/// Un solo trabajador y un solo lote. Veinte apuntes no son veinte peticiones en
/// paralelo, y no por elegancia: veinte peticiones a la vez al recuperar la
/// senal es lo que dispara veinte 401 a la vez, y eso es lo que el candado de
/// renovacion tiene que aguantar (caso I1). Mejor no darselo.
class Subida {
  Subida({
    required ClienteApi cliente,
    required ColaDeSalida cola,
    required String aparato,
  }) : _cliente = cliente,
       _cola = cola,
       _aparato = aparato;

  final ClienteApi _cliente;
  final ColaDeSalida _cola;
  final String _aparato;

  /// Sube un lote y aplica los resultados. Devuelve cuantos apuntes se
  /// resolvieron.
  ///
  /// Lo que lance sale tal cual: si es `FalloDeRed`, la cola se queda entera y
  /// se reintenta luego; si es `SesionMuerta`, quien llama manda a la pantalla
  /// de acceso. En ningun caso se borra un apunte por no haber podido subirlo.
  Future<int> ciclo({int maximo = 200}) async {
    final lote = await _cola.lote(maximo: maximo);
    if (lote.isEmpty) return 0;

    final respuesta = await _cliente.mandar<Map<String, Object?>>(
      'POST',
      '/subida',
      <String, Object?>{
        'aparato': _aparato,
        'apuntes': [for (final a in lote) a.aJson(ColaDeSalida.cuerpoDe(a))],
      },
    );

    final crudos = respuesta['resultados'];
    if (crudos is! List) {
      throw const FormatException('la subida no devolvio `resultados`');
    }

    // Se casa por `clave`, NO por posicion. El protocolo dice que vienen en el
    // mismo orden, pero fiarse de eso significa que un servidor que un dia
    // reordene marcaria el apunte equivocado como rechazado, y eso no da ningun
    // error: sólo trabajo perdido en el sitio que no es.
    var resueltos = 0;
    for (final crudo in crudos) {
      if (crudo is! Map<String, Object?>) continue;
      final clave = crudo['clave'] as String?;
      if (clave == null) {
        Registro.fallo('resultado de subida sin clave: $crudo');
        continue;
      }
      await _cola.resolver(clave, ResultadoApunte.deJson(crudo));
      resueltos++;
    }

    // Los que no vinieron en la respuesta se quedan pendientes y se reintentan.
    final sinRespuesta = lote.length - resueltos;
    if (sinRespuesta > 0) {
      Registro.aviso('$sinRespuesta apuntes subieron sin respuesta; se quedan');
    }
    return resueltos;
  }
}
