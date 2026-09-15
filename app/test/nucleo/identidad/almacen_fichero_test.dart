@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion_fichero.dart';

import '../../apoyo/apoyo_sesion.dart';

/// EL ALMACEN DEL ESCRITORIO — el caso S1 de `docs/pruebas.md` en la mitad que
/// hasta hoy no se cumplia.
///
/// > «con red: abrir, entrar, que baje el dia. sin red: CERRAR la aplicacion y
/// > volver a abrirla ← aqui se rompe»
///
/// En Linux se rompia de verdad, y no por el codigo de la casa: el almacen del
/// sistema acepta la escritura y despues no encuentra nada
/// (`almacen_sesion_fichero.dart` tiene el porque con el C++ delante). La
/// aplicacion de escritorio quedaba descalificada entera, porque «funciona sin
/// conexion» es la razon de ser del proyecto.
///
/// Lo que se prueba aqui es exactamente eso, con ficheros de verdad en el
/// disco: **se guarda, se monta el almacen DE CERO, y lo guardado se lee**. Y
/// las tres cosas que lo rodean: que el par no queda en claro, que el fichero
/// de otra maquina no se abre ni se borra, y que un sitio donde no se puede
/// escribir **lo dice** en vez de prometer un dia entero sin senal.
void main() {
  late Directory carpeta;

  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('reparto-almacen-');
  });

  tearDown(() async {
    // Que la carpeta quede legible pase lo que pase: una prueba deja 0500 a
    // proposito y sin esto el borrado falla y ensucia /tmp.
    await Process.run('chmod', <String>['700', carpeta.path]);
    if (carpeta.existsSync()) await carpeta.delete(recursive: true);
  });

  AlmacenEnFichero almacen({String maquina = 'maquina-de-prueba'}) =>
      AlmacenEnFichero(carpeta: carpeta, materialDeLaMaquina: maquina);

  test('lo que se guarda se lee con el almacen montado DE CERO', () async {
    // «De cero» es lo que importa: leer de la misma instancia que acaba de
    // escribir no prueba nada, porque el caso de verdad es cerrar la
    // aplicacion en el almacen y volver a abrirla al dia siguiente, sin senal.
    final sesion = sesionDePrueba(refresh: 'refresh-del-dia');
    expect(await almacen().guardar(sesion), isTrue);

    final otroArranque = almacen();
    final leida = await otroArranque.leer();

    expect(leida, isNotNull);
    expect(leida!.refresh, 'refresh-del-dia');
    expect(leida.token, sesion.token);
    expect(leida.sub, sesion.sub);
    expect(leida.sucursalId, sesion.sucursalId);
    expect(leida.roles, sesion.roles);
  });

  test('sin nada guardado no hay sesion, y no es un fallo', () async {
    expect(await almacen().leer(), isNull);
  });

  test('borrar deja el almacen sin sesion', () async {
    await almacen().guardar(sesionDePrueba());
    await almacen().borrar();
    expect(await almacen().leer(), isNull);
  });

  test('guardar dos veces deja la ultima, no las dos', () async {
    await almacen().guardar(sesionDePrueba(refresh: 'el-viejo'));
    await almacen().guardar(sesionDePrueba(refresh: 'el-nuevo'));
    expect((await almacen().leer())?.refresh, 'el-nuevo');
  });

  group('lo que hay en el disco', () {
    test('el par NO queda en claro en el fichero', () async {
      await almacen().guardar(sesionDePrueba(refresh: 'refresh-en-claro-no'));
      final crudo = await _elFichero(carpeta).readAsString();

      expect(crudo, isNot(contains('refresh-en-claro-no')));
      expect(crudo, isNot(contains('sucursalId')));
      // Y el sobre es lo que dice ser: version, sal, nonce, dato y sello.
      final sobre = jsonDecode(crudo) as Map<String, Object?>;
      expect(sobre['v'], 1);
      expect(
        sobre.keys,
        containsAll(<String>['sal', 'nonce', 'dato', 'sello']),
      );
    });

    test('el fichero queda a 0600', () async {
      // Es lo unico que separa el par de tokens de otra cuenta de este mismo
      // ordenador. El cifrado no vale para eso: la clave se puede rehacer desde
      // esta maquina (ver la nota de seguridad del almacen).
      await almacen().guardar(sesionDePrueba());
      final permisos = await Process.run('stat', <String>[
        '-c',
        '%a',
        _elFichero(carpeta).path,
      ]);
      expect((permisos.stdout as String).trim(), '600');
    });

    test('dos guardados del MISMO par no salen iguales', () async {
      // Sal y nonce nuevos en cada escritura. Si salieran iguales, el keystream
      // se repetiria con la misma clave, que es como se rompen estas cosas.
      await almacen().guardar(sesionDePrueba(refresh: 'igual'));
      final primero = await _elFichero(carpeta).readAsString();
      await almacen().guardar(sesionDePrueba(refresh: 'igual'));
      final segundo = await _elFichero(carpeta).readAsString();
      expect(primero, isNot(segundo));
    });
  });

  group('el fichero esta atado a esta maquina', () {
    test('el de otra maquina no se abre', () async {
      await almacen(maquina: 'la-de-la-oficina').guardar(sesionDePrueba());
      expect(await almacen(maquina: 'otra-cualquiera').leer(), isNull);
    });

    test('y NO se borra: puede ser esta maquina manana', () async {
      // Un fichero que hoy no se abre —un `machine-id` que cambio, una carpeta
      // restaurada— no es motivo para tirar el par. La regla 3 de
      // `identidad.md` aplicada al disco.
      await almacen(maquina: 'la-buena').guardar(sesionDePrueba());
      expect(await almacen(maquina: 'la-mala').leer(), isNull);
      expect(_elFichero(carpeta).existsSync(), isTrue);
      expect(await almacen(maquina: 'la-buena').leer(), isNotNull);
    });

    test('un fichero tocado a mano no se cuela', () async {
      await almacen().guardar(sesionDePrueba());
      final fichero = _elFichero(carpeta);
      final sobre =
          jsonDecode(await fichero.readAsString()) as Map<String, Object?>;
      // Un byte del dato cambiado: el sello no cuadra y no se descifra nada.
      final dato = base64.decode(sobre['dato']! as String);
      dato[0] = dato[0] ^ 0xff;
      sobre['dato'] = base64.encode(dato);
      await fichero.writeAsString(jsonEncode(sobre));

      expect(await almacen().leer(), isNull);
    });

    test(
      'un fichero que no es ni JSON se trata como que no hay sesion',
      () async {
        await _elFichero(carpeta).writeAsString('esto no es una caja');
        expect(await almacen().leer(), isNull);
      },
    );
  });

  group('un sitio donde no se puede guardar LO DICE', () {
    // Esta es la prueba que no se puede romper: la promesa de la pantalla de
    // acceso —«una vez dentro puedes trabajar el dia entero sin senal»— solo se
    // hace si el almacen contesta que si. O se cumple, o no se promete.

    test('comprobar dice que si cuando el sitio sirve', () async {
      final salud = await almacen().comprobar();
      expect(salud.guarda, isTrue);
      expect(salud.motivo, isNull);
    });

    test('comprobar no deja basura detras', () async {
      await almacen().comprobar();
      final quedo = carpeta
          .listSync()
          .map((e) => e.path.split('/').last)
          .where((n) => n != 'maquina.sal')
          .toList();
      expect(quedo, isEmpty, reason: 'el fichero de la comprobacion se limpia');
    });

    test('comprobar NO se lleva por delante la sesion guardada', () async {
      await almacen().guardar(sesionDePrueba(refresh: 'r-bueno'));
      await almacen().comprobar();
      expect((await almacen().leer())?.refresh, 'r-bueno');
    });

    test('carpeta de solo lectura: guardar devuelve false, no lanza', () async {
      await almacen().guardar(sesionDePrueba()); // para que exista la carpeta
      await Process.run('chmod', <String>['500', carpeta.path]);

      expect(
        await almacen().guardar(sesionDePrueba(refresh: 'nuevo')),
        isFalse,
      );
    });

    test(
      'carpeta de solo lectura: comprobar lo dice ANTES de la contrasena',
      () async {
        await almacen().comprobar();
        await Process.run('chmod', <String>['500', carpeta.path]);

        final salud = await almacen().comprobar();
        expect(salud.guarda, isFalse);
        expect(salud.motivo, isNotNull);
      },
    );
  });
}

File _elFichero(Directory carpeta) => File('${carpeta.path}/sesion.caja');
