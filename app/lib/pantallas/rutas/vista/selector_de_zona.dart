import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../pedidos/vista/kit.dart';
import '../datos/zona_en_el_asistente.dart';

/// EL DESPLEGABLE DE ZONAS DEL TABLERO, en la fila de filtros del paso 4.
///
/// Es un filtro mas, al lado del dia, el vendedor y el municipio, y se comporta
/// como ellos: elegir una zona deja la lista de disponibles **solo con sus
/// pedidos**. Lo que no hace ningun otro filtro es lo que pidio Jose:
/// ademas **los marca todos** y **trae el camion de la zona**.
///
/// > «tengo un seleccionar con dropdown q tenga todos los pedidos y de ahi
/// > selecciono el tablero y ya selecciono los pedidos de ese tablero ya tendria
/// > el camion preparado»
///
/// Cada opcion dice lo que lleva —«Vista · 12 pedidos · 340 kg»— y, debajo, el
/// camion previsto. Sin eso hay que salir del asistente, abrir el tablero y
/// volver para saber cual es la zona que se preparo.
///
/// **La primera opcion es no filtrar**, que es lo de ahora: el tablero es
/// opcional y quien no lo use no puede perder la lista completa.
///
/// No sale si no hay zonas que ofrecer —ningun tablero cargado, el de otra
/// sucursal, o todas las zonas vacias—. Un desplegable con una sola opcion que
/// no hace nada es un control que engaña: parece que hay zonas y no las hay.
class SelectorDeZonaDelTablero extends ConsumerWidget {
  const SelectorDeZonaDelTablero({
    required this.sucursalId,
    required this.zonaId,
    required this.alElegir,
    super.key,
  });

  /// La sucursal del paso 1. Las zonas son de **esa**, no de la de la barra.
  final String? sucursalId;

  /// La zona elegida ahora mismo. `null` = todas.
  final String? zonaId;

  /// `null` cuando se vuelve a «todas las zonas».
  final void Function(ZonaParaArmar? zona) alElegir;

  static const todas = 'Todas las zonas';

  static const titulo = 'Zona del tablero';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zonas = ref.watch(zonasParaArmarProvider(sucursalId));
    if (zonas.isEmpty) return const SizedBox.shrink();

    return Selector<String>(
      titulo: titulo,
      valor: zonaId ?? '',
      opciones: [
        const OpcionSelector('', todas),
        for (final zona in zonas)
          OpcionSelector(
            zona.id,
            zona.etiqueta,
            // El camion va en la nota y no en la etiqueta: es lo que hace que
            // este gesto ahorre el paso 3, y merece su linea. Cuando no hay, se
            // dice que no hay — un hueco en blanco se lee como «no lo se».
            nota: zona.vehiculoNombre == null
                ? 'Sin camión previsto'
                : 'Camión: ${zona.vehiculoNombre}',
          ),
      ],
      alElegir: (id) =>
          alElegir(zonas.where((zona) => zona.id == id).firstOrNull),
    );
  }
}
