// UN 403 SALE A LA PRIMERA: NO SE REINTENTA.
//
// Riverpod 3 reintenta solo los providers que fallan, con espera creciente. Está bien para
// un fallo de red —la conexión de allá se cae y vuelve— y está MAL para una respuesta
// definitiva: el servidor ya dijo que no, y repetirlo da exactamente lo mismo.
//
// LO QUE SE VEÍA EN PRODUCCIÓN el 26/09/2026, entrando en `/admin/webhook` como SUPER
// ADMIN: **siete peticiones con un 403 cada una** —a los 5, 6, 7, 9, 12 y 19 segundos— y la
// rueda girando para siempre. El cerrojo funcionaba perfectamente; lo que no aparecía nunca
// era el mensaje que lo explica, así que desde la silla de quien mira, la pantalla está
// rota y no cerrada.
//
// Es la regla de la casa escrita en otro sitio: **un rechazo permanente contra un
// reintentador no es una defensa, es un bucle.**
//
// LA FORMA DE LA PRUEBA: se cuentan las llamadas. Comprobar sólo que «sale error» no valdría
// —también salía antes, al final de los siete intentos— y es justo lo que hacía que esto
// pasara desapercibido.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/pantallas/webhook/datos/estado_del_webhook.dart';
import 'package:reparto/pantallas/webhook/estado/proveedores_webhook.dart';

void main() {
  test('el rechazo del servidor se pide UNA vez', () async {
    var llamadas = 0;
    final c = ProviderContainer(
      overrides: [
        estadoDelWebhookProvider.overrideWith((ref) async {
          llamadas++;
          throw const Rechazo(
            403,
            'Esta pantalla es del desarrollador: mira cómo van las tuberías con '
            'PEDIDO y no es de administrar el reparto.',
          );
        }),
      ],
      // `retry` se hereda del provider real, no del override: lo que se prueba es la
      // decisión escrita en `proveedores_webhook.dart`.
      retry: estadoDelWebhookProvider.retry,
    );
    addTearDown(c.dispose);

    await expectLater(
      c.read(estadoDelWebhookProvider.future),
      throwsA(isA<Rechazo>()),
    );
    // Y se le da tiempo de sobra para reintentar si fuera a hacerlo: la primera
    // espera de Riverpod es de menos de un segundo.
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    expect(
      llamadas,
      1,
      reason:
          'se pidió $llamadas veces una respuesta que ya era definitiva: la '
          'rueda se queda girando y el mensaje que explica el 403 no aparece '
          'nunca, así que la pantalla parece rota en vez de cerrada',
    );
  });

  // LA OTRA MITAD, para que «no reintentar» no se cumpla no llamando nunca.
  test('cuando el servidor contesta bien, el dato llega', () async {
    final c = ProviderContainer(
      overrides: [
        estadoDelWebhookProvider.overrideWith(
          (ref) async => EstadoDelWebhook.deJson(const {
            'resumen': {'avisosPendientes': 3},
            'enviados': <Object?>[],
            'recibidos': <Object?>[],
            'sinMandar': <Object?>[],
          }),
        ),
      ],
    );
    addTearDown(c.dispose);

    final d = await c.read(estadoDelWebhookProvider.future);

    expect(d.resumen.esperando, 3);
  });
}
