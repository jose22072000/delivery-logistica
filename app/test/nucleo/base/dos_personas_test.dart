import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/base/conexion/nombre.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/sincro/identidad_del_aparato.dart';
import 'package:reparto/nucleo/sincro/subida.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';

/// DOS PERSONAS EN LA MISMA TABLET.
///
/// Palabras de Jose: «para q despues pueda tener varios usuario en un mismo
/// tablet pero es para q despues trabaje offline».
///
/// Lo que habia antes era **una sola base por aparato** y una cola que sobrevivia
/// al cierre de sesion a proposito. Juntas daban esto:
///
///  1. A entra, baja lo suyo, trabaja sin senal, le quedan 23 apuntes sin subir.
///  2. A cierra sesion: sus datos se borran, **sus 23 apuntes se quedan**.
///  3. Entra B y baja lo suyo.
///  4. Al haber senal, **los 23 apuntes de A suben con el token de B**.
///
/// Eso es trabajo de una sucursal subiendo como si fuera de otra, y no se ve en
/// ningun sitio hasta que no cuadra el inventario.
void main() {
  const a = 'uaoOUHqTXNYUv672kjdLoZLpFrseCz9e';
  const b = 'zzTRrLm19QfKd0aXpWnJ4uC2vB7sYhEg';

  group('el nombre del fichero', () {
    test('dos personas NUNCA comparten fichero', () {
      expect(nombreDeLaBase(a), isNot(nombreDeLaBase(b)));
    });

    test('la misma persona vuelve SIEMPRE al mismo fichero', () {
      // Es lo que hace que quien vuelve encuentre lo suyo en vez de rebajarse
      // sus ocho mil clientes por la conexion de alla.
      expect(nombreDeLaBase(a), nombreDeLaBase(a));
      expect(nombreDeLaBase(' $a '), nombreDeLaBase(a));
    });

    test('dos `sub` que empiezan igual y son largos NO chocan', () {
      // La parte legible se recorta a 32; sin la huella del `sub` entero, dos
      // personas compartirian fichero, que es exactamente lo que esto evita.
      final uno = 'a' * 40;
      final otro = '${'a' * 39}b';
      expect(nombreDeLaBase(uno), isNot(nombreDeLaBase(otro)));
    });

    test('sin nadie dentro NO se abre la base de la version vieja', () {
      // Si el nombre neutro fuera `reparto`, la pantalla de acceso estaria
      // leyendo los datos del ultimo que entro.
      expect(nombreDeLaBase(null), isNot(nombreDeLaBaseDeAntes));
      expect(nombreDeLaBase(''), isNot(nombreDeLaBaseDeAntes));
    });

    test('el nombre vale como fichero: nada raro dentro', () {
      expect(
        nombreDeLaBase('un/sub\\con:cosas raras'),
        matches(RegExp(r'^[A-Za-z0-9_-]+$')),
      );
    });
  });

  group('A y B en el mismo aparato, con ficheros de verdad', () {
    late Directory carpeta;

    setUp(() => carpeta = Directory.systemTemp.createTempSync('reparto-'));
    tearDown(() => carpeta.deleteSync(recursive: true));

    /// La base de una persona, en SU fichero, con el mismo nombre que usaria el
    /// aparato. Ficheros de verdad y no memoria: lo que se prueba es
    /// justamente que son dos ficheros.
    BaseLocal laDe(String? dueno) => BaseLocal.con(
      NativeDatabase(File('${carpeta.path}/${nombreDeLaBase(dueno)}.sqlite')),
      dueno: dueno,
    );

    test('los datos de A no aparecen en la sesion de B', () async {
      final deA = laDe(a);
      await deA
          .into(deA.customers)
          .insert(
            CustomersCompanion.insert(
              id: 'cliente-de-a',
              name: 'Ferretería del Centro',
              lat: 20.02,
              lng: -75.82,
            ),
          );
      await aparatoYaConfigurado(deA);
      await deA.close();

      // Cerrar sesion NO borra: cambia de copia.
      final deB = laDe(b);
      expect(await deB.select(deB.customers).get(), isEmpty);
      expect(
        await deB.select(deB.frescura).get(),
        isEmpty,
        reason: 'B empieza sin configurar, no con la marca de A',
      );
      await deB.close();

      // Y cuando A vuelve, lo suyo sigue ahi: entero y sin volver a bajarlo.
      final aDeVuelta = laDe(a);
      expect(await aDeVuelta.select(aDeVuelta.customers).get(), hasLength(1));
      expect(await aDeVuelta.duenoGuardado(), a);
      await aDeVuelta.close();
    });

    test('la cola de A no aparece en la cola de B', () async {
      final deA = laDe(a);
      final colaDeA = ColaDeSalida(
        deA,
        reloj: RelojFalso(DateTime(2026, 9, 15, 16, 4)).leer,
      );
      for (var i = 0; i < 23; i++) {
        await colaDeA.encolar(
          metodo: 'POST',
          ruta: '/api/routes/local-9f3a/results',
          cuerpo: <String, Object?>{'parada': i, 'resultado': 'entregado'},
        );
      }
      expect(await deA.cuantosPendientes(), 23);
      await deA.close();

      final deB = laDe(b);
      expect(
        await deB.cuantosPendientes(),
        0,
        reason: 'los 23 apuntes de A no pueden salir con el token de B',
      );
      await deB.close();

      final aDeVuelta = laDe(a);
      expect(
        await aDeVuelta.cuantosPendientes(),
        23,
        reason: 'y tampoco se pierden: son de A y esperan a A',
      );
      await aDeVuelta.close();
    });

    test('una copia dice de quién es y con qué nombre', () async {
      // Sin el nombre, el gesto de olvidar a alguien tendría que enseñar el
      // `sub` del token, que a quien lo lee no le dice nada.
      final deA = laDe(a);
      await deA.anotarNombreDelDueno('Yasmani');
      expect(await deA.duenoGuardado(), a);
      expect(await deA.nombreDelDueno(), 'Yasmani');
      await deA.close();
    });

    test('olvidar a alguien se lleva su dominio Y su cola', () async {
      final deA = laDe(a);
      await ColaDeSalida(deA).encolar(
        metodo: 'POST',
        ruta: '/api/routes/r-1/results',
        cuerpo: const <String, Object?>{},
      );
      await aparatoYaConfigurado(deA);
      expect(await deA.cuantosPendientes(), 1);

      await deA.olvidar();

      expect(await deA.cuantosPendientes(), 0);
      expect(await deA.select(deA.frescura).get(), isEmpty);
      await deA.close();
    });
  });

  group('LA GUARDA: la cola de A no viaja con el token de B', () {
    late BaseLocal base;
    late ColaDeSalida cola;

    setUp(() async {
      // La base es de A —lo dice ella misma, en `preferencias`— y lleva su
      // trabajo dentro.
      base = BaseLocal.con(NativeDatabase.memory(), dueno: a);
      await base
          .into(base.preferencias)
          .insertOnConflictUpdate(
            PreferenciasCompanion.insert(
              clave: ClaveDePreferencia.dueno,
              valor: a,
            ),
          );
      await aparatoYaDeAlta(base);
      cola = ColaDeSalida(base);
      await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes/r-1/results',
        cuerpo: const <String, Object?>{'resultado': 'entregado'},
      );
    });

    tearDown(() => base.close());

    ({Subida subida, ServidorFalso servidor}) conSesionDe(String? quien) {
      final servidor = ServidorFalso(
        (p) async =>
            RespuestaFalsa(200, <String, Object?>{'resultados': <Object?>[]}),
      );
      final cliente = clienteFalso(
        (p) async =>
            RespuestaFalsa(200, <String, Object?>{'resultados': <Object?>[]}),
        baseUrl: 'https://sync.test',
      );
      cliente.dio.httpClientAdapter = servidor;
      return (
        subida: Subida(
          cliente: cliente,
          cola: cola,
          aparato: IdentidadDelAparato(base),
          base: base,
          quienEsta: () async => quien,
        ),
        servidor: servidor,
      );
    }

    test('con B delante NO se manda nada, y la cola se queda entera', () async {
      final montaje = conSesionDe(b);

      await expectLater(
        montaje.subida.ciclo(),
        throwsA(isA<ColaDeOtraPersona>()),
      );

      expect(
        montaje.servidor.vistas,
        isEmpty,
        reason: 'ni una peticion: el apunte de A no sale firmado por B',
      );
      expect(
        await base.cuantosPendientes(),
        1,
        reason: 'y no se descarta: sube el dia que entre A',
      );
    });

    test('SIN SABER quién está, sube: la web no guarda sesión', () async {
      // ## Esta prueba exigía justo el fallo, y lo sostuvo hasta el 16/09/2026
      //
      // Decía «sin nadie dentro tampoco sale» y esperaba `ColaDeOtraPersona`. Pero
      // `null` no significa «hay otra persona delante»: significa **que no se sabe
      // quién está**, que no es lo mismo. Es la ausencia del dato, no un dato
      // distinto.
      //
      // En la web `quienEsta` es `null` SIEMPRE, porque allí la sesión es la
      // cookie del acceso único y no se guarda ningún token en el aparato. Y
      // `duenoGuardado()` sí devuelve el `sub`, que se anota al entrar. Así que
      // esto lanzaba en cada ciclo: **la web no ha subido ni un apunte desde que
      // existe**.
      //
      // Y lo que encadena detrás es lo que se veía en la pantalla: la cola se
      // queda llena para siempre, el tablero se niega a bajar mientras haya cola
      // —con razón, para no pisar lo que no ha subido— y la pantalla se congela a
      // la hora del primer gesto. Refrescar no hacía nada. El tablero de la web
      // llevaba hora y media parado mientras el teléfono subía sin problema.
      //
      // La guarda sigue entera donde importa: se bloquea con una CONTRADICCIÓN
      // —se sabe quién está y no es el dueño de la cola—, que es el caso del
      // móvil, donde dos personas comparten un aparato. En un navegador no las
      // hay.
      final montaje = conSesionDe(null);

      await montaje.subida.ciclo();

      expect(
        montaje.servidor.cuantas('POST', '/subida'),
        1,
        reason:
            'sin esto, la web no sube nada y su tablero no se actualiza nunca',
      );
    });

    test('con A delante sube, que es de lo que va todo esto', () async {
      final montaje = conSesionDe(a);
      await montaje.subida.ciclo();
      expect(montaje.servidor.cuantas('POST', '/subida'), 1);
    });
  });
}
