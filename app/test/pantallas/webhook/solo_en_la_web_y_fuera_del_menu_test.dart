// LA PANTALLA DEL CANAL: SÓLO EN LA WEB Y FUERA DEL MENÚ.
//
// Jose, 26/09/2026: «eso me lo dejas en la web solamente, no lo pongas en más ningún lado»
// y «que sólo lo pueda ver yo, eso no lo puede ver más nadie, sólo yo, el desarrollador».
//
// SON TRES CERROJOS Y NINGUNO SOBRA, pero **sólo uno cierra de verdad**:
//
//  1. No está en el menú — para que nadie tropiece.
//  2. No existe fuera de la web — el repartidor está en la calle y esto es una pantalla de
//     tuberías entre dos sistemas; además la APK trabaja sin señal, donde este dato no
//     significa nada.
//  3. **El servidor contesta 403 a cualquier rol que no sea DESARROLLADOR.** Ése es el
//     único que cierra, y vive en la api
//     (`el_webhook_es_solo_del_desarrollador_test.go`, los siete roles uno a uno).
//
// Los dos primeros son para que no estorbe, NO para proteger, y conviene que quede escrito:
// el rol que lleva el aparato no decide permisos. Lo dice la propia `Sesion`: «confiar en
// esto para decidir permisos sería darle a cualquiera con un editor de texto el rol que
// quiera». Una pantalla escondida sigue siendo alcanzable escribiendo la dirección.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/pantallas.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/pantallas/webhook/registro.dart';

void main() {
  test('en la web se registra, y fuera del menú', () async {
    await Destino.comoSiFueraWeb(() async {
      final p = registrarWebhook();

      expect(
        p,
        isNotNull,
        reason: 'en la web tiene que existir: es donde Jose la mira',
      );
      expect(
        p!.enElMenu,
        isFalse,
        reason:
            'en el menú la ve todo el que entra, y esto no es de armar rutas: '
            'son colas, reintentos y motivos de error de otro sistema',
      );
      expect(p.ruta, '/admin/webhook');
    });
  });

  test('en la APK y en el escritorio NO existe', () {
    // Sin el envoltorio de `comoSiFueraWeb`, las pruebas corren como aparato.
    expect(
      registrarWebhook(),
      isNull,
      reason:
          'el repartidor está en la calle: una pantalla de tuberías entre dos '
          'sistemas no pinta nada ahí, y encima la APK trabaja sin señal, '
          'donde este dato no significa nada',
    );
  });

  test('en la APK no entra en la lista de pantallas', () {
    final rutas = pantallasDeLaAplicacion().map((p) => p.ruta).toList();

    expect(
      rutas,
      isNot(contains('/admin/webhook')),
      reason: 'se coló en el aparato: ver el motivo arriba',
    );
    // Y LA OTRA MITAD: que la lista siga teniendo las de siempre. Sin esto, «no
    // está» se cumple con una lista vacía y la prueba pasaría con la aplicación
    // entera rota.
    expect(rutas, contains('/tablero'));
    expect(rutas, contains('/orders'));
  });

  test('en la web sí entra en la lista', () async {
    await Destino.comoSiFueraWeb(() async {
      final rutas = pantallasDeLaAplicacion().map((p) => p.ruta).toList();

      expect(rutas, contains('/admin/webhook'));
      expect(rutas, contains('/tablero'));
    });
  });
}
