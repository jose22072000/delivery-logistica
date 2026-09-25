// UN TOQUE, UNA DESCARGA. NO DOS.
//
// Jose, 25/09/2026, actualizando desde su teléfono:
//
//     «cuando le doy a descargar me dispara dos descargas en ves de una»
//
// El botón no tenía nada que impidiera dispararse dos veces. En Flutter un
// doble toque —o un toque con rebote, que en una pantalla usada con prisa pasa—
// llama `onPressed` dos veces, y cada llamada era un `launchUrl` que Android
// atiende arrancando una bajada.
//
// Y no es un detalle: el APK son **78 MB**. Dos bajadas en la conexión de allá
// son media tarde, y encima dejan un fichero a medias que no sirve de nada,
// porque el servidor no acepta continuar una descarga cortada —comprobado el
// mismo día: contesta 200 donde debería contestar 206—.
//
// Esta prueba recorre el camino DE VERDAD —la franja del aviso, el cajón, su
// pie— y no una copia del botón: una prueba que se escribe a sí misma el widget
// que prueba no prueba lo que se despliega.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reparto/navegacion/aviso_de_version_nueva.dart';
import 'package:reparto/nucleo/actualizacion/comprobador.dart';
import 'package:reparto/nucleo/actualizacion/version_publicada.dart';
import 'package:reparto/nucleo/proveedores.dart';

void main() {
  const publicada = VersionPublicada(version: '1.0.6', compilacion: 7);
  const enlace = 'https://archivos.procovar.cloud/reparto/apk/x.apk';

  /// Monta la franja del aviso con una versión nueva ya detectada, que es el
  /// estado en el que se encuentra el repartidor al abrir la aplicación.
  Future<int Function()> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var veces = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          actualizacionProvider.overrideWith(
            (ref) async =>
                const SePuedeActualizar(publicada: publicada, enlace: enlace),
          ),
          abridorDeLaDescargaProvider.overrideWithValue((_) async {
            veces++;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AvisoDeVersionNueva()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return () => veces;
  }

  /// Abre el cajón desde la franja: «Cómo instalarla».
  Future<void> abrirElCajon(WidgetTester tester) async {
    expect(
      find.text('Cómo instalarla'),
      findsOneWidget,
      reason: 'la franja de «hay una versión nueva» no salió',
    );
    await tester.tap(find.text('Cómo instalarla'));
    await tester.pumpAndSettle();
    expect(
      find.text('Descargar'),
      findsOneWidget,
      reason: 'el cajón de la versión nueva no se abrió',
    );
  }

  testWidgets('un toque pide la descarga UNA vez', (tester) async {
    final veces = await montar(tester);
    await abrirElCajon(tester);

    await tester.tap(find.text('Descargar'));
    await tester.pumpAndSettle();

    expect(
      veces(),
      1,
      reason: 'un toque tiene que pedir la descarga exactamente una vez',
    );
  });

  testWidgets('el SEGUNDO toque ya no dispara nada', (tester) async {
    final veces = await montar(tester);
    await abrirElCajon(tester);

    // SE LLAMA DOS VECES A LA MISMA FUNCIÓN YA CONSTRUIDA, que es literalmente
    // lo que hace un doble toque: los dos toques caen en el mismo fotograma, el
    // widget no ha tenido tiempo de reconstruirse, y el botón que reciben los
    // dos es el MISMO objeto con el MISMO `onPressed`.
    //
    // No vale hacerlo con dos `tester.tap`: el banco de pruebas procesa el
    // primero y el cajón ya se ha cerrado cuando llega el segundo, así que la
    // prueba sale verde aunque la guarda no exista. Comprobado escribiéndola —
    // las dos primeras versiones daban verde con el código roto—.
    final boton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Descargar'),
    );
    boton.onPressed!();
    boton.onPressed!();
    await tester.pumpAndSettle();

    expect(
      veces(),
      1,
      reason:
          'se pidieron ${veces()} descargas con dos toques. Son 78 MB cada '
          'una: es el fallo del 25/09/2026. El botón tiene que apagarse en '
          'cuanto se pulsa.',
    );
  });
}
