import 'package:flutter/material.dart';

import '../../navegacion/pantalla_registrada.dart';
import 'vista/pantalla_informes.dart';

/// El registro de Reportes. El contrato esta en
/// `navegacion/pantalla_registrada.dart`.
///
/// `enElMenu: false` **a proposito**: el pliego (§8.1) dice que la pantalla
/// existe pero no sale en la barra lateral. Se llega por URL y desde las
/// acciones rapidas del Panel.
PantallaRegistrada registrarInformes() => PantallaRegistrada(
  ruta: '/reports',
  titulo: 'Reportes',
  icono: Icons.assessment_outlined,
  enElMenu: false,
  construir: (contexto, estado) => const PantallaInformes(),
);
