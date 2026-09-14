import 'package:flutter/material.dart';

import '../datos/vehiculo_api.dart';

/// La tarjeta de la rejilla. Pliego: `pantallas.md` §5.
class TarjetaVehiculo extends StatelessWidget {
  const TarjetaVehiculo({
    required this.vehiculo,
    required this.alEditar,
    required this.alEliminar,
    required this.alMarcarDisponible,
    required this.alUsarParaDomicilio,
    super.key,
  });

  final VehiculoDeLaApi vehiculo;
  final VoidCallback alEditar;
  final VoidCallback alEliminar;
  final VoidCallback alMarcarDisponible;
  final VoidCallback alUsarParaDomicilio;

  static const _verde = Color(0xFF15803D);
  static const _azul = Color(0xFF1D4ED8);
  static const _ambar = Color(0xFFB45309);

  Color get _colorEstado {
    if (vehiculo.enUso) return _azul;
    if (vehiculo.enMantenimiento) return _ambar;
    return _verde;
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  vehiculo.enMantenimiento ? Icons.build : Icons.local_shipping,
                  color: _colorEstado,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(vehiculo.nombre, style: tema.textTheme.titleSmall),
                      if (vehiculo.placa?.isNotEmpty ?? false)
                        Text(
                          vehiculo.placa!,
                          style: tema.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ),
                ),
                _Insignia(texto: vehiculo.etiquetaEstado, color: _colorEstado),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (vehiculo.tipo != null)
                  Chip(
                    label: Text(vehiculo.tipo!),
                    visualDensity: VisualDensity.compact,
                  ),
                if (vehiculo.usarParaDomicilio)
                  Chip(
                    avatar: const Icon(Icons.home_work, size: 16),
                    label: Text(
                      vehiculo.costoKmUsd == null
                          ? 'Cálculo domicilio'
                          : 'Cálculo domicilio · \$${vehiculo.costoKmUsd}/km',
                    ),
                    visualDensity: VisualDensity.compact,
                  )
                else
                  OutlinedButton(
                    onPressed: alUsarParaDomicilio,
                    child: const Text('Usar para domicilio'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _Caja(
                    titulo: 'Capacidad',
                    valor: '${vehiculo.capacidad.toStringAsFixed(0)} kg',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Caja(titulo: 'Rutas', valor: '${vehiculo.rutas}'),
                ),
              ],
            ),
            if (vehiculo.enUso && vehiculo.rutaActiva != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _azul.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Ruta activa', style: tema.textTheme.labelSmall),
                    Text(vehiculo.rutaActiva!.titulo),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '${vehiculo.pedidos} órdenes asignadas',
              style: tema.textTheme.bodySmall,
            ),
            if (vehiculo.notas?.isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              Text(vehiculo.notas!, style: tema.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (vehiculo.enUso)
                  TextButton(
                    onPressed: alMarcarDisponible,
                    child: const Text('Marcar disponible'),
                  ),
                TextButton(onPressed: alEditar, child: const Text('Editar')),
                // Sin confirmacion, como la de Next. Se deja igual a proposito:
                // cambiarlo aqui y no alla es que la misma accion se comporte
                // distinto segun por donde entres.
                TextButton(
                  onPressed: alEliminar,
                  child: const Text('Eliminar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Caja extends StatelessWidget {
  const _Caja({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titulo, style: Theme.of(context).textTheme.labelSmall),
        Text(valor),
      ],
    ),
  );
}

class _Insignia extends StatelessWidget {
  const _Insignia({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      texto,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
    ),
  );
}
