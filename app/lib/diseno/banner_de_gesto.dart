import 'package:flutter/material.dart';

import 'anchos.dart';
import 'colores.dart';
import 'tema.dart';

/// UN GESTO GRANDE del Panel: traer el día, entregar el día.
///
/// Esta en `diseno/` —y no dentro de una de las dos pantallas— porque los dos
/// gestos **son una pareja y tienen que leerse como una**: el mismo alto, la
/// misma banda de color a la izquierda, el boton en el mismo sitio. Si cada uno
/// se pintara en su carpeta, a los tres meses uno tendria el boton a la derecha
/// y el otro debajo, y dejarian de parecer las dos mitades de lo mismo.
///
/// No sabe nada de providers: recibe texto y devuelve pintura. Asi se puede
/// mirar en una prueba sin montar media aplicacion.
class BannerDeGesto extends StatelessWidget {
  const BannerDeGesto({
    required this.titulo,
    required this.explicacion,
    required this.color,
    required this.icono,
    this.textoDelBoton,
    this.lineaFuerte = '',
    this.lineaSuave = '',
    this.alPulsarBoton,
    this.alPulsarBanner,
    super.key,
  });

  final String titulo;
  final String explicacion;

  /// El estado, en el color del estado. Es lo que se lee de un vistazo.
  final String lineaFuerte;

  /// La hora, o el detalle. En gris.
  final String lineaSuave;

  /// El color de la banda de la izquierda y de [lineaFuerte].
  final Color color;

  final IconData icono;

  /// `null` = **no se pinta boton**. No es lo mismo que uno apagado: sin senal,
  /// ofrecer un boton que va a fallar es peor que no ofrecer ninguno, y dejarlo
  /// gris invita a pulsarlo igual.
  final String? textoDelBoton;

  /// `null` deja el boton apagado. Se usa mientras el ciclo corre y cuando no
  /// hay nada que hacer: un boton encendido que no hace nada ensena a
  /// desconfiar del que si hace algo.
  final VoidCallback? alPulsarBoton;

  /// Pulsar el banner entero. Abre el cajon **sin disparar nada**: es para
  /// mirar. Quien quiere hacerlo le da al boton, que es lo que se ve.
  final VoidCallback? alPulsarBanner;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    final etiqueta = textoDelBoton;
    final Widget? boton = etiqueta == null
        ? null
        : FilledButton.icon(
            onPressed: alPulsarBoton,
            icon: Icon(icono, size: 20),
            style: FilledButton.styleFrom(
              // Grande: es un gesto principal, y se le da con el pulgar de pie en el
              // almacen.
              padding: const EdgeInsets.symmetric(
                horizontal: Aire.xl,
                vertical: Aire.lg,
              ),
              textStyle: Tipos.texto(tamano: 15, peso: FontWeight.w600),
            ),
            label: Text(etiqueta),
          );

    final texto = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          titulo,
          style: Tipos.texto(
            tamano: 17,
            peso: FontWeight.w700,
            color: Colores.tinta,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          explicacion,
          style: tema.textTheme.bodySmall?.copyWith(color: Colores.tintaSuave),
        ),
        // Las dos lineas se pintan SIEMPRE, aunque vengan vacias. Es lo que hace
        // que los dos gestos midan lo mismo puestos uno al lado del otro: dos
        // tarjetas hermanas de distinto alto se leen como dos cosas distintas, y
        // el Panel no puede medirlas con un `IntrinsicHeight` porque aqui dentro
        // hay un `LayoutBuilder`.
        const SizedBox(height: Aire.sm),
        Text(
          lineaFuerte,
          style: Tipos.mono(tamano: 13, peso: FontWeight.w700, color: color),
        ),
        Text(
          lineaSuave,
          style: tema.textTheme.bodySmall?.copyWith(color: Colores.tintaSuave),
        ),
      ],
    );

    return Material(
      color: Colores.blanco,
      borderRadius: BorderRadius.circular(Radios.xl),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radios.xl),
        onTap: alPulsarBanner,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radios.xl),
            border: Border.all(color: Colores.linea),
            // La banda de color a la izquierda, como en la tabla de aparatos:
            // deja leer el estado sin leer una palabra.
            gradient: LinearGradient(
              colors: [color, color, Colores.blanco, Colores.blanco],
              stops: const [0, 0.008, 0.008, 1],
            ),
            boxShadow: Sombras.sm,
          ),
          padding: const EdgeInsets.fromLTRB(
            Aire.xl,
            Aire.lg,
            Aire.lg,
            Aire.lg,
          ),
          child: LayoutBuilder(
            builder: (context, medidas) {
              // Sin boton —el estado de «sin conexión»— la pieza es solo el
              // texto: ofrecer uno apagado invita a pulsarlo igual.
              if (boton == null) return texto;
              // Por debajo de 768 px el boton no cabe al lado del texto sin
              // partirle el titulo: se apila y ocupa el ancho entero, que ademas
              // es donde cae el pulgar.
              if (medidas.maxWidth < Anchos.entrega) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    texto,
                    const SizedBox(height: Aire.lg),
                    boton,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: texto),
                  const SizedBox(width: Aire.lg),
                  boton,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
