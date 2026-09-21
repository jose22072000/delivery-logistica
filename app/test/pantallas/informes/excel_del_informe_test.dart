// EL EXCEL DE REPORTES, ABIERTO Y MIRADO POR DENTRO.
//
// Cada prueba de aquí genera el fichero de verdad, lo descomprime y lee las
// celdas (`apoyo/leer_xlsx.dart`). Lo que se comprueba son las tres cosas que
// el pliego exige (`docs/pantallas.md:632-634`) y la que más caro sale:
//
//  1. las tres hojas, con sus nombres y en su orden;
//  2. las columnas de cada una y su fila de totales;
//  3. **los importes en la moneda que se está mirando**, cuadrando con lo que
//     `TasaDeLaMirada.importe` pinta en la pantalla.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/diseno/numeros.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/pantallas/informes/datos/consultas_informes.dart';
import 'package:reparto/pantallas/informes/datos/excel_del_informe.dart';

import 'apoyo/leer_xlsx.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  final generado = DateTime(2026, 9, 14, 10, 36);

  // Dos camiones y tres pedidos. El tercero va sin vehículo a propósito: entra
  // en `Detalle` y en el `Resumen`, y NO en `Por Vehículo` (contrato §9).
  final filas = [
    FilaDeInforme(
      id: 'o1',
      cliente: 'Panadería La Habana',
      destino: 'Calle 23 & L',
      pesoKg: 12.34,
      importe: 100,
      fecha: DateTime(2026, 9, 13),
      ruta: 'R-001',
      vehiculoId: 'v1',
      vehiculo: 'Ford 600',
      placa: 'P123',
      kmDesdePartida: 8.25,
    ),
    FilaDeInforme(
      id: 'o2',
      cliente: 'Bodega Centro',
      destino: 'Neptuno 12',
      pesoKg: 5,
      importe: 50.5,
      fecha: DateTime(2026, 9, 13),
      ruta: 'R-001',
      vehiculoId: 'v1',
      vehiculo: 'Ford 600',
      placa: 'P123',
    ),
    const FilaDeInforme(
      id: 'o3',
      cliente: 'Sin camión',
      destino: 'Almacén',
      pesoKg: 2,
      importe: 9.99,
    ),
  ];

  final informe = Informe(
    filas: filas,
    resumen: ConsultasInformes.resumir(filas),
    porVehiculo: ConsultasInformes.agruparPorVehiculo(filas),
  );

  const filtro = FiltroDeInforme();

  LibroLeido exportar({
    ConversionDelInforme conversion = ConversionDelInforme.usd,
    FiltroDeInforme elFiltro = filtro,
  }) => leerXlsx(
    ExcelDelInforme.armar(
      informe: informe,
      filtro: elFiltro,
      conversion: conversion,
      generado: generado,
    ),
  );

  // ---------------------------------------------------------------------------
  // Las tres hojas
  // ---------------------------------------------------------------------------

  test(
    'el libro trae LAS TRES HOJAS del pliego, con su nombre y en su orden',
    () {
      expect(
        exportar().keys.toList(),
        ['Resumen', 'Por Vehículo', 'Detalle de Órdenes'],
        reason:
            'Las tres hojas del pliego (docs/pantallas.md:632-634) son «Resumen», '
            '«Por Vehículo» y «Detalle de Órdenes», en ese orden, que es el de '
            'las tres pestañas de la pantalla. Falta una, sobra una o están '
            'cambiadas de sitio: quien abra el fichero no encuentra lo que vio '
            'en la pantalla.',
      );
    },
  );

  test('el fichero se llama reporte-procovar-AAAA-MM-DD.xlsx', () {
    expect(
      ExcelDelInforme.nombreDeFichero(DateTime(2026, 9, 4)),
      'reporte-procovar-2026-09-04.xlsx',
    );
    expect(
      ExcelDelInforme.nombreDeFichero(DateTime(2026, 12, 31)),
      'reporte-procovar-2026-12-31.xlsx',
    );
  });

  // ---------------------------------------------------------------------------
  // Hoja 1 — Resumen
  // ---------------------------------------------------------------------------

  group('la hoja Resumen', () {
    test('lleva la cabecera del pliego y las cuatro cifras', () {
      final hoja = exportar()['Resumen']!;

      expect(hoja[0].first, 'Reporte de transportación — ProCovar');
      expect(hoja[1], ['Generado', '14/9/2026, 10:36']);
      expect(hoja[2], ['Filtro fecha', '— - —']);
      expect(hoja[3], ['Moneda', 'USD']);

      expect(hoja[5], ['Total Órdenes', 3]);
      // 100 + 50,50 + 9,99
      expect(hoja[6], ['Ingresos Totales (USD)', 160.49]);
      // 160,49 / 3 = 53,4966… y en la celda van dos decimales, como la tarjeta.
      expect(hoja[7], ['Precio Promedio (USD)', 53.5]);
      // 12,34 + 5 + 2, con un decimal como `Numeros.kg`.
      expect(hoja[8], ['Peso Total (kg)', 19.3]);
    });

    test('el rango de fechas es el que está puesto en los filtros', () {
      final hoja = exportar(
        elFiltro: FiltroDeInforme(
          desde: DateTime(2026, 9, 1),
          hasta: DateTime(2026, 9, 14),
        ),
      )['Resumen']!;
      expect(hoja[2], ['Filtro fecha', '1/9/2026 - 14/9/2026']);
    });
  });

  // ---------------------------------------------------------------------------
  // Hoja 2 — Por Vehículo
  // ---------------------------------------------------------------------------

  group('la hoja Por Vehículo', () {
    test(
      'lleva las seis columnas del pliego, con la moneda en la cabecera',
      () {
        expect(exportar()['Por Vehículo']!.first, [
          'Vehículo',
          'Placa',
          'Órdenes',
          'Ingresos (USD)',
          'Peso (kg)',
          'Promedio/Orden (USD)',
        ]);
      },
    );

    test('sólo entran los pedidos con vehículo, y cierra con TOTALES', () {
      final hoja = exportar()['Por Vehículo']!;

      // Cabecera, una fila de camión y el pie. El pedido sin camión no asoma
      // por aquí.
      expect(hoja.length, 3);
      expect(hoja[1], ['Ford 600', 'P123', 2, 150.5, 17.3, 75.25]);

      expect(
        hoja.last,
        ['Totales', '', 2, 150.5, 17.3, ''],
        reason:
            'La hoja «Por Vehículo» tiene que cerrar con la misma fila de '
            'totales que el pie de la pantalla. Sin ella, quien cuadra caja '
            'vuelve a sumar a mano sobre una hoja que ya traía el total.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Hoja 3 — Detalle de Órdenes
  // ---------------------------------------------------------------------------

  group('la hoja Detalle de Órdenes', () {
    test('lleva las ocho columnas del pliego', () {
      expect(exportar()['Detalle de Órdenes']!.first, [
        'Fecha',
        'Cliente',
        'Ruta',
        'Destino',
        'Vehículo',
        'Km desde partida',
        'Peso (kg)',
        'Precio (USD)',
      ]);
    });

    test('sale entera —no se pagina— y cierra con TOTALES', () {
      final hoja = exportar()['Detalle de Órdenes']!;

      // Cabecera + las tres órdenes + el pie.
      expect(hoja.length, 5);
      expect(hoja[1], [
        '13/9/2026',
        'Panadería La Habana',
        'R-001',
        // El `&` del destino sale tal cual: si el XML no lo escapara, el
        // fichero no abriría.
        'Calle 23 & L',
        'Ford 600',
        8.3,
        12.3,
        100,
      ]);

      expect(
        hoja.last,
        ['Totales:', '', '', '', '', '', 19.3, 160.49],
        reason:
            'El pie de «Detalle de Órdenes» tiene que traer el peso total y el '
            'importe total, los mismos que el pie de la pantalla.',
      );
    });

    test('sin km desde partida se deja el HUECO, nunca un cero', () {
      final segunda = exportar()['Detalle de Órdenes']![2];
      expect(
        segunda[5],
        isNull,
        reason:
            'Un cero en «Km desde partida» se lee como «salió de la partida», '
            'que es otra cosa que «no se sabe». Un hueco se ve y se pregunta.',
      );
      // Y la fila no se corre: el precio sigue en su columna.
      expect(segunda[7], 50.5);
    });

    test('un pedido sin ruta ni vehículo sale con la raya, no vacío', () {
      final tercera = exportar()['Detalle de Órdenes']![3];
      expect(tercera[2], '—');
      expect(tercera[4], '—');
    });
  });

  // ---------------------------------------------------------------------------
  // LA MONEDA. Lo más caro de esta pantalla.
  // ---------------------------------------------------------------------------

  group('los importes van EN LA MONEDA QUE SE ESTÁ MIRANDO', () {
    // La tasa real de producción: 700 CUP por USD.
    const enCup = ConversionDelInforme(moneda: 'CUP', cupPorUsd: 700);

    test('en CUP se convierten TODOS, y la cabecera lo dice', () {
      final libro = exportar(conversion: enCup);

      expect(libro['Resumen']![3], ['Moneda', 'CUP']);
      expect(
        libro['Resumen']![6],
        ['Ingresos Totales (CUP)', 112343],
        reason:
            'Los ingresos salieron en dólares bajo una cabecera que pone '
            '«(CUP)». 160,49 USD y 112.343 CUP son el mismo dinero, pero el '
            'primero se lee como una cifra 700 veces menor y nadie lo nota: es '
            'el número creíble y equivocado que el CLAUDE.md pone como lo peor '
            'que le puede pasar a un importe que alguien va a cobrar.',
      );
      expect(libro['Resumen']![7].last, 37448); // 53,4966… × 700
      expect(libro['Por Vehículo']![1][3], 105350); // 150,50 × 700
      expect(libro['Por Vehículo']![1][5], 52675); // 75,25 × 700
      expect(libro['Detalle de Órdenes']![1].last, 70000); // 100 × 700
      expect(libro['Detalle de Órdenes']!.last.last, 112343);

      // Y lo que NO es dinero se queda como estaba: el peso no se convierte.
      expect(libro['Resumen']![8], ['Peso Total (kg)', 19.3]);
      expect(libro['Resumen']![5], ['Total Órdenes', 3]);
    });

    test('la celda cuadra EXACTAMENTE con lo que pinta la pantalla', () {
      // El mismo objeto que usa la pantalla para pintar cada importe.
      final tasa = TasaDeLaMirada.hay(
        cupPorUsd: 700,
        traidoAt: DateTime(2026, 9, 9),
      );

      for (final enPantalla in [
        (celda: exportar(conversion: enCup)['Resumen']![6].last, usd: 160.49),
        (
          celda: exportar(conversion: enCup)['Detalle de Órdenes']![2].last,
          usd: 50.5,
        ),
      ]) {
        expect(
          '${Numeros.entero(enPantalla.celda! as num)} CUP',
          tasa.importe(enPantalla.usd, 'CUP'),
          reason:
              'La hoja y la pantalla dan dos números distintos para la misma '
              'suma. Esta pantalla existe para cuadrar caja: si el Excel no '
              'cuadra con ella, no sirve para nada.',
        );
      }
    });

    test('en USD se escribe el importe tal cual, con dos decimales', () {
      final libro = exportar();
      expect(libro['Detalle de Órdenes']![2].last, 50.5);
      expect(
        Numeros.importe(libro['Resumen']![7].last! as num),
        '53,50',
        reason: 'El promedio de la hoja no cuadra con el de la tarjeta.',
      );
    });

    test('pedir CUP sin tasa NO escribe dólares: se niega', () {
      expect(
        () => ExcelDelInforme.armar(
          informe: informe,
          filtro: filtro,
          conversion: const ConversionDelInforme(moneda: 'CUP'),
          generado: generado,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'el motivo',
            contains('no tiene tasa de cambio'),
          ),
        ),
        reason:
            'Sin la tasa de ESA sucursal no se convierte nada y no se cae a la '
            'de otra ni a los dólares crudos. Mejor no dar fichero —eso se ve— '
            'que dar uno con la cabecera «(CUP)» encima de dólares.',
      );
    });

    test('una tasa en cero o negativa tampoco vale', () {
      for (final tasa in [0.0, -700.0]) {
        expect(
          () => ConversionDelInforme(
            moneda: 'CUP',
            cupPorUsd: tasa,
          ).convertir(100),
          throwsStateError,
        );
      }
    });
  });
}
