// La tabla de Pedidos: 13 columnas que se esconden por anchura.
//
// **El escondite es por orden de prescindibilidad, no por hueco disponible**
// (`pantallas.md` §11): `Sucursal` y `Vehículo` bajo 1536, `Ruta` bajo 1280,
// `Artículos` y `Factura` bajo 1024, `Entrega` bajo 768. **Nunca se van:**
// cliente, direccion, peso, precio y estado. Escrito con umbrales fijos y no con
// un `Flexible` que se encoja, porque una columna de 12 px no se lee y ademas
// engana: parece que el dato esta.

import 'package:flutter/material.dart';

import '../../../nucleo/base/base.dart';
import '../datos/estado_reparto.dart';
import '../datos/formato.dart';
import '../datos/repositorio_pedidos.dart';
import 'kit.dart';

/// Que columnas caben a este ancho.
class ColumnasVisibles {
  const ColumnasVisibles(this.ancho, {required this.conSucursal});

  final double ancho;

  /// La columna `Sucursal` sólo sale **si no hay sucursal elegida arriba**:
  /// repetir en cada fila lo que ya dice la barra es gastar el ancho que le hace
  /// falta a la direccion.
  final bool conSucursal;

  bool get sucursal => conSucursal && ancho >= 1536;
  bool get vehiculo => ancho >= 1536;
  bool get ruta => ancho >= 1280;
  bool get articulos => ancho >= 1024;
  bool get factura => ancho >= 1024;
  bool get entrega => ancho >= 768;
}

class TablaPedidos extends StatelessWidget {
  const TablaPedidos({
    required this.pedidos,
    required this.renglones,
    required this.rutas,
    required this.seleccion,
    required this.alMarcar,
    required this.alMarcarPagina,
    required this.alAbrir,
    required this.ahora,
    required this.conSucursal,
    super.key,
  });

  final List<Pedido> pedidos;
  final Map<String, List<RenglonConPeso>> renglones;

  /// Las rutas por id: de aqui salen el codigo que pinta la columna `Ruta` y el
  /// estado del que depende `En despacho` / `En ruta`.
  final Map<String, Ruta> rutas;
  final Set<String> seleccion;
  final void Function(String id) alMarcar;
  final void Function(List<String> ids, bool marcar) alMarcarPagina;
  final void Function(Pedido) alAbrir;
  final DateTime ahora;
  final bool conSucursal;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (contexto, medidas) {
      final columnas = ColumnasVisibles(
        medidas.maxWidth,
        conSucursal: conSucursal,
      );
      final ids = [for (final p in pedidos) p.id];
      final todosMarcados = ids.isNotEmpty && ids.every(seleccion.contains);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Cabecera(
            columnas: columnas,
            todosMarcados: todosMarcados,
            alMarcarPagina: (marcar) => alMarcarPagina(ids, marcar),
          ),
          const Divider(height: 1),
          for (final pedido in pedidos)
            _Fila(
              pedido: pedido,
              columnas: columnas,
              renglones: renglones[pedido.id] ?? const [],
              estadoDeSuRuta: pedido.routeId == null
                  ? null
                  : rutas[pedido.routeId]?.status,
              codigoDeRuta: pedido.routeId == null
                  ? null
                  : rutas[pedido.routeId]?.routeCode,
              marcado: seleccion.contains(pedido.id),
              alMarcar: () => alMarcar(pedido.id),
              alAbrir: () => alAbrir(pedido),
              ahora: ahora,
            ),
        ],
      );
    },
  );
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.columnas,
    required this.todosMarcados,
    required this.alMarcarPagina,
  });

  final ColumnasVisibles columnas;
  final bool todosMarcados;
  final void Function(bool) alMarcarPagina;

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Colores.gris);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Semantics(
            label: 'Elegir todos los de esta página',
            child: Checkbox(
              value: todosMarcados,
              onChanged: (v) => alMarcarPagina(v ?? false),
            ),
          ),
          _celda(flex: 2, hijo: Text('Fecha', style: estilo)),
          if (columnas.sucursal)
            _celda(flex: 2, hijo: Text('Sucursal', style: estilo)),
          _celda(flex: 2, hijo: Text('Pedido', style: estilo)),
          _celda(flex: 3, hijo: Text('Cliente', style: estilo)),
          if (columnas.ruta) _celda(flex: 2, hijo: Text('Ruta', style: estilo)),
          if (columnas.vehiculo)
            _celda(flex: 2, hijo: Text('Vehículo', style: estilo)),
          if (columnas.articulos)
            _celda(flex: 2, hijo: Text('Artículos', style: estilo)),
          _celda(flex: 4, hijo: Text('Dirección', style: estilo)),
          _celda(
            flex: 2,
            hijo: Text('Peso', style: estilo, textAlign: TextAlign.right),
          ),
          _celda(flex: 2, hijo: Text('Precio', style: estilo)),
          if (columnas.factura)
            _celda(flex: 2, hijo: Text('Factura', style: estilo)),
          if (columnas.entrega)
            _celda(flex: 2, hijo: Text('Entrega', style: estilo)),
          const SizedBox(width: 32),
        ],
      ),
    );
  }
}

Widget _celda({required int flex, required Widget hijo}) => Expanded(
  flex: flex,
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: hijo,
  ),
);

