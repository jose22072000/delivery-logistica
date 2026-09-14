import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../diseno/cajon.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/insignia.dart';
import '../../../diseno/numeros.dart';
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

String dineroBonito(double usd) => '${Numeros.importe(usd)} \$';

String horaBonita(DateTime cuando) => DateFormat('H:mm').format(cuando);

/// Los dos colores con los que se marcan las tarjetas. En **rojo** lo que hoy no
/// sale; en **ambar** lo que sale distinto de como se pidio. Pintarlo todo en
/// ambar es no pintar nada.
abstract final class ColoresTablero {
  static const rojo = Colores.rojo;
  static const rojoFondo = Colores.rojoFondo;
  static const ambar = Colores.ambar;
  static const ambarFondo = Colores.ambarFondo;
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
