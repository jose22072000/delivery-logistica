import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../diseno/anchos.dart';
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
class Armazon extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final esEscritorio = ancho >= Anchos.escritorio;

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
              const FranjaDeEstado(),
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
