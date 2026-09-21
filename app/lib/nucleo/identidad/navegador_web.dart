import 'package:web/web.dart' as web;

import 'navegador.dart';

Navegador abrirNavegador() => const NavegadorDelNavegador();

/// El de verdad: cambia la direccion de la pestana.
class NavegadorDelNavegador implements Navegador {
  const NavegadorDelNavegador();

  /// `assign` y no `replace`: la vuelta atras del navegador tiene que seguir
  /// funcionando. Con `replace`, quien pulsa «atras» desde Accesos se encuentra
  /// otra vez la pagina que le mando alli y vuelve a salir disparado.
  @override
  void irA(String destino) => web.window.location.assign(destino);

  @override
  Uri get direccionAlCargar => Uri.base;
}
