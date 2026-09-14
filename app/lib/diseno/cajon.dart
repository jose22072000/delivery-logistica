import 'package:flutter/material.dart';

import 'anchos.dart';
import 'colores.dart';

/// EL CAJON. **Siempre cajon, nunca `AlertDialog`** (pliego §9.2).
///
/// En el resto de Procovar la regla es modal en escritorio y cajon por debajo de
/// 1024 px. Delivery es una **excepcion aprobada el 05/09/2026**: aqui es cajon
/// tambien en escritorio. El motivo es de uso, no de gusto: estos paneles llevan
/// listas largas (las paradas de una ruta, los renglones de un pedido) y un
/// modal centrado con scroll interno es peor que un panel a alto completo.
///
/// Estructura fija: cabecera (titulo + subtitulo + cerrar), cuerpo desplazable y
/// pie opcional pegado abajo con los botones **siempre a la vista**.
Future<T?> abrirCajon<T>(
  BuildContext contexto, {
  required String titulo,
  required WidgetBuilder cuerpo,
  String? subtitulo,
  WidgetBuilder? pie,
  AnchoCajon ancho = AnchoCajon.lg,
}) {
  return showGeneralDialog<T>(
    context: contexto,
    // El velo negro al 40 % del pliego. `barrierDismissible` da las dos cosas
    // que pide §9.2 de una vez: pulsar fuera cierra y Escape cierra (el
    // `ModalBarrier` de Flutter atiende el `DismissIntent` del teclado).
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (contextoCajon, _, _) => Cajon(
      titulo: titulo,
      subtitulo: subtitulo,
      ancho: ancho,
      pie: pie?.call(contextoCajon),
      child: cuerpo(contextoCajon),
    ),
    transitionBuilder: (_, animacion, _, hijo) {
      // Entra desde 24 px a la derecha, 180 ms. Los mismos numeros del pliego:
      // lo bastante para que se lea «viene de fuera» y no tanto como para
      // esperarlo cincuenta veces al dia.
      final curva = CurvedAnimation(
        parent: animacion,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curva,
        child: Padding(
          padding: EdgeInsets.only(left: 24 * (1 - curva.value)),
          child: hijo,
        ),
      );
    },
  );
}

/// El panel en si. Se expone suelto para poder probarlo sin abrir una ruta.
class Cajon extends StatelessWidget {
  const Cajon({
    required this.titulo,
    required this.child,
    this.subtitulo,
    this.pie,
    this.ancho = AnchoCajon.lg,
    super.key,
  });

  final String titulo;
  final String? subtitulo;
  final Widget child;
  final Widget? pie;
  final AnchoCajon ancho;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final anchoPantalla = MediaQuery.sizeOf(context).width;
    // En movil la pantalla entera, sin excepciones: un panel de 448 px sobre una
    // pantalla de 390 px es un panel de 390 px con los bordes cortados.
    final anchoUtil = anchoPantalla < Anchos.escritorio
        ? anchoPantalla
        : (ancho.px.isFinite ? ancho.px : anchoPantalla);

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: tema.colorScheme.surface,
        child: SizedBox(
          width: anchoUtil,
          height: double.infinity,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Cabecera(titulo: titulo, subtitulo: subtitulo),
                const Divider(height: 1, color: Colores.borde),
                // El cuerpo es lo unico que se desplaza.
                Expanded(child: SingleChildScrollView(child: child)),
                if (pie != null) ...[
                  const Divider(height: 1, color: Colores.borde),
                  Padding(padding: const EdgeInsets.all(16), child: pie),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.titulo, this.subtitulo});

  final String titulo;
  final String? subtitulo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: tema.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitulo != null)
                  Text(
                    subtitulo!,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: Colores.gris,
                    ),
                  ),
              ],
            ),
          ),
          // La ✕ NUNCA puede desaparecer: es la unica salida garantizada cuando
          // el teclado del telefono tapa media pantalla.
          IconButton(
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
