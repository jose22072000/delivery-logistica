import 'package:flutter/material.dart';

import '../../navegacion/pantalla_registrada.dart';
import 'datos/panel_sincronizacion.dart';
import 'vista/pantalla_sincronizacion.dart';

/// El registro de Sincronización. El contrato está en
/// `navegacion/pantalla_registrada.dart`.
///
/// `enElMenu: true` **y con motivo**: el pliego (§8.1) no la lista porque la de
/// Next no tiene sincronizador, así que esto es una pantalla nueva, como el
/// tablero. Va en el menú porque sin entrada no se llega a ella —y una pantalla
/// a la que no se llega no avisa de nada—, y porque lo que enseña ya viene
/// acotado por sucursal desde el servidor: un logístico ve su aparato y sabe si
/// le queda algo sin subir; el Super Admin ve los diez. Si se decide lo
/// contrario, es cambiar este `enElMenu` a `false`.
PantallaRegistrada registrarSincronizacion() => PantallaRegistrada(
  ruta: PantallaSincronizacion.ruta,
  titulo: TextosDeSincronizacion.titulo,
  icono: Icons.sync_outlined,
  enElMenu: true,
  construir: (contexto, estado) => const PantallaSincronizacion(),
);
