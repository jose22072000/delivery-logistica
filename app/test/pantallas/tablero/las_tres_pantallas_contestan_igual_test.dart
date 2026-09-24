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
      await almacen('a5a', 'HAB', principal: false, nombre: 'Patio');
      await almacen('a5b', 'HAB', nombre: 'Almacén Habana'); // el principal
    }

    Future<bool> elPanelDice(String sucursalId) async {
      final pasos = await ConfiguracionPendiente(
        base,
      ).mirar(sucursalId: sucursalId).first;
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
      final deClientes = await RepositorioClientes(
        base,
      ).almacenDeReferencia('HAB');
      expect(
        origen.id,
        deClientes?.id,
        reason:
            'dos medidas distintas de «cuán lejos está este cliente» es peor '
            'que una aproximada: con ésta se le cobra el domicilio',
      );
      expect(origen.nombre, 'Almacén Habana', reason: 'gana el principal');
    });

    /// LOS DOS CASOS QUE SEPARABAN AL PANEL DEL TABLERO.
    ///
    /// Clientes queda fuera **a propósito y está apuntado**: su consulta vive en
    /// `pantallas/clientes/`, que lleva otro, y todavía no descarta ni el
    /// inactivo ni el (0,0). Mientras no lo haga, de esa sucursal la ficha
    /// mediría desde el golfo de Guinea.
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
