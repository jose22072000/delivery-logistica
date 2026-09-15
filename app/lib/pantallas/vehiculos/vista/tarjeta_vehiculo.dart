import 'package:flutter/material.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/insignia.dart';
import '../../../diseno/tarjeta.dart';
import '../../../diseno/tema.dart';
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

  /// Los tres colores son los SEMANTICOS del kit, no unos propios: azul = en
  /// marcha, ambar = atencion, verde = listo. Los tenia repetidos aqui y por eso
  /// el «en uso» de un vehiculo no era el mismo azul que el de un pedido.
  Color get _colorEstado {
    if (vehiculo.enUso) return Colores.azul;
    if (vehiculo.enMantenimiento) return Colores.ambar;
    return Colores.verde;
  }

  Color get _fondoEstado {
    if (vehiculo.enUso) return Colores.azulFondo;
    if (vehiculo.enMantenimiento) return Colores.ambarFondo;
    return Colores.verdeFondo;
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Tarjeta(
      relleno: const EdgeInsets.all(Aire.xl),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // El icono en su cuadrado tintado, como las tarjetas del panel.
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _fondoEstado,
                    borderRadius: BorderRadius.circular(Radios.md),
                  ),
                  child: Icon(
                    vehiculo.enMantenimiento
                        ? Icons.build
                        : Icons.local_shipping,
                    size: 20,
                    color: _colorEstado,
                  ),
                ),
                const SizedBox(width: Aire.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(vehiculo.nombre, style: tema.textTheme.titleSmall),
                      // La placa en JetBrains Mono: es un codigo, y con la
                      // `monospace` del sistema sale en Courier New en Windows.
                      if (vehiculo.placa?.isNotEmpty ?? false)
                        Text(
                          vehiculo.placa!,
                          style: Tipos.mono(
                            tamano: 12,
                            color: Colores.tintaSuave,
                          ),
                        ),
                    ],
                  ),
                ),
                Insignia(
                  vehiculo.etiquetaEstado,
                  color: _colorEstado,
                  fondo: _fondoEstado,
                ),
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
                  color: Colores.azulFondo,
                  borderRadius: BorderRadius.circular(Radios.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'RUTA ACTIVA',
                      style: Tipos.texto(
                        tamano: 10,
                        peso: FontWeight.w600,
                        color: Colores.azul,
                        interletra: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(vehiculo.rutaActiva!.titulo),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '${vehiculo.pedidos} órdenes asignadas',
              style: tema.textTheme.bodySmall?.copyWith(
                color: Colores.tintaSuave,
              ),
            ),
            if (vehiculo.notas?.isNotEmpty ?? false) ...[
              const SizedBox(height: Aire.xs),
              Text(
                vehiculo.notas!,
                style: tema.textTheme.bodySmall?.copyWith(
                  color: Colores.tintaSuave,
                ),
              ),
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
    );
  }
}

class _Caja extends StatelessWidget {
  const _Caja({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: Aire.md,
      vertical: Aire.sm,
    ),
    decoration: BoxDecoration(
      color: Colores.papel,
      border: Border.all(color: Colores.linea),
      borderRadius: BorderRadius.circular(Radios.md),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          titulo.toUpperCase(),
          style: Tipos.texto(
            tamano: 10,
            peso: FontWeight.w600,
            color: Colores.tintaSuave,
            interletra: 1,
          ),
        ),
        const SizedBox(height: 2),
        // La cifra en mono: dos tarjetas de vehiculo una al lado de la otra se
        // comparan por estas dos cajas.
        Text(
          valor,
          style: Tipos.mono(
            tamano: 15,
            peso: FontWeight.w600,
            color: Colores.tinta,
          ),
        ),
      ],
    ),
  );
}
