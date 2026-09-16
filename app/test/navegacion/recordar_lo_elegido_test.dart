import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/proveedores.dart';

import '../apoyo/base_de_prueba.dart';

/// LA SUCURSAL Y LA MONEDA SOBREVIVEN A CERRAR LA APLICACIÓN.
///
/// La prueba hermana (`nucleo/base/preferencias_test.dart`) sólo cubre el disco:
/// `anotarPreferencia` y `preferencia`. Nadie probaba lo que hay encima —que elegir
/// GUARDE y que al entrar se RESTAURE—, y se notaba: comentando entero
/// `_recordarLoElegido()` en el portero, las 716 pruebas seguían en verde y la aplicación
/// volvía a abrir en «Todas (8)» y USD. Medio protocolo escrito con nadie al otro lado,
/// que es el fallo que más veces se ha repetido en este proyecto.
///
/// Importa más de lo que parece: con «Todas» puesto el Panel dice «Falta configurar esta
/// sucursal, 3 de 4» y no convierte a CUP —la tasa es POR SUCURSAL—, así que la aplicación
/// se abre pareciendo a medio configurar sin estarlo.
void main() {
  late BaseLocal base;
  late ProviderContainer contenedor;

  setUp(() {
    base = baseDePrueba();
    contenedor = ProviderContainer(
      overrides: [baseProvider.overrideWithValue(base)],
    );
  });

  tearDown(() {
    contenedor.dispose();
    return base.close();
  });

  test('elegir una sucursal la deja anotada en el aparato', () async {
    contenedor.read(sucursalMiradaProvider.notifier).mirar('hab-1');
    expect(contenedor.read(sucursalMiradaProvider), 'hab-1');

    // La escritura va sin esperarse —quien toca el selector no puede quedarse mirando el
    // disco—, así que se le deja terminar.
    await Future<void>.delayed(Duration.zero);
    expect(
      await base.preferencia(ClaveDePreferencia.sucursalMirada),
      'hab-1',
      reason: 'sin esto, al abrir mañana vuelve a «Todas»',
    );
  });

  test('restaurar devuelve lo último que se eligió', () async {
    await base.anotarPreferencia(ClaveDePreferencia.sucursalMirada, 'stg-1');
    await base.anotarPreferencia(ClaveDePreferencia.monedaMirada, 'CUP');

    await contenedor.read(sucursalMiradaProvider.notifier).restaurar();
    await contenedor.read(monedaMiradaProvider.notifier).restaurar();

    expect(contenedor.read(sucursalMiradaProvider), 'stg-1');
    expect(contenedor.read(monedaMiradaProvider), 'CUP');
  });

  test('sin nada anotado se queda como estaba: «todas» y USD', () async {
    await contenedor.read(sucursalMiradaProvider.notifier).restaurar();
    await contenedor.read(monedaMiradaProvider.notifier).restaurar();

    expect(contenedor.read(sucursalMiradaProvider), isNull);
    expect(
      contenedor.read(monedaMiradaProvider),
      'USD',
      reason: 'un aparato nuevo no puede arrancar en una moneda que nadie eligió',
    );
  });

  test('volver a «Todas» se recuerda como «Todas», no como la de antes', () async {
    contenedor.read(sucursalMiradaProvider.notifier).mirar('hab-1');
    await Future<void>.delayed(Duration.zero);
    contenedor.read(sucursalMiradaProvider.notifier).mirar(null);
    await Future<void>.delayed(Duration.zero);

    final otro = ProviderContainer(
      overrides: [baseProvider.overrideWithValue(base)],
    );
    addTearDown(otro.dispose);
    await otro.read(sucursalMiradaProvider.notifier).restaurar();

    expect(
      otro.read(sucursalMiradaProvider),
      isNull,
      reason: 'si «Todas» no se guardara, quitar el filtro no duraría hasta mañana',
    );
  });

  test('elegir la moneda la deja anotada', () async {
    contenedor.read(monedaMiradaProvider.notifier).mirar('CUP');
    await Future<void>.delayed(Duration.zero);
    expect(await base.preferencia(ClaveDePreferencia.monedaMirada), 'CUP');
  });
}
