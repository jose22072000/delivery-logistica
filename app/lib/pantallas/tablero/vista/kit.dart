import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
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

/// LOS PUNTEROS QUE ARRASTRAN DEL TIRÓN: el raton y el lapiz.
///
/// Se enumeran los que van a arrastre INMEDIATO, y no al reves, a proposito.
/// Un tipo de puntero que no este en esta lista —`touch`, `unknown`, o uno que
/// se invente Flutter manana— cae del lado seguro: pulsacion larga, que como
/// mucho estorba. Al reves, un dedo tratado como raton levanta tarjetas sin
/// querer mientras alguien baja la lista, que es exactamente el fallo que la
/// pulsacion larga vino a tapar.
const Set<PointerDeviceKind> punterosQueArrastranDelTiron = {
  PointerDeviceKind.mouse,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
};

/// Lo que tarda un dedo en «agarrar» algo antes de poder moverlo.
const Duration retardoDelDedo = Duration(milliseconds: 200);

/// ARRASTRE QUE DECIDE SU GESTO POR EL PUNTERO, NO POR LA PLATAFORMA.
///
/// Con **raton o lapiz** se arrastra del tiron, en cuanto el puntero se mueve.
/// Con **el dedo** hace falta mantener pulsado [retardoDelDedo] antes de
/// levantar nada.
///
/// # Por que hacian falta las dos cosas
///
/// Con el dedo la pulsacion larga es imprescindible: la lista se desplaza
/// arrastrando, asi que un arrastre inmediato se come el desplazamiento y quien
/// queria bajar a ver la tarjeta treinta levanta una tarjeta sin querer.
///
/// Con el raton ese problema **no existe**: la lista se desplaza con la rueda
/// (el `ScrollBehavior` de escritorio ni siquiera acepta el raton como `drag
/// device`), asi que ahi la pulsacion larga no protege de nada y solo estorba.
/// Y estorbaba de verdad: Jose, 17/09/2026, «en la web no tengo el drag and
/// drop… que yo arrastre las cosas y no funcionen». Una persona con raton pincha
/// y tira del tiron, nunca llega a los 200 ms, y la tarjeta no se levanta jamas.
/// El arrastre estaba entero y llegaba al servidor; lo que no llegaba a empezar
/// era el gesto.
///
/// # Por que NO se mira la plataforma
///
/// Nada de `kIsWeb` ni de `Platform.isAndroid`: un portatil con pantalla tactil
/// y una tableta con raton existen, y la web se abre igual desde un telefono. El
/// dato correcto es el del gesto concreto que esta ocurriendo, y ese es
/// [PointerDeviceKind]. El mismo tablero, en el mismo aparato, responde a los
/// dos si tiene los dos.
///
/// # Por que este camino y no otro
///
/// Hay tres formas de hacerlo y esta es la que menos codigo propio necesita:
///
///  1. `RawGestureDetector` con dos `MultiDragGestureRecognizer` a mano —
///     obligaria a reescribir el `feedback`, el `childWhenDragging`, el
///     `DragTarget` y todo el tinglado del `_DragAvatar` de Flutter. Mucho
///     codigo nuestro que Flutter ya tiene probado;
///  2. una sola `Draggable` con un reconocedor propio que fuera inmediato o con
///     retardo segun el puntero — un reconocedor escrito por nosotros, que es
///     justo la pieza mas delicada de todo esto;
///  3. **las dos `Draggable` de Flutter, una encima de otra, cada una con su
///     `supportedDevices`** — que es lo de aqui. Cada `GestureRecognizer` ya
///     sabe rechazar los punteros que no son suyos (`isPointerAllowed`), asi que
///     ante un `PointerDownEvent` solo una de las dos coge el puntero y la otra
///     ni se entera. No compiten, no hay arena que desempatar, y el unico codigo
///     nuestro son dos `createRecognizer` de tres lineas.
///
/// Pulsar sin mover sigue siendo un toque: el reconocedor inmediato no acepta el
/// gesto hasta que el puntero se mueve mas que el `hitSlop`, asi que el `onTap`
/// de la tarjeta —el que abre «moverla a»— se queda intacto, y soltar un
/// arrastre no lo dispara.
class ArrastrableSegunPuntero<T extends Object> extends StatelessWidget {
  const ArrastrableSegunPuntero({
    required this.datos,
    required this.feedback,
    required this.child,
    this.childWhenDragging,
    super.key,
  });

  /// Lo que viaja con el arrastre.
  final T datos;

  /// Lo que se ve pegado al puntero mientras se arrastra.
  final Widget feedback;

  final Widget child;

  /// Lo que se queda en el hueco. `null` = el propio [child].
  final Widget? childWhenDragging;

  @override
  Widget build(BuildContext context) => _ArrastreConDedo<T>(
    data: datos,
    feedback: feedback,
    childWhenDragging: childWhenDragging,
    child: _ArrastreConPuntero<T>(
      data: datos,
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      child: child,
    ),
  );
}

/// El de siempre —pulsacion larga— pero **solo para el dedo**.
class _ArrastreConDedo<T extends Object> extends LongPressDraggable<T> {
  const _ArrastreConDedo({
    required super.data,
    required super.feedback,
    required super.child,
    required super.childWhenDragging,
  }) : super(delay: retardoDelDedo);

  @override
  DelayedMultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) =>
      DelayedMultiDragGestureRecognizer(
          delay: delay,
          // Todo lo que no sea raton ni lapiz entra por aqui, incluido lo que no
          // sepamos identificar: ver `punterosQueArrastranDelTiron`.
          supportedDevices: PointerDeviceKind.values.toSet().difference(
            punterosQueArrastranDelTiron,
          ),
          allowedButtonsFilter: allowedButtonsFilter,
        )
        ..onStart = (posicion) {
          final arrastre = onStart(posicion);
          // El tic al agarrar, que es lo que le dice a un dedo que YA la lleva.
          // `LongPressDraggable` lo hace en su `createRecognizer`, y al sobrescribirlo
          // se perdia sin que se notara en ninguna prueba: en un widget test no
          // vibra nada.
          if (arrastre != null && hapticFeedbackOnStart) {
            HapticFeedback.selectionClick();
          }
          return arrastre;
        };
}

/// El nuevo —del tiron— **solo para raton y lapiz**.
class _ArrastreConPuntero<T extends Object> extends Draggable<T> {
  const _ArrastreConPuntero({
    required super.data,
    required super.feedback,
    required super.childWhenDragging,
    required super.child,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => ImmediateMultiDragGestureRecognizer(
    supportedDevices: punterosQueArrastranDelTiron,
    allowedButtonsFilter: allowedButtonsFilter,
  )..onStart = onStart;
}
