import 'package:flutter/material.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/insignia.dart';
import '../../../diseno/tabla_ancha.dart';
import '../../../diseno/tema.dart';
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
        child: Theme(
          data: Theme.of(context)
              .copyWith(dataTableTheme: temaDeTabla(context)),
          child: DataTable(
            columns: [
              DataColumn(label: cabecera('Cliente')),
              DataColumn(label: cabecera('Dirección')),
              DataColumn(label: cabecera('Vendedor')),
              DataColumn(label: cabecera('Origen')),
            ],
            rows: [for (final c in clientes) _fila(context, c)],
          ),
        ),
      ),
    ),
  );

  DataRow _fila(BuildContext context, ClienteConKm fila) {
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
              Text(
                c.name,
                style: Tipos.texto(tamano: 14, peso: FontWeight.w500),
              ),
              // El codigo en JetBrains Mono, no en la `monospace` del sistema:
              // en Windows esa es Courier New y no se parece a nada de aqui.
              if (c.codigo != null && c.codigo!.isNotEmpty)
                Text(
                  c.codigo!,
                  style: Tipos.mono(tamano: 11.5, color: Colores.tintaSuave),
                ),
              if (c.phone != null && c.phone!.isNotEmpty)
                Text(
                  c.phone!,
                  style: Tipos.mono(tamano: 11.5, color: Colores.tintaSuave),
                )
              else
                // En ambar porque un cliente sin telefono es una entrega que no
                // se puede avisar, y eso se decide antes de salir, no en la
                // puerta.
                Text(
                  'sin teléfono',
                  style: Tipos.texto(tamano: 11.5, color: Colores.ambar),
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
                Text(
                  '${fila.km} km',
                  style: Tipos.mono(tamano: 11.5, color: Colores.tintaSuave),
                ),
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
    return Insignia(
      dePedido ? 'PEDIDO' : 'Manual',
      color: dePedido ? Colores.enCurso : Colores.tintaSuave,
      fondo: dePedido ? Colores.enCursoFondo : Colores.grisFondo,
    );
  }
}
