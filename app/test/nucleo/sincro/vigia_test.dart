import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/sincro/vigia.dart';

/// EL VIGIA, con la red y el reloj inyectados.
///
/// Ni un `sleep` ni un `Future.delayed`: el temporizador es de mentira y la
/// prueba lo dispara a mano. Un `Timer.periodic` de verdad en una prueba es un
/// temporizador colgado que falla por lo que no es — y aqui lo que se comprueba
/// es justamente que no quede ninguno vivo.
class TemporizadorFalso implements Timer {
  TemporizadorFalso(this.periodo, this.alTocar);

  final Duration periodo;
  final void Function(Timer) alTocar;

  bool cancelado = false;
  int _tics = 0;

  /// Un tic, como si hubiera pasado el periodo.
  void tocar() {
    if (cancelado) {
      throw StateError('un temporizador cancelado no puede tocar');
    }
    _tics++;
    alTocar(this);
  }

  @override
  void cancel() => cancelado = true;

  @override
  bool get isActive => !cancelado;

  @override
  int get tick => _tics;
}

void main() {
  late StreamController<bool> red;
  late List<String> disparos;
  late List<TemporizadorFalso> temporizadores;

  setUp(() {
    red = StreamController<bool>.broadcast();
    disparos = <String>[];
    temporizadores = <TemporizadorFalso>[];
  });

  tearDown(() => red.close());

  VigiaDeSincronizacion montar({
    Future<void> Function(String)? ciclo,
    Duration periodo = const Duration(minutes: 5),
  }) => VigiaDeSincronizacion(
    ciclo:
        ciclo ??
        (motivo) async {
          disparos.add(motivo);
        },
    avisosDeRed: () => red.stream,
    periodo: periodo,
    crearTemporizador: (cuanto, alTocar) {
      final t = TemporizadorFalso(cuanto, alTocar);
      temporizadores.add(t);
      return t;
    },
  );

  /// Deja correr las microtareas pendientes. No avanza el reloj: no hace falta.
  Future<void> asentar() => Future<void>.delayed(Duration.zero);

  group('el aviso de red', () {
    test('volvio la red: se dispara un ciclo', () async {
      final vigia = montar()..arrancar();
      addTearDown(vigia.parar);

      red.add(true);
      await asentar();

      expect(disparos, ['volvio la red']);
    });

    test('se FUE la red: no se dispara nada', () async {
      final vigia = montar()..arrancar();
      addTearDown(vigia.parar);

      red.add(false);
      await asentar();

      expect(
        disparos,
        isEmpty,
        reason:
            'sin red no hay nada que intentar; la aplicacion ya se comporta '
            'igual siempre',
      );
    });

    test('el aviso es una PISTA: dos avisos son dos intentos', () async {
      // El vigia no decide si hay red ni se acuerda de nada: dispara intentos.
      // Quien impide que se solapen es el candado del ciclo, no esto — asi un
      // primer intento que fallo porque el wifi mentia se vuelve a intentar.
      final vigia = montar()..arrancar();
      addTearDown(vigia.parar);

      red
        ..add(true)
        ..add(true);
      await asentar();

      expect(disparos, ['volvio la red', 'volvio la red']);
    });

    test('un error del plugin no tumba la vigilancia', () async {
      // Un destino sin soporte, o una prueba sin canales de plugin. Queda el
      // reloj, que es justamente para esto.
      final vigia = montar()..arrancar();
      addTearDown(vigia.parar);

      red.addError(StateError('el canal no existe'));
      await asentar();
      red.add(true);
      await asentar();

      expect(vigia.andando, isTrue);
      expect(disparos, ['volvio la red']);
    });
  });

  group('el reloj', () {
    test('toca y dispara un ciclo, por si el aviso no llega nunca', () async {
      // En web es lo normal: no hay aviso de connectivity y sin el reloj el dia
      // no subiria jamas.
      final vigia = montar()..arrancar();
      addTearDown(vigia.parar);

      expect(temporizadores, hasLength(1));
      expect(temporizadores.single.periodo, const Duration(minutes: 5));

      temporizadores.single.tocar();
      await asentar();

      expect(disparos, ['toco el reloj']);
    });

    test('arrancar dos veces no monta dos relojes', () async {
      final vigia = montar()
        ..arrancar()
        ..arrancar();
      addTearDown(vigia.parar);

      expect(temporizadores, hasLength(1));
    });
  });

  group('primer plano', () {
    test('detras se para el reloj; delante vuelve y se intenta ya', () async {
      final vigia = montar()..arrancar();
      addTearDown(vigia.parar);

      vigia.enPrimerPlano(false);
      expect(vigia.hayTemporizador, isFalse);
      expect(temporizadores.single.cancelado, isTrue);
      expect(disparos, isEmpty);

      vigia.enPrimerPlano(true);
      await asentar();

      expect(vigia.hayTemporizador, isTrue);
      expect(
        disparos,
        ['la aplicacion volvio delante'],
        reason:
            'es el momento en que alguien saca el telefono del bolsillo '
            'despues de la mannana entera sin cobertura',
      );
    });
  });

  group('al cerrar sesion', () {
    test('NO queda ningun temporizador vivo ni nadie escuchando', () async {
      final vigia = montar()..arrancar();

      expect(vigia.hayTemporizador, isTrue);
      expect(red.hasListener, isTrue);

      vigia.parar();

      expect(vigia.andando, isFalse);
      expect(vigia.hayTemporizador, isFalse);
      expect(
        temporizadores.single.cancelado,
        isTrue,
        reason:
            'un temporizador vivo despues de salir es trabajo corriendo '
            'sobre una sesion muerta',
      );

      await asentar();
      expect(red.hasListener, isFalse);
    });

    test('despues de parar, ni el aviso de red despierta nada', () async {
      final vigia = montar()..arrancar();
      vigia.parar();
      await asentar();

      red.add(true);
      await asentar();

      expect(disparos, isEmpty);
    });

    test('se puede volver a arrancar al entrar otra vez', () async {
      final vigia = montar()
        ..arrancar()
        ..parar();
      await asentar();

      vigia.arrancar();
      addTearDown(vigia.parar);
      red.add(true);
      await asentar();

      expect(disparos, ['volvio la red']);
      expect(temporizadores, hasLength(2));
      expect(temporizadores.last.cancelado, isFalse);
    });
  });
}
