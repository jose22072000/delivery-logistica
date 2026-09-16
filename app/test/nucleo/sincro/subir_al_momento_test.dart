import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/sincro/vigia.dart';

/// LO QUE SE ACABA DE HACER SE INTENTA SUBIR YA. No se espera al reloj.
///
/// La cola de salida es el aparato de **no tener** señal. Con señal no hay ninguna razón
/// para que arrastrar una tarjeta se quede cinco minutos esperando al temporizador, ni para
/// que alguien tenga que pulsar un botón.
///
/// Jose, 16/09/2026: «cuando hay conexión trabajaría sin estar dándole a subir todo el
/// tiempo y hiciera todo solo; el problema es cuando se trabaja sin conexión y hay que
/// traer el trabajo que se hizo sin conexión».
///
/// Se escucha LA TABLA de apuntes y no se avisa desde quien encola, a propósito: así entra
/// cualquier gesto lo escriba quien lo escriba, y la cola no tiene que saber nada del
/// ciclo — que además sería un ciclo de dependencias, porque el ciclo necesita la cola.
void main() {
  late StreamController<void> cola;
  late List<String> ciclos;
  late VigiaDeSincronizacion vigia;

  setUp(() {
    cola = StreamController<void>.broadcast();
    ciclos = <String>[];
    vigia = VigiaDeSincronizacion(
      ciclo: (motivo) async => ciclos.add(motivo),
      avisosDeRed: Stream<bool>.empty,
      avisosDeLaCola: () => cola.stream,
      // Sin temporizador: lo que se comprueba es el aviso, no el reloj.
      crearTemporizador: (_, _) => Timer(const Duration(days: 1), () {}),
    );
  });

  tearDown(() async {
    vigia.parar();
    await cola.close();
  });

  test('un apunte nuevo dispara el ciclo, sin esperar al reloj', () async {
    vigia.arrancar();
    cola.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(
      ciclos,
      ['se hizo algo'],
      reason: 'sin esto, lo que se hace con señal espera al temporizador o a que '
          'alguien pulse un botón',
    );
  });

  test('sin arrancar no escucha nada', () async {
    cola.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(ciclos, isEmpty);
  });

  test('al parar se suelta la cola: nada vivo sin sesión', () async {
    vigia.arrancar();
    vigia.parar();
    cola.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(
      ciclos,
      isEmpty,
      reason: 'un aviso vivo después de salir es trabajo corriendo sobre una '
          'sesión muerta',
    );
  });

  test('un fallo en el aviso no tumba la vigilancia', () async {
    // El reloj es justamente el respaldo de esto: si el aviso se cae, se sigue
    // sincronizando cada pocos minutos.
    vigia.arrancar();
    cola.addError(Exception('se rompió'));
    await Future<void>.delayed(Duration.zero);

    cola.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(ciclos, ['se hizo algo']);
  });
}
