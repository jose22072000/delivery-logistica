// EL BOTON `Exportar a Excel` (pliego §7, `docs/pantallas.md:602`).
//
// El patron lo tiene asi (`reports/page.tsx:179-182`):
// `disabled={isLoading || orders.length === 0}`. Aqui se hace lo mismo **y una
// cosa mas: se dice POR QUE esta apagado**.
//
// Un boton gris sin explicacion es de los que se pulsan tres veces y luego
// vuelven como «el Excel no funciona». Y los tres motivos por los que puede
// estar apagado no son el mismo problema ni se arreglan igual: esperar a que
// cargue, cambiar los filtros, o avisar a la oficina porque la bajada no llego.
//
// El motivo va en un `Tooltip` que envuelve al boton, no dentro de el. Un
// `FilledButton` apagado no recibe el gesto, asi que el dedo llega al `Tooltip`
// de fuera: en un telefono sale con una pulsacion larga y en un monitor con
// pasar el raton por encima.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../navegacion/estado_navegacion.dart';
import '../../../nucleo/frescura/primera_bajada.dart';
import '../../../nucleo/proveedores.dart';
import '../datos/consultas_informes.dart';
import '../datos/entrega_del_excel.dart';
import '../datos/excel_del_informe.dart';
import '../datos/hoja_de_calculo.dart';
import '../estado/informes_estado.dart';

/// Lo que dice el boton y lo que dice cuando no se puede pulsar.
abstract final class TextosDeExportar {
  static const etiqueta = 'Exportar a Excel';

  /// Lo que se promete al pulsarlo: la moneda va en el rotulo del `Tooltip`
  /// porque el fichero se escribe **en la moneda que se esta mirando**, y un
  /// Excel en CUP que alguien creia en USD es el numero creible y equivocado
  /// de siempre.
  static String enQueMoneda(String moneda) =>
      'Exportar a Excel, con los importes en $moneda';

  /// Mientras el informe todavia se esta armando.
  static const cargando = 'Esperá a que termine de cargar el reporte.';

  /// Con filtros que no dejan ni una orden.
  static const sinOrdenes =
      'No hay ninguna orden que exportar con estos '
      'filtros.';

  /// En el aparato, sin haber bajado nunca.
  static const sinDescargar =
      'No hay nada descargado todavía: no hay nada que '
      'exportar.';

  /// En la web, cuando la bajada no llego.
  static const noBajo =
      'Los datos del reporte no bajaron: no hay nada que '
      'exportar.';

  /// Cuando el informe ni siquiera se pudo armar.
  static const noSePudoArmar =
      'El reporte no se pudo armar, así que no hay '
      'nada que exportar.';

  /// Mientras se escribe el fichero.
  static const armando = 'Armando el Excel...';
}

/// POR QUE no se puede exportar, o `null` si se puede.
///
/// Fuera del widget para poder probarla sola, y con los cuatro casos separados
/// a proposito: «no hay órdenes» delante de alguien cuya bajada no llegó es una
/// acusación falsa —le dice que sus filtros están mal cuando lo que pasa es que
/// no hay datos— y es el mismo error que ya se arregló en el cuerpo de esta
/// pantalla el 17/09/2026.
String? motivoParaNoExportar({
  required AsyncValue<Informe> informe,
  required bool sinDescargar,
  required PorQueEstaVacio porQue,
}) {
  if (sinDescargar) {
    return switch (porQue) {
      PorQueEstaVacio.noSeDescargo => TextosDeExportar.sinDescargar,
      PorQueEstaVacio.todaviaBajando => TextosDeExportar.cargando,
      PorQueEstaVacio.noPudoBajar => TextosDeExportar.noBajo,
    };
  }
  final valor = informe.value;
  if (valor == null) {
    return informe.hasError
        ? TextosDeExportar.noSePudoArmar
        : TextosDeExportar.cargando;
  }
  if (valor.filas.isEmpty) return TextosDeExportar.sinOrdenes;
  return null;
}

class BotonExportarExcel extends ConsumerStatefulWidget {
  const BotonExportarExcel({
    required this.sinDescargar,
    required this.porQue,
    super.key,
  });

  final bool sinDescargar;
  final PorQueEstaVacio porQue;

  @override
  ConsumerState<BotonExportarExcel> createState() => _BotonExportarExcelState();
}

class _BotonExportarExcelState extends ConsumerState<BotonExportarExcel> {
  /// Mientras se escribe el zip el boton no se puede volver a pulsar: dos
  /// exportaciones seguidas en la web sacan dos descargas del mismo fichero.
  bool _armando = false;

  @override
  Widget build(BuildContext context) {
    final informe = ref.watch(informeProvider);
    final moneda = ref.watch(monedaEfectivaProvider);
    final motivo = _armando
        ? TextosDeExportar.armando
        : motivoParaNoExportar(
            informe: informe,
            sinDescargar: widget.sinDescargar,
            porQue: widget.porQue,
          );

    return Tooltip(
      message: motivo ?? TextosDeExportar.enQueMoneda(moneda),
      child: FilledButton.icon(
        icon: const Icon(Icons.table_view_outlined, size: 18),
        onPressed: motivo == null ? _exportar : null,
        label: const Text(TextosDeExportar.etiqueta),
      ),
    );
  }

  Future<void> _exportar() async {
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final informe = ref.read(informeProvider).value;
    if (informe == null) return;

    final filtro = ref.read(filtroDeInformesProvider);
    final tasa = ref.read(tasaDeLaMiradaProvider);
    // LA MISMA PAREJA QUE PINTA LA PANTALLA. `monedaEfectivaProvider` ya se cae
    // a USD cuando la sucursal que se mira no tiene tasa, asi que aqui no puede
    // llegar un CUP sin tasa; si llegara, `convertir` lanza y se dice, que es
    // mucho mejor que escribir dolares bajo una cabecera que pone «(CUP)».
    final conversion = ConversionDelInforme(
      moneda: ref.read(monedaEfectivaProvider),
      cupPorUsd: tasa.cupPorUsd,
    );
    final cuando = ref.read(relojProvider)();
    final entrega = ref.read(entregaDeFicheroProvider);

    setState(() => _armando = true);
    Entregado resultado;
    try {
      final bytes = ExcelDelInforme.armar(
        informe: informe,
        filtro: filtro,
        conversion: conversion,
        generado: cuando,
      );
      resultado = await entrega.entregar(
        bytes: bytes,
        nombre: ExcelDelInforme.nombreDeFichero(cuando),
        tipoMime: tipoMimeXlsx,
      );
    } on Object catch (e) {
      // Armar el libro tambien puede fallar —una moneda sin tasa, un nombre de
      // hoja imposible— y eso NO se puede quedar en un `catch` vacio: la
      // pantalla se quedaria verde con un boton que no hizo nada.
      resultado = Entregado.noSePudo('No se pudo armar el Excel: $e');
    } finally {
      if (mounted) setState(() => _armando = false);
    }

    mensajero?.showSnackBar(SnackBar(content: Text(resultado.mensaje)));
  }
}
