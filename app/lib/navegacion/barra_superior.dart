import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diseno/anchos.dart';
import '../diseno/colores.dart';
import '../diseno/numeros.dart';
import '../diseno/selector.dart';
import '../diseno/tema.dart';
import '../nucleo/base/base.dart';
import '../nucleo/proveedores.dart';
import 'estado_navegacion.dart';
import 'menu_de_cuenta.dart';

/// La barra superior: 64 px, pegajosa arriba (pliego §8.2).
///
/// Izquierda: boton de menu **solo en movil**, titulo de la pantalla y
/// `actualizando…` con el giro mientras haya cualquier consulta en vuelo.
/// Derecha: sucursal, moneda y avatar.
class BarraSuperior extends ConsumerWidget implements PreferredSizeWidget {
  const BarraSuperior({required this.titulo, this.alAbrirMenu, super.key});

  final String titulo;

  /// `null` en escritorio: alli la barra lateral esta siempre a la vista y un
  /// boton de menu que no abre nada es un boton que ensena a desconfiar.
  final VoidCallback? alAbrirMenu;

  @override
  Size get preferredSize => const Size.fromHeight(Anchos.altoBarraSuperior);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final actualizando = ref.watch(actualizandoProvider);

    // Sobre PAPEL, no sobre blanco: en delivery la barra es `bg-paper/80` y lo
    // blanco son las tarjetas y la barra lateral. Una barra superior blanca
    // sobre un fondo casi blanco hace que la pantalla no tenga arriba.
    // El umbral es el mismo con el que el pliego (§11) esconde el idioma: por
    // debajo de esto la barra ya no tiene sitio para todo.
    final estrecho = MediaQuery.sizeOf(context).width < Anchos.idioma;

