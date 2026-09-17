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

    // Lo que hay en la web tiene que ser un subconjunto de lo del aparato: la
    // web nunca puede tener una entrada de menú que el aparato no tenga, y las
    // que dependen de `trabajaSinConexion` tienen que haberse caído.
    expect(
      enLaWeb.difference(deSinConexion),
      isEmpty,
      reason: 'la web tiene entradas de menú que el aparato no tiene',
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
  });
}
