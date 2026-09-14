import 'package:flutter/material.dart';

import '../datos/modelos.dart';
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
/// Se arrastra con **pulsacion larga** y no con un arrastre directo, y eso es
/// para el dedo: en un movil, el arrastre directo se come el desplazamiento de
/// la lista y no se puede bajar a ver la tarjeta numero treinta. Con el raton
/// funciona igual, manteniendo pulsado.
class TarjetaDePedido extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final tarjeta = _contenido(context);
    final datos = TarjetaArrastrada(pedido.pedidoId, desdeColumnaId: columnaId);
    return LongPressDraggable<TarjetaArrastrada>(
      data: datos,
      delay: const Duration(milliseconds: 200),
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 280,
          child: _contenido(context, arrastrando: true),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: tarjeta),
      child: tarjeta,
    );
  }

  Widget _contenido(BuildContext context, {bool arrastrando = false}) {
    final tema = Theme.of(context);
    final marcas = pedido.marcas;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      elevation: arrastrando ? 0 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
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
                    dineroBonito(pedido.pedidoCosto!),
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
