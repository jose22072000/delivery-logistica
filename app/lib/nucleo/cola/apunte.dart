import '../base/base.dart';

export '../base/base.dart' show Apunte, EstadoApunte;

/// Lo que el servidor contesta de UN apunte, en `POST /sync/subida`.
/// Ver ../../../docs/sincronizacion.md §2.
enum EstadoResultado {
  /// Se aplico ahora.
  aplicado,

  /// Ya estaba aplicado de un intento anterior que se corto antes de contestar.
  /// **No es un error**: es exactamente para lo que existe la `clave`.
  repetido,

  /// El servidor dijo que no. Final: ni se reintenta ni se borra.
  rechazado,
}

/// La respuesta del servidor para un apunte.
class ResultadoApunte {
  const ResultadoApunte({
    required this.estado,
    this.id,
    this.motivo,
  });

  ResultadoApunte.deJson(Map<String, Object?> json)
    : estado = switch (json['estado']) {
        'aplicado' => EstadoResultado.aplicado,
        'repetido' => EstadoResultado.repetido,
        'rechazado' => EstadoResultado.rechazado,
        final otro => throw FormatException('estado desconocido: $otro'),
      },
      id = json['id'] as String?,
      motivo = json['motivo'] as String?;

  final EstadoResultado estado;

  /// El id de verdad de lo que este apunte creo. Es lo que sustituye al
  /// `local-…`.
  final String? id;

  /// El motivo literal del servidor. Se ensena TAL CUAL, en espanol, sin
  /// envolver en «Ha ocurrido un error».
  final String? motivo;

  bool get seAplico =>
      estado == EstadoResultado.aplicado || estado == EstadoResultado.repetido;
}

/// Un apunte, tal y como sale hacia `POST /sync/subida`.
extension ApunteAJson on Apunte {
  Map<String, Object?> aJson(Object? cuerpoDecodificado) => <String, Object?>{
    'clave': clave,
    // La hora del APARATO, en UTC con su marca, no la de la subida.
    'hecho': hechoAt.toUtc().toIso8601String(),
    'metodo': metodo,
    'ruta': ruta,
    'cuerpo': cuerpoDecodificado,
    if (provisional != null) 'provisional': provisional,
  };
}