    return Container(
      height: Anchos.altoBarraSuperior,
      decoration: BoxDecoration(
        color: Colores.papel,
        border: Border(bottom: BorderSide(color: Colores.linea)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Aire.md),
      child: Row(
        children: [
          if (alAbrirMenu != null)
            IconButton(
              tooltip: 'Menú',
              icon: const Icon(Icons.menu, size: 22),
              color: Colores.tintaSuave,
              onPressed: alAbrirMenu,
            ),
          const SizedBox(width: Aire.xs),
          // EL TITULO SE COME TODO EL HUECO LIBRE, y por eso va en `Expanded` y
          // no en `Flexible` con un `Spacer` detras.
          //
          // Con `Flexible` + `Spacer` los dos pesan igual, asi que Flutter les
          // reparte el sobrante A MEDIAS: el `Spacer` empujaba el grupo de la
          // derecha solo hasta la mitad y la otra mitad quedaba vacia detras del
          // avatar. En un monitor ancho eso se ve como la sucursal, la moneda y
          // el avatar flotando en el centro en vez de en su esquina; en un
          // telefono no se notaba porque alli no sobra hueco que repartir.
          //
          // El titulo y el giro van juntos DENTRO del Expanded para que el giro
          // salga pegado al titulo, como en delivery, y no al otro lado.
          //
          // EN UN TELEFONO EL TITULO NO SE PINTA, y es una decision, no un
          // recorte por falta de sitio. En 390 px la barra llevaba el boton de
          // menu, el titulo, el selector de sucursal (hasta 220 px), la moneda y
          // el avatar: suman mas que la pantalla, y lo que se salia por la
          // derecha era el avatar — o sea el menu de la cuenta y «Salir—.
          // Visto por Jose el 16/09/2026: «el avatar a la derecha no se ve casi
          // por q tengo el select de las sucursales q oocupa mucho espacio».
          //
          // De las cuatro piezas, la que menos falta hace es el titulo: dice el
          // nombre de la pantalla que se acaba de elegir en el menu. La sucursal
          // y la moneda, en cambio, CAMBIAN LOS NUMEROS que se estan mirando, y
          // por eso el pliego (§11) prohibe esconderlas. El avatar tiene que
          // poder pulsarse.
          Expanded(
            child: Row(
              children: [
                if (!estrecho)
                  Flexible(
                    child: Text(
                      titulo,
                      overflow: TextOverflow.ellipsis,
                      style: tema.textTheme.titleLarge,
                    ),
                  ),
                // EL GIRO DE «actualizando…» NO SALE EN UN TELEFONO.
                //
                // No cabe, y lo que hacia al no caber era peor que faltar: con
                // el titulo ya fuera, este hueco se queda en unos pocos pixeles
                // —el menu, la sucursal, la moneda y el avatar se llevan los
                // 390—, asi que el giro se salia y se pintaba DEBAJO del
                // selector de sucursal. Visto por Jose el 16/09/2026: «el
                // actualizando me sale atras de el selector de sucursales».
                //
                // Y tiene un sitio mejor: la franja de estado de debajo, que es
                // donde se mira si los datos estan al dia. Ahi va, con la hora
                // al lado, que es lo que de verdad hace falta saber.
                if (actualizando && !estrecho) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colores.tintaSuave,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'actualizando…',
                    style: Tipos.texto(
                      tamano: 11,
                      peso: FontWeight.w500,
                      color: Colores.tintaSuave.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // NADA DE `Flexible` AQUI, por mucho que lo pida el cuerpo.
          //
          // Se probó y rompió la prueba de «el grupo de la derecha llega al
          // borde»: un `Flexible` al lado del `Expanded` del título son dos
          // hijos con el mismo peso, así que Flutter les reparte el sobrante A
          // MEDIAS y el grupo de la derecha vuelve a quedarse flotando en mitad
          // de la barra. Es exactamente el fallo que explica el comentario de
          // arriba, recreado desde el otro lado.
          //
          // Lo que hace que quepa en un teléfono es que la caja mida 150 en vez
          // de 220 (ver `_Sucursal`), no un reparto de espacio.
          _Sucursal(compacta: estrecho),
          // `Idioma` (ES/EN) va JUSTO AQUI, entre sucursal y moneda, y se oculta
          // por debajo de 640 px (§11). No esta todavia porque no hay ARB ni
          // `flutter_localizations` en el pubspec — es la ola 1-C —, y un
          // desplegable de idioma que no cambia ni una palabra ensena a
          // desconfiar de la barra entera. Cuando entre gen_l10n se anade aqui,
          // envuelto en `if (ancho >= Anchos.idioma)`.
          const SizedBox(width: 8),
          const _Moneda(),
          const SizedBox(width: 8),
          const MenuDeCuenta(),
        ],
      ),
    );
  }
}

/// El selector de sucursal del Super Admin.
///
/// Cambiarlo **no recarga la pagina**: los providers de pantalla miran
/// `sucursalMiradaProvider`, asi que se reconstruyen solos y los numeros cambian
/// en el sitio. Eso es lo que pide el pliego §0 y es la razon de que la sucursal
/// viva en un provider y no en la URL.
class _Sucursal extends ConsumerWidget {
  const _Sucursal({required this.compacta});

  /// En un telefono la etiqueta se acorta y la caja se estrecha. «Todas las
  /// sucursales (8)» son veintitres caracteres para decir «ninguna elegida»;
  /// «Todas (8)» son nueve y dice lo mismo.
  final bool compacta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sucursales =
        ref.watch(sucursalesProvider).value ?? const <Sucursal>[];
    final mirada = ref.watch(sucursalMiradaProvider);

    // Con ninguna no se pinta nada; con una sola, etiqueta fija (§8.2).
    if (sucursales.isEmpty) return const SizedBox.shrink();
    if (sucursales.length == 1) {
      final unica = sucursales.first;
      final codigo = unica.externalId;
      // Una sola sucursal: se dice cual es en una pastilla blanca con su borde
      // fino — la misma caja que el selector, para que la barra no tenga una
      // pieza sin forma al lado de otra que si la tiene.
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: Aire.md, vertical: 8),
        decoration: BoxDecoration(
          color: Colores.blanco,
          border: Border.all(color: Colores.linea),
          borderRadius: BorderRadius.circular(Radios.lg),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store_outlined, size: 16, color: Colores.tintaSuave),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: compacta ? 110 : 180),
              child: Text(
                codigo == null
                    ? unica.name
                    : (compacta ? codigo : '${unica.name} ($codigo)'),
                overflow: TextOverflow.ellipsis,
                style: Tipos.texto(tamano: 14, color: Colores.tinta),
              ),
            ),
          ],
        ),
      );
    }

    // Si la sucursal guardada ya no esta entre las visibles, se olvida (§8.2):
    // dejarla puesta filtraria por una sucursal que la persona ya no ve y la
    // pantalla saldria vacia sin motivo a la vista.
    final valida = mirada != null && sucursales.any((s) => s.id == mirada);
    final valor = valida ? mirada : '';

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compacta ? 150 : 220),
      child: Selector<String>(
        icono: Icons.store_outlined,
        tooltip: 'Sucursal que se está mirando',
        // La etiqueta de la CAJA se acorta en el telefono; la de la LISTA no,
        // porque ahi se esta eligiendo y hace falta el nombre entero.
        etiquetaVacia: compacta
            ? 'Todas (${sucursales.length})'
            : 'Todas las sucursales (${sucursales.length})',
        valor: valor,
        opciones: [
          OpcionSelector<String>(
            valor: '',
            etiqueta: 'Todas las sucursales (${sucursales.length})',
          ),
          for (final s in sucursales)
            OpcionSelector<String>(
              valor: s.id,
              etiqueta: s.name,
              nota: s.externalId,
            ),
        ],
        alElegir: (v) => ref
            .read(sucursalMiradaProvider.notifier)
            .mirar(v.isEmpty ? null : v),
      ),
    );
  }
}

