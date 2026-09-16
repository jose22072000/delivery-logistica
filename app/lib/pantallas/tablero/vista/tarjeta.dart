import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/modelos.dart';
import '../../../diseno/tema.dart';
import 'kit.dart';

/// Lo que viaja mientras se arrastra: el pedido y de donde sale.
///
/// De donde sale hace falta para no encolar un movimiento que no mueve nada
/// —soltar una tarjeta en la columna en la que ya estaba—, que sin conexion es
/// un apunte de mas en la cola por cada vez que a alguien se le escapa el dedo.
class TarjetaArrastrada {
  const TarjetaArrastrada(this.pedidoId, {this.desdeColumnaId});

  final String pedidoId;
  final String? desdeColumnaId;
}

/// Una tarjeta de pedido, la misma en las dos mitades.
///
/// # EN EL MOVIL NO SE ARRASTRA. Se toca y se elige a donde va.
///
/// Palabras de Jose, 16/09/2026: «el drag and drop en el movil no... eso lo
/// puedes quitar de ahi». Y antes, el 14: «recuerda q para movil es con boton
/// para mover entre tablas».
///
/// El motivo es fisico y no de gusto. En un telefono la mitad de «sin colocar»
/// y las columnas **no caben a la vez**: son dos pestanas, y no se puede
/// arrastrar algo a un sitio que no esta en pantalla. Lo unico que conseguia el
/// arrastre ahi era comerse el desplazamiento de la lista: quien intentaba
/// bajar a ver la tarjeta numero treinta levantaba una tarjeta sin querer.
///
/// El gesto que sirve ya existe y hace exactamente lo mismo, llamando al mismo
/// sitio: tocar la tarjeta abre «moverla a» (`AccionesTablero.moverTarjeta`).
///
/// En escritorio se queda el arrastre, con **pulsacion larga** y no arrastre
/// directo, por lo mismo de la lista. Ahi las dos mitades SI se ven a la vez,
/// que es lo que hace que arrastrar tenga sentido.
class TarjetaDePedido extends ConsumerWidget {
  const TarjetaDePedido({
    required this.pedido,
    this.columnaId,
    this.posicion,
    this.onTap,
    super.key,
  });

  final TarjetaPedido pedido;

  /// La columna en la que esta, si esta puesta.
  final String? columnaId;

  /// Su sitio dentro de la columna: el orden de visita que propuso el
  /// logistico.
  final int? posicion;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tarjeta = _contenido(context, ref);

    // El umbral es el MISMO que decide si el tablero se parte en dos mitades
    // (`pantalla_tablero.dart`, `_anchoDeDosMitades`). No es casualidad: se
    // arrastra exactamente cuando hay un sitio visible al que soltar. Si
    // manana se mueve ese numero, los dos se mueven juntos.
    final cabenLasDosMitades =
        MediaQuery.sizeOf(context).width >= anchoDeDosMitades;
    if (!cabenLasDosMitades) return tarjeta;

    final datos = TarjetaArrastrada(pedido.pedidoId, desdeColumnaId: columnaId);
    return LongPressDraggable<TarjetaArrastrada>(
      data: datos,
      delay: const Duration(milliseconds: 200),
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 280,
          child: _contenido(context, ref, arrastrando: true),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: tarjeta),
      child: tarjeta,
    );
  }

  Widget _contenido(
    BuildContext context,
    WidgetRef ref, {
    bool arrastrando = false,
  }) {
    final tema = Theme.of(context);
    final marcas = pedido.marcas;
    // Sin elevacion de Material: la tarjeta del tablero es la caja blanca de
    // delivery —borde fino y sombra calida—, y al arrastrarla se queda plana
    // para que la que se mueve no sea la que parece pegada al tablero.
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.lg),
        side: BorderSide(color: arrastrando ? Colores.primario : Colores.linea),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radios.lg),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (posicion != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        '$posicion.',
                        style: tema.textTheme.labelMedium,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        kmBonito(pedido.kmAlAlmacen),
                        style: tema.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      pedido.operationNumber ?? pedido.pedidoId,
                      style: tema.textTheme.labelMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Text(
                pedido.customerName,
                style: tema.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                pedido.address,
                style: tema.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                [
                  pesoBonito(pedido.weight),
                  if (pedido.pedidoCosto != null)
                    dineroBonito(ref, pedido.pedidoCosto!),
                  if (pedido.municipio != null) pedido.municipio!,
                  if (posicion != null && pedido.kmAlAlmacen.isFinite)
                    kmBonito(pedido.kmAlAlmacen),
                ].join(' · '),
                style: tema.textTheme.bodySmall?.copyWith(
                  color: tema.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (marcas.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final marca in marcas) insigniaDeMarca(marca),
                  ],
                ),
              ],
              // No se funden las tarjetas: se dicen. Que caigan seguidas al
              // ordenar por cercania ya las junta; esto es para que el
              // logistico las meta en la misma columna a proposito y no por
              // casualidad (§7.1).
              if (pedido.mismoCliente > 1) ...[
                const SizedBox(height: 4),
                Text(
                  '${pedido.mismoCliente} pedidos de este cliente hoy',
                  style: tema.textTheme.labelSmall?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
