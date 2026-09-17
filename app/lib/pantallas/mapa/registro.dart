import 'package:flutter/material.dart';

import '../../navegacion/pantalla_registrada.dart';
import '../../nucleo/plataforma.dart';
import 'pantalla_mapa_sin_conexion.dart';

/// El registro del Mapa sin conexión. El contrato está en
/// `navegacion/pantalla_registrada.dart`.
///
/// **`enElMenu` depende del destino, y es la regla 1 de `CLAUDE.md`.** En la web
/// no se enseña: quien abre un navegador tiene servidor detrás, siempre, así que
/// una entrada de menú que lleva a «descarga el mapa de Cuba» le explicaría algo
/// que en su caso nunca pasa — que es exactamente lo que Jose ha tenido que
/// pedir que se quite tres veces.
///
/// **La ruta sí existe en los cuatro destinos**, y a propósito: si la entrada se
/// quita pero la ruta también, abrir el enlace en la web daría un 404 de la
/// aplicación en vez de una pantalla que explica por qué eso no va con ella. La
/// pantalla trata el caso (`MapaNoAplica`) y lo dice con palabras.
PantallaRegistrada registrarMapaSinConexion() => PantallaRegistrada(
  ruta: '/mapa-sin-conexion',
  titulo: TextosDelMapaGuardado.titulo,
  icono: Icons.map_outlined,
  enElMenu: Destino.trabajaSinConexion,
  construir: (contexto, estado) => const PantallaMapaSinConexion(),
);
