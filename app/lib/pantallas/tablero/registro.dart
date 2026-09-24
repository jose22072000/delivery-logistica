import 'package:flutter/material.dart';

import '../../navegacion/pantalla_registrada.dart';
import 'estado/filtros_en_la_url.dart';
import 'vista/pantalla_tablero.dart';

export 'vista/pantalla_tablero.dart' show PantallaTablero;

/// EL REGISTRO DEL TABLERO. El contrato esta en
/// `navegacion/pantalla_registrada.dart`; para enchufarlo basta sustituir en
/// `navegacion/pantallas.dart` la linea
/// `_pendiente('/tablero', 'Tablero', Icons.view_column_outlined)` por
/// `registrarTablero()`, con su import.
///
/// **En el menu**, y con esa decision ya anotada alli: es la pantalla del dia
/// del logistico y sin entrada no se llega a ella. No sale en el §8.1 del
/// pliego porque ese describe la aplicacion de Next, y el tablero es de
/// `docs/tablero.md`, del 14/09/2026.
///
/// Los filtros de la mitad izquierda se leen de la direccion, que es lo que
/// hace que se pueda mandar un enlace al tablero ya filtrado.
PantallaRegistrada registrarTablero() => PantallaRegistrada(
  ruta: FiltrosEnLaUrl.camino,
  titulo: 'Tablero',
  icono: Icons.view_column_outlined,
  enElMenu: true,
  construir: (contexto, estado) => PantallaTablero(
    lectura: FiltrosEnLaUrl.leer(estado.uri.queryParameters),
  ),
);
