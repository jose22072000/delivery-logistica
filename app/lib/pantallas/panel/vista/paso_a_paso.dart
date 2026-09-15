import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../datos/configuracion_pendiente.dart';
import '../estado/configuracion_estado.dart';

/// EL PASO A PASO DE LA PUESTA EN MARCHA — lo primero del Panel cuando falta
/// algo, y nada en absoluto cuando no falta.
///
/// ## Por que vive en el Panel y no en una pantalla propia
///
/// Porque tiene que verlo **quien entra y le falta algo, sin ir a buscarlo**.
/// El Panel es la primera pantalla de la manana (`rutas.dart`, `rutaDeInicio`):
/// una pantalla «Puesta en marcha» en el menu sólo la abre quien ya sospecha que
/// falta algo, y quien sospecha eso no es el que se encuentra Vehiculos vacio.
/// Tampoco va en el armazon —siete pantallas con la misma banda encima es una
/// banda que nadie lee—, y ademas `lib/navegacion/` es de otro.
///
/// ## Quien manda cuando coincide con el estado del dia
///
/// `EstadoDelDia` ya ocupa el sitio de arriba del Panel con el gesto del dia
/// (traer / enviar). Cuando los dos tienen algo que decir, **el paso a paso va
/// encima**, y no es un capricho:
///
///  * **Si el aparato no tiene datos, este widget NO SE PINTA** (la regla vive
///    en `ElPasoAPaso.seEnsena`). Sin nada bajado no se sabe que falta, y poner
///    cuatro pasos en «no se sabe» justo encima del boton que los resolveria es
///    tapar la respuesta con la pregunta. Ahi manda `EstadoDelDia`: lo primero
///    es traer el dia.
///  * **Si el aparato ya tiene datos y falta configuracion, manda configurar.**
///    Volver a traer el dia no va a hacer aparecer un camion que nadie ha dado
///    de alta, asi que el gesto de sincronizar, puesto primero, seria el consejo
///    equivocado repetido cada manana.
///
/// O sea: los dos nunca compiten por el primer sitio. Cuando este aparece, es
/// porque el otro ya no es lo que toca.
class PasoAPaso extends ConsumerWidget {
  const PasoAPaso({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(pasoAPasoProvider).value;
    // Mientras se mira la base no se pinta nada. Un hueco que aparece medio
    // segundo despues empuja el Panel entero hacia abajo debajo del dedo.
    if (estado == null || !estado.seEnsena) return const SizedBox.shrink();

    final pendientes = estado.pendientes;
    final hechos = estado.hechos;
    final estrecho = MediaQuery.sizeOf(context).width < Anchos.entrega;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: Aire.xl),
      padding: EdgeInsets.all(estrecho ? Aire.lg : Aire.xl),
      decoration: BoxDecoration(
        color: Colores.blanco,
        borderRadius: BorderRadius.circular(Radios.xl),
        border: Border.all(color: Colores.ambar.withValues(alpha: 0.35)),
        boxShadow: Sombras.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.checklist_rtl_outlined,
                size: 20,
                color: Colores.ambar,
              ),
              const SizedBox(width: Aire.sm),
              Expanded(
                child: Text(
                  'Falta configurar esta sucursal',
                  style: Tipos.texto(
                    tamano: 17,
                    peso: FontWeight.w700,
                    color: Colores.tinta,
                  ),
                ),
              ),
              Text(
                '${hechos.length} de ${estado.pasos.length}',
                style: Tipos.mono(
                  tamano: 12,
                  peso: FontWeight.w600,
                  color: Colores.tintaSuave,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Sin esto no se puede armar una ruta. Van en este orden: cada uno '
            'necesita el anterior.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colores.tintaSuave),
          ),
          const SizedBox(height: Aire.lg),

          // LOS QUE FALTAN, enteros. Numerados con el sitio que ocupan en la
          // lista completa —«3 de 4»— y no con el sitio que ocupan entre los que
          // faltan: si no, al hacer uno los demas se renumerarian y el paso 3 de
          // ayer seria el 2 de hoy.
          for (final paso in pendientes) ...[
            _PasoQueFalta(
              numero: estado.pasos.indexOf(paso) + 1,
              total: estado.pasos.length,
              paso: paso,
            ),
            const SizedBox(height: Aire.md),
          ],

          // LOS QUE YA ESTAN: una linea y fuera del camino. Se dicen —para que
          // se vea que el paso a paso los miro y no se los saltó— pero no
          // ocupan.
          if (hechos.isNotEmpty) ...[
            const SizedBox(height: Aire.xs),
            for (final paso in hechos) _PasoHecho(paso: paso),
          ],
        ],
      ),
    );
  }
}