class _Fila extends StatelessWidget {
  const _Fila({
    required this.pedido,
    required this.columnas,
    required this.renglones,
    required this.estadoDeSuRuta,
    required this.codigoDeRuta,
    required this.marcado,
    required this.alMarcar,
    required this.alAbrir,
    required this.ahora,
  });

  final Pedido pedido;
  final ColumnasVisibles columnas;
  final List<RenglonConPeso> renglones;
  final String? estadoDeSuRuta;
  final String? codigoDeRuta;
  final bool marcado;
  final VoidCallback alMarcar;
  final VoidCallback alAbrir;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final reparto = estadoDeReparto(pedido, estadoDeSuRuta);
    final enPedido = estadoEnPedido(pedido, ahora: ahora);

    return InkWell(
      // La fila entera abre el detalle; la casilla no lo abre.
      onTap: alAbrir,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(value: marcado, onChanged: (_) => alMarcar()),
            _celda(flex: 2, hijo: _Fecha(pedido: pedido)),
            if (columnas.sucursal)
              _celda(flex: 2, hijo: Text(pedido.sucursalCodigo ?? '—')),
            _celda(
              flex: 2,
              hijo: Insignia(
                enPedido.etiqueta,
                color: switch (enPedido) {
                  EstadoEnPedidoVisto.completada => Colores.verde,
                  EstadoEnPedidoVisto.expirada => Colores.rojo,
                  EstadoEnPedidoVisto.enProceso => Colores.ambar,
                },
                tooltip: pedido.archivado ? 'Archivado en PEDIDO' : null,
              ),
            ),
            _celda(
              flex: 3,
              hijo: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(pedido.customerName, overflow: TextOverflow.ellipsis),
                  Text(
                    pedido.operationNumber ?? '',
                    style: tema.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: Colores.gris,
                    ),
                  ),
                ],
              ),
            ),
            if (columnas.ruta)
              _celda(
                flex: 2,
                hijo: codigoDeRuta == null
                    ? const Text('—')
                    : Insignia(codigoDeRuta!, color: Colores.azul),
              ),
            if (columnas.vehiculo)
              _celda(flex: 2, hijo: Text(pedido.vehicleId == null ? '—' : '·')),
            if (columnas.articulos)
              _celda(flex: 2, hijo: _Articulos(renglones: renglones)),
            _celda(
              flex: 4,
              hijo: Text(
                pedido.endAddress ?? pedido.address,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _celda(
              flex: 2,
              hijo: Text(kg(pedido.weight), textAlign: TextAlign.right),
            ),
            _celda(
              flex: 2,
              hijo: Text(
                usd(pedido.pedidoCosto),
                style: pedido.pedidoCosto == null
                    ? const TextStyle(color: Colores.gris)
                    : null,
              ),
            ),
            if (columnas.factura)
              _celda(flex: 2, hijo: _Factura(pedido: pedido)),
            if (columnas.entrega)
              _celda(
                flex: 2,
                hijo: Insignia(
                  reparto.etiqueta,
                  color: switch (reparto) {
                    EstadoReparto.entregado => Colores.verde,
                    EstadoReparto.enRuta => Colores.azul,
                    EstadoReparto.enDespacho => Colores.primario,
                    EstadoReparto.devuelto ||
                    EstadoReparto.cancelado => Colores.ambar,
                    EstadoReparto.sinEntregar => Colores.gris,
                  },
                ),
              ),
            const SizedBox(
              width: 32,
              child: Icon(Icons.chevron_right, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fecha extends StatelessWidget {
  const _Fecha({required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final propia = pedido.orderDate;
    if (propia != null) return Text(fechaCorta(propia));
    // Sin `orderDate` se pinta la del espejo con un `≈`: decirlo a medias es
    // peor que decirlo, porque el dia del pedido es con lo que se cuadra.
    return Tooltip(
      message:
          'Pedido copiado antes de que se guardara su fecha: '
          'ésta es la del espejo.',
      child: Text('≈ ${fechaCorta(pedido.createdAt)}'),
    );
  }
}

class _Articulos extends StatelessWidget {
  const _Articulos({required this.renglones});

  final List<RenglonConPeso> renglones;

  @override
  Widget build(BuildContext context) {
    if (renglones.isEmpty) return const Text('—');
    final primero = renglones.first;
    final resto = renglones.length - 1;
    return Tooltip(
      message: [
        for (final r in renglones)
          '${r.renglon.description} ×${cantidad(r.empaques)}',
      ].join('\n'),
      child: Text(
        '${primero.renglon.description} ×${cantidad(primero.empaques)}'
        '${resto > 0 ? '  +$resto' : ''}',
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _Factura extends StatelessWidget {
  const _Factura({required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final numero = pedido.facturaNumero ?? '';
    switch (pedido.facturaEstado) {
      case EstadoFactura.igual:
        return Insignia(
          numero,
          color: Colores.verde,
          tooltip: 'Cuadra con lo pedido: se puede repartir tal cual.',
        );
      case EstadoFactura.cambiado:
        return Insignia(
          '$numero !',
          color: Colores.ambar,
          tooltip:
              'Se facturó algo distinto de lo pedido. '
              'No puede ir en una ruta hasta que se corrija.',
        );
      case EstadoFactura.sinFactura:
        return const Text('sin facturar');
      default:
        // NULL no es `sin_factura`: es que el cotejo no ha pasado por aqui.
        return const Tooltip(
          message:
              'El cotejo contra Ventra no ha pasado por este pedido todavía.',
          child: Text('sin cotejar'),
        );
    }
  }
}
