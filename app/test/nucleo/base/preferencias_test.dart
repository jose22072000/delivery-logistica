import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/base/preferencias_del_aparato.dart';

import '../../apoyo/base_de_prueba.dart';

/// LO QUE SE ESTABA MIRANDO SOBREVIVE A CERRAR LA APLICACIÓN.
///
/// La sucursal y la moneda vivían en dos `Notifier` que arrancaban en «todas» y
/// en USD, así que se perdían en cada arranque. Con «Todas» puesto el Panel dice
/// «Falta configurar esta sucursal, 3 de 4» y los importes no se convierten —la
/// tasa es POR SUCURSAL—, de modo que la aplicación se abría pareciendo a medio
/// configurar cuando no lo estaba. Jose lo vio en su teléfono el 16/09/2026 con
/// La Habana ya elegida y completa.
void main() {
  late BaseLocal base;

  setUp(() => base = baseDePrueba());
  tearDown(() => base.close());

  test('lo elegido se lee igual que se escribió', () async {
    await base.anotarPreferencia(ClaveDePreferencia.sucursalMirada, 'hab-1');
    await base.anotarPreferencia(ClaveDePreferencia.monedaMirada, 'CUP');

    expect(await base.preferencia(ClaveDePreferencia.sucursalMirada), 'hab-1');
    expect(await base.preferencia(ClaveDePreferencia.monedaMirada), 'CUP');
  });

  test('elegir otra sucursal pisa la anterior, no añade una fila', () async {
    await base.anotarPreferencia(ClaveDePreferencia.sucursalMirada, 'hab-1');
    await base.anotarPreferencia(ClaveDePreferencia.sucursalMirada, 'stg-1');

    expect(await base.preferencia(ClaveDePreferencia.sucursalMirada), 'stg-1');
    final filas = await base.select(base.preferencias).get();
    expect(
      filas.where((f) => f.clave == ClaveDePreferencia.sucursalMirada).length,
      1,
      reason: 'la clave es la llave primaria: una sola fila por preferencia',
    );
  });

  test('volver a «Todas» BORRA la fila, no guarda una cadena vacía', () async {
    // Guardar «» y leerlo luego como sucursal elegida sería pedirle al servidor
    // los datos de una sucursal sin id. `null` significa «todas» y la única
    // forma de decirlo es que no haya fila.
    await base.anotarPreferencia(ClaveDePreferencia.sucursalMirada, 'hab-1');
    await base.anotarPreferencia(ClaveDePreferencia.sucursalMirada, null);

    expect(await base.preferencia(ClaveDePreferencia.sucursalMirada), isNull);
    final filas = await base.select(base.preferencias).get();
    expect(
      filas.any((f) => f.clave == ClaveDePreferencia.sucursalMirada),
      isFalse,
      reason: 'no queda una fila vacía haciéndose pasar por una elección',
    );
  });

  test(
    'una preferencia que nadie escribió es null, no una excepción',
    () async {
      expect(await base.preferencia(ClaveDePreferencia.monedaMirada), isNull);
    },
  );

  test('cada preferencia va por su lado', () async {
    await base.anotarPreferencia(ClaveDePreferencia.monedaMirada, 'CUP');
    await base.anotarPreferencia(ClaveDePreferencia.sucursalMirada, null);

    expect(
      await base.preferencia(ClaveDePreferencia.monedaMirada),
      'CUP',
      reason: 'borrar la sucursal no puede llevarse la moneda por delante',
    );
  });

  test('en la APK van a la base, que es un fichero y sobrevive', () async {
    // En la web NO: la base del navegador es en memoria desde que la web dejó de
    // guardar copia, así que estas dos elecciones se perderían en cada recarga y el
    // Super Admin tendría que volver a elegir su sucursal cada vez. Allí van a
    // `localStorage`, que es donde ya vive la sesión.
    //
    // Estas pruebas corren en la VM, o sea el camino de la APK.
    expect(
      PreferenciasDelAparato.fueraDeLaBase,
      isFalse,
      reason: 'fuera de la web mandan la tabla y el fichero',
    );

    await base.anotarPreferencia(ClaveDePreferencia.sucursalMirada, 'hab-1');
    final filas = await base.select(base.preferencias).get();
    expect(
      filas.where((f) => f.clave == ClaveDePreferencia.sucursalMirada).length,
      1,
      reason: 'se escribió en la tabla, no en otro sitio',
    );
  });
}
