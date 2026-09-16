import 'package:flutter/material.dart';

import '../../diseno/colores.dart';

import 'package:intl/intl.dart';

/// En que tramo cae lo que se esta viendo.
///
/// Es una funcion pura y por eso se puede probar con el reloj movido a mano, sin
/// pintar nada.
sealed class EstadoFrescura {
  const EstadoFrescura();

  /// El tramo que toca, con el reloj del aparato.
  ///
  /// [bajadaAt] a `null` **no es** «hace mucho»: es que no se bajo NUNCA, y es
  /// un estado distinto que hay que decir con otras palabras.
  factory EstadoFrescura.de(DateTime? bajadaAt, {required DateTime ahora}) {
    if (bajadaAt == null) return const SinDescargar();
    final desde = ahora.difference(bajadaAt);
    if (desde < const Duration(hours: 1)) return DatosRecientes(bajadaAt);
    if (desde < const Duration(hours: 24)) return DatosDeHoras(desde.inHours);
    return DatosViejos(bajadaAt, desde.inDays);
  }

  /// El texto de la barra, literal.
  String get texto;

  /// En ambar = «mira esto». Sólo lo que de verdad puede enganar: lo de hace
  /// mas de un dia y lo que no se bajo nunca. Pintarlo todo en ambar es no
  /// pintar nada.
  bool get enAmbar;
}

/// Nunca se bajo. Ambar.
class SinDescargar extends EstadoFrescura {
  const SinDescargar();

  @override
  String get texto => 'Sin descargar todavía';

  @override
  bool get enAmbar => true;

  /// El estado vacio de una coleccion que nunca se bajo. **No es el mismo que
  /// «no hay nada»**, y por eso tiene su propio texto: una lista vacia ahi es un
  /// fallo, no un dato (caso S7).
  static const textoDeLaPantallaVacia =
      'Esta pantalla no se ha descargado todavía. Con conexión baja sola.';
}

/// Menos de una hora. Gris. Se dice la hora porque a esa distancia es util.
class DatosRecientes extends EstadoFrescura {
  const DatosRecientes(this.bajadaAt);

  final DateTime bajadaAt;

  @override
  String get texto => 'Datos de las ${DateFormat('H:mm').format(bajadaAt)}';

  @override
  bool get enAmbar => false;
}

/// Entre una hora y un dia. Gris. Se dice la distancia, que es lo que importa.
class DatosDeHoras extends EstadoFrescura {
  const DatosDeHoras(this.horas);

  final int horas;

  @override
  String get texto => 'Datos de hace $horas h';

  @override
  bool get enAmbar => false;
}

/// Mas de un dia. **Ambar.** Aqui es donde se arma la ruta de anteayer.
class DatosViejos extends EstadoFrescura {
  const DatosViejos(this.bajadaAt, this.dias);

  final DateTime bajadaAt;
  final int dias;

  @override
  String get texto {
    final dia = DateFormat('EEEE', 'es').format(bajadaAt);
    final cuantos = dias == 1 ? 'hace 1 día' : 'hace $dias días';
    return 'Datos del $dia — $cuantos';
  }

  @override
  bool get enAmbar => true;
}

/// El reloj de datos. **Siempre visible, en las 7 pantallas** (caso S8).
///
/// Dice dos cosas y sólo dos: **de que hora son los datos** y **cuantos apuntes
/// quedan sin subir**.
///
/// Lo que NO dice es `actualizando…`. Lo decia, y el resultado era dos ruedas
/// girando a la vez en la misma pantalla: una junto al titulo de la barra
/// superior y otra dentro de la franja de debajo, diciendo lo mismo una encima
/// de la otra. El sitio de «hay algo en vuelo» es la barra superior —es lo que
/// hace la de Next (`Navbar.tsx`, `useIsFetching() > 0` al lado del titulo)—, y
/// **es el unico**. Aqui se quito el parametro entero en vez de dejarlo apagado
/// con un `if`: un parametro que nadie pone vuelve solo a los seis meses.
///
/// Recibe todo por parametro y no lee providers: asi se prueba con el reloj
/// donde haga falta y no arrastra media aplicacion a un test de widget.
class RelojDeDatos extends StatelessWidget {
  const RelojDeDatos({
    required this.estado,
    this.sinSubir = 0,
    this.alPulsarPendientes,
    super.key,
  });

  final EstadoFrescura estado;

  /// Cuantos apuntes quedan en la cola. Pulsable: lleva a la bandeja.
  final int sinSubir;

  final VoidCallback? alPulsarPendientes;

  // AQUI HABIA DOS COLORES COPIADOS A MANO —`#96560A` y `#5C544A`— con el
  // motivo de que «nucleo/ no depende de diseno/». El motivo era bueno y el
  // resultado malo: el dia que la paleta paso a salir del oro del logo, estos
  // dos se quedaron con el ambar y el gris viejos, y este reloj era el unico
  // sitio de la aplicacion pintado de la paleta anterior.
  //
  // `diseno/colores.dart` no arrastra nada: es un fichero de tokens que solo
  // importa `material`. Se importa y se acabo la copia.

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final color = estado.enAmbar ? Colores.ambar : Colores.tintaSuave;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          estado.texto,
          style: tema.textTheme.bodySmall?.copyWith(color: color),
        ),
        if (sinSubir > 0) ...[
          const SizedBox(width: 8),
          // Nada se descarta en silencio: lo que queda sin subir se ve y se
          // puede abrir.
          TextButton(
            onPressed: alPulsarPendientes,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: Colores.ambar,
              textStyle: tema.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text('$sinSubir sin subir'),
          ),
        ],
      ],
    );
  }
}
