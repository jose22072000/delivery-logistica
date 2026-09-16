import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/modelos.dart';
import 'kit.dart';
import 'tarjeta.dart';

/// Lo que viaja cuando se arrastra una columna entera por su cabecera.
class ColumnaArrastrada {
  const ColumnaArrastrada(this.columnaId);

  final String columnaId;
}

/// Una columna del tablero: la zona que se invento el logistico, con lo que
/// lleva puesto dentro.
class ColumnaDelTablero extends StatelessWidget {
  const ColumnaDelTablero({
    required this.columna,
    required this.tarjetas,
    required this.alSoltar,
    required this.alPulsarTarjeta,
    required this.alAbrirMenu,
    required this.alSoltarColumna,
    this.ancho,
    super.key,
  });

  final ColumnaTablero columna;
  final List<TarjetaColocada> tarjetas;

  /// [posicion] es donde se solto: `null` significa «al final».
  final void Function(TarjetaArrastrada datos, int? posicion) alSoltar;
  final void Function(TarjetaColocada tarjeta) alPulsarTarjeta;
  final VoidCallback alAbrirMenu;

  /// Arrastrar la cabecera de una columna reordena el tablero: la que se suelta
  /// se pone donde estaba esta.
  final void Function(ColumnaArrastrada arrastrada) alSoltarColumna;

  /// `null` = ocupa lo que le den (el movil).
  final double? ancho;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return DragTarget<ColumnaArrastrada>(
      onAcceptWithDetails: (detalles) {
        if (detalles.data.columnaId != columna.id) {
          alSoltarColumna(detalles.data);
        }
      },
      builder: (contexto, encimaColumna, _) => Container(
        width: ancho,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: tema.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: encimaColumna.isEmpty
              ? null
              : Border.all(color: tema.colorScheme.primary, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // La cabecera se arrastra: es como se reordena el tablero. Va en
            // pulsacion larga, igual que las tarjetas, para no comerse el
            // desplazamiento lateral de la tira en un telefono. Quien no quiera
            // arrastrar tiene «mover a la izquierda / derecha» en el menu.
            LongPressDraggable<ColumnaArrastrada>(
              data: ColumnaArrastrada(columna.id),
              delay: const Duration(milliseconds: 250),
              feedback: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: ancho ?? 260,
                  child: _Cabecera(
                    columna: columna,
                    alAbrirMenu: alAbrirMenu,
                    alSoltar: alSoltar,
                  ),
                ),
              ),
              child: _Cabecera(
                columna: columna,
                alAbrirMenu: alAbrirMenu,
                alSoltar: alSoltar,
              ),
            ),
            Expanded(
              child: DragTarget<TarjetaArrastrada>(
                // Soltar en el hueco de abajo es «ponlo el ultimo».
                onAcceptWithDetails: (detalles) =>
                    alSoltar(detalles.data, null),
                builder: (contexto, encima, _) => Container(
                  decoration: BoxDecoration(
                    color: encima.isNotEmpty
                        ? tema.colorScheme.primary.withValues(alpha: 0.08)
                        : null,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(10),
                    ),
                  ),
                  child: tarjetas.isEmpty
                      ? _Vacia(encima: encima.isNotEmpty)
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 48),
                          itemCount: tarjetas.length,
                          itemBuilder: (contexto, i) => _Ranura(
                            // Soltar SOBRE una tarjeta es «ponlo aqui», en su
                            // sitio: el orden dentro de la columna es el orden de
                            // visita que propone quien conoce las calles.
                            alSoltar: (datos) =>
                                alSoltar(datos, tarjetas[i].posicion),
                            hijo: TarjetaDePedido(
                              pedido: tarjetas[i].pedido,
                              columnaId: columna.id,
                              posicion: tarjetas[i].posicion,
                              onTap: () => alPulsarTarjeta(tarjetas[i]),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cabecera extends ConsumerWidget {
  const _Cabecera({
    required this.columna,
    required this.alAbrirMenu,
    required this.alSoltar,
  });

  final ColumnaTablero columna;
  final VoidCallback alAbrirMenu;
  final void Function(TarjetaArrastrada datos, int? posicion) alSoltar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final excede = columna.excedeCamion;
    return DragTarget<TarjetaArrastrada>(
      // Tambien se puede soltar en la cabecera: en el movil es lo que queda a
      // la vista cuando la columna esta llena.
      onAcceptWithDetails: (detalles) => alSoltar(detalles.data, null),
      builder: (contexto, encima, _) => Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        decoration: BoxDecoration(
          color: encima.isNotEmpty
              ? tema.colorScheme.primary.withValues(alpha: 0.12)
              : null,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${columna.nombre} (${columna.pedidos})',
                    style: tema.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Opciones de la columna',
                  visualDensity: VisualDensity.compact,
                  onPressed: alAbrirMenu,
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  '${pesoBonito(columna.pesoKg)} · '
                  '${dineroBonito(ref, columna.costoUsd)}',
                  style: tema.textTheme.bodySmall,
                ),
                // El exceso AVISA y no impide: el tablero es un borrador y el
                // camion previsto es una intencion. La capacidad se comprueba
                // donde importa, al armar la ruta (§7.3).
                if (excede == true) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: ColoresTablero.ambar,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'no cabe',
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: ColoresTablero.ambar,
                    ),
                  ),
                ],
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    // Sin camion previsto NO se dice «cabe»: se dice que no se
                    // sabe, que es lo que pasa.
                    'Camión: ${columna.vehiculoNombre ?? '—'}',
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: tema.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Una columna creada sin senal se puede usar igual; lo unico
                // que se dice es que todavia no ha subido.
                if (columna.esProvisional) insigniaAviso('sin subir'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Ranura extends StatelessWidget {
  const _Ranura({required this.hijo, required this.alSoltar});

  final Widget hijo;
  final void Function(TarjetaArrastrada datos) alSoltar;

  @override
  Widget build(BuildContext context) => DragTarget<TarjetaArrastrada>(
    onAcceptWithDetails: (detalles) => alSoltar(detalles.data),
    builder: (contexto, encima, _) => Container(
      decoration: encima.isEmpty
          ? null
          : BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Theme.of(contexto).colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
      child: hijo,
    ),
  );
}

class _Vacia extends StatelessWidget {
  const _Vacia({required this.encima});

  final bool encima;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        encima ? 'Suelta aquí' : 'Todavía no hay nada en esta zona',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}
