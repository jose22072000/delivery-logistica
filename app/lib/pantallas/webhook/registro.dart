import 'package:flutter/material.dart';

import '../../navegacion/pantalla_registrada.dart';
import '../../nucleo/plataforma.dart';
import 'vista/pantalla_webhook.dart';

/// La ruta de esta pantalla. Bajo `/admin` a propósito: dice de qué va sin abrirla.
const rutaDelWebhook = '/admin/webhook';

/// CÓMO VA EL CANAL CON PEDIDO. **Sólo en la web y fuera del menú.**
///
/// Jose, 26/09/2026: «eso me lo dejas en la web solamente, no lo pongas en más ningún lado»
/// y «que sólo lo pueda ver yo, eso no lo puede ver más nadie, sólo yo, el desarrollador».
///
/// TRES CERROJOS, y ninguno sobra:
///
///  1. **No está en el menú.** Nadie tropieza con ella.
///  2. **No existe fuera de la web.** En la APK y en el escritorio ni siquiera se registra:
///     el repartidor está en la calle y esto es una pantalla de tuberías entre dos
///     sistemas. Y además la APK trabaja sin señal, donde este dato no significa nada.
///  3. **El servidor contesta 403 a cualquier rol que no sea DESARROLLADOR**, y ése es el
///     único que de verdad cierra. Los dos de arriba son para que no estorbe, no para
///     proteger: el rol que lleva el aparato **no decide permisos** —lo dice la propia
///     `Sesion`: «confiar en esto para decidir permisos sería darle a cualquiera con un
///     editor de texto el rol que quiera»—.
PantallaRegistrada? registrarWebhook() {
  // `trabajaSinConexion` es `false` SÓLO en la web. Es el único `kIsWeb` de todo esto y
  // está en un sitio, que es lo que permite probar las dos plataformas.
  if (Destino.trabajaSinConexion) return null;
  return PantallaRegistrada(
    ruta: rutaDelWebhook,
    titulo: 'Canal con PEDIDO',
    enElMenu: false,
    icono: Icons.cable_outlined,
    construir: (contexto, estado) => const PantallaWebhook(),
  );
}
