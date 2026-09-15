import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'diseno/tema.dart';
import 'navegacion/portero.dart';
import 'navegacion/rutas.dart';
import 'textos/textos.dart';

/// La aplicacion.
///
/// `MaterialApp.router` y no `MaterialApp` porque en web la URL tiene que ser de
/// verdad: los filtros de las listas viajan en la direccion, y una pantalla
/// filtrada que no se puede mandar por enlace deja a media oficina leyendo
/// numeros por telefono.
class RepartoApp extends ConsumerStatefulWidget {
  const RepartoApp({super.key, this.enrutador});

  /// Se puede inyectar en los tests para montar el armazon con pantallas de
  /// mentira.
  final GoRouter? enrutador;

  @override
  ConsumerState<RepartoApp> createState() => _RepartoAppState();
}

class _RepartoAppState extends ConsumerState<RepartoApp> {
  late final GoRouter _enrutador =
      widget.enrutador ?? crearEnrutador(portero: ref.read(porteroProvider));

  @override
  void initState() {
    super.initState();
    // EL ARRANQUE, una sola vez y aqui: abre la base, lee la sesion guardada e
    // intenta renovar. Mientras tanto se ve la espera; al acabar, el portero
    // mueve la aplicacion al Panel o al acceso.
    if (widget.enrutador == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(porteroProvider).comprobar(),
      );
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Reparto',
    debugShowCheckedModeBanner: false,
    theme: temaDeReparto(),
    // El papel con su rejilla, DEBAJO de todas las pantallas y por encima de
    // nada. Va aqui, en el `builder`, y no en cada `Scaffold`: asi lo tienen
    // tambien los cajones y los menus, que se pintan fuera del arbol de la
    // pantalla.
    builder: (contexto, pantalla) =>
        FondoDePapel(child: pantalla ?? const SizedBox.shrink()),
    // Sin estas dos lineas `Textos.of(context)` revienta en cada pantalla, y
    // las de Material dejarian un selector de fecha en ingles dentro de una
    // pantalla en espanol.
    localizationsDelegates: delegacionesDeIdioma,
    supportedLocales: idiomas,
    routerConfig: _enrutador,
  );
}
