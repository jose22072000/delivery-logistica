import 'package:web/web.dart' as web;

/// RECARGA LA PESTAÑA PIDIENDO EL HTML OTRA VEZ.
///
/// `location.replace` y no `location.reload()`, y con una marca de tiempo en la
/// direccion, por lo mismo que lo hace el patron (`delivery`,
/// `src/lib/version-nueva.ts`): entre el navegador y nginx puede haber un proxy
/// que se guarde una copia aunque la respuesta venga con `no-cache`. Una
/// direccion que nadie ha pedido nunca no se puede servir de una copia vieja —
/// que es exactamente el truco de la huella de `deploy/Dockerfile.app`, aplicado
/// aqui a la puerta.
///
/// `replace` y no `assign` para no dejar la pestaña con una entrada mas en el
/// historial: quien le da a «Recargar ahora» no espera que «atras» le devuelva a
/// la version vieja.
///
/// El `?v=` sobra para el enrutador —go_router ignora los parametros que no
/// conoce— y se queda en la barra de direcciones. Es el precio, y es barato.
Future<void> recargarLaPagina() async {
  final actual = Uri.parse(web.window.location.href);
  final destino = actual.replace(
    queryParameters: <String, String>{
      ...actual.queryParameters,
      'v': '${DateTime.now().millisecondsSinceEpoch}',
    },
  );
  web.window.location.replace(destino.toString());
}
