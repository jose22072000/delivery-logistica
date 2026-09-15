import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diseno/colores.dart';
import '../diseno/tema.dart';
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
      padding: const EdgeInsets.symmetric(horizontal: Aire.lg, vertical: 6),
      decoration: BoxDecoration(
        // En calma es el propio papel, un punto mas oscuro: la franja tiene que
        // estar SIEMPRE, pero cuando no hay nada que decir no debe pedir la
        // vista. En ambar si, porque entonces si la pide.
        color: enAmbar ? Colores.ambarFondo : Colores.grisFondo,
        border: Border(
          bottom: BorderSide(
            color: enAmbar
                ? Colores.ambar.withValues(alpha: 0.25)
                : Colores.linea,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            enAmbar ? Icons.schedule : Icons.schedule_outlined,
            size: 14,
            color: enAmbar ? Colores.ambar : Colores.tintaSuave,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: estado == null
                ? const SizedBox.shrink()
                // `FittedBox` y no un recorte: en un telefono estrecho, con la
                // hora y «<n> sin subir` a la vez, el texto no cabe — y aqui no
                // se puede cortar nada, porque las dos mitades son el aviso. Se
                // encoge la letra, que sigue leyendose, en vez de perder media
                // franja por la derecha.
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: RelojDeDatos(
                      estado: estado,
                      actualizando: actualizando,
                      sinSubir: pendientes,
                      alPulsarPendientes: alPulsarPendientes,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
