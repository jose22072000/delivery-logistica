// LAS TRES PANTALLAS CONTESTAN LO MISMO SOBRE EL MISMO DATO.
//
// El 22/09/2026, con Santiago elegida arriba:
//
//  * **Tablero** — en blanco: «Santiago de Cuba no tiene ningún almacén con
//    coordenadas»;
//  * **Almacenes** — uno, «Santiago de Cuba», Principal, Activo, con su punto en
//    20.0247, -75.8219;
//  * **Panel** — ✓ «Al menos un almacén con su punto puesto».
//
// Tres respuestas para una sola pregunta, y la que manda —el Tablero— dejaba sin
// usar la pantalla a **siete de las ocho sucursales**: 220 pedidos y 40.983 kg
// parados sólo en Camagüey. Es el patrón del `CLAUDE.md` §3-bis, y lo que lo ata
// es esta prueba, no un comentario.
//
// LA FORMA DE LA PRUEBA IMPORTA: **dos sucursales sembradas, una con almacén y
// otra sin él.** Con una sola, un filtro que compara el código contra el uuid
// —o que mira la tabla equivocada— sale verde igual, que es exactamente como
// esto llegó hasta producción.

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/almacenes/almacen_de_referencia.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/clientes/datos/repositorio_clientes.dart';
import 'package:reparto/pantallas/panel/datos/configuracion_pendiente.dart';
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

  Future<void> sucursal(String id, String codigo, String nombre) => base
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

  Future<void> almacen(
    String id,
    String codigo, {
    double? lat = 20.0247,
    double? lng = -75.8219,
    bool principal = true,
    bool activo = true,
    String nombre = 'Almacén central',
  }) => base
      .into(base.warehouses)
      .insertOnConflictUpdate(
        WarehousesCompanion.insert(
          id: id,
          sucursalCodigo: codigo,
          nombre: nombre,
          lat: Value(lat),
          lng: Value(lng),
          principal: Value(principal),
          activo: Value(activo),
        ),
      );

  /// Las cuatro colecciones bajadas: sin esto el paso a paso contesta «no se
  /// sabe» y el tablero, «todavía no ha bajado», que es otra pregunta.
  Future<void> yaBajaronLasCuatro() async {
    for (final c in const [
      Colecciones.sucursales,
      Colecciones.vehiculos,
      Colecciones.almacenes,
      Colecciones.ajustes,
    ]) {
      await base
          .into(base.frescura)
          .insertOnConflictUpdate(
            FrescuraCompanion.insert(
              coleccion: c,
              bajadaAt: Value(DateTime(2026, 9, 22, 8)),
            ),
          );
    }
  }

  // ───────────────── el fallo de producción, con DOS sucursales ─────────────

  group('el tablero de CADA sucursal', () {
    test(
      'la que tiene su almacén puesto SACA tablero, y la que no, el cartel',
      () async {
        await yaBajaronLasCuatro();
        await sucursal('b-stg', 'STG', 'Santiago de Cuba');
        await sucursal('b-hol', 'HOL', 'Holguín');
        // Sólo Santiago tiene almacén. Holguín no.
        await almacen('a-stg', 'STG', nombre: 'Santiago de Cuba');

        final origen = await tablero.almacenDe('b-stg');
        expect(origen.nombre, 'Santiago de Cuba');
        expect(origen.lat, 20.0247);

        await expectLater(
          () => tablero.almacenDe('b-hol'),
          throwsA(
            isA<SinAlmacenConCoordenadas>()
                .having((e) => e.noHaBajado, 'noHaBajado', isFalse)
                .having(
                  (e) => e.mensaje,
                  'mensaje',
                  'Holguín no tiene ningún almacén con coordenadas',
                ),
          ),
          reason: 'el cartel se queda: sin punto no se cotizan distancias',
        );
      },
    );

    test('las OCHO sacan tablero cuando las ocho tienen su almacén', () async {
      await yaBajaronLasCuatro();
      const lasOcho = <(String, String, String)>[
        ('b1', 'CAM', 'Camagüey'),
        ('b2', 'GR', 'Granma'),
        ('b3', 'GTO', 'Guantánamo'),
        ('b4', 'HOL', 'Holguín'),
        ('b5', 'HAB', 'La Habana'),
        ('b6', 'TUN', 'Las Tunas'),
        ('b7', 'SS', 'Sancti Spíritus'),
        ('b8', 'STG', 'Santiago'),
      ];
      for (final (id, codigo, nombre) in lasOcho) {
        await sucursal(id, codigo, nombre);
        await almacen('a-$id', codigo, nombre: 'Almacén de $nombre');
      }

      for (final (id, _, nombre) in lasOcho) {
        final origen = await tablero.almacenDe(id);
        expect(
          origen.nombre,
          'Almacén de $nombre',
          reason:
              'el tablero de $nombre mide desde el almacén de otra sucursal '
              'o no mide',
        );
      }
    });

    test('el almacén de OTRA sucursal no vale como origen', () async {
      await yaBajaronLasCuatro();
      await sucursal('b-stg', 'STG', 'Santiago');
      await sucursal('b-hab', 'HAB', 'La Habana');
      await almacen('a-hab', 'HAB');

      await expectLater(
        () => tablero.almacenDe('b-stg'),
        throwsA(isA<SinAlmacenConCoordenadas>()),
        reason:
            'ordenar Santiago desde La Habana sale con kilómetros y todo, y '
            'está mal',
      );
    });
  });

  // ───────────────── lo que no se sabe no es lo que falta ───────────────────

  group('el cartel dice la verdad', () {
    test('sin bajar los almacenes NO se acusa a la sucursal', () async {
      await sucursal('b-hab', 'HAB', 'La Habana');
      // Nada bajado todavía: es como arranca la web en cada carga.

      await expectLater(
        () => tablero.almacenDe('b-hab'),
        throwsA(
          isA<SinAlmacenConCoordenadas>()
              .having((e) => e.noHaBajado, 'noHaBajado', isTrue)
              .having((e) => e.mensaje, 'mensaje', contains('no ha bajado')),
        ),
      );
    });

    test('bajados y sin ninguno, el cartel de siempre CON el nombre', () async {
      await yaBajaronLasCuatro();
      await sucursal('b-gto', 'GTO', 'Guantánamo');
      // Uno sin coordenadas: se miró, y no sirve.
      await almacen('a-gto', 'GTO', lat: null, lng: null);

      await expectLater(
        () => tablero.almacenDe('b-gto'),
        throwsA(
          isA<SinAlmacenConCoordenadas>()
              .having((e) => e.noHaBajado, 'noHaBajado', isFalse)
              .having(
                (e) => e.mensaje,
                'mensaje',
                'Guantánamo no tiene ningún almacén con coordenadas',
              ),
        ),
      );
    });
  });

  // ───────────────── el nudo: las tres contestan igual ──────────────────────

  group('Panel, Tablero y Clientes', () {
    /// Las ocho, cada una con su almacén en un estado distinto. Es el caso que
    /// ninguna de las pruebas de antes cubría: todas sembraban UNA sucursal con
    /// su almacén bueno.
    Future<void> lasOchoComoEstanDeVerdad() async {
      await yaBajaronLasCuatro();
      await sucursal('b1', 'CAM', 'Camagüey');
      await almacen('a1', 'CAM'); // principal, con punto
      await sucursal('b2', 'GR', 'Granma');
      await almacen('a2', 'GR', principal: false); // con punto, no principal
      await sucursal('b3', 'GTO', 'Guantánamo');
      await almacen('a3', 'GTO', lat: null, lng: null); // sin punto
      await sucursal('b4', 'HOL', 'Holguín'); // sin almacén ninguno
      await sucursal('b5', 'HAB', 'La Habana');
      // EL NOMBRE DEL PRINCIPAL IMPORTA, y por eso es «Zona franca» y no
      // «Almacén Habana», que es como estaba: contra «Patio» ganaba también
      // por orden alfabético, así que la preferencia por `principal` no se
      // ejercitaba y quitarla salía verde. Ahora el alfabético dice «Patio» y
      // el principal dice «Zona franca»: sólo uno de los dos puede tener razón.
      await almacen('a5a', 'HAB', principal: false, nombre: 'Patio');
      await almacen('a5b', 'HAB', nombre: 'Zona franca'); // el principal
    }

    Future<bool> elPanelDice(String sucursalId) async {
      final pasos = await ConfiguracionPendiente(base)
          .mirar(sucursalId: sucursalId)
          .first;
      return pasos.paso(ClaveDePaso.almacen).como == ComoVa.hecho;
    }

    Future<bool> elTableroDice(String sucursalId) async {
      try {
        await tablero.almacenDe(sucursalId);
        return true;
      } on SinAlmacenConCoordenadas {
        return false;
      }
    }

    Future<bool> clientesDice(String sucursalId) async {
      final repo = RepositorioClientes(base);
      final codigo = await repo.codigoDeSucursal(sucursalId);
      return await repo.almacenDeReferencia(codigo) != null;
    }

    test('contestan lo mismo, sucursal por sucursal', () async {
      await lasOchoComoEstanDeVerdad();

      for (final (id, nombre) in const [
        ('b1', 'Camagüey'),
        ('b2', 'Granma'),
        ('b3', 'Guantánamo'),
        ('b4', 'Holguín'),
        ('b5', 'La Habana'),
      ]) {
        final panel = await elPanelDice(id);
        final tab = await elTableroDice(id);
        expect(
          tab,
          panel,
          reason:
              'almacén de $nombre: el Panel dice una cosa y el Tablero otra. '
              'La que alguien cree es siempre la equivocada.',
        );
        expect(
          await clientesDice(id),
          panel,
          reason:
              'almacén de $nombre: el Panel dice una cosa y la ficha de '
              'Clientes otra',
        );
      }
    });

    test('y eligen EL MISMO, no sólo «hay o no hay»', () async {
      await lasOchoComoEstanDeVerdad();

      final origen = await tablero.almacenDe('b5');
      final deClientes = await RepositorioClientes(base)
          .almacenDeReferencia('HAB');
      expect(
        origen.id,
        deClientes?.id,
        reason:
            'dos medidas distintas de «cuán lejos está este cliente» es peor '
            'que una aproximada: con ésta se le cobra el domicilio',
      );
      expect(
        origen.nombre,
        'Zona franca',
        reason:
            'gana el principal, no el primero por orden alfabético («Patio»)',
      );
    });

    /// LA PREFERENCIA POR `principal`, SIN EL ORDER BY QUE LA TAPA.
    ///
    /// `de(...)` pide `ORDER BY principal DESC, nombre ASC`, así que le llega a
    /// [AlmacenDeReferencia.elegir] una lista que YA trae el principal delante:
    /// por ahí, quitar el bucle que lo prefiere sale verde igual. Quien tiene
    /// las filas en la mano no las trae siempre así, y entonces el bucle es lo
    /// único que hay. Esta prueba se las da en el orden malo a propósito.
    test('elegir prefiere el principal aunque llegue el último', () async {
      await lasOchoComoEstanDeVerdad();

      final porNombre =
          await (base.select(base.warehouses)
                ..where((w) => w.sucursalCodigo.equals('HAB'))
                ..orderBy([(w) => OrderingTerm.asc(w.nombre)]))
              .get();
      expect(
        porNombre.first.nombre,
        'Patio',
        reason:
            'la lista tiene que llegar con el principal detrás, o no prueba '
            'nada',
      );

      expect(
        AlmacenDeReferencia.elegir(porNombre)?.nombre,
        'Zona franca',
        reason:
            'se midió desde «Patio» teniendo principal: dos lecturas del mismo '
            'cliente dan dos distancias, y con ésa se le cobra el domicilio',
      );
    });

    /// Y EL DESEMPATE ENTRE DOS QUE NO SON PRINCIPAL, que es donde el orden
    /// de la consulta es lo ÚNICO que hay: `elegir` devuelve el primero de la
    /// lista tal y como se la den. Se siembran al revés del alfabeto a
    /// propósito, porque sin `ORDER BY` SQLite los devuelve en el orden en que
    /// entraron y entonces la prueba no probaría nada.
    test(
      'sin principal manda el nombre, y no el orden en que entraron',
      () async {
        await yaBajaronLasCuatro();
        await sucursal('b9', 'CMG', 'Ciego');
        await almacen('a9b', 'CMG', principal: false, nombre: 'Zona sur');
        await almacen('a9a', 'CMG', principal: false, nombre: 'Almacén norte');

        final elegido = await AlmacenDeReferencia.de(base, 'CMG');
        expect(
          elegido?.nombre,
          'Almacén norte',
          reason:
              'sin un desempate estable, dos lecturas seguidas miden desde dos '
              'almacenes distintos y los km de la misma tarjeta bailan solos',
        );
      },
    );

    /// LOS DOS CASOS QUE SEPARABAN AL PANEL DEL TABLERO — y que hasta el
    /// 24/09/2026 también separaban a Clientes, que tenía su propia consulta y
    /// sólo miraba que las coordenadas estuvieran puestas. Las TRES entran aquí:
    /// son justo las dos sucursales donde una ficha mediría desde un almacén de
    /// baja (un número creíble) o desde el golfo de Guinea (8.600 km).
    test('un almacén inactivo y uno en (0,0) no cuentan en NINGUNA', () async {
      await yaBajaronLasCuatro();
      await sucursal('b6', 'TUN', 'Las Tunas');
      await almacen('a6', 'TUN', activo: false);
      await sucursal('b7', 'SS', 'Sancti Spíritus');
      await almacen('a7', 'SS', lat: 0, lng: 0);

      for (final (id, nombre) in const [
        ('b6', 'Las Tunas'),
        ('b7', 'Sancti Spíritus'),
      ]) {
        expect(
          await elPanelDice(id),
          isFalse,
          reason: '$nombre: el Panel lo da por bueno y no lo es',
        );
        expect(
          await elTableroDice(id),
          isFalse,
          reason: '$nombre: el Tablero lo da por bueno y no lo es',
        );
        expect(
          await clientesDice(id),
          isFalse,
          reason:
              '$nombre: Clientes lo da por bueno y no lo es. Con eso la ficha '
              'rellena la columna de km desde ese almacén y el filtro «Hasta N '
              'km» contesta con otros clientes — y de esos km sale lo que se le '
              'cobra al cliente.',
        );
      }
    });

    test('la regla compartida y la del Panel son LA MISMA', () async {
      await lasOchoComoEstanDeVerdad();
      await sucursal('b7', 'SS', 'Sancti Spíritus');
      await almacen('a7', 'SS', lat: 0, lng: 0);

      for (final (id, codigo) in const [
        ('b1', 'CAM'),
        ('b2', 'GR'),
        ('b3', 'GTO'),
        ('b4', 'HOL'),
        ('b5', 'HAB'),
        ('b7', 'SS'),
      ]) {
        expect(
          await AlmacenDeReferencia.de(base, codigo) != null,
          await elPanelDice(id),
          reason:
              'el SQL del paso a paso y `AlmacenDeReferencia.elegir` tienen '
              'que contestar igual para $codigo',
        );
      }
    });
  });
}
