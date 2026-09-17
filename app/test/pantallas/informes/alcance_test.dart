// EL ALCANCE DE INFORMES: NI UN VEHICULO DE OTRA SUCURSAL, Y EL DINERO CON SU
// MONEDA.
//
// El selector de vehiculos de esta pantalla hacia un `select(vehicles)` a pelo,
// sin filtro de sucursal: era la unica fuga de alcance de toda la aplicacion.
// Con ella, un operador veia en el desplegable los camiones de las otras siete
// sucursales y, al elegir uno, se le abria el informe de esa sucursal — sus
// ingresos, sus pedidos y sus precios. En delivery ya paso: un operador de
// Santiago vio los precios de La Habana.
//
// Y la otra mitad: los importes se GUARDAN en USD siempre y el CUP se calcula al
// pintarlo, con la tasa de ESA sucursal. Sin tasa suya no se convierte nada y no
// se cae a la de otra.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/informes/estado/informes_estado.dart';

import '../../apoyo/base_de_prueba.dart';

// El dato de produccion de hoy: sólo La Habana y Santiago tienen tasa (700
// CUP/USD, del 09/09/2026, que Accesos da por NO fresca).
const _tasaDeHoy = 700.0;
final _del9 = DateTime(2026, 9, 9, 22, 3, 4);

