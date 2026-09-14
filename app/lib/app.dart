import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'diseno/colores.dart';
import 'navegacion/rutas.dart';
import 'textos/textos.dart';

/// La aplicacion.
///
/// `MaterialApp.router` y no `MaterialApp` porque en web la URL tiene que ser de
/// verdad: los filtros de las listas viajan en la direccion, y una pantalla
/// filtrada que no se puede mandar por enlace deja a media oficina leyendo
/// numeros por telefono.
class RepartoApp extends StatefulWidget {
  const RepartoApp({super.key, this.enrutador});

  /// Se puede inyectar en los tests para montar el armazon con pantallas de
  /// mentira.
  final GoRouter? enrutador;

  @override
  State<RepartoApp> createState() => _RepartoAppState();
}

class _RepartoAppState extends State<RepartoApp> {
  late final GoRouter _enrutador = widget.enrutador ?? crearEnrutador();

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Reparto',
    debugShowCheckedModeBanner: false,
    theme: temaDeReparto(),
    // Sin estas dos lineas `Textos.of(context)` revienta en cada pantalla, y
    // las de Material dejarian un selector de fecha en ingles dentro de una
    // pantalla en espanol.
    localizationsDelegates: delegacionesDeIdioma,
    supportedLocales: idiomas,
    routerConfig: _enrutador,
  );
}
