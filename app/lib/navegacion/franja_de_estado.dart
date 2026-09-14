import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diseno/colores.dart';
import '../nucleo/frescura/reloj_de_datos.dart';
import '../nucleo/proveedores.dart';
import 'estado_navegacion.dart';

/// LA FRANJA DE ESTADO. Arriba, a lo ancho, en las siete pantallas.
///
/// Es una franja propia y no un hueco dentro de la barra superior **a
/// proposito**: en la barra compite por sitio con el titulo, la sucursal, la
/// moneda y el avatar, y en un telefono de 390 px lo primero que se recorta es
/// lo que no cabe. Justo esto es lo que no se puede recortar (caso S8).
///
/// Y dice **la hora**, no «sin conexión». A quien despacha no le sirve saber si
/// hay senal: le sirve saber si los pedidos que esta mirando son de esta manana
/// o de anteayer, porque de eso depende si arma la ruta de hoy o la de ayer.
class FranjaDeEstado extends ConsumerWidget {
  const FranjaDeEstado({this.alPulsarPendientes, super.key});

  final VoidCallback? alPulsarPendientes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bajada = ref.watch(frescuraGlobalProvider);
    final sinSubir = ref.watch(sinSubirProvider);
    final actualizando = ref.watch(actualizandoProvider);
    final ahora = ref.watch(relojProvider)();

    // Mientras la consulta de frescura no ha contestado NO se dice «sin
    // descargar»: seria acusar de vacio a algo que aun no se ha mirado. Se
    // espera, que dura un fotograma.
    final estado = bajada.hasValue
        ? EstadoFrescura.de(bajada.value, ahora: ahora)
        : null;

    final pendientes = sinSubir.value ?? 0;
    final enAmbar = estado?.enAmbar ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: enAmbar ? Colores.ambarFondo : Colores.grisFondo,
        border: const Border(bottom: BorderSide(color: Colores.borde)),
      ),
      child: Row(
        children: [
          Icon(
            enAmbar ? Icons.schedule : Icons.schedule_outlined,
            size: 14,
            color: enAmbar ? Colores.ambar : Colores.gris,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: estado == null
                ? const SizedBox.shrink()
                : RelojDeDatos(
                    estado: estado,
                    actualizando: actualizando,
                    sinSubir: pendientes,
                    alPulsarPendientes: alPulsarPendientes,
                  ),
          ),
        ],
      ),
    );
  }
}
