import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diseno/colores.dart';
import '../diseno/tema.dart';
import '../nucleo/frescura/reloj_de_datos.dart';
import '../nucleo/proveedores.dart';
// La UNICA cosa que `navegacion/` importa de `pantallas/`, y con motivo: la
// franja es la pieza del armazon que esta en las siete pantallas, asi que es la
// unica desde la que se puede llegar al gesto de traer el dia estando en
// Clientes o en Rutas. El cajon no puede vivir en `nucleo/` porque `nucleo/` no
// depende de `diseno/` y el cajon es todo diseno.
import '../pantallas/entregar_el_dia/vista/cajon_entregar_el_dia.dart';
import '../pantallas/traer_el_dia/vista/cajon_traer_el_dia.dart';
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
    final ahora = ref.watch(relojProvider)();

    // Mientras la consulta de frescura no ha contestado NO se dice «sin
    // descargar»: seria acusar de vacio a algo que aun no se ha mirado. Se
    // espera, que dura un fotograma.
    final estado = bajada.hasValue
        ? EstadoFrescura.de(bajada.value, ahora: ahora)
        : null;

    final pendientes = sinSubir.value ?? 0;
    final enAmbar = estado?.enAmbar ?? false;

    // LA FRANJA ES PULSABLE y lleva al gesto de traer el dia.
    //
    // Es la segunda puerta, y la que hace que el gesto exista tambien en las
    // otras seis pantallas: quien esta armando una ruta y ve «Datos de hace 9 h»
    // tiene que poder darle ahi mismo, sin aprenderse que hay que volver al
    // Panel. El sitio donde se lee que los datos estan viejos es el sitio donde
    // se arregla.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => abrirCajonDeTraerElDia(context),
        child: _pintar(
          context,
          estado: estado,
          pendientes: pendientes,
          enAmbar: enAmbar,
        ),
      ),
    );
  }

  Widget _pintar(
    BuildContext context, {
    required EstadoFrescura? estado,
    required int pendientes,
    required bool enAmbar,
  }) {
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
                      sinSubir: pendientes,
                      // «<n> sin subir» lleva al gesto que lo arregla, que es
                      // entregar el dia. El numero y el boton que lo baja a
                      // cero tienen que estar a un dedo el uno del otro: quien
                      // lee «23 sin subir» en la pantalla de Rutas no tiene por
                      // que aprenderse que hay que volver al Panel.
                      alPulsarPendientes:
                          alPulsarPendientes ??
                          () => abrirCajonDeEntregarElDia(context),
                    ),
                  ),
          ),
          // La senal de que esto se pulsa. Un icono y nada de texto: en 390 px
          // la franja ya lleva la hora y «<n> sin subir», y una palabra mas se
          // comeria la que importa.
          const SizedBox(width: 6),
          Icon(
            Icons.cloud_download_outlined,
            size: 15,
            color: enAmbar ? Colores.ambar : Colores.tintaSuave,
          ),
        ],
      ),
    );
  }
}
