import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'proveedores.dart';

/// LOS FILTROS VIVEN EN LA DIRECCION.
///
/// Es el contrato de la casa (`navegacion/pantalla_registrada.dart`) y aqui
/// vale igual que en Pedidos: en web, un logistico manda «mira estos, los de
/// Songo a menos de 10 km» pegando un enlace, y el enlace tiene que llevar al
/// mismo tablero. Guardar el filtro sólo en memoria convierte eso en una
/// explicacion por teléfono.
abstract final class FiltrosEnLaUrl {
  static const camino = '/tablero';

  static FiltrosSinColocar leer(Map<String, String> parametros) {
    final dia = parametros['dia'];
    final km = parametros['kmMax'];
    // `cobro=si` / `cobro=no`. Sin el parametro son los dos, que es lo que
    // significa `null` — y por eso NO se lee como un booleano suelto: un `false`
    // por defecto convertiria «todos» en «sin cobro» al abrir un enlace viejo.
    final cobro = parametros['cobro'];
    return FiltrosSinColocar(
      q: parametros['q'],
      municipio: parametros['municipio'],
      vendedor: parametros['vendedor'],
      dia: dia == null ? null : DateTime.tryParse(dia),
      kmMax: km == null ? null : double.tryParse(km),
      conCobroDeDomicilio: switch (cobro) {
        'si' => true,
        'no' => false,
        _ => null,
      },
    );
  }

  static Map<String, String> escribir(FiltrosSinColocar f) {
    final dia = f.dia;
    final km = f.kmMax;
    return <String, String>{
      if (f.q != null && f.q!.trim().isNotEmpty) 'q': f.q!.trim(),
      if (f.municipio != null) 'municipio': f.municipio!,
      if (f.vendedor != null) 'vendedor': f.vendedor!,
      if (dia != null) 'dia': '${dia.year}-${_dos(dia.month)}-${_dos(dia.day)}',
      if (km != null) 'kmMax': '$km',
      if (f.conCobroDeDomicilio != null)
        'cobro': f.conCobroDeDomicilio! ? 'si' : 'no',
    };
  }

  static bool iguales(FiltrosSinColocar a, FiltrosSinColocar b) =>
      escribir(a).toString() == escribir(b).toString();

  /// Pone los filtros **en los dos sitios**: el provider, que es lo que lee la
  /// consulta, y la direccion, que es lo que se puede mandar.
  ///
  /// Si no hay enrutador —un test de widget que pinta la pantalla suelta— se
  /// queda sólo con el provider en vez de reventar: la pantalla tiene que poder
  /// probarse sin arrastrar media aplicacion.
  static void poner(
    BuildContext contexto,
    WidgetRef ref,
    FiltrosSinColocar filtros,
  ) {
    ref.read(filtrosTableroProvider.notifier).poner(filtros);
    if (GoRouter.maybeOf(contexto) == null) return;
    contexto.go(
      Uri(path: camino, queryParameters: escribir(filtros)).toString(),
    );
  }

  static String _dos(int n) => n.toString().padLeft(2, '0');
}
