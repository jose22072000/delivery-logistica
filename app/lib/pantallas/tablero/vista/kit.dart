import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../diseno/cajon.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/insignia.dart';
import '../../../diseno/numeros.dart';
import '../../../navegacion/estado_navegacion.dart';
import '../datos/modelos.dart';

export '../../../diseno/colores.dart' show Colores;
export '../../../diseno/insignia.dart' show Insignia;

/// Lo poco de pintar que es del tablero y no del kit de la casa.
///
/// El kit comun (`lib/diseno/`) manda: los colores, la insignia, los numeros y
/// **el cajon** salen de alli, no de aqui. Lo que queda en este fichero son
/// tres formatos que el tablero necesita y el kit no tiene: los kilometros de
/// un pedido SIN coordenadas, y la hora de la ultima bajada.

/// Los kilometros de una tarjeta.
///
/// Un pedido sin coordenadas llega como `infinity` —no como cero, que lo
/// pondria el primero de «lo mas cerca»— y aqui se dice con letras. Pintar
/// «0,0 km» sobre un pedido que nadie sabe donde esta es peor que no pintar
/// nada.
String kmBonito(double km) => km.isFinite ? Numeros.km(km) : 'sin ubicar';

/// El peso de una columna va redondeado: es el subtexto de una cabecera, no una
/// factura.
String pesoBonito(double kg) => Numeros.kgRedondeado(kg);

/// UN IMPORTE DEL TABLERO, en la moneda que se este mirando.
///
/// Pasa por la MISMA tasa que el resto de la aplicacion
/// (`TasaDeLaMirada.importe`), y por eso pide `ref` en vez de formatear a mano.
/// Antes era `'${Numeros.importe(usd)} \$'` a pelo: el tablero se saltaba el
/// selector de moneda entero, asi que con CUP puesto en la barra las tarjetas
/// y las cabeceras de columna seguian diciendo «0,04 \$». No era un numero
/// equivocado —decia «\$», que es lo que era—, pero si la unica pantalla donde
/// el selector no hacia nada, y en la que mas se mira el dinero.
///
/// La regla de la casa sigue intacta: si la sucursal que se mira no tiene tasa,
/// `monedaEfectivaProvider` se cae a USD sola y aqui no se convierte nada. **No
/// se cae a la tasa de otra sucursal.**
String dineroBonito(WidgetRef ref, double usd) => ref
    .watch(tasaDeLaMiradaProvider)
    .importe(usd, ref.watch(monedaEfectivaProvider));

String horaBonita(DateTime cuando) => DateFormat('H:mm').format(cuando);

/// Los dos colores con los que se marcan las tarjetas. En **rojo** lo que hoy no
/// sale; en **ambar** lo que sale distinto de como se pidio. Pintarlo todo en
/// ambar es no pintar nada.
abstract final class ColoresTablero {
  static final rojo = Colores.rojo;
  static final rojoFondo = Colores.rojoFondo;
  static final ambar = Colores.ambar;
  static final ambarFondo = Colores.ambarFondo;
}

/// La marca de una tarjeta, con su color.
///
/// En rojo lo que hoy NO sale (archivado, ya en otra ruta, sin factura, sin
/// cotejar); en ambar lo que sale distinto (`cambiado`), que se reparte igual
/// pero deja el peso de la columna sin ser el que era.
Insignia insigniaDeMarca(MarcaTarjeta marca) =>
    marca.grave ? insigniaGrave(marca.texto) : insigniaAviso(marca.texto);

Insignia insigniaGrave(String texto) =>
    Insignia(texto, color: Colores.rojo, fondo: Colores.rojoFondo);

Insignia insigniaAviso(String texto) =>
    Insignia(texto, color: Colores.ambar, fondo: Colores.ambarFondo);

/// El cajon de la casa, con el nombre que usa esta pantalla.
///
/// En delivery es **cajon tambien en escritorio** (excepcion aprobada el
/// 05/09/2026): estos paneles llevan listas largas —las doce columnas del
/// tablero, las paradas de una ruta— y un modal centrado con scroll dentro es
/// peor que un panel a alto completo. La ✕ de cerrar la pone el cajon y no
/// desaparece nunca.
Future<T?> mostrarCajon<T>({
  required BuildContext context,
  required String titulo,
  required WidgetBuilder contenido,
}) => abrirCajon<T>(context, titulo: titulo, cuerpo: contenido);

/// EL ANCHO A PARTIR DEL CUAL EL TABLERO SE VE ENTERO.
///
/// Por encima caben la mitad de «sin colocar» y las columnas A LA VEZ, que es lo
/// que hace que arrastrar una tarjeta tenga sentido. Por debajo son dos
/// pestanas, no se ve el destino, y el gesto es tocar la tarjeta para elegir a
/// donde va (`AccionesTablero.moverTarjeta`).
///
/// Vive aqui y no dentro de una pantalla porque lo leen DOS sitios —el que parte
/// la pantalla y el que decide si la tarjeta se arrastra— y tienen que decir lo
/// mismo siempre. Con el numero repetido, mover uno y olvidar el otro deja un
/// telefono donde se puede levantar una tarjeta que no se puede soltar.
const double anchoDeDosMitades = 900.0;
