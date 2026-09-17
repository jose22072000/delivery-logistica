import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/proveedores.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/estado/proveedores.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';
import 'apoyo.dart';

/// EN LA WEB, LO QUE EL SERVIDOR RECHAZA SE DICE. CON SU MOTIVO.
///
/// ## El agujero, y el falso positivo que casi lo tapa peor
///
/// La web tenía arriba un «N sin subir», y se quitó —con razón: hablarle de
/// trabajo sin conexión a quien está en un navegador es mentirle, y Jose lo ha
/// repetido cinco veces—. Pero quitarlo sin poner nada deja algo PEOR: la
/// tarjeta se mueve en la pantalla, el servidor dice que no, y no se entera
/// nadie. Al recargar vuelve a su sitio y quien la movió jura que la movió.
///
/// El primer intento fue esperar al ciclo después de cada gesto y mirar si la
/// cola quedaba vacía. **Estaba mal, y lo cazó un agente antes de salir**: un
/// apunte está legítimamente pendiente durante el instante que va del gesto a
/// la subida, así que eso saltaba en CADA movimiento. Un aviso que sale siempre
/// deja de leerse, y entonces tampoco se lee el día que importa.
///
/// Lo que sí es inequívoco es un apunte **rechazado**: ahí el servidor contestó
/// que no. No hay ventana ni carrera. Esta prueba fija las dos mitades: que el
/// rechazo se vea, y que lo normal **no** avise.
void main() {
  late BaseLocal base;
  late ServidorFalso servidor;

  ProviderContainer montar() {
    final dio = Dio(BaseOptions(baseUrl: 'https://reparto.prueba'))
      ..httpClientAdapter = servidor;
    return ProviderContainer.test(
      overrides: [
        baseProvider.overrideWith((ref) => base),
        clienteApiProvider.overrideWithValue(
          ClienteApi(dio: dio, esperas: const <Duration>[]),
        ),
        almacenSesionProvider.overrideWithValue(
          AlmacenEnMemoria(
            const Sesion(
              token: 't',
              refresh: 'r',
              sub: 'logistico',
              sucursalId: sucursalStg,
            ),
          ),
        ),
      ],
    );
  }

  setUp(() async {
    base = baseDePrueba();
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarPedido(base, id: 'p-cerca', aGrados: 0.01, peso: 120);
    servidor = ServidorFalso(
      (p) async => RespuestaFalsa(200, const {
        'columnas': <Object?>[],
        'colocados': <Object?>[],
      }),
    );
  });

  tearDown(() => base.close());

  /// Un apunte que el servidor rechazó, con su motivo, como lo deja la subida.
  Future<void> elServidorRechazo(String motivo) async {
    final cola = ColaDeSalida(base);
    final clave = await cola.encolar(
      metodo: 'PUT',
      ruta: '/board/placements/p-cerca',
      cuerpo: const {'columnaId': 'c1', 'posicion': 1},
    );
    await cola.resolver(
      clave,
      ResultadoApunte(estado: EstadoResultado.rechazado, motivo: motivo),
    );
  }

  test(
    'la web: el rechazo llega CON LA PANTALLA YA ABIERTA y se dice igual, '
    'con el motivo literal',
    () async {
    await Destino.comoSiFueraWeb(() async {
      // EL ORDEN DE LA VIDA REAL, y la primera versión de esta prueba lo tenía
      // al revés: sembraba el rechazo ANTES de montar, así que ya estaba en la
      // base cuando corría el `build`. Pasaba en verde sobre un aviso que en
      // producción no salía nunca — es la forma que el `CLAUDE.md` §3-ter
      // prohíbe, escrita por mí y rota por mí en el mismo día.
      final contenedor = montar();
      await contenedor.read(tableroProvider.future);

      // SUSCRITO ANTES de que pase nada, que es como está en un navegador con
      // la pantalla delante. `.future` no sirve aquí: devuelve el PRIMER valor,
      // que ya llegó y era nulo.
      final llego = Completer<String>();
      final quita = contenedor.listen(loQueElServidorRechazoProvider, (
        _,
        ahora,
      ) {
        final texto = ahora.value;
        if (texto != null && !llego.isCompleted) llego.complete(texto);
      });
      addTearDown(quita.close);

      expect(
        contenedor.read(loQueElServidorRechazoProvider).value,
        isNull,
        reason: 'todavía no ha pasado nada',
      );

      // Ahora se arrastra la tarjeta y el servidor dice que no.
      await elServidorRechazo('Ese pedido ya va en otra ruta');
      final aviso = await llego.future.timeout(const Duration(seconds: 5));

      expect(
        aviso,
        isNotNull,
        reason:
            'sin esto el cambio se ve hecho en pantalla, el servidor lo rechazó '
            'y nadie lo sabe hasta que alguien recarga',
      );
      expect(
        aviso,
        contains('Ese pedido ya va en otra ruta'),
        reason:
            'el motivo LITERAL del servidor, no uno nuestro: «ya va en otra '
            'ruta» le dice a alguien qué hacer, «no se pudo guardar» no',
      );

      contenedor.dispose();
    });
    },
  );

  test('la web: sin rechazos no se dice nada — lo normal no avisa', () async {
    await Destino.comoSiFueraWeb(() async {
      // Un apunte PENDIENTE, que es lo que hay durante el instante que va del
      // gesto a la subida. Esto NO puede avisar: si avisa, avisa siempre.
      await ColaDeSalida(base).encolar(
        metodo: 'PUT',
        ruta: '/board/placements/p-cerca',
        cuerpo: const {'columnaId': 'c1', 'posicion': 1},
      );

      final contenedor = montar();
      await contenedor.read(tableroProvider.future);

      expect(
        contenedor.read(loQueElServidorRechazoProvider).value,
        isNull,
        reason:
            'un apunte pendiente es lo normal un instante después de cada '
            'gesto; avisar aquí es avisar en cada movimiento',
      );

      contenedor.dispose();
    });
  });

  test('la APK: esto no sale. Allí lo rechazado vive en su bandeja', () async {
    // El otro mundo, intacto: en el aparato hay una bandeja de rechazos y un
    // reloj arriba que ya lo cuentan, y este aviso sería el tercero diciendo lo
    // mismo.
    await elServidorRechazo('Ese pedido ya va en otra ruta');

    final contenedor = montar();
    await contenedor.read(tableroProvider.future);

    expect(contenedor.read(loQueElServidorRechazoProvider).value, isNull);

    contenedor.dispose();
  });
}
