import 'package:reparto/nucleo/red/cliente_api.dart';

/// CÓMO VA EL CANAL CON PEDIDO, leído del servidor.
///
/// Esta pantalla **sólo existe en la web y sólo la ve el desarrollador**. Jose, 26/09/2026:
/// «eso me lo dejas en la web solamente, no lo pongas en más ningún lado» y «que sólo lo
/// pueda ver yo, eso no lo puede ver más nadie, sólo yo, el desarrollador».
///
/// LAS PALABRAS SON LAS MISMAS QUE LAS DE PEDIDO, y eso no es un detalle: la otra mitad de
/// este tubo tiene su propia pantalla en PEDIDO → Sincronización → Reparto. Si una dice
/// «pendientes» y la otra «esperando», comparar las dos obliga a traducir, y en una
/// traducción es donde se cuela la conclusión equivocada. Se acordaron entre las dos
/// sesiones el 26/09/2026:
///
///   **esperando** · **sin terminar** · **el más viejo** · **último aviso**
///
/// Con dos diferencias a propósito: aquí no hay «nadie está leyendo» —el que lee es éste— y
/// aquí sí está «el más viejo sin mandar», que es EL número que dice si la salida está
/// atascada: veinte esperando de hace un minuto es el ritmo normal, uno de hace seis horas
/// no lo es.
class EstadoDelWebhook {
  const EstadoDelWebhook({
    required this.resumen,
    required this.enviados,
    required this.recibidos,
    required this.sinMandar,
  });

  factory EstadoDelWebhook.deJson(Map<String, Object?> j) => EstadoDelWebhook(
    resumen: ResumenDelWebhook.deJson(
      (j['resumen'] as Map<String, Object?>?) ?? const {},
    ),
    enviados: [
      for (final e in (j['enviados'] as List<Object?>? ?? const []))
        if (e is Map<String, Object?>) TandaEnviada.deJson(e),
    ],
    recibidos: [
      for (final e in (j['recibidos'] as List<Object?>? ?? const []))
        if (e is Map<String, Object?>) TandaRecibida.deJson(e),
    ],
    sinMandar: [
      for (final e in (j['sinMandar'] as List<Object?>? ?? const []))
        if (e is Map<String, Object?>) AvisoSinMandar.deJson(e),
    ],
  );

  final ResumenDelWebhook resumen;
  final List<TandaEnviada> enviados;
  final List<TandaRecibida> recibidos;
  final List<AvisoSinMandar> sinMandar;
}

class ResumenDelWebhook {
  const ResumenDelWebhook({
    this.ultimaEntrada,
    this.ultimaSalida,
    this.escritosHoy = 0,
    this.rechazadosAlEntrar = 0,
    this.esperando = 0,
    this.rechazados = 0,
    this.masViejo,
  });

  factory ResumenDelWebhook.deJson(Map<String, Object?> j) => ResumenDelWebhook(
    ultimaEntrada: _fecha(j['ultimaEntrada']),
    ultimaSalida: _fecha(j['ultimaSalida']),
    escritosHoy: _entero(j['escritosHoy']),
    rechazadosAlEntrar: _entero(j['rechazadosAlEntrar']),
    esperando: _entero(j['avisosPendientes']),
    rechazados: _entero(j['avisosRechazados']),
    masViejo: _fecha(j['pendienteMasViejo']),
  );

  /// `null` = **nunca**, que no es lo mismo que «hace mucho» y la pantalla lo dice con
  /// otras palabras. Un canal que nunca ha recibido nada y uno que lleva seis horas
  /// parado se arreglan en sitios distintos.
  final DateTime? ultimaEntrada;
  final DateTime? ultimaSalida;

  final int escritosHoy;
  final int rechazadosAlEntrar;

  /// Avisos nuestros que aún no han salido hacia PEDIDO.
  final int esperando;

  /// Los que PEDIDO rechazó: llegaron perfectamente y dijo que no. **No se reintentan**, y
  /// por eso son una bandeja que alguien tiene que mirar, no un número que baja solo.
  final int rechazados;

  /// El más viejo sin mandar. Es EL número que dice si esto está atascado.
  final DateTime? masViejo;

  /// ¿Hay algo que mirar? Se usa para el punto de color, y NO incluye `esperando`: veinte
  /// esperando de hace un minuto es el ritmo normal de un cierre de ruta.
  bool get hayQueMirar => rechazados > 0 || estaAtascado;

  /// Atascado: algo lleva más de diez minutos sin salir. Es el mismo listón que usa la
  /// pantalla de PEDIDO, acordado entre las dos sesiones para que las dos digan lo mismo.
  bool get estaAtascado {
    final desde = masViejo;
    if (desde == null) return false;
    return DateTime.now().difference(desde) > const Duration(minutes: 10);
  }
}

/// Una tanda que salió hacia PEDIDO.
class TandaEnviada {
  const TandaEnviada({
    required this.mandados,
    required this.aceptados,
    required this.rechazados,
    required this.cuando,
    this.http,
    this.motivo,
    this.duracionMs = 0,
  });

  factory TandaEnviada.deJson(Map<String, Object?> j) => TandaEnviada(
    mandados: _entero(j['mandados']),
    aceptados: _entero(j['aceptados']),
    rechazados: _entero(j['rechazados']),
    http: j['http'] == null ? null : _entero(j['http']),
    motivo: j['motivo'] as String?,
    duracionMs: _entero(j['duracionMs']),
    cuando: _fecha(j['createdAt']) ?? DateTime.now(),
  );

