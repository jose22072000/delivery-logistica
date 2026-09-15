import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion_nativo.dart';

import '../../apoyo/apoyo_sesion.dart';

/// EL ALMACEN DE LA SESION — el caso S1 de `docs/pruebas.md`, el que sostiene
/// la promesa entera.
///
/// > «con red: abrir, entrar, que baje el dia. sin red: CERRAR la aplicacion y
/// > volver a abrirla ← aqui se rompe»
///
/// El 15/09/2026 se rompio de verdad, en la aplicacion de escritorio compilada
/// contra produccion: se entro con una cuenta buena, se cerro, se volvio a abrir
/// y pidio la contrasena otra vez. El par estaba escrito en el llavero del
/// sistema, asi que guardar guardo; lo que fallo fue **leerlo al arrancar**, y
/// lo que lo hizo grave fue que no se dijo en ningun sitio.
///
/// Estas pruebas cubren las tres mitades de eso:
///
///  1. lo que se guarda **se vuelve a leer montando el almacen de cero**;
///  2. un almacen que no deja leer **no lanza** —devolver `null` sube al portero
///     como «no hay sesion», y una excepcion suelta acaba en lo mismo pero
///     ademas puede tumbar el arranque—;
///  3. un almacen que acepta la escritura y despues no encuentra nada **lo
///     dice**, tanto al guardar como al preguntarle si sirve.
void main() {
  test('lo que se guarda se lee con el almacen montado DE CERO', () async {
    // «De cero» es la parte que importa: leer de la misma instancia que acaba de
    // escribir no prueba nada, porque el caso de verdad es abrir la aplicacion
    // otra vez al dia siguiente.
    final caja = _CajaDeMentira();
    final sesion = sesionDePrueba(refresh: 'refresh-del-dia');

    expect(await AlmacenSeguro(caja).guardar(sesion), isTrue);

    final otroArranque = AlmacenSeguro(caja);
    final leida = await otroArranque.leer();

    expect(leida, isNotNull);
    expect(leida!.refresh, 'refresh-del-dia');
    expect(leida.sub, sesion.sub);
    expect(leida.sucursalId, sesion.sucursalId);
  });

  test('borrar deja el almacen sin sesion', () async {
    final caja = _CajaDeMentira();
    final almacen = AlmacenSeguro(caja);
    await almacen.guardar(sesionDePrueba());
    await almacen.borrar();
    expect(await AlmacenSeguro(caja).leer(), isNull);
  });

  group('un almacen que se cae', () {
    test('leer NO lanza: devuelve null y lo deja en el registro', () async {
      // Antes el `try` solo envolvia el `jsonDecode`, asi que un fallo del
      // almacen del sistema subia hasta el portero, que lo traducia a «no hay
      // sesion» sin decir una palabra.
      final almacen = AlmacenSeguro(_CajaDeMentira(seCaeAlLeer: true));
      expect(await almacen.leer(), isNull);
    });

    test('leer que se cae NO borra lo guardado', () async {
      // Un almacen que hoy no contesta puede contestar mañana. Borrar el par por
      // un fallo del sistema es la regla 3 de `identidad.md` rota contra el
      // disco: dejar a alguien fuera en la calle por una caida pasajera.
      final caja = _CajaDeMentira();
      await AlmacenSeguro(caja).guardar(sesionDePrueba());
      caja.seCaeAlLeer = true;
      expect(await AlmacenSeguro(caja).leer(), isNull);

      caja.seCaeAlLeer = false;
      expect(await AlmacenSeguro(caja).leer(), isNotNull);
    });

    test('guardar que se cae devuelve false en vez de lanzar', () async {
      final almacen = AlmacenSeguro(_CajaDeMentira(seCaeAlEscribir: true));
      expect(await almacen.guardar(sesionDePrueba()), isFalse);
    });

    test('un guardado ilegible se trata como «no hay sesion»', () async {
      final caja = _CajaDeMentira()
        ..datos['reparto.sesion'] = 'esto no es json';
      expect(await AlmacenSeguro(caja).leer(), isNull);
    });
  });

  group('el almacen de Linux: acepta guardar y despues no encuentra nada', () {
    // ESTE es el modo de fallo que se vio, reproducido. No es que lance: es que
    // dice que si, y al leer contesta que no hay nada. Comprobado a mano el
    // 15/09/2026 con el propio codigo del plugin
    // (`flutter_secure_storage_linux` 3.0.3) contra el llavero de este equipo:
    // se escribe, el secreto queda en el llavero, y el `lookup` de vuelta
    // devuelve vacio. Con la version de antes de este cambio eso era, punto por
    // punto, un formulario de contrasena sin una sola explicacion.

    test('guardar lo dice: devuelve false', () async {
      final almacen = AlmacenSeguro(_CajaDeMentira(soloEscribe: true));
      expect(await almacen.guardar(sesionDePrueba()), isFalse);
    });

    test('comprobar lo dice ANTES de pedir la contrasena', () async {
      final salud = await AlmacenSeguro(_CajaDeMentira(soloEscribe: true))
          .comprobar();
      expect(salud.guarda, isFalse);
      expect(salud.motivo, isNotNull);
    });

    test('un almacen sano contesta que si, y no deja basura detras', () async {
      final caja = _CajaDeMentira();
      final salud = await AlmacenSeguro(caja).comprobar();
      expect(salud.guarda, isTrue);
      expect(
        caja.datos.keys,
        isEmpty,
        reason: 'la clave de la comprobacion se limpia detras',
      );
    });

    test('comprobar NO se lleva por delante la sesion guardada', () async {
      final caja = _CajaDeMentira();
      await AlmacenSeguro(caja).guardar(sesionDePrueba(refresh: 'r-bueno'));
      await AlmacenSeguro(caja).comprobar();
      expect((await AlmacenSeguro(caja).leer())?.refresh, 'r-bueno');
    });
  });
}

/// Un almacen del sistema de mentira, con sus tres formas de portarse mal.
///
/// Se hereda de `FlutterSecureStorage` de verdad —y no se simula con mocktail—
/// porque lo que se prueba es `AlmacenSeguro` hablando con LA MISMA interfaz que
/// usa en el aparato, con los mismos nombres de parametro.
class _CajaDeMentira extends FlutterSecureStorage {
  _CajaDeMentira({
    this.seCaeAlLeer = false,
    this.seCaeAlEscribir = false,
    this.soloEscribe = false,
  });

  final Map<String, String> datos = <String, String>{};

  /// Lanza al leer, como un servicio de secretos que no contesta.
  bool seCaeAlLeer;

  bool seCaeAlEscribir;

  /// **El caso de Linux**: acepta la escritura y no guarda nada.
  final bool soloEscribe;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (seCaeAlEscribir) throw Exception('el almacen del sistema no contesta');
    if (soloEscribe) return;
    if (value == null) {
      datos.remove(key);
    } else {
      datos[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (seCaeAlLeer) throw Exception('el almacen del sistema no contesta');
    return datos[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => datos.remove(key);
}
