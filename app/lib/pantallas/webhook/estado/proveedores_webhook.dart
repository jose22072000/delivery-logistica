import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/proveedores.dart';
import '../datos/estado_del_webhook.dart';

/// EL ESTADO DEL CANAL, pedido al servidor.
///
/// `autoDispose` a propósito: esta pantalla se abre para mirar algo concreto y se cierra.
/// Dejar el provider vivo mantendría un dato viejo en memoria para la próxima vez, y en una
/// pantalla que existe justamente para saber «¿está pasando algo AHORA?» un dato viejo es
/// peor que no tener ninguno.
final estadoDelWebhookProvider = FutureProvider.autoDispose<EstadoDelWebhook>((
  ref,
) async {
  final api = ref.watch(clienteApiProvider);
  return RepositorioDelWebhook(api).mirar();
});
