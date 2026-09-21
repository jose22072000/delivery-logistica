// UNA RUTA QUE SUBE MIENTRAS SE MIRA NO PUEDE QUEDARSE EN CERO PARADAS.
//
// Jose, 21/09/2026, armando una ruta de cinco pedidos con el teléfono delante:
// el detalle se abrió solo y dijo **«Ver paradas (0)»** y «Carga total: 0»,
// con «27.0 km (incl. regreso) · 616.7 kg» en la misma línea. Cerrar la ruta y
// volver a abrirla la enseñaba entera, con sus cinco paradas.
//
// O sea: el dato estaba bien y la pantalla mentía. «No, eso no puede pasar, eso
// es al momento».
//
// Lo que pasaba: la ruta se arma con un id provisional (`local-…`), el detalle
// se queda con ese id, y en cuanto sube, el id de verdad sustituye al
// provisional en TODAS las filas —incluidos los pedidos, que pasan a colgar del
// nuevo—. La pantalla seguía preguntando por el viejo, que ya no tiene paradas.
//
// La prueba no monta pantalla: mira el estado, que es donde estaba el fallo. Y
// sobre todo **cambia el id DESPUÉS**, con el provider ya mirando, que es la
// forma que exige el §3-ter del CLAUDE.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/provisionales.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/pantallas/rutas/estado/proveedores_rutas.dart';

import '../../apoyo/base_de_prueba.dart';

void main() {
  late BaseLocal base;
  late ProviderContainer caja;

  setUp(() {
    base = baseDePrueba();
    caja = ProviderContainer(overrides: [baseProvider.overrideWithValue(base)]);
  });

  tearDown(() async {
    caja.dispose();
    await base.close();
  });

  test('la ruta elegida sigue a su id cuando el provisional sube', () async {
    caja.listen(rutaElegidaProvider, (_, _) {});
    caja.listen(equivalenciasProvider, (_, _) {});

    const provisional = 'local-ruta-recien-armada';
    caja.read(rutaElegidaProvider.notifier).elegir(provisional);
    expect(caja.read(rutaElegidaProvider), provisional);

    // Y AHORA sube: el id de verdad sustituye al provisional, con la pantalla ya
    // mirando. Sembrar esto antes de elegir sería justo el caso que el fallo
    // resolvía bien.
    const real = '0199a0f0-1111-7000-8000-000000000001';
    await Provisionales(base).sustituir(provisional, real);
    await caja.read(equivalenciasProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(
      caja.read(rutaElegidaProvider),
      real,
      reason:
          'LA PANTALLA SE QUEDÓ MIRANDO UN ID QUE YA NO EXISTE: la ruta subió y '
          'sus pedidos pasaron al id de verdad, así que el detalle enseña «Ver '
          'paradas (0)» encima de una ruta que tiene paradas. Cerrar y volver a '
          'abrir lo tapa, y eso es peor: el dato está bien y la pantalla miente.',
    );
  });

  test('una ruta que NO es provisional no se toca', () async {
    caja.listen(rutaElegidaProvider, (_, _) {});
    caja.listen(equivalenciasProvider, (_, _) {});

    const deVerdad = '0199a0f0-2222-7000-8000-000000000002';
    caja.read(rutaElegidaProvider.notifier).elegir(deVerdad);

    await Provisionales(base).sustituir('local-otra', 'otra-de-verdad');
    await caja.read(equivalenciasProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(
      caja.read(rutaElegidaProvider),
      deVerdad,
      reason:
          'se cambió la ruta que estaba mirando por otra: la equivalencia de una '
          'ruta ajena no puede mover la elección de nadie',
    );
  });

  test('y si ya había subido ANTES de elegirla, se elige la de verdad', () async {
    // El caso más común, y el que se le escapaba al seguidor: el ciclo está
    // corriendo, la ruta sube en el mismo segundo en que se arma, y para cuando
    // el asistente la selecciona la equivalencia ya está escrita. No hay ningún
    // cambio que escuchar: hay que resolverlo al elegir.
    caja.listen(rutaElegidaProvider, (_, _) {});
    caja.listen(equivalenciasProvider, (_, _) {});

    const provisional = 'local-ruta-que-ya-subio';
    const real = '0199a0f0-3333-7000-8000-000000000003';
    await Provisionales(base).sustituir(provisional, real);
    await caja.read(equivalenciasProvider.future);

    caja.read(rutaElegidaProvider.notifier).elegir(provisional);

    expect(
      caja.read(rutaElegidaProvider),
      real,
      reason:
          'SE ELIGIÓ UN ID QUE YA NO EXISTE: la ruta subió antes de que el '
          'asistente la seleccionara, así que no hubo ningún cambio que '
          'escuchar. El detalle se abre con cero paradas sobre una ruta que las '
          'tiene.',
    );
  });
}
