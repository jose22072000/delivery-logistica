import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../datos/modelos.dart';
import '../estado/proveedores.dart';
import 'kit.dart';
import 'tarjeta.dart';

/// LA MITAD IZQUIERDA: los pedidos sin colocar, **ordenados por cercania al
/// almacen, el mas cerca primero**.
///
/// Ese orden es la mitad del encargo: es como se decide que se reparte hoy
/// cuando no cabe todo. Lo que esta cerca sale igual, porque cuesta poco; lo que
/// esta lejos espera al dia en que haya suficiente para ese lado.
class PanelSinColocar extends ConsumerStatefulWidget {
  const PanelSinColocar({
    required this.tablero,
    required this.alPulsarTarjeta,
    required this.alDevolver,
    super.key,
  });

  final Tablero tablero;
  final void Function(TarjetaPedido pedido) alPulsarTarjeta;

  /// Arrastrar de vuelta a la izquierda: vuelve a «sin colocar» y la lista lo
  /// recoloca sola por cercania.
  final void Function(TarjetaArrastrada datos) alDevolver;

  @override
  ConsumerState<PanelSinColocar> createState() => _PanelSinColocarState();
}

class _PanelSinColocarState extends ConsumerState<PanelSinColocar> {
  late final TextEditingController _busqueda = TextEditingController(
    text: ref.read(filtrosTableroProvider).q ?? '',
  );

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final filtros = ref.watch(filtrosTableroProvider);
    final izquierda = widget.tablero.sinColocar;

    return DragTarget<TarjetaArrastrada>(
      onAcceptWithDetails: (detalles) => widget.alDevolver(detalles.data),
      builder: (contexto, encima, _) => Container(
        color: encima.isEmpty
            ? null
            : tema.colorScheme.primary.withValues(alpha: 0.08),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Sin colocar (${izquierda.total})',
                      style: tema.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    icon: Badge(
                      isLabelVisible: filtros.hayAlguno,
                      child: const Icon(Icons.filter_list),
                    ),
                    tooltip: 'Filtros',
                    onPressed: _abrirFiltros,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _busqueda,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  // La misma caja de la lista de pedidos, contenido de los
                  // renglones incluido: «¿que pedidos llevan malta?».
                  hintText: 'Cliente, operación, dirección, artículo…',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (texto) => ref
                    .read(filtrosTableroProvider.notifier)
                    .poner(filtros.copiaCon(q: texto)),
              ),
            ),
            if (izquierda.truncada)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Text(
                  'Se ven ${izquierda.pedidos.length} de ${izquierda.total}. '
                  'Afina con los filtros.',
                  style: tema.textTheme.labelSmall?.copyWith(
                    color: ColoresTablero.ambar,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: izquierda.pedidos.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          filtros.hayAlguno
                              ? 'Ningún pedido con estos filtros.'
                              : 'No queda ningún pedido por colocar.',
                          textAlign: TextAlign.center,
                          style: tema.textTheme.bodySmall,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: izquierda.pedidos.length,
                      itemBuilder: (contexto, i) => TarjetaDePedido(
                        pedido: izquierda.pedidos[i],
                        onTap: () =>
                            widget.alPulsarTarjeta(izquierda.pedidos[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirFiltros() async {
    final facetas = await ref
        .read(consultasTableroProvider)
        .facetas(widget.tablero.sucursalId);
    if (!mounted) return;
    await mostrarCajon<void>(
      context: context,
      titulo: 'Filtros',
      contenido: (contexto) => _Filtros(
        municipios: facetas.$1,
        vendedores: facetas.$2,
      ),
    );
  }
}

class _Filtros extends ConsumerWidget {
  const _Filtros({required this.municipios, required this.vendedores});

  final List<String> municipios;
  final List<String> vendedores;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtros = ref.watch(filtrosTableroProvider);
    final mando = ref.read(filtrosTableroProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Día del pedido'),
          subtitle: Text(
            filtros.dia == null
                ? 'Todos'
                : DateFormat('d/M/y').format(filtros.dia!),
          ),
          trailing: filtros.dia == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      mando.poner(filtros.copiaCon(quitarDia: true)),
                ),
          onTap: () async {
            final elegido = await showDatePicker(
              context: context,
              initialDate: filtros.dia ?? DateTime.now(),
              firstDate: DateTime(2024),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (elegido != null) mando.poner(filtros.copiaCon(dia: elegido));
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: filtros.municipio,
          decoration: const InputDecoration(
            labelText: 'Municipio',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String>(child: Text('Todos')),
            for (final m in municipios)
              DropdownMenuItem<String>(value: m, child: Text(m)),
          ],
          onChanged: (valor) => mando.poner(
            valor == null
                ? filtros.copiaCon(quitarMunicipio: true)
                : filtros.copiaCon(municipio: valor),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: filtros.vendedor,
          decoration: const InputDecoration(
            labelText: 'Vendedor',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String>(child: Text('Todos')),
            for (final v in vendedores)
              DropdownMenuItem<String>(value: v, child: Text(v)),
          ],
          onChanged: (valor) => mando.poner(
            valor == null
                ? filtros.copiaCon(quitarVendedor: true)
                : filtros.copiaCon(vendedor: valor),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: filtros.kmMax?.toString() ?? '',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Hasta cuántos km del almacén',
            border: OutlineInputBorder(),
          ),
          onFieldSubmitted: (texto) {
            final valor = double.tryParse(texto.replaceAll(',', '.'));
            mando.poner(
              valor == null
                  ? filtros.copiaCon(quitarKmMax: true)
                  : filtros.copiaCon(kmMax: valor),
            );
          },
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: mando.limpiar,
          child: const Text('Quitar todos los filtros'),
        ),
      ],
    );
  }
}
