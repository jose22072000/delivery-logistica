import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/pantallas.dart';

/// Lo que garantiza el contrato de registro. Si un agente de pantalla lo rompe,
/// falla aqui y no en la pantalla de alguien.
void main() {
  final pantallas = pantallasDeLaAplicacion();

  test('ninguna ruta repetida', () {
    final rutas = pantallas.map((p) => p.ruta).toList();
    expect(rutas.toSet().length, rutas.length, reason: 'hay una ruta repetida');
  });

  test('todas las rutas empiezan por barra', () {
    for (final p in pantallas) {
      expect(p.ruta.startsWith('/'), isTrue, reason: p.ruta);
    }
  });

  /// NINGUNA PANTALLA PUEDE LLAMARSE COMO UN CAMINO DEL PROXY — 17/09/2026.
  ///
  /// En el servidor, Traefik reparte por camino y **se queda con lo suyo antes
  /// de que la aplicacion vea nada**:
  ///
  /// ```
  /// Host(`reparto.procovar.cloud`) && PathPrefix(`/api`)   -> el reparto
  /// Host(`reparto.procovar.cloud`) && PathPrefix(`/sync`)  -> el sincronizador
  /// Host(`reparto.procovar.cloud`)                         -> esta aplicacion
  /// ```
  ///
  /// La pantalla de Sincronizacion vivia en `/sync`. Navegando por el menu
  /// funcionaba —eso lo resuelve el enrutador dentro del navegador— y por eso
  /// nadie lo vio: el unico camino que falla es **recargar ahi o abrir el
  /// enlace**, y entonces contesta el sincronizador con un `401` que no tiene
  /// nada que ver con la aplicacion.
  ///
  /// Es un fallo que no se ve leyendo el codigo de la aplicacion, porque la
  /// mitad que lo causa esta en el fichero de Traefik. Aqui queda escrito para
  /// que la proxima pantalla que se llame `/api-algo` o `/sync-algo` falle antes
  /// de salir de esta maquina.
  test('ninguna ruta invade un camino del proxy', () {
    // Los prefijos que el servidor NO entrega a la aplicacion.
    const delProxy = <String>['/api', '/sync'];
    for (final p in pantallas) {
      for (final suyo in delProxy) {
        // `startsWith(suyo)` a secas, y no `'$suyo/'`, que era lo que estaba y
        // no cubria nada. `PathPrefix` de Traefik es prefijo de CADENA, no de
        // segmento: con `PathPrefix(`/sync`)`, la direccion `/sync-estado` se la
        // queda el sincronizador igual que `/sync`. Se comprobo poniendo la
        // pantalla en `/sync-estado`: la guarda pasaba en verde y la aplicacion
        // habria vuelto a quedarse fuera.
        expect(
          p.ruta.startsWith(suyo),
          isFalse,
          reason:
              '«${p.ruta}» cae dentro de «$suyo», que en el servidor es del '
              'proxy: recargar ahi no llega a la aplicacion. Ponle otro nombre '
              'a la pantalla; el prefijo no se toca, que es la direccion que '
              'ya usan las APK instaladas.',
        );
      }
    }
  });

  test('las seis del pliego mas el tablero y reportes estan registradas', () {
    final rutas = pantallas.map((p) => p.ruta).toSet();
    expect(
      rutas,
      containsAll(<String>[
        '/dashboard',
        '/routes',
        '/orders',
        '/customers',
        '/vehicles',
        '/warehouses',
        '/reports',
        '/tablero',
        // Se podia borrar `registrarSincronizacion()` entera —sin ruta y sin
        // entrada de menu— y las 788 pruebas seguian verdes. Lo encontro el
        // auditor el 17/09/2026, justo en el cambio que movia esa pantalla de
        // sitio.
        '/sincronizacion',
      ]),
    );
  });

  test('Reportes SI esta en el menu, a proposito', () {
    // Iba en `false` copiando al Next, que no la tiene en su barra lateral y
    // solo se llega desde las acciones rapidas del Panel. Asi copiado, Jose no
    // la encontro: «esa vista de reportes no sale en los links para moverse».
    //
    // Una pantalla entera detras de un atajo del Panel es una pantalla que nadie
    // abre, y esta es la que se usa para cuadrar la caja. El patron se sigue
    // salvo donde se equivoca.
    final reportes = pantallas.firstWhere((p) => p.ruta == '/reports');
    expect(
      reportes.enElMenu,
      isTrue,
      reason: 'si vuelve a salir del menu que sea por una razon, no por copiar',
    );
    expect(reportes.titulo, 'Reportes');
  });

  test('las etiquetas del menu son las literales del pliego', () {
    final porRuta = {for (final p in pantallas) p.ruta: p.titulo};
    expect(porRuta['/dashboard'], 'Panel');
    expect(porRuta['/routes'], 'Rutas');
    expect(porRuta['/orders'], 'Pedidos');
    expect(porRuta['/customers'], 'Clientes');
    expect(porRuta['/vehicles'], 'Vehículos');
    expect(porRuta['/warehouses'], 'Almacenes');
  });

  test('todo lo que sale en el menu tiene icono', () {
    for (final p in pantallas.where((p) => p.enElMenu)) {
      expect(p.icono, isNotNull, reason: p.ruta);
    }
  });
}
