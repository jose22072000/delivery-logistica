import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/proveedores.dart';
import '../../../nucleo/refresco_en_vivo.dart';
import '../datos/estado_del_webhook.dart';

/// EL ESTADO DEL CANAL, pedido al servidor.
///
/// `autoDispose` a propósito: esta pantalla se abre para mirar algo concreto y se cierra.
/// Dejar el provider vivo mantendría un dato viejo en memoria para la próxima vez, y en una
/// pantalla que existe justamente para saber «¿está pasando algo AHORA?» un dato viejo es
/// peor que no tener ninguno.
/// UN 403 NO SE REINTENTA, y por eso este provider lleva `retry` apagado.
///
/// Riverpod 3 reintenta solo los providers que fallan, con espera creciente. Está bien para
/// un fallo de red —la conexión de allá se cae y vuelve— y está MAL para una respuesta
/// definitiva: el servidor ya dijo que no, y repetirlo da lo mismo.
///
/// Lo que se veía en producción el 26/09/2026, entrando como SUPER ADMIN: siete peticiones
/// a `/admin/webhook` con un 403 cada una —a los 5, 6, 7, 9, 12 y 19 segundos— y **la rueda
/// girando para siempre**. El cerrojo funcionaba perfectamente; lo que no aparecía nunca
/// era el mensaje que lo explica.
///
/// Es la misma regla de la casa escrita en otro sitio: un rechazo permanente contra un
/// reintentador no es una defensa, es un bucle. Devolver `null` es «no lo vuelvas a
/// intentar»: el error sale a la primera y la pantalla dice de quién es.
///
/// ## Y SE REPINTA SOLA: NADA DE SONDEO
///
/// Jose, 26/09/2026: «SSE con todo esto igual, nada de polling». Esta pantalla nacio con una
/// sola peticion y un boton de «volver a mirar» al lado, y ese boton es medio sondeo con el
/// dedo de una persona haciendo de temporizador.
///
/// [refrescarConElAviso] la vuelve a pedir en cuanto el servidor dice que se movio algo en el
/// canal —entro un aviso, salio una tanda, o PEDIDO no contesto—. **Se mira el TIPO y no
/// «llego algo»**: un cambio de pedidos no puede costar una peticion de esta pantalla.
///
/// El boton se queda, y ya no es el unico camino: sirve para cuando el canal de eventos no
/// esta —ahi no se dispara nada— y para el 403, donde no va a llegar ningun aviso porque la
/// peticion ni se atiende.
final estadoDelWebhookProvider = FutureProvider.autoDispose<EstadoDelWebhook>((
  ref,
) async {
  refrescarConElAviso(ref, const [CambioEnVivo.canal]);
  final api = ref.watch(clienteApiProvider);
  return RepositorioDelWebhook(api).mirar();
}, retry: (_, _) => null);
