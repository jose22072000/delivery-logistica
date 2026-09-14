import 'package:flutter/material.dart';

import '../datos/repositorio_clientes.dart';

/// La tabla de Clientes: 4 columnas y **desplazamiento propio**.
///
/// El scroll horizontal es de la TABLA, no de la pagina (`pantallas.md` §11).
/// Si se deja que empuje la pagina, en el telefono se mueve de lado todo —
/// cabecera, filtros y paginacion— y se pierde el sitio con el dedo.
class TablaClientes extends StatelessWidget {
  const TablaClientes({
    required this.clientes,
    required this.conDistancia,
    super.key,
  });

  final List<ClienteConKm> clientes;

  /// Los km sólo salen debajo del vendedor **cuando se filtro por distancia**,
  /// que es lo que hace la de Next.
  final bool conDistancia;

  /// El ancho por debajo del cual la tabla se desplaza sola.
  static const anchoMinimo = 736.0;

  static const ambar = Color(0xFFB45309);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, medidas) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: medidas.maxWidth < anchoMinimo
              ? anchoMinimo
              : medidas.maxWidth,
        ),
        child: DataTable(
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('Cliente')),
            DataColumn(label: Text('Dirección')),
            DataColumn(label: Text('Vendedor')),
            DataColumn(label: Text('Origen')),
          ],
          rows: [for (final c in clientes) _fila(context, c)],
        ),
      ),
    ),
  );

  DataRow _fila(BuildContext context, ClienteConKm fila) {
    final tema = Theme.of(context);
    final c = fila.cliente;
    final direccion = [
      c.address,
      c.municipio,
    ].where((t) => t != null && t.isNotEmpty).join(' · ');

    return DataRow(
      cells: [
        DataCell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(c.name),
              if (c.codigo != null && c.codigo!.isNotEmpty)
                Text(
                  c.codigo!,
                  style: tema.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              if (c.phone != null && c.phone!.isNotEmpty)
                Text(c.phone!, style: tema.textTheme.bodySmall)
              else
                // En ambar porque un cliente sin telefono es una entrega que no
                // se puede avisar, y eso se decide antes de salir, no en la
                // puerta.
                Text(
                  'sin teléfono',
                  style: tema.textTheme.bodySmall?.copyWith(color: ambar),
                ),
            ],
          ),
        ),
        DataCell(Text(direccion.isEmpty ? '—' : direccion)),
        DataCell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(c.vendedor?.isNotEmpty ?? false ? c.vendedor! : '—'),
              if (conDistancia && fila.km != null)
                Text('${fila.km} km', style: tema.textTheme.bodySmall),
            ],
          ),
        ),
        DataCell(_Insignia(deSource: c.source)),
      ],
    );
  }
}

class _Insignia extends StatelessWidget {
  const _Insignia({required this.deSource});

  final String? deSource;

  @override
  Widget build(BuildContext context) {
    final dePedido = deSource == 'pedido';
    final color = dePedido ? const Color(0xFF1D4ED8) : const Color(0xFF4B5563);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        dePedido ? 'PEDIDO' : 'Manual',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
