import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/salud.dart';

/// LA SALUD DE LA RED SE CUENTA POR INTENTO, NO POR CICLO.
///
/// El 16/09/2026, con el teléfono SIN salida a internet —medido desde el propio
/// aparato: 100 % de paquetes perdidos a 8.8.8.8 y ni siquiera resolvía el
/// nombre del servidor—, la aplicación seguía sin decirlo. Palabras de Jose:
/// «ahora mismo estoy sin conexion y el movil me dice q tengo internet por q
/// razon».
///
/// La causa: hacían falta TRES CICLOS caídos, y un ciclo tarda. Contando
/// intentos, los tres caben dentro de uno solo —cada petición reintenta a 1 s,
/// 4 s y 10 s—, así que el aviso sale en menos de medio minuto.
///
/// El motivo de que sean tres y no uno sigue en pie: un aviso que parpadea con
/// cada paquete perdido deja de leerse.
void main() {
  late List<bool> avisos;

  ClienteApi clienteQue(Future<Response<Object?>> Function() responde) {
    avisos = [];
    final dio = Dio();
    dio.httpClientAdapter = _AdaptadorFalso(responde);
    return ClienteApi(
      dio: dio,
      esperas: const [Duration.zero, Duration.zero, Duration.zero],
      esperar: (_) async {},
      alIntentar: ({required bool llego}) => avisos.add(llego),
    );
  }

  test('una petición que no sale avisa de CADA intento, no de uno', () async {
    final cliente = clienteQue(
      () => throw DioException.connectionError(
        requestOptions: RequestOptions(),
        reason: 'sin red',
      ),
    );

    await expectLater(cliente.pedir<Object?>('/loquesea'), throwsA(anything));

    expect(
      avisos.length,
      4,
      reason:
          'el intento y sus tres reintentos: cuatro avisos dentro de UNA '
          'petición, que es lo que hace que el aviso salga en segundos',
    );
    expect(avisos.every((llego) => !llego), isTrue);

    // Y con esos cuatro, la salud ya da la red por mala.
    var salud = SaludDeLaRed.bienDeSalida;
    for (final llego in avisos) {
      salud = llego ? salud.conUnaBuena(DateTime.now()) : salud.conUnaMala();
    }
    expect(
      salud.vaMal,
      isTrue,
      reason: 'sin esto habría que esperar a tres CICLOS, o sea minutos',
    );
  });

  test('un 4xx NO cuenta como red mala: la petición sí llegó', () async {
    final cliente = clienteQue(
      () async => Response<Object?>(
        requestOptions: RequestOptions(),
        statusCode: 404,
        data: const <String, Object?>{},
      ),
    );

    await expectLater(cliente.pedir<Object?>('/loquesea'), throwsA(anything));

    expect(
      avisos,
      [true],
      reason:
          'que el servidor conteste «no existe» significa que contestó: la '
          'red está bien y decir lo contrario manda a mirar donde no es',
    );
  });

  test('una que llega da la red por sana al momento', () async {
    final cliente = clienteQue(
      () async => Response<Object?>(
        requestOptions: RequestOptions(),
        statusCode: 200,
        data: const <String, Object?>{},
      ),
    );

    await cliente.pedir<Object?>('/loquesea');

    expect(avisos, [true]);
    expect(
      const SaludDeLaRed(fallosSeguidos: 9).conUnaBuena(DateTime.now()).vaMal,
      isFalse,
      reason:
          'basta UNA buena: dejar el aviso puesto delante de alguien que ya '
          'tiene señal es mentir en la otra dirección',
    );
  });
}

/// Un adaptador que contesta lo que se le diga, sin tocar la red.
class _AdaptadorFalso implements HttpClientAdapter {
  _AdaptadorFalso(this.responde);

  final Future<Response<Object?>> Function() responde;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final r = await responde();
    return ResponseBody.fromString('{}', r.statusCode ?? 200);
  }
}
