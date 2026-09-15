import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diseno/anchos.dart';
import '../nucleo/plataforma.dart';
import 'barra_lateral.dart';
import 'barra_superior.dart';
import 'franja_de_estado.dart';
import 'pantalla_registrada.dart';

/// EL ARMAZON COMUN de todas las pantallas.
///
/// De arriba abajo y siempre en el mismo orden:
///
///   barra superior (64 px)  ← titulo, menu en movil, sucursal, moneda, avatar
///   FRANJA DE ESTADO        ← de que hora son los datos y cuantos sin subir
///   la pantalla
///
/// La franja va **debajo** de la barra y no dentro: asi sobrevive a los 390 px
/// de un telefono, donde dentro de la barra seria lo primero en recortarse. Y es
/// justo lo que no puede faltar (caso S8).
///
/// ## …en la APK y en el escritorio. En web NO va — 15/09/2026
///
/// La franja contesta «¿de que hora son estos datos?», y esa pregunta solo tiene
/// sentido donde los datos pueden ser de anteayer: el logistico baja el dia por
/// la mannana y se va al almacen sin cobertura, y sin la franja arma la ruta de
/// ayer convencido de que es la de hoy. En un navegador con internet la
/// respuesta es siempre «de hace un momento», asi que la franja gasta sitio
/// arriba de las siete pantallas para decir algo que nunca cambia — y, peor,
/// **ensena que aqui hay un dia que traer a mano**, que es lo que en web no
/// existe. Es ademas la puerta a los dos cajones de traer y entregar el dia, que
/// tampoco pintan nada alli.
///
/// Lo que se quita es el aparato de PREPARARSE para no tener conexion, no el
/// aviso de que ahora mismo no la hay: si la web pierde la red a mitad, eso
/// sigue saliendo por su sitio de siempre (ver el informe).
class Armazon extends ConsumerWidget {
  const Armazon({
    required this.pantallas,
    required this.rutaActual,
    required this.child,
    super.key,
  });

  final List<PantallaRegistrada> pantallas;
  final String rutaActual;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ancho = MediaQuery.sizeOf(context).width;
    final esEscritorio = ancho >= Anchos.escritorio;
    final hayDiaQueTraer = ref.watch(trabajaSinConexionProvider);

    final actual = pantallas.firstWhereOrNull((p) => p.ruta == rutaActual);
    final titulo = actual?.titulo ?? '';

    return Scaffold(
      // En movil la barra lateral vive en el cajon del Scaffold: fuera de
      // pantalla, con velo, y pulsar fuera cierra (§8.1).
      drawer: esEscritorio
          ? null
          : Drawer(
              width: Anchos.barraLateral,
              child: BarraLateral(
                pantallas: pantallas,
                rutaActual: rutaActual,
                dentroDeCajon: true,
              ),
            ),
      // El `Builder` no es adorno: `Scaffold.of` necesita un contexto POR DEBAJO
      // del Scaffold. Con el contexto de `build` el boton de menu no encuentra
      // ningun cajon y revienta al pulsarlo.
      body: Builder(
        builder: (contexto) {
          final columna = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BarraSuperior(
                titulo: titulo,
                // En escritorio no hay boton de menu: la barra lateral esta
                // fija y un boton que no abre nada ensena a desconfiar.
                alAbrirMenu: esEscritorio
                    ? null
                    : () => Scaffold.of(contexto).openDrawer(),
              ),
              if (hayDiaQueTraer) const FranjaDeEstado(),
              Expanded(child: child),
            ],
          );

          if (!esEscritorio) return columna;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BarraLateral(pantallas: pantallas, rutaActual: rutaActual),
              Expanded(child: columna),
            ],
          );
        },
      ),
    );
  }
}