/// Un paso pendiente. Dice **que es**, **que pasa si falta** y **a donde ir**.
class _PasoQueFalta extends StatelessWidget {
  const _PasoQueFalta({
    required this.numero,
    required this.total,
    required this.paso,
  });

  final int numero;
  final int total;
  final PasoDeConfiguracion paso;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    // EL COLOR SEPARA LOS DOS ESTADOS. Ambar = falta, hay que hacerlo. Azul =
    // no se sabe todavia, y se arregla trayendo el dia. Con el mismo color los
    // dos se leen igual, que es el fallo que esto viene a quitar.
    final sinSaber = paso.como == ComoVa.sinSaber;
    final color = sinSaber ? Colores.azul : Colores.ambar;
    final fondo = sinSaber ? Colores.azulFondo : Colores.ambarFondo;

    final ruta = paso.ruta;
    final donde = paso.dondeSeArregla;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Aire.md),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(Radios.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '$numero/$total',
                  style: Tipos.mono(
                    tamano: 12,
                    peso: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paso.titulo,
                      style: Tipos.texto(
                        tamano: 14,
                        peso: FontWeight.w600,
                        color: Colores.tinta,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Que es y para que sirve, siempre; y debajo, que pasa si
                    // falta. Las dos: la primera dice de que se habla y la
                    // segunda es la que hace que alguien lo haga hoy.
                    Text(
                      paso.paraQue,
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: Colores.tintaSuave,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      paso.explicacion,
                      style: tema.textTheme.bodySmall?.copyWith(color: color),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // EL BOTON SOLO SI LLEVA A ALGUN SITIO.
          //
          //  * Falta y se arregla aqui   → boton a su pantalla.
          //  * No se sabe               → no hay boton propio: se arregla con
          //    «Traer el día», que es el gesto que ya esta justo debajo, en
          //    `EstadoDelDia`. Poner aqui un segundo boton que hace lo mismo son
          //    dos puertas a la misma habitacion.
          //  * No se arregla en esta aplicacion (el punto de partida y la tasa)
          //    → se dice donde se arregla, en texto. **Nunca un boton apagado**:
          //    uno gris invita a pulsarlo igual, y uno que lleva a una pantalla
          //    donde el problema no se toca es peor que ninguno.
          if (!sinSaber && ruta != null) ...[
            const SizedBox(height: Aire.sm),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: () => context.go(ruta),
                  child: Text(paso.textoDelBoton ?? 'Ir'),
                ),
              ),
            ),
          ] else if (!sinSaber && donde != null) ...[
            const SizedBox(height: Aire.sm),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 15,
                    color: Colores.tintaSuave,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      donde,
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: Colores.tintaSuave,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Un paso ya hecho: una linea gris con su marca y nada mas.
class _PasoHecho extends StatelessWidget {
  const _PasoHecho({required this.paso});

  final PasoDeConfiguracion paso;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        const Icon(Icons.check_circle_outline, size: 16, color: Colores.verde),
        const SizedBox(width: Aire.sm),
        Expanded(
          child: Text(
            paso.titulo,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colores.tintaSuave),
          ),
        ),
      ],
    ),
  );
}
