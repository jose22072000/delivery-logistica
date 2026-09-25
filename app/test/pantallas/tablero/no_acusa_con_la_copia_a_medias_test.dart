// EL TABLERO NO ACUSA A UNA SUCURSAL CON LA COPIA A MEDIO REHACER.
//
// Jose, 25/09/2026, cambiando de sucursal en la barra de arriba: «me sale ahora
// en tablero q santiago no tiene ninguna sucursal activa por q razon me sale eso
// eso no lo habiamos arreglado y al ratico se arregla por q actualiza».
//
// Reproducido en la web desplegada, tres veces y con tres sucursales distintas
// —Granma, Holguín y Camagüey—: al cambiar arriba, el Tablero se quedaba en
// blanco con «X no tiene ningún almacén con coordenadas» durante unos treinta
// segundos y luego se arreglaba solo. Contrastado contra Accesos: **las tres lo
// tienen**, con su punto, principal y activo.
//
// POR QUÉ PASABA, que es lo que esta prueba sujeta. La guarda que separa «no lo
// tiene» de «todavía no ha bajado» existía desde el 22/09 y era demasiado floja:
//
//     if (tablaVacía && !bajaronNunca) -> «todavía no ha bajado»
//     -> si no, ACUSA
//
// `bajadaAt` se pone la primera vez y ya no se quita. Pasado ese momento
// `bajaronNunca` es falso para siempre, así que **cualquier instante con la
// tabla vacía caía en la rama que acusa**. Y la tabla se vaciaba a menudo: la
// bajada de almacenes borraba entera antes de rellenar, y el ciclo entero corre
// en cada cambio de sucursal.
//
// Es el §3-quinquies del `CLAUDE.md` visto del otro lado: no basta con tener la
// distinción escrita, tiene que disparar en el caso que ocurre.
//
// LA FORMA: la copia se deja a medias de las tres maneras en que se queda a
// medias de verdad, y se comprueba que ninguna acusa. Y **en pareja**, porque
// una guarda que nunca acusa tampoco vale: el hueco de verdad —Moa y Palma
// Soriano no tienen almacén— tiene que seguir saliendo.

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  late BaseLocal base;
  late ConsultasTablero tablero;

  setUp(() {
    base = baseDePrueba();
    tablero = ConsultasTablero(base);
  });

  tearDown(() => base.close());

  Future<void> sucursal(String id, String? codigo, String nombre) => base
      .into(base.branches)
      .insertOnConflictUpdate(
        BranchesCompanion.insert(
          id: id,
          name: nombre,
          lat: 20.02,
          lng: -75.82,
          externalId: Value(codigo),
        ),
      );

  Future<void> almacen(String id, String codigo, String nombre) => base
      .into(base.warehouses)
      .insertOnConflictUpdate(
        WarehousesCompanion.insert(
          id: id,
          sucursalCodigo: codigo,
          nombre: nombre,
          lat: const Value(20.0247),
          lng: const Value(-75.8219),
          principal: const Value(true),
          activo: const Value(true),
        ),
      );

  /// Los almacenes YA bajaron alguna vez a este aparato. Es el estado normal de
  /// cualquier sesión pasada el primer minuto, y es justo el que hacía que la
  /// guarda vieja se fuera siempre a la rama que acusa.
  Future<void> yaBajaronLosAlmacenes() => base
      .into(base.frescura)
      .insertOnConflictUpdate(
        FrescuraCompanion.insert(
          coleccion: Colecciones.almacenes,
          bajadaAt: Value(DateTime(2026, 9, 25, 16, 40)),
        ),
      );

  /// Lo que se espera de una copia a medias: se dice que no se sabe, **y no se
  /// nombra a la sucursal como culpable**.
  Matcher noAcusa(String nombre) => isA<SinAlmacenConCoordenadas>()
      .having((e) => e.noHaBajado, 'noHaBajado', isTrue)
      .having(
        (e) => e.mensaje,
        'mensaje',
        allOf(
          contains('todavía no han llegado'),
          isNot(contains('$nombre no tiene')),
        ),
      );

  group('la copia a medias NO es culpa de la sucursal', () {
    // EL CASO DE PRODUCCIÓN, exacto.
    //
    // Con la guarda vieja esto salía «Camagüey no tiene ningún almacén con
    // coordenadas» y dejaba el Tablero en blanco. Es el instante en que la
    // bajada había borrado la tabla y todavía no la había rellenado.
    test('la tabla entera vacía no dice nada de ninguna sucursal', () async {
      await yaBajaronLosAlmacenes();
      await sucursal('b-cam', 'CAM', 'Camagüey');

      await expectLater(
        () => tablero.almacenDe('b-cam'),
        throwsA(noAcusa('Camagüey')),
        reason:
            'ocho sucursales no pierden su almacén a la vez: una tabla vacía '
            'es una copia rehaciéndose, nunca un hecho sobre una sucursal',
      );
    });

    // La fila de la sucursal llegó, pero sin su código. `warehouses` guarda la
    // sucursal por CÓDIGO (`STG`), así que sin él no se ha podido ni preguntar.
    test('una sucursal todavía sin código no se puede juzgar', () async {
      await yaBajaronLosAlmacenes();
      await sucursal('b-stg', null, 'Santiago de Cuba');
      await almacen('a-stg', 'STG', 'Santiago de Cuba');

      await expectLater(
        () => tablero.almacenDe('b-stg'),
        throwsA(noAcusa('Santiago de Cuba')),
        reason: 'sin código no hay con qué preguntar por sus almacenes',
      );
    });

    test('los almacenes que no han bajado nunca siguen sin acusar', () async {
      await sucursal('b-hol', 'HOL', 'Holguín');

      await expectLater(
        () => tablero.almacenDe('b-hol'),
        throwsA(noAcusa('Holguín')),
      );
    });
  });

  // LA OTRA MITAD DE LA PAREJA.
  //
  // Sin esto, la guarda se podría arreglar poniendo `return true` y las tres de
  // arriba saldrían verdes mientras el hueco de verdad deja de avisar. Moa y
  // Palma Soriano existen en Accesos y no tienen almacén: a esas hay que
  // decírselo, porque se arregla dándolo de alta.
  group('el hueco de verdad SÍ se dice', () {
    test('con la copia entera delante, la que no lo tiene se nombra', () async {
      await yaBajaronLosAlmacenes();
      await sucursal('b-stg', 'STG', 'Santiago de Cuba');
      await sucursal('b-moa', 'MOA', 'Moa');
      // Hay almacenes en la copia, pero ninguno de Moa.
      await almacen('a-stg', 'STG', 'Santiago de Cuba');

      final origen = await tablero.almacenDe('b-stg');
      expect(origen.nombre, 'Santiago de Cuba');

      await expectLater(
        () => tablero.almacenDe('b-moa'),
        throwsA(
          isA<SinAlmacenConCoordenadas>()
              .having((e) => e.noHaBajado, 'noHaBajado', isFalse)
              .having(
                (e) => e.mensaje,
                'mensaje',
                'Moa no tiene ningún almacén con coordenadas',
              ),
        ),
        reason:
            'hay almacenes de otras y de ésta ninguno: eso es un hueco de '
            'verdad y se arregla dándolo de alta',
      );
    });
  });
}
