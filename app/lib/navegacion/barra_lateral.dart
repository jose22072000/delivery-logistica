import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../diseno/anchos.dart';
import '../diseno/colores.dart';
import 'pantalla_registrada.dart';

/// La barra lateral: 256 px, alto completo, fija a la izquierda en escritorio.
/// Por debajo de 1024 px vive dentro del `Drawer` del `Scaffold` y se abre con
/// el boton de menu de la barra superior.
class BarraLateral extends StatelessWidget {
  const BarraLateral({
    required this.pantallas,
    required this.rutaActual,
    this.dentroDeCajon = false,
    super.key,
  });

  final List<PantallaRegistrada> pantallas;
  final String rutaActual;

  /// En movil la barra va dentro del cajon del `Scaffold`, y al elegir una
  /// entrada hay que cerrarlo: **se cierra sola al cambiar de pantalla** (§8.1).
  /// Dejarlo abierto tapa justo la pantalla a la que se acaba de ir.
  final bool dentroDeCajon;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final enElMenu = pantallas.where((p) => p.enElMenu).toList();

    return Container(
      width: Anchos.barraLateral,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colores.borde)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_shipping,
                    color: Colores.indigo,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  // `Expanded`: «Plataforma de Delivery» no cabe en los 256 px
                  // junto al camion, y un `Row` sin reparto se sale por la
                  // derecha en vez de recortar.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ProCovar',
                          style: tema.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Plataforma de Delivery',
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.bodySmall?.copyWith(
                            color: Colores.gris,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  for (final p in enElMenu)
                    _Entrada(
                      pantalla: p,
                      activa: rutaActual == p.ruta,
                      dentroDeCajon: dentroDeCajon,
                    ),
                ],
              ),
            ),
            // Abajo NO hay nada de la cuenta: cerrar sesion y cambiar de
            // aplicacion viven en el avatar de la barra superior (§8.1).
          ],
        ),
      ),
    );
  }
}

class _Entrada extends StatelessWidget {
  const _Entrada({
    required this.pantalla,
    required this.activa,
    required this.dentroDeCajon,
  });

  final PantallaRegistrada pantalla;
  final bool activa;
  final bool dentroDeCajon;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final color = activa ? tema.colorScheme.primary : Colores.gris;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: activa
            ? tema.colorScheme.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            if (dentroDeCajon) Navigator.of(context).pop();
            context.go(pantalla.ruta);
          },
          child: Stack(
            children: [
              // La barra vertical a la izquierda de la activa (§8.1).
              if (activa)
                Positioned(
                  left: 0,
                  top: 8,
                  bottom: 8,
                  child: Container(width: 3, color: tema.colorScheme.primary),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                child: Row(
                  children: [
                    Icon(
                      pantalla.icono ?? Icons.circle_outlined,
                      size: 20,
                      color: color,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        pantalla.titulo,
                        style: tema.textTheme.bodyMedium?.copyWith(
                          color: color,
                          fontWeight: activa
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
