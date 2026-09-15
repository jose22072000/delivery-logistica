import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';

const sesionDePrueba = Sesion(
  token: 'tok',
  refresh: 'r0',
  sub: 'u1',
  sucursalId: 'b-camaguey',
);

/// El `sync` de mentira.
///
/// Escrito aqui y no reutilizando `apoyo/servidor_falso.dart` por una razon
/// concreta: lo que hace falta comprobar en esta pantalla es **la URL entera**
/// —que el `?sucursal=` del Super Admin sale— y el ayudante comun solo guarda
/// el camino.
class SincroFalso implements HttpClientAdapter {
  SincroFalso(this.cuerpo);

  /// El JSON de `GET /sync/estado`. Si es `null`, la peticion no sale: es la
  /// pantalla sin red.
  Map<String, Object?>? cuerpo;

  /// Las direcciones pedidas, en orden.
  final List<Uri> pedidas = <Uri>[];

  int get cuantas => pedidas.length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions opciones,
    Stream<Uint8List>? cuerpoStream,
    Future<void>? cancelar,
  ) async {
    pedidas.add(opciones.uri);
    final actual = cuerpo;
    if (actual == null) {
      throw DioException.connectionError(
        requestOptions: opciones,
        reason: 'sin red (sync falso)',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(actual),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Un `ClienteApi` de `sync` enchufado al servidor de mentira. **Sin esperas**:
/// lo que se prueba es la pantalla, no el reloj de los reintentos.
ClienteApi clienteDePrueba(SincroFalso servidor) {
  final almacen = AlmacenEnMemoria(sesionDePrueba);
  final auth = Dio(BaseOptions(baseUrl: 'https://auth.test'))
    ..httpClientAdapter = servidor;
  final cliente = ClienteApi.montar(
    baseUrl: 'https://sync.test',
    almacen: almacen,
    renovador: Renovador(auth, almacen),
    esperar: (_) async {},
  );
  cliente.dio.httpClientAdapter = servidor;
  return cliente;
}

/// Un aparato del panel, en JSON, con los campos EXACTOS de
/// `sync/internal/sincro/estado.go`.
///
/// `subida` vacia y `horas_sin_subir` vacio es «nunca ha subido». Van juntos a
/// proposito: asi es como lo manda el servicio.
Map<String, Object?> aparatoJson({
  required String aparato,
  required String persona,
  String sucursal = 'b-camaguey',
  String? nombre,
  String? subida,
  int? horasSinSubir,
  int pendientes = 0,
  int rechazados = 0,
  String? visto,
  String? bajada,
}) => <String, Object?>{
  'aparato': aparato,
  'persona': persona,
  'sucursal': sucursal,
  'nombre': nombre,
  'visto': visto,
  'alta': '2026-09-01T08:00:00Z',
  'bajada': bajada,
  'bajada_hasta': bajada,
  'subida': subida,
  'pendientes': pendientes,
  'rechazados': rechazados,
  'horas_sin_subir': horasSinSubir,
};

Map<String, Object?> rechazoJson({
  required String rechazo,
  required String motivo,
  String aparato = 'ap-palma',
  String persona = 'María',
  String sucursal = 'b-palma',
  String? nombre = 'Teléfono de Palma',
  String clave = '01J8AAA',
  String metodo = 'POST',
  String ruta = '/api/routes/local-9f3a/results',
  String? hecho = '2026-09-14T16:04:22Z',
  String? rechazadoEl = '2026-09-14T19:20:00Z',
}) => <String, Object?>{
  'rechazo': rechazo,
  'aparato': aparato,
  'persona': persona,
  'sucursal': sucursal,
  'nombre': nombre,
  'clave': clave,
  'motivo': motivo,
  'metodo': metodo,
  'ruta': ruta,
  'hecho': hecho,
  // La clave del JSON es `rechazado`, no `rechazado_at`.
  'rechazado': rechazadoEl,
  'cuerpo': null,
};

Map<String, Object?> estadoJson({
  List<Map<String, Object?>> aparatos = const [],
  List<Map<String, Object?>> bandeja = const [],
  List<Map<String, Object?>> sinAtender = const [],
}) => <String, Object?>{
  'aparatos': aparatos,
  'bandeja': bandeja,
  'sin_atender': sinAtender,
};