  final int mandados;
  final int aceptados;
  final int rechazados;

  /// El código tal cual. Un 200 con cero aceptados y un 502 **no son lo mismo**: uno llegó
  /// y dijo que no, el otro no llegó. Guardar sólo «falló» los confunde.
  final int? http;
  final String? motivo;
  final int duracionMs;
  final DateTime cuando;

  bool get llegoBien => http != null && http! >= 200 && http! < 300;
}

/// Una tanda que entró, por la cola o por HTTP.
class TandaRecibida {
  const TandaRecibida({
    required this.origen,
    required this.traidos,
    required this.escritos,
    required this.rechazados,
    required this.cuando,
    this.motivos,
    this.duracionMs = 0,
  });

  factory TandaRecibida.deJson(Map<String, Object?> j) => TandaRecibida(
    origen: (j['origen'] as String?) ?? 'pedido',
    traidos: _entero(j['traidos']),
    escritos: _entero(j['escritos']),
    rechazados: _entero(j['rechazados']),
    motivos: j['motivos'] as String?,
    duracionMs: _entero(j['duracionMs']),
    cuando: _fecha(j['createdAt']) ?? DateTime.now(),
  );

  /// De qué puerta vino. **SON TRES, y se dicen con palabras distintas**:
  ///
  ///  - `webhook` — un aviso de PEDIDO por `POST /api/webhooks/pedido`, de uno en uno.
  ///  - `stream` — por la cola de Redis, mientras las dos puertas convivan.
  ///  - `pedido` — una tanda del espejo por `/api/quote/batch`, de 200 en 200.
  ///
  /// LOS TRES EN LA MISMA LISTA: son caminos para lo mismo, y tenerlos separados obliga a
  /// mirar en tres sitios para responder «¿está entrando algo?», que es la primera pregunta
  /// cuando algo no llega.
  ///
  /// PERO CON NOMBRES DISTINTOS, y eso costó una vuelta: `webhook` y `pedido` se llamaban los
  /// dos `pedido`, así que los avisos —de uno en uno— quedaban enterrados entre lotes de
  /// doscientos y no se podía contestar «¿entra algo POR EL WEBHOOK?». Se vio en producción el
  /// 26/09/2026 con las dos clases de fila mezcladas en la tabla.
  final String origen;

  final int traidos;

  /// Los que llevaron a una acción.
  final int escritos;

  /// Los que NO llevaron a nada. **No son fallos**: un pedido repetido en la misma tanda,
  /// o un traer que un borrado anuló, es el sistema haciendo lo correcto. Pintarlos de
  /// rojo enseña a ignorar el rojo, y entonces el rojo de verdad tampoco se mira.
  final int rechazados;

  final String? motivos;
  final int duracionMs;
  final DateTime cuando;

  String get comoSeLlama => switch (origen) {
    'webhook' => 'por el webhook',
    'stream' => 'por la cola',
    'pedido' => 'por el lote del espejo',
    // UN ORIGEN QUE NO SE CONOCE SE DICE TAL CUAL, no se traduce a «por HTTP».
    // Traducirlo escondería que hay una puerta nueva que nadie sabe que existe.
    _ => origen,
  };
}

/// Un aviso nuestro que no llegó a PEDIDO.
class AvisoSinMandar {
  const AvisoSinMandar({
    required this.pedidoId,
    required this.estado,
    required this.situacion,
    required this.intentos,
    required this.cuando,
    this.folio,
    this.motivo,
  });

  factory AvisoSinMandar.deJson(Map<String, Object?> j) => AvisoSinMandar(
    pedidoId: (j['pedidoId'] as String?) ?? '',
    folio: j['folio'] as String?,
    estado: (j['estado'] as String?) ?? '',
    situacion: (j['situacion'] as String?) ?? '',
    intentos: _entero(j['intentos']),
    motivo: j['motivo'] as String?,
    cuando: _fecha(j['createdAt']) ?? DateTime.now(),
  );

  final String pedidoId;
  final String? folio;
  final String estado;

  /// `pendiente` = no se pudo ni preguntar, se reintenta. `rechazado` = PEDIDO dijo que
  /// no, **y eso no se reintenta**: repetir lo mismo da lo mismo. Son dos cosas distintas
  /// y se arreglan distinto.
  final String situacion;

  final int intentos;
  final String? motivo;
  final DateTime cuando;

  bool get loRechazaron => situacion == 'rechazado';
}

DateTime? _fecha(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

int _entero(Object? v) => switch (v) {
  final int n => n,
  final num n => n.toInt(),
  final String s => int.tryParse(s) ?? 0,
  _ => 0,
};

/// Lee el estado del canal. **Contra el servidor y sólo contra el servidor**: esto no vive
/// en la copia local, que es de la sucursal y esto no es de ninguna.
class RepositorioDelWebhook {
  const RepositorioDelWebhook(this._api);

  final ClienteApi _api;

  Future<EstadoDelWebhook> mirar() async {
    final crudo = await _api.pedir<Map<String, Object?>>('/admin/webhook');
    return EstadoDelWebhook.deJson(crudo);
  }
}
