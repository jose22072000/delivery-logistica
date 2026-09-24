import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/base/personas.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/sincro/huerfanos.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';

/// «¿TE QUEDA TRABAJO SIN SUBIR?» — LA PREGUNTA QUE SE HACE ANTES DE BORRAR.
///
/// Dos personas comparten la tablet, así que cada una tiene su copia y cerrar
/// sesión no borra nada. Lo que sí borra es **olvidar a alguien**
/// (`nucleo/base/personas.dart`): se lleva su dominio, su cola y su fichero.
/// Por eso ese gesto tiene una guarda, y la guarda es una sola pregunta:
/// `PersonaEnElAparato.tieneTrabajoSinSubir`, que es `cuantosPendientes() > 0`.
///
/// **Y `cuantosPendientes()` contaba una sola cosa**: las filas de `apuntes` en
/// estado `pendiente`. Ni los rechazados, ni lo huérfano. Las dos son trabajo
/// que se hizo en la calle y que **no está arriba**, y las dos salían a cero.
///
/// Era el mismo agujero que el tablero ya cerró el 16/09/2026 —su guarda de
/// «no bajes que me pisas» preguntaba exactamente esto y por eso el `DELETE` se
/// llevó la zona «Vista»— y `pantallas/tablero/datos/servicio.dart` lo dice con
/// todas las letras: «un apunte descartado —o rechazado, que tampoco cuenta
/// como pendiente— deja su fila local ahí, a la vista y sin nada que la suba».
/// El tablero aprendió a preguntar por las dos cosas; olvidar una copia, no.
///
/// **Cerrado el 24/09/2026**, y las dos pruebas de abajo iban marcadas
/// `HALLAZGO ·` pidiendo que se les diera la vuelta. Así quedó:
///
///  * `BaseLocal.cuantosSinSubir()` cuenta `pendiente` **y** `rechazado`, y
///    `cuantosPendientes()` se queda para donde la pregunta sí es la cola.
///  * `PersonaEnElAparato` trae además los rechazados y lo huérfano, y
///    `queSePierde` **nombra cada cosa** para poder ponerlo delante de alguien.
///  * `Personas.olvidar` anota **siempre** lo que se llevó, no sólo cuando
///    había pendientes.
///
/// La base va a un FICHERO, como en el molde de `jornada_entera_sin_senal`: lo
/// que se comprueba aquí es qué queda y qué se borra de un aparato de verdad, y
/// en memoria eso no significa nada.
void main() {
  late Directory carpeta;
  late File fichero;
  late RelojFalso reloj;

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('sin_subir');
    fichero = File('${carpeta.path}/reparto.sqlite');
    reloj = RelojFalso(DateTime(2026, 9, 24, 18));
  });

  tearDown(() async {
    if (carpeta.existsSync()) await carpeta.delete(recursive: true);
  });

  Future<BaseLocal> abrir() async {
    final base = BaseLocal.con(NativeDatabase(fichero));
    await aparatoYaDeAlta(base);
    return base;
  }

  test('un RECHAZADO SÍ cuenta como trabajo sin subir: es justo lo que nunca '
      'llegó', () async {
    final base = await abrir();
    addTearDown(base.close);
    final cola = ColaDeSalida(base, reloj: reloj.leer);

    // El cierre de la tarde salió, el servidor dijo que no y se quedó en la
    // bandeja con su motivo, esperando a que una persona decida. Eso es la
    // regla de la casa y está bien.
    final clave = await cola.encolar(
      metodo: 'POST',
      ruta: '/routes/r-tarde/results',
      cuerpo: const {'resultados': <Object?>[]},
    );
    await cola.resolver(
      clave,
      const ResultadoApunte(
      estado: EstadoResultado.rechazado,
      motivo: 'Esa ruta ya está cerrada',
    ),
    );
    expect((await cola.rechazados().first).single.motivo,
        'Esa ruta ya está cerrada');

    // LA COLA SIGUE VACÍA, y eso está bien: un rechazado no espera a subir,
    // espera a que alguien decida. Las dos preguntas son distintas y por eso
    // son dos.
    expect(
      await base.cuantosPendientes(),
      0,
      reason: '`cuantosPendientes` es «¿queda algo EN LA COLA?», y no queda',
    );

    // LA QUE SE HACE ANTES DE BORRAR SÍ LO VE.
    expect(
      await base.cuantosSinSubir(),
      1,
      reason:
          'un rechazado es trabajo que NO llegó al servidor. Si esto vuelve a '
          'dar 0, olvidar una copia se lleva por delante la única constancia '
          'de un cierre que no entró, sin avisar y sin dejar rastro',
    );
    expect(await base.cuantosRechazados(), 1);

    final persona = PersonaEnElAparato(
      sub: 'u1',
      nombre: 'Palma',
      pendientes: 0,
      rechazados: await base.cuantosRechazados(),
    );
    expect(persona.tieneTrabajoSinSubir, isTrue);
    expect(
      persona.queSePierde,
      '1 rechazado esperando a que alguien decida',
      reason:
          'se NOMBRA lo que se pierde. «Le queda trabajo sin subir» no le dice '
          'a nadie que lo que hay delante es un cierre que el servidor tumbó',
    );

    // Lo que se borra sigue siendo todo —eso es lo que ES olvidar—, pero ya no
    // se hace a ciegas: quien lo ofrece tiene el texto de arriba delante.
    await base.olvidar();
    expect(await cola.rechazados().first, isEmpty);
  });

  test('una ruta HUÉRFANA también cuenta, y ésa no la va a subir nadie nunca',
      () async {
    final base = await abrir();
    addTearDown(base.close);

    // La ruta se armó sin señal —lleva `local-…`— y su apunte se descartó.
    // `Huerfanos.volverAEncolar` sólo sabe rehacer el tablero, así que esto no
    // sube ni hoy ni mañana.
    await base
        .into(base.routes)
        .insert(RoutesCompanion.insert(id: 'local-9f3a2b7c'));

    expect(
      (await Huerfanos(base).mirar()).texto,
      '1 ruta',
      reason: 'quien pregunta bien SÍ la ve',
    );
    expect(
      await base.cuantosPendientes(),
      0,
      reason: 'no está en la cola: no le queda ningún apunte, ése es el caso',
    );
    expect(
      await base.cuantosSinSubir(),
      0,
      reason:
          'y tampoco está en `apuntes` de ninguna forma: lo huérfano vive en '
          'las tablas de dominio, así que hay que preguntarle a `Huerfanos`',
    );

    // POR ESO `PersonaEnElAparato` PREGUNTA POR LAS DOS COSAS.
    final persona = PersonaEnElAparato(
      sub: 'u1',
      nombre: 'Palma',
      pendientes: await base.cuantosSinSubir(),
      colgado: await Huerfanos(base).mirar(),
    );
    expect(
      persona.tieneTrabajoSinSubir,
      isTrue,
      reason:
          'si esto vuelve a ser `false`, el gesto de olvidar borra el trabajo '
          'de una mañana sin avisar de nada',
    );
    expect(
      persona.queSePierde,
      '1 ruta que sólo existe en este aparato',
      reason:
          'y se nombra: no es lo mismo que «sin subir», porque esto no lo sube '
          'nadie ni con señal',
    );

    await base.olvidar();
    expect(await Huerfanos(base).mirar(), isEmpty);
  });

  test('con un apunte pendiente de verdad la guarda SÍ salta', () async {
    // La pareja del §3-quinquies: la pregunta no está rota del todo, sólo es
    // demasiado estrecha. Sin esto, «arreglarla» poniéndola a `true` siempre
    // pasaría las dos de arriba.
    final base = await abrir();
    addTearDown(base.close);
    await ColaDeSalida(base, reloj: reloj.leer).encolar(
      metodo: 'PATCH',
      ruta: '/routes/r-1',
      cuerpo: const {'status': 'completed'},
    );

    expect(await base.cuantosPendientes(), 1);
    expect(await base.cuantosSinSubir(), 1);
    const persona = PersonaEnElAparato(sub: 'u1', nombre: 'Palma', pendientes: 1);
    expect(persona.tieneTrabajoSinSubir, isTrue);
    expect(persona.queSePierde, '1 apunte sin subir');
  });

  test('y una copia limpia de verdad no enciende nada', () async {
    final base = await abrir();
    addTearDown(base.close);
    await base.into(base.routes).insert(RoutesCompanion.insert(id: 'r-bajada'));

    expect(await base.cuantosPendientes(), 0);
    expect(await base.cuantosSinSubir(), 0);
    expect(await Huerfanos(base).mirar(), isEmpty);

    // LA OTRA MITAD DE LA PAREJA: sin nada dentro no se avisa de nada. Un aviso
    // que sale siempre deja de leerse, y este sale delante de un botón de
    // borrar (§3-quinquies).
    const persona = PersonaEnElAparato(sub: 'u1', nombre: 'Palma', pendientes: 0);
    expect(persona.tieneTrabajoSinSubir, isFalse);
    expect(persona.queSePierde, isEmpty);
  });

  test('las tres cosas a la vez se nombran las tres, y con «y» al final',
      () async {
    // El texto que va delante del botón de borrar. Se comprueba entero porque
    // es lo único que va a leer quien decide, y porque «4 cosas» —que es lo que
    // sale si alguien junta los tres números— no dice cuál de las tres tiene
    // delante ni cuál se arregla con señal.
    final base = await abrir();
    addTearDown(base.close);
    final cola = ColaDeSalida(base, reloj: reloj.leer);

    await cola.encolar(
      metodo: 'PATCH',
      ruta: '/routes/r-1',
      cuerpo: const {'status': 'completed'},
    );
    final clave = await cola.encolar(
      metodo: 'POST',
      ruta: '/routes/r-tarde/results',
      cuerpo: const {'resultados': <Object?>[]},
    );
    await cola.resolver(
      clave,
      const ResultadoApunte(
        estado: EstadoResultado.rechazado,
        motivo: 'Esa ruta ya está cerrada',
      ),
    );
    await base
        .into(base.routes)
        .insert(RoutesCompanion.insert(id: 'local-9f3a2b7c'));

    final persona = PersonaEnElAparato(
      sub: 'u1',
      nombre: 'Palma',
      pendientes: 1,
      rechazados: await base.cuantosRechazados(),
      colgado: await Huerfanos(base).mirar(),
    );

    expect(
      persona.queSePierde,
      '1 apunte sin subir, 1 rechazado esperando a que alguien decida y 1 ruta '
      'que sólo existe en este aparato',
    );
  });
}
