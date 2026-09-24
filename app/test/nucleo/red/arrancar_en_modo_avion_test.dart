// ABRIR LA APLICACIÓN CON EL MODO AVIÓN YA PUESTO — 22/09/2026.
//
// `el_modo_avion_se_nota_ya_test.dart` prueba el otro caso: la aplicación
// abierta y la red que se va. Éste es el arranque de verdad del repartidor —
// **sale del almacén sin cobertura y ABRE la aplicación ahí**—, y es distinto
// porque no hay ningún cambio que avisar: el sistema ya estaba diciendo que no
// hay interfaz antes de que nadie preguntara.
//
// Lo que no puede pasar: que la salud nazca «bien» y se quede así hasta que
// alguien pida algo y se caiga. Eso es el Panel diciendo «Los datos son de
// ahora mismo» con el teléfono en modo avión, que es la pantalla mintiendo.
//
// Las dos pruebas van en pareja a propósito: sin la de «con interfaz nace
// bien», una salud que naciera SIEMPRE mal pasaría la primera.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/proveedores.dart';

void main() {
  late StreamController<bool> sistema;

  setUp(() {
    sistema = StreamController<bool>.broadcast();
  });

  tearDown(() => sistema.close());

  /// Un contenedor con la pista del sistema contestando [hayInterfaz] a la
  /// pregunta de una vez, que es la que se hace al abrir.
  ProviderContainer conElAparatoAsi({required bool hayInterfaz}) =>
      ProviderContainer(
        overrides: [
          pistaDeRedProvider.overrideWithValue(() async => hayInterfaz),
          avisosDeRedProvider.overrideWithValue(() => sistema.stream),
        ],
      );

  Future<void> unRespiro() => Future<void>.delayed(Duration.zero);

  test('abriendo YA en modo avión, la salud nace vaMal', () async {
    final contenedor = conElAparatoAsi(hayInterfaz: false);
    addTearDown(contenedor.dispose);

    // EL ORDEN ES EL DEL APARATO Y ES LA MITAD DE LA PRUEBA: la pista del
    // sistema se pregunta al pintar la primera pantalla, y la salud la
    // construye después quien la mire —el ciclo, o la franja—. Cuando eso pasa,
    // el «no hay interfaz» YA está contestado y no va a volver a cambiar: nadie
    // va a avisar de nada. Si la salud no se lo lleva puesto al nacer, nace
    // mintiendo.
    contenedor.listen(hayRedProvider, (_, _) {});
    await unRespiro();
    expect(
      contenedor.read(hayRedProvider).value,
      isFalse,
      reason: 'la pista ya contestó «no hay interfaz» antes de este punto',
    );

    final salud = contenedor.read(saludDeLaRedProvider);

    expect(
      salud.sinInterfaz,
      isTrue,
      reason:
          'el aparato abrió en modo avión y la salud nació con $salud: no se '
          'enteró del «no» que el sistema ya había dado',
    );
    expect(
      salud.vaMal,
      isTrue,
      reason:
          'nació «bien» a la espera de que se caiga la primera petición; hasta '
          'entonces el Panel dice «Los datos son de ahora mismo» en modo avión',
    );
  });

  test('abriendo CON interfaz, la salud nace bien', () async {
    final contenedor = conElAparatoAsi(hayInterfaz: true);
    addTearDown(contenedor.dispose);

    contenedor.listen(hayRedProvider, (_, _) {});
    await unRespiro();

    final salud = contenedor.read(saludDeLaRedProvider);

    expect(
      salud.sinInterfaz,
      isFalse,
      reason: 'hay interfaz: nació con $salud, avisando de una red que sí hay',
    );
    expect(
      salud.vaMal,
      isFalse,
      reason:
          'un aviso que sale siempre deja de leerse, y entonces tampoco se lee '
          'el día que importa',
    );
    // Y tener interfaz NO es haber hablado con el servidor: eso lo escribe una
    // petición que llegue, no el plugin.
    expect(salud.ultimaBuena, isNull);
  });
}
