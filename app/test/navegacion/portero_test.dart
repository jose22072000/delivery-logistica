import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/portero.dart';
import 'package:reparto/navegacion/rutas.dart';

/// EL PORTERO, suelto. Es una funcion sin estado a proposito: la regla de quien
/// entra y quien no se puede probar entera sin montar la aplicacion.
void main() {
  String? donde(
    String ruta,
    EstadoDeAcceso estado, {
    String? uri,
    String? volverA,
  }) => redirigir(
    rutaActual: ruta,
    estado: estado,
    inicio: rutaDeInicio,
    uriEntera: uri ?? ruta,
    volverA: volverA,
  );

  group('mientras se comprueba lo guardado', () {
    test('todo el mundo espera, y quien ya espera no se mueve', () {
      expect(
        donde('/dashboard', EstadoDeAcceso.comprobando),
        '$rutaDeArranque?volverA=%2Fdashboard',
      );
      expect(donde(rutaDeArranque, EstadoDeAcceso.comprobando), isNull);
    });

    test('NO se ensena el formulario de contrasena mientras tanto', () {
      // El parpadeo del formulario antes de entrar ensena a escribir la
      // contrasena por reflejo.
      expect(
        donde(rutaDeAcceso, EstadoDeAcceso.comprobando),
        rutaDeArranque,
        reason: 'y sin arrastrar la propia puerta como destino',
      );
    });
  });

  group('sin sesion', () {
    test('cualquier pantalla lleva al acceso', () {
      for (final ruta in ['/dashboard', '/routes', '/tablero']) {
        expect(
          donde(ruta, EstadoDeAcceso.fuera),
          contains(rutaDeAcceso),
          reason: ruta,
        );
      }
    });

    test('el acceso se queda donde esta', () {
      expect(donde(rutaDeAcceso, EstadoDeAcceso.fuera), isNull);
    });
  });

  group('con sesion', () {
    test('el acceso y la espera llevan al Panel', () {
      expect(donde(rutaDeAcceso, EstadoDeAcceso.dentro), rutaDeInicio);
      expect(donde(rutaDeArranque, EstadoDeAcceso.dentro), rutaDeInicio);
    });

    test('las demas pantallas no se tocan', () {
      // Incluidas las que llevan filtros en la URL: un redirect aqui se comeria
      // el filtro y la lista saldria entera sin que nadie sepa por que.
      expect(
        donde(
          '/orders',
          EstadoDeAcceso.dentro,
          uri: '/orders?municipio=Centro',
        ),
        isNull,
      );
    });
  });

  group('se acuerda de a donde iba', () {
    test('recargar /orders con filtro acaba en /orders con filtro', () {
      // El caso de verdad: recargar la pagina en una lista filtrada. Sin esto se
      // aterriza siempre en el Panel y el enlace que alguien mando no sirve.
      const conFiltro = '/orders?municipio=Centro';
      final aEsperar = donde(
        '/orders',
        EstadoDeAcceso.comprobando,
        uri: conFiltro,
      );
      expect(aEsperar, startsWith(rutaDeArranque));

      final destino = Uri.parse(aEsperar!).queryParameters[claveDelDestino];
      expect(destino, conFiltro);
      expect(
        donde(rutaDeArranque, EstadoDeAcceso.dentro, volverA: destino),
        conFiltro,
      );
    });

    test('si la sesion no valia, el destino sobrevive al acceso', () {
      final alAcceso = donde(
        rutaDeArranque,
        EstadoDeAcceso.fuera,
        volverA: '/routes',
      );
      expect(alAcceso, '$rutaDeAcceso?volverA=%2Froutes');
      expect(
        donde(rutaDeAcceso, EstadoDeAcceso.dentro, volverA: '/routes'),
        '/routes',
      );
    });

    test('un destino que sea la propia puerta no hace bucle', () {
      expect(
        donde(rutaDeAcceso, EstadoDeAcceso.dentro, volverA: rutaDeAcceso),
        rutaDeInicio,
      );
      expect(
        donde(rutaDeArranque, EstadoDeAcceso.dentro, volverA: rutaDeArranque),
        rutaDeInicio,
      );
    });
  });
}
