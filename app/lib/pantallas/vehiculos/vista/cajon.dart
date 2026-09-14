import 'package:flutter/material.dart';

/// Los anchos del pliego (`pantallas.md` §9.2), en pantalla grande.
enum AnchoCajon {
  md(448),
  lg(672),
  xl(896),
  completo(double.infinity);

  const AnchoCajon(this.px);
  final double px;
}

/// A partir de aqui se considera escritorio. Es el mismo corte que la barra
/// lateral fija del armazon (§0).
const anchoDeEscritorio = 1024.0;

/// SIEMPRE cajon lateral, tambien en escritorio (pliego §9.2, excepcion de delivery).
///
/// Es la regla de la casa de Procovar y vale para todos sus proyectos: en el
/// telefono el panel ocupa la pantalla y se cierra con el pulgar; en el
/// escritorio no hay pulgar y un panel pegado al borde obliga a cruzar la
/// pantalla con el raton para cada boton.
///
/// (`pantallas.md` §9.2 describe la excepcion contraria —cajon tambien en
/// escritorio— aprobada para delivery el 05/09/2026. Manda la regla de la casa,
/// que es lo que se pidio para esta pantalla; cambiarlo de vuelta es este
/// `esEscritorio` y nada mas.)
///
/// **Nada de `AlertDialog` centrado con el contenido apretado**: en los dos
/// casos hay cabecera con titulo, cuerpo desplazable y pie con los botones
/// siempre a la vista.
Future<T?> abrirCajon<T>({
  required BuildContext context,
  required WidgetBuilder constructor,
  AnchoCajon ancho = AnchoCajon.lg,
}) {
  // CORREGIDO 14/09/2026. Delivery NO usa modal en escritorio.
  //
  // Esto se escribió con la regla general de Procovar —cajón en móvil, modal en
  // escritorio— porque así se pidió. Es la regla equivocada para este proyecto:
  // `docs/pantallas.md:25` recoge una excepción aprobada el 05/09/2026 según la cual
  // **delivery usa SIEMPRE cajón lateral, también en escritorio**, y §9.2 dice que no hay
  // variante modal. El motivo está escrito allí: estas fichas son largas y un modal
  // centrado con desplazamiento interno se lee peor que un panel a alto completo.
  //
  // Se quita la rama de escritorio y se deja una sola forma. El fichero sigue siendo una
  // copia de `lib/diseno/cajon.dart` —se escribieron a la vez y ese kit no existía— y
  // desaparece cuando estas dos pantallas pasen a usarlo; hace falta darles título, que
  // hoy va dentro del cuerpo. Está apuntado en `docs/integracion-pendiente.md`.
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // A pantalla completa en movil: media pantalla con el teclado abierto no
    // deja ver ni el campo que se esta escribiendo.
    constraints: const BoxConstraints.expand(),
    builder: constructor,
  );
}

/// El marco de dentro: cabecera, cuerpo desplazable y pie pegado abajo.
class MarcoCajon extends StatelessWidget {
  const MarcoCajon({
    required this.titulo,
    required this.cuerpo,
    this.subtitulo,
    this.pie,
    super.key,
  });

  final String titulo;
  final String? subtitulo;
  final Widget cuerpo;

  /// Los botones de accion. Van pegados abajo y **siempre a la vista**: un
  /// `Guardar` al final de un formulario largo se queda fuera de pantalla justo
  /// cuando hace falta.
  final Widget? pie;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(titulo, style: tema.textTheme.titleMedium),
                    if (subtitulo != null)
                      Text(subtitulo!, style: tema.textTheme.bodySmall),
                  ],
                ),
              ),
              // La ✕ NO desaparece nunca: ni al guardar, ni mientras guarda, ni
              // con el teclado abierto. Un panel sin salida visible es una
              // trampa, y en el telefono el gesto de atras no siempre esta.
              IconButton(
                tooltip: 'Cerrar',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: cuerpo,
          ),
        ),
        if (pie != null) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(alignment: Alignment.centerRight, child: pie),
          ),
        ],
      ],
    );
  }
}
