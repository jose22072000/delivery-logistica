import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'mapa/proveedores_de_mapa.dart';
import 'pantallas/rutas/datos/mapa_en_vivo.dart';
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
  runApp(
    ProviderScope(
      // EL MAPA GUARDADO EN EL APARATO, delante del de la red.
      //
      // `croquis_de_ruta.dart` pide sus teselas por `fondoDeCallesProvider` y
      // le da igual de dónde salgan. Esto le pone delante el paquete de Cuba
      // que hay descargado, con OSM detrás para lo que el paquete no tenga.
      // **Sin esta línea el paquete se descarga y no se dibuja**, que es la
      // peor de las dos mitades: ocupa y no sirve.
      //
      // En la web el paquete no existe (regla 1) y el proveedor cae solo al de
      // siempre. Ver `docs/mapa-sin-conexion.md` §9.
      overrides: [
        fondoDeCallesProvider.overrideWith(
          (ref) => ref.watch(fondoConPaqueteProvider),
        ),
        // Y LA RUTA POR CALLES, que es la otra mitad del mismo mapa.
        //
        // Sin esta línea pasa lo que Jose vio el 21/09/2026 con el avión
        // puesto: el fondo salía del paquete —las calles de La Habana se
        // veían— y encima la ruta se dibujaba en líneas rectas de parada a
        // parada, porque el único enrutador que había era una petición a
        // OSRM. «la ruta no es logica es son rectas eso no lo queremos te
        // dije». La geometría para enrutar estaba ya dentro del aparato.
        //
        // En la web no hay paquete y el proveedor cae solo a OSRM, igual que
        // el fondo.
        recorridoPorCallesProvider.overrideWith(
          (ref) => ref.watch(recorridoConPaqueteProvider),
        ),
      ],
      child: const RepartoApp(),
    ),
  );
}
