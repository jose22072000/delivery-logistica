import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';

void main() {
  // URL limpias: `/dashboard`, no `/#/dashboard`.
  //
  // Flutter web enruta por defecto con almohadilla porque asi no hace falta que el
  // servidor sepa nada: todo lo que va detras del `#` no llega a pedirse. Pero deja unas
  // direcciones que no se pueden mandar por WhatsApp sin que parezcan rotas, y que
  // ninguna otra aplicacion de Procovar tiene.
  //
  // Quitarla exige que el servidor devuelva `index.html` para CUALQUIER ruta, porque
  // `/dashboard` ya no es un fichero: `deploy/nginx.conf` lo hace con
  // `try_files $uri $uri/ /index.html`. Sin eso, recargar en cualquier pantalla da un 404.
  //
  // En movil y escritorio no cambia nada: alli no hay barra de direcciones.
  usePathUrlStrategy();
  runApp(const ProviderScope(child: RepartoApp()));
}
