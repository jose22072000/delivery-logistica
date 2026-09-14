import 'package:flutter/material.dart';

import '../../navegacion/pantalla_registrada.dart';
import 'vista/pantalla_panel.dart';

/// El registro del Panel. El contrato esta en
/// `navegacion/pantalla_registrada.dart`.
PantallaRegistrada registrarPanel() => PantallaRegistrada(
  ruta: '/dashboard',
  titulo: 'Panel',
  icono: Icons.dashboard_outlined,
  enElMenu: true,
  construir: (contexto, estado) => const PantallaPanel(),
);
