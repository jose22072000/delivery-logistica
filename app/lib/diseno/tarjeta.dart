import 'package:flutter/material.dart';

import 'colores.dart';
import 'tema.dart';

/// La caja de siempre: fondo blanco, **borde fino de 1 px del color `--line`**,
/// esquinas de `rounded-2xl` y la sombra `md` calida.
///
/// Las tres cosas juntas, no una: en delivery la tarjeta se despega del papel
/// por la sombra y se recorta contra el por el borde. Con sombra y sin borde se
/// ve difusa; con borde y sin sombra se ve plana, que es como estaba.
class Tarjeta extends StatefulWidget {
  const Tarjeta({
    required this.child,
    this.titulo,
    this.icono,
    this.relleno = const EdgeInsets.all(Aire.xl),
    this.alPulsar,
    this.franja,
    super.key,
  });

  final Widget child;
  final String? titulo;

  /// El icono del titulo, en primario y a la izquierda, como los `h3` de las
  /// tarjetas del panel de delivery.
  final IconData? icono;

  final EdgeInsetsGeometry relleno;
  final VoidCallback? alPulsar;

  /// La FRANJA DE COLOR de 3 px pegada al borde de arriba
  /// (`<span className="absolute inset-x-0 top-0 h-1 …" />`). Es lo que hace que
  /// cuatro tarjetas iguales se distingan de un vistazo.
  final Color? franja;

  @override
  State<Tarjeta> createState() => _TarjetaState();
}

class _TarjetaState extends State<Tarjeta> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final sePulsa = widget.alPulsar != null;
    final radio = BorderRadius.circular(Radios.xl);

    final contenido = Padding(
      padding: widget.relleno,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.titulo != null) ...[
            Row(
              children: [
                if (widget.icono != null) ...[
                  Icon(widget.icono, size: 20, color: Colores.primario),
                  const SizedBox(width: Aire.sm),
                ],
                Expanded(
                  child: Text(widget.titulo!, style: tema.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: Aire.lg),
          ],
          widget.child,
        ],
      ),
    );

    return MouseRegion(
      onEnter: sePulsa ? (_) => setState(() => _encima = true) : null,
      onExit: sePulsa ? (_) => setState(() => _encima = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        // `hover:-translate-y-0.5`: la tarjeta que se puede pulsar se levanta
        // dos pixeles. Es la senal de que se pulsa, sin tener que escribirlo.
        transform: Matrix4.translationValues(0, _encima ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: Colores.blanco,
          borderRadius: radio,
          border: Border.all(color: Colores.linea),
          boxShadow: _encima ? Sombras.lg : Sombras.md,
        ),
        // `ClipRRect` para que la franja de arriba siga la curva de la esquina.
        child: ClipRRect(
          borderRadius: radio,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.alPulsar,
              hoverColor: Colors.transparent,
              child: Stack(
                children: [
                  contenido,
                  if (widget.franja != null)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(height: 3, color: widget.franja),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La tarjeta de cifra del Panel: etiqueta arriba en versalitas, el numero
/// grande en Bricolage y el icono en su cuadrado tintado a la derecha.
///
/// Es la pieza que mas se mira de toda la aplicacion, y es exactamente el
/// `StatCard` de `delivery/src/app/(dashboard)/dashboard/page.tsx`.
class TarjetaDeCifra extends StatelessWidget {
  const TarjetaDeCifra({
    required this.etiqueta,
    required this.valor,
    this.subtexto,
    this.color,
    this.icono,
    super.key,
  });

  final String etiqueta;
  final String valor;
  final String? subtexto;

  /// En ambar cuando hay algo que mirar; en primario cuando no. Lo decide la
  /// pantalla, no la tarjeta.
  final Color? color;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final tinte = color ?? Colores.primario;
    return Tarjeta(
      franja: tinte,
      relleno: const EdgeInsets.fromLTRB(Aire.xl, Aire.xl, Aire.xl, Aire.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // `text-[11px] font-semibold uppercase tracking-[0.14em]`.
                Text(
                  etiqueta.toUpperCase(),
                  style: Tipos.texto(
                    tamano: 11,
                    peso: FontWeight.w600,
                    color: Colores.tintaSuave,
                    interletra: 11 * 0.14,
                  ),
                ),
                const SizedBox(height: 10),
                // `text-[2.1rem] font-extrabold font-display tabular-nums`.
                Text(
                  valor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tema.textTheme.displaySmall?.copyWith(
                    color: Colores.tinta,
                    fontFeatures: Tipos.cifrasEnColumna,
                  ),
                ),
                if (subtexto != null) ...[
                  const SizedBox(height: Aire.sm),
                  Text(
                    subtexto!,
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: Colores.tintaSuave,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (icono != null) ...[
            const SizedBox(width: Aire.md),
            // El cuadrado tintado del icono: `w-11 h-11 rounded-xl bg-…/10`.
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tinte.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(Radios.lg),
              ),
              child: Icon(icono, size: 24, color: tinte),
            ),
          ],
        ],
      ),
    );
  }
}