void main() {
  late BaseLocal base;
  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  Future<void> sucursal(
    String id,
    String nombre, {
    double? cupRate,
    DateTime? traidoAt,
    bool? fresca,
  }) => base
      .into(base.branches)
      .insertOnConflictUpdate(
        BranchesCompanion.insert(
          id: id,
          name: nombre,
          lat: 20,
          lng: -75,
          cupRate: Value(cupRate),
          cupRateTraidoAt: Value(traidoAt),
          cupRateFresca: Value(fresca),
        ),
      );

  Future<void> vehiculo(String id, String nombre, String sucursalId) => base
      .into(base.vehicles)
      .insertOnConflictUpdate(
        VehiclesCompanion.insert(
          id: id,
          name: nombre,
          branchId: Value(sucursalId),
        ),
      );

  /// Monta un contenedor con la sucursal elegida y deja que Drift entregue.
  ///
  /// **Nada de `await` sobre el primer valor de un stream de Drift**: se deja el
  /// stream escuchado y se le da una vuelta al bucle de eventos. Un `await`
  /// sobre `.first` de un stream que ya emitio no vuelve nunca y deja la prueba
  /// colgada sin decir por que.
  Future<ProviderContainer> mirando(String? sucursalId) async {
    final contenedor = ProviderContainer(
      overrides: [baseProvider.overrideWithValue(base)],
    );
    addTearDown(contenedor.dispose);
    contenedor.read(sucursalMiradaProvider.notifier).mirar(sucursalId);
    for (final p in [sucursalesProvider, vehiculosDelInformeProvider]) {
      addTearDown(contenedor.listen(p, (_, _) {}).close);
    }
    await Future<void>.delayed(Duration.zero);
    return contenedor;
  }

  // ---------------------------------------------------------------------------
  // LA GUARDA: el filtro de sucursal del selector de vehiculos
  // ---------------------------------------------------------------------------

  group('el selector de vehiculos de Informes', () {
    test('NO enseña vehiculos de otra sucursal', () async {
      await sucursal('stg', 'Santiago');
      await sucursal('hab', 'La Habana');
      await vehiculo('v1', 'Ford 600', 'stg');
      await vehiculo('v2', 'Camión de La Habana', 'hab');

      final contenedor = await mirando('stg');
      final vistos = contenedor.read(vehiculosDelInformeProvider).value!;

      expect(
        vistos.map((v) => v.id).toList(),
        ['v1'],
        reason:
            'El selector de vehiculos de Informes esta enseñando camiones de '
            'otra sucursal: le falta el filtro por `sucursalMiradaProvider`. '
            'Elegir uno de esos abre el informe de esa otra sucursal — sus '
            'ingresos, sus pedidos y sus precios. Es exactamente lo que paso '
            'en delivery cuando Santiago vio los precios de La Habana.',
      );
    });

    test('con «todas las sucursales» se ven todos', () async {
      await sucursal('stg', 'Santiago');
      await sucursal('hab', 'La Habana');
      await vehiculo('v1', 'Ford 600', 'stg');
      await vehiculo('v2', 'Camión de La Habana', 'hab');

      final contenedor = await mirando(null);
      final vistos = contenedor.read(vehiculosDelInformeProvider).value!;
      expect(vistos.map((v) => v.id).toSet(), {'v1', 'v2'});
    });

    test('al cambiar de sucursal la lista cambia con ella', () async {
      await sucursal('stg', 'Santiago');
      await sucursal('hab', 'La Habana');
      await vehiculo('v1', 'Ford 600', 'stg');
      await vehiculo('v2', 'Camión de La Habana', 'hab');

      final contenedor = await mirando('stg');
      expect(
        contenedor.read(vehiculosDelInformeProvider).value!.single.id,
        'v1',
      );

      contenedor.read(sucursalMiradaProvider.notifier).mirar('hab');
      await Future<void>.delayed(Duration.zero);
      expect(
        contenedor.read(vehiculosDelInformeProvider).value!.single.id,
        'v2',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // El dinero, con su moneda
  // ---------------------------------------------------------------------------

  group('un importe de Informes', () {
    test('en una sucursal CON tasa sale en CUP y sin decimales', () async {
      await sucursal(
        'hab',
        'La Habana',
        cupRate: _tasaDeHoy,
        traidoAt: _del9,
        fresca: false,
      );
      await sucursal('gr', 'Granma');

      final contenedor = await mirando('hab');
      contenedor.read(monedaMiradaProvider.notifier).mirar('CUP');

      final tasa = contenedor.read(tasaDeLaMiradaProvider);
      final moneda = contenedor.read(monedaEfectivaProvider);
      expect(moneda, 'CUP');
      // 1234.56 × 700 = 864192. En CUP no hay centimos: los precios reales van
      // en cientos o en miles y el centimo sólo ensucia la lectura.
      expect(tasa.importe(1234.56, moneda), '864.192 CUP');
      // La tasa es del dia 9 y se usa igual, PERO diciendolo.
      expect(tasa.aviso, contains('9/9/2026'));
    });

    test('en una sucursal SIN tasa se queda en USD, y dice por que', () async {
      await sucursal(
        'hab',
        'La Habana',
        cupRate: _tasaDeHoy,
        traidoAt: _del9,
        fresca: true,
      );
      await sucursal('gr', 'Granma');

      final contenedor = await mirando('gr');
      contenedor.read(monedaMiradaProvider.notifier).mirar('CUP');

      final tasa = contenedor.read(tasaDeLaMiradaProvider);
      final moneda = contenedor.read(monedaEfectivaProvider);

      // LA GUARDA: aunque arriba este elegido CUP, Granma no tiene tasa y NO se
      // usa la de La Habana. Un importe convertido con la tasa que no era se lee
      // bien y esta mal, que es lo peor que le puede pasar a un numero que
      // alguien va a cobrar.
      expect(
        moneda,
        'USD',
        reason:
            'Se esta ofreciendo CUP en una sucursal sin tasa: el unico numero '
            'disponible es el de OTRA sucursal, y usarlo es el fallo que esta '
            'regla existe para impedir.',
      );
      expect(
        tasa.importe(1234.56, moneda),
        '1.234,56 USD',
        reason:
            'El importe de una sucursal sin tasa salio convertido: se esta '
            'usando la tasa de otra sucursal.',
      );
      expect(tasa.motivo, contains('Granma'));
    });

    test('con «todas las sucursales» tampoco hay CUP', () async {
      await sucursal('hab', 'La Habana', cupRate: _tasaDeHoy, traidoAt: _del9);
      await sucursal('stg', 'Santiago', cupRate: _tasaDeHoy, traidoAt: _del9);

      final contenedor = await mirando(null);
      contenedor.read(monedaMiradaProvider.notifier).mirar('CUP');

      final moneda = contenedor.read(monedaEfectivaProvider);
      expect(
        moneda,
        'USD',
        reason:
            'Con todas las sucursales a la vista no hay UNA tasa que valga '
            'para las ocho: enseñar la de una cualquiera es el error que mas '
            'daño hace.',
      );
    });
  });
}
