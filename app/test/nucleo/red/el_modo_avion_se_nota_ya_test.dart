// EL MODO AVIÓN SE TIENE QUE NOTAR YA — 22/09/2026.
//
// Jose puso el modo avión a las 12:21:31 y la franja siguió diciendo «Datos de
// las 12:20» en gris hasta las 12:23. Dos minutos en los que el Panel afirmaba
// «Los datos son de ahora mismo y no queda nada sin enviar». Una pantalla
// mintiendo, que es lo que este proyecto no se puede permitir.
//
// El motivo era que el estado salía SÓLO de contar peticiones caídas, y sin
// nadie pidiendo nada no hay nada que contar hasta el siguiente ciclo.
//
// Lo que se prueba aquí es el CABLE, no el modelo: que el aviso del sistema
// llega de verdad hasta `saludDeLaRedProvider`. El modelo —cuándo se cree y
// cuándo no— lo prueba `salud_test.dart`, y las dos hacen falta: con el modelo
// bien y el cable suelto, la pantalla volvería a mentir dos minutos.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/proveedores.dart';

void main() {
  late StreamController<bool> sistema;
  late ProviderContainer contenedor;

  setUp(() {
    sistema = StreamController<bool>.broadcast();
    contenedor = ProviderContainer(
      overrides: [
        // La pregunta de una vez dice que SÍ hay red, que es como arranca el
        // aparato de alguien que sale del almacén con cobertura.
        pistaDeRedProvider.overrideWithValue(() async => true),
        avisosDeRedProvider.overrideWithValue(() => sistema.stream),
      ],
    );
    // Alguien tiene que estar escuchando para que el `listen` de dentro corra.
    contenedor.listen(saludDeLaRedProvider, (_, _) {});
  });

  tearDown(() {
    contenedor.dispose();
    sistema.close();
  });

  Future<void> unRespiro() => Future<void>.delayed(Duration.zero);

  test('el aviso de «no hay red» del sistema enciende el estado al momento', () async {
    await unRespiro();
    expect(
      contenedor.read(saludDeLaRedProvider).vaMal,
      isFalse,
      reason: 'con cobertura y sin fallos, no hay nada que avisar',
    );

    sistema.add(false);
    await unRespiro();

    expect(
      contenedor.read(saludDeLaRedProvider).vaMal,
      isTrue,
      reason: 'modo avión: no hay que esperar a que se caigan tres peticiones',
    );
  });

  test('que vuelva la interfaz NO afirma que la conexión sirva', () async {
    await unRespiro();
    sistema.add(false);
    await unRespiro();
    sistema.add(true);
    await unRespiro();

    final salud = contenedor.read(saludDeLaRedProvider);
    expect(salud.sinInterfaz, isFalse);
    // Y no se inventa una «última buena»: eso lo escribe una petición que
    // llegue, no el plugin. En Cuba el teléfono enseña el wifi conectado y no
    // sale un paquete.
    expect(salud.ultimaBuena, isNull);
  });
}
