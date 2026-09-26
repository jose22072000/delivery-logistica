// EN EL MENÚ DE LA WEB NO SALE NADA DE SIN CONEXIÓN.
//
// La regla 1 de la casa, que Jose ha tenido que repetir cuatro veces: «la web siempre está
// en línea, nunca se desconecta; quita todo lo que tenga que ver con eso».
//
// El predicado central —`Destino.trabajaSinConexion`— sí está vigilado. El agujero estaba
// en el **registro de cada pantalla**: el 17/09/2026, al añadir el mapa descargable, se
// puso `enElMenu: Destino.trabajaSinConexion` en `pantallas/mapa/registro.dart` y cambiarlo
// a `true` dejaba «Mapa sin conexión» en el menú de la web **con las 1105 pruebas en
// verde**. A un descuido de distancia de lo que ya ha costado cuatro conversaciones.
//
// Esta prueba mira el registro entero y no una pantalla concreta, para que la siguiente que
// alguien añada entre por aquí sola.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/pantallas.dart';
import 'package:reparto/nucleo/plataforma.dart';

void main() {
  test('ninguna pantalla de sin-conexión entra en el menú de la web', () async {
    // El registro se arma con el destino de verdad. En una prueba de Flutter
    // `kIsWeb` es falso, así que esto es el registro del APARATO: aquí SÍ puede
    // haber pantallas de sin conexión.
    expect(
      Destino.trabajaSinConexion,
      isTrue,
      reason:
          'esta prueba da por hecho que corre como aparato; si eso cambia, lo '
          'de abajo deja de comprobar lo que dice',
    );

    // Las que entran en el menú SÓLO porque el aparato trabaja sin conexión.
    // Son las que no pueden salir en la web.
    final deSinConexion = pantallasDeLaAplicacion()
        .where((p) => p.enElMenu)
        .map((p) => p.ruta)
        .toSet();

    // Y ahora el mismo registro, pero **como si fuera la web**. El interruptor
    // restaura siempre, también si lo de dentro lanza.
    final enLaWeb = await Destino.comoSiFueraWeb(
      () async => pantallasDeLaAplicacion()
          .where((p) => p.enElMenu)
          .map((p) => p.ruta)
          .toSet(),
    );

    // LO QUE LA WEB TIENE DE MÁS SÓLO PUEDE SER ALGO QUE EL APARATO NO REGISTRE.
    //
    // La versión anterior exigía que el menú de la web fuera un SUBCONJUNTO del
    // del aparato, y eso se rompió el 26/09/2026 al poner «Canal con PEDIDO» en
    // el menú: es una pantalla que **sólo existe en la web** —en el aparato
    // `registrarWebhook()` devuelve `null`— y por tanto no puede estar en un
    // subconjunto de nada.
    //
    // La regla precisa, y es la que se quería desde el principio: una pantalla de
    // SIN CONEXIÓN existe en el aparato y lo que no puede es asomar en la web. Si
    // una ruta **no está registrada en el aparato**, no es de sin-conexión: es
    // web-only a propósito, y el sitio donde eso se decide es su `registro.dart`.
    //
    // Se compara contra TODAS las rutas del aparato, no sólo las de su menú: una
    // pantalla de sin-conexión que alguien saque del menú del aparato y meta en
    // el de la web seguiría existiendo allí, así que seguiría cazándose.
    final todasLasDelAparato = pantallasDeLaAplicacion()
        .map((p) => p.ruta)
        .toSet();
    final soloDeLaWeb = await Destino.comoSiFueraWeb(
      () async => pantallasDeLaAplicacion().map((p) => p.ruta).toSet(),
    );

    expect(
      enLaWeb.difference(deSinConexion).difference(
        soloDeLaWeb.difference(todasLasDelAparato),
      ),
      isEmpty,
      reason:
          'la web tiene en el menú una pantalla que el aparato TAMBIÉN registra '
          'pero no le pone en el menú. Eso es el fallo de siempre: una pantalla '
          'de sin-conexión asomando en la web',
    );

    // Y LA OTRA MITAD: que la web-only siga estando donde tiene que estar. Sin
    // esto, el hueco que acabo de abrir en la comprobación de arriba se podría
    // llenar con cualquier cosa y nadie se enteraría.
    expect(
      enLaWeb.contains('/admin/webhook'),
      isTrue,
      reason:
          'EL CANAL CON PEDIDO NO SALE EN EL MENÚ DE LA WEB, y es el único sitio '
          'donde se mira: Jose entró por la dirección y dijo «no lo veo». Va con '
          '`enElMenu: true` y `soloParaRoles`, y quién lo ve de verdad lo decide '
          'el 403 de la api',
    );
    expect(
      todasLasDelAparato.contains('/admin/webhook'),
      isFalse,
      reason:
          'EL CANAL CON PEDIDO SE COLÓ EN EL APARATO. El repartidor está en la '
          'calle y esto son colas y códigos HTTP de otro sistema; y la APK '
          'trabaja sin señal, donde este dato no significa nada',
    );
    expect(
      enLaWeb.contains('/mapa-sin-conexion'),
      isFalse,
      reason:
          'EL MAPA SIN CONEXIÓN SALE EN EL MENÚ DE LA WEB. La regla 1: en un '
          'navegador siempre hay servidor detrás, así que un mapa guardado en '
          'el aparato no le sirve a nadie y sólo explica algo que en su caso '
          'no pasa. Va con `enElMenu: Destino.trabajaSinConexion`.',
    );

    // SINCRONIZACIÓN, por lo mismo y con una factura medida — 22/09/2026.
    //
    // Estuvo en `enElMenu: true` fijo, y en la web la entrada no llegaba ni a
    // abrirse: `GET /sync/estado` contestaba `401` —el sincronizador habla con
    // aparatos dados de alta y un navegador no lo es—, el cliente daba la
    // sesión por muerta y el portero rebotaba a `/acceso?volverA=…`, que
    // volvía a entrar y volvía a pedir. Treinta peticiones en poco más de un
    // minuto.
    //
    // El subconjunto de arriba NO cazaba esto: una entrada que existe en los
    // dos sitios no aparece en la diferencia. Por eso cada pantalla de
    // sin-conexión se nombra aquí una a una.
    expect(
      enLaWeb.contains('/sincronizacion'),
      isFalse,
      reason:
          'SINCRONIZACIÓN SALE EN EL MENÚ DE LA WEB. Lo que enseña son '
          'aparatos y su cola —quién lleva sin subir, qué le queda pendiente y '
          'qué se le rechazó—, o sea el aparato de prepararse para quedarse '
          'sin señal: es de la APK y del escritorio. Va con '
          '`enElMenu: Destino.trabajaSinConexion`.',
    );
  });
}
