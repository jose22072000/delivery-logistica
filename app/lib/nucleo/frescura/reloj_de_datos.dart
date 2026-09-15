import 'package:flutter/material.dart';
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

/// El reloj de datos de la barra superior. **Siempre visible, en las 7
/// pantallas** (caso S8).
///
/// Recibe todo por parametro y no lee providers: asi se prueba con el reloj
/// donde haga falta y no arrastra media aplicacion a un test de widget.
class RelojDeDatos extends StatelessWidget {
  const RelojDeDatos({
    required this.estado,
    this.actualizando = false,
    this.sinSubir = 0,
    this.alPulsarPendientes,
    super.key,
  });

  final EstadoFrescura estado;

  /// Subiendo o bajando: el giro y `actualizando…`.
  final bool actualizando;

  /// Cuantos apuntes quedan en la cola. Pulsable: lleva a la bandeja.
  final int sinSubir;

  final VoidCallback? alPulsarPendientes;

  /// El ambar del pliego. Es el mismo `Colores.ambar` de `diseno/`, repetido
  /// aqui porque `nucleo/` no depende de `diseno/`: el reloj de datos tiene que
  /// poder montarse en un test sin arrastrar el kit entero.
  static const ambar = Color(0xFF96560A);

  /// El `--ink-soft` de delivery, por lo mismo.
  static const tintaSuave = Color(0xFF5C544A);

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final color = estado.enAmbar ? ambar : tintaSuave;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (actualizando) ...[
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: tintaSuave,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'actualizando…',
            style: tema.textTheme.bodySmall?.copyWith(color: tintaSuave),
          ),
        ] else
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
              foregroundColor: ambar,
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