/// La moneda en la que se PINTAN los importes.
///
/// Sin tasa se queda en USD fijo, con borde ambar y **el motivo de verdad** en el
/// tooltip (§8.2). No se ofrece elegir CUP sin tasa: convertir sin tasa es
/// inventarse un numero, y un numero inventado en una hoja de reparto acaba
/// cobrado.
///
/// ## De donde sale la tasa, y de donde NO
///
/// De [tasaDeLaMiradaProvider], que la lee de la SUCURSAL que se esta mirando.
///
/// Antes se leia la tabla local `currencies`, **que no llenaba nadie**: no esta
/// en `Colecciones`, la bajada del dia no la trae y el servidor no la sirve. Salia
/// vacia siempre, asi que esta pastilla se quedaba en ambar para siempre, en las
/// ocho sucursales, tuvieran tasa o no — y como el mensaje que enseñaba («esta
/// sucursal no tiene tasa de cambio todavia») puede ser verdad, nadie lo iba a
/// cuestionar. Esa tabla ya no existe.
///
/// Tampoco se lee `settings.cupRate`, que es el campo viejo y GLOBAL de delivery,
/// con 320 por defecto. Leerlo seria darle a las ocho sucursales la misma tasa,
/// que es como Granma acabo enseñando los 685 de La Habana.
class _Moneda extends ConsumerWidget {
  const _Moneda();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasa = ref.watch(tasaDeLaMiradaProvider);
    final mirada = ref.watch(monedaEfectivaProvider);

    // --- Sin tasa de ESTA sucursal: USD fijo, y se dice por que --------------
    if (!tasa.hayCup) {
      return _pastillaAmbar(
        aviso: tasa.motivo ?? '',
        icono: Icons.money_off_csred_outlined,
      );
    }

    // --- Con tasa ------------------------------------------------------------
    //
    // La NOTA de la opcion lleva la tasa Y SU FECHA. La fecha no es un adorno: es
    // lo unico que demuestra que la tasa es de verdad y lo que deja ver de cuando
    // es sin abrir nada. Hoy las que hay son del 9 de septiembre.
    final nota =
        '1 USD = ${Numeros.entero(tasa.cupPorUsd!)} · '
        'del ${tasa.traidoAt!.day}/${tasa.traidoAt!.month}/'
        '${tasa.traidoAt!.year}';

    final selector = Selector<String>(
      tooltip: tasa.aviso ?? 'Moneda de visualización',
      etiquetaVacia: 'USD',
      valor: mirada,
      opciones: [
        const OpcionSelector<String>(valor: 'USD', etiqueta: 'USD'),
        OpcionSelector<String>(valor: 'CUP', etiqueta: 'CUP', nota: nota),
      ],
      alElegir: (v) => ref.read(monedaMiradaProvider.notifier).mirar(v),
    );

    // TASA VIEJA: SE ENSEÑA, CON AVISO. Lo decide Accesos (24 h alli), no esta
    // pantalla. El aviso va a la vista y no solo en el tooltip cuando se esta
    // pintando en CUP: es cuando el numero desfasado esta delante de los ojos.
    if (tasa.aviso == null || mirada != 'CUP') return selector;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: tasa.aviso!,
          child: Icon(Icons.schedule_outlined, size: 16, color: Colores.ambar),
        ),
        const SizedBox(width: 6),
        selector,
      ],
    );
  }

  /// La pastilla de «aqui no se puede ver en CUP», con el motivo dentro.
  Widget _pastillaAmbar({required String aviso, required IconData icono}) {
    return Tooltip(
      message: aviso,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Aire.md, vertical: 8),
        decoration: BoxDecoration(
          color: Colores.blanco,
          border: Border.all(color: Colores.ambar.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(Radios.lg),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 16, color: Colores.ambar),
            const SizedBox(width: 6),
            // En mono: es una cifra, aunque sea el codigo de la moneda.
            Text(
              'USD',
              style: Tipos.mono(
                tamano: 12,
                peso: FontWeight.w600,
                color: Colores.ambar,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
