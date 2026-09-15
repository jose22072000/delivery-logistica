import 'package:flutter/material.dart';

import '../../../diseno/colores.dart';

/// UN RECHAZO, con su motivo y su hora. La misma pieza en los dos sitios.
///
/// Vive suelta porque la miran dos pantallas distintas y **tienen que verse
/// igual**: la de Sincronizacion, que ensena lo que el servidor rechazo a los
/// diez aparatos, y el cajon de entregar el dia, que ensena lo que rechazo a
/// ESTE. Si cada una la pintara a su manera, quien mira las dos tendria que
/// aprender dos veces a leer lo mismo.
///
/// `rechazado` no se reintenta y no se borra. Un apunte que desaparece solo es
/// trabajo perdido que nadie sabe que perdio, y esto es donde se ve.
class FilaDeRechazo extends StatelessWidget {
  const FilaDeRechazo({
    required this.motivo,
    required this.quien,
    required this.horas,
    required this.peticion,
    super.key,
  });

  /// El motivo LITERAL del servidor. Se pinta tal cual: es lo unico que le dice
  /// a alguien que hacer. «3 de los 8 pedidos ya están en otra ruta. Vuelve a
  /// elegirlos.» sirve; «Ha ocurrido un error», no.
  final String motivo;

  /// De quien es. En el cajon del propio aparato se queda vacio: ahi no hay a
  /// quien atribuirlo, es de quien esta mirando.
  final String quien;

  /// Las horas ya compuestas. Son DOS y las dos hacen falta: la del aparato
  /// —cuando se hizo de verdad— y la del servidor. Con ocho horas sin senal de
  /// por medio, no son la misma tarde.
  final String horas;

  /// `POST /api/routes/…/results`. Es lo que deja saber QUE se perdio.
  final String peticion;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colores.rojoFondo,
        border: Border.all(color: Colores.rojo.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.block_outlined, size: 18, color: Colores.rojo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  motivo,
                  style: tema.textTheme.bodyMedium?.copyWith(
                    color: Colores.rojo,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (quien.isNotEmpty)
            Text(
              quien,
              style: tema.textTheme.bodySmall?.copyWith(color: Colores.gris),
            ),
          if (horas.isNotEmpty)
            Text(
              horas,
              style: tema.textTheme.bodySmall?.copyWith(color: Colores.gris),
            ),
          Text(
            peticion,
            style: tema.textTheme.bodySmall?.copyWith(color: Colores.gris),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
