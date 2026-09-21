// «LOS ALMACENES SON LOS DE LA ÚLTIMA VEZ QUE HUBO RED», con su fecha.
//
// Los almacenes están declarados en `faltan` a propósito y esa decisión no se
// toca: Accesos no da marca de cambio ni dice qué borró, así que no se pueden
// bajar por diferencias (`docs/integracion-pendiente.md`). La copia del aparato
// se reemplaza entera cada vez que hay red, y entre una vez y la siguiente el
// aparato **enseña la copia vieja como si fuera la de ahora**.
//
// Eso no parece nada y es caro: desde el almacén se mide lo que se le cobra al
// cliente por el domicilio. Uno retirado que este aparato todavía no sabe que se
// retiró cobra mal cada entrega del día, y no se nota hasta cuadrar la caja. Es
// el mismo fallo de familia que el `optimized` clavado o el `price || 0`: un
// número creíble, equivocado, que ninguna pantalla desmiente.
//
// Lo que queda por hacer es lo único que se puede hacer hoy, y es la regla 4 de
// la casa: **si algo puede estar viejo, se dice**. Con la fecha, que es lo que
// convierte un aviso en un dato.
//
// **EN LA WEB NO SE PINTA NADA, y es la regla 1.** Allí no hay copia que pueda
// envejecer: la página lee del servidor y los almacenes que se ven son los de
// ahora mismo. Decirle a quien está sentado en la oficina que sus almacenes son
// los del lunes es contarle un problema que en su caso no existe — el mismo
// razonamiento que ya tenían `RelojDeDatos` y `TextosDeCaida`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/estado_vacio.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/frescura/reloj_de_datos.dart';
import '../../../nucleo/plataforma.dart';
import '../../../nucleo/proveedores.dart';
import '../estado/estado_almacenes.dart';

/// El patrón va SIN locale y numérico (`d/M/y`) a propósito: da el mismo
/// resultado en `es` y en `en`, así que una prueba de widget no depende de que
/// alguien haya cargado los datos de localización antes. Es la misma decisión
/// que ya está escrita en `pantallas/pedidos/datos/formato.dart`.
final _fechaYHora = DateFormat('d/M/y, H:mm');

/// La franja que dice de cuándo son los almacenes que tiene este aparato.
///
/// Se pone donde se elige el punto de partida y en la pantalla de Almacenes: los
/// dos sitios donde alguien mira una lista de almacenes y decide con ella.
class AlmacenesDeLaUltimaBajada extends ConsumerWidget {
  const AlmacenesDeLaUltimaBajada({super.key});

  /// El literal, aparte del widget para poder comprobarlo sin pintar.
  ///
  /// Dice las tres cosas y en este orden: **de cuándo son**, **por qué no se
  /// refrescan solos** y **qué se rompe** si uno está de más. La tercera es la
  /// que decide si alguien conecta el aparato antes de salir o lo deja para
  /// mañana, y es la que faltaba.
  static String texto(DateTime bajadaAt) =>
      'Los almacenes son los de la última vez que hubo red: '
      '${_fechaYHora.format(bajadaAt)}. Accesos no avisa de los que se '
      'retiran, así que este aparato no puede enterarse hasta la próxima '
      'bajada. Desde el almacén se mide lo que se le cobra por el domicilio: '
      'si sobra uno, cada entrega del día se cobra mal y no se ve hasta '
      'cuadrar la caja.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // REGLA 1. En un navegador no hay copia de la que hablar.
    if (!ref.watch(trabajaSinConexionProvider)) return const SizedBox.shrink();

    // POR `Stream` Y NO POR `Future` (§3-ter). La marca de frescura cambia con
    // la pantalla delante —el ciclo corre por detrás— y una sola respuesta se
    // queda con la fecha del instante en que se pintó. En la web, además, nace
    // vacía y no llegaría nunca.
    final copia = ref.watch(almacenesEnElAparatoProvider).value;
    final bajadaAt = copia?.bajadaAt;
    // Sin copia no se habla de la copia: «este aparato no ha descargado los
    // almacenes» es otra cosa y la dicen los vacíos de cada pantalla, que además
    // saben qué se rompe sin ellos.
    if (copia == null || bajadaAt == null || !copia.hayCopia) {
      return const SizedBox.shrink();
    }

    // EL ÁMBAR SE GASTA. Se reserva para lo que de verdad puede engañar —más de
    // un día— y el resto va en gris. Pintarlo todo en ámbar es no pintar nada,
    // que es la regla que ya sigue `EstadoFrescura`.
    final viejo = EstadoFrescura.de(
      bajadaAt,
      ahora: ref.watch(relojProvider)(),
    ).enAmbar;
    final recado = texto(bajadaAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: Aire.md),
      child: viejo
          ? AvisoAmbar(recado, icono: Icons.warehouse_outlined)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warehouse_outlined,
                  size: 16,
                  color: Colores.tintaSuave,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    recado,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Colores.tintaSuave),
                  ),
                ),
              ],
            ),
    );
  }
}
