// LA LISTA DE CLIENTES EN UN TELÉFONO, y la fila que no abría nada.
//
// Dos quejas de Jose del 22/09/2026, medidas en su teléfono (390 px lógicos):
//
//  1. la dirección **se salía de la pantalla** y quedaba cortada a mitad de
//     palabra contra el borde derecho, sin elipsis: «calle 101 e», «Calzada
//     de». Sin elipsis no se sabe si falta una palabra o el barrio entero;
//  2. se tocaba el nombre y **no pasaba nada**. Ni abría, ni había chevrón, ni
//     ninguna pista de si aquello se podía pulsar. Una fila que no contesta no
//     se distingue de una aplicación colgada.
//
// Se miden coordenadas y no widgets: un texto cortado por el borde ESTÁ en el
// árbol con su literal entero, así que `findsOneWidget` lo da por bueno. Lo
// único que lo delata es `rect.right` por encima del ancho de la pantalla.
//
// En pareja, siempre: a 390 px tarjetas, a 1440 px la tabla de cuatro columnas.
// Y la fila abre en los dos sitios — cajón también en escritorio, que es la
// excepción aprobada de este proyecto (CLAUDE.md §4).
//
// Sin Drift: los `Cliente` se construyen a mano. Dentro de un `testWidgets` una
// consulta de Drift cuelga la prueba en vez de fallar (CLAUDE.md §5), y la ficha
// no consulta nada a propósito — pinta lo que la lista ya tiene en la mano.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/clientes/datos/repositorio_clientes.dart';
import 'package:reparto/pantallas/clientes/vista/tabla_clientes.dart';

void main() {
  const anchoDelTelefono = 390.0;
  const altoDelTelefono = 844.0;
  const anchoDeEscritorio = 1440.0;

  /// Las dos direcciones que Jose vio cortadas, enteras.
  const direccion =
      'calle 101 entre Calzada de Güines y Reparto Eléctrico, edificio 12 apto 3';
  const municipio = 'San Miguel del Padrón';
  const direccionEnLaLista = '$direccion · $municipio';

  ClienteConKm clienteDePrueba({
    String id = 'c1',
    String nombre = 'Ferretería La Esquina',
    String? telefono = '+53 5555 1234',
    double? km = 12.34,
  }) => ClienteConKm(
    Cliente(
      id: id,
      name: nombre,
      lat: 23.05,
      lng: -82.29,
      address: direccion,
      municipio: municipio,
      zona: 'Zona 3',
      codigo: 'CL-0042',
      vendedor: 'Marta Díaz',
      phone: telefono,
      source: 'pedido',
      sucursalCodigo: 'HAB',
    ),
    km,
  );

  Future<void> pintar(
    WidgetTester tester, {
    required double ancho,
    List<ClienteConKm>? clientes,
    bool conDistancia = false,
  }) async {
    tester.view.physicalSize = Size(ancho, altoDelTelefono);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TablaClientes(
              clientes: clientes ?? [clienteDePrueba()],
              conDistancia: conDistancia,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('a 390 px —el teléfono de Jose—', () {
    testWidgets('la dirección no se sale de la pantalla', (tester) async {
      await pintar(tester, ancho: anchoDelTelefono);

      final caja = tester.getRect(find.text(direccionEnLaLista));
      expect(
        caja.right,
        lessThanOrEqualTo(anchoDelTelefono),
        reason:
            'La dirección llega a x=${caja.right.toStringAsFixed(1)} en una '
            'pantalla de $anchoDelTelefono px: eso es lo que se veía cortado '
            'contra el borde.',
      );
      expect(caja.left, greaterThanOrEqualTo(0));
      // Y no se parte letra a letra: una línea de texto es ancha y baja.
      expect(caja.width, greaterThan(caja.height));
    });

    testWidgets('sin tabla de escritorio metida en 390 px', (tester) async {
      await pintar(tester, ancho: anchoDelTelefono);

      expect(find.byType(DataTable), findsNothing);
      // Y tampoco quedan los rótulos de columna sueltos.
      expect(find.text('Vendedor'), findsNothing);
      expect(find.text('Origen'), findsNothing);
    });

    testWidgets('el nombre y el teléfono tampoco se salen', (tester) async {
      await pintar(tester, ancho: anchoDelTelefono);

      for (final texto in ['Ferretería La Esquina', '+53 5555 1234']) {
        final caja = tester.getRect(find.text(texto));
        expect(
          caja.right,
          lessThanOrEqualTo(anchoDelTelefono),
          reason: '«$texto» llega a x=${caja.right.toStringAsFixed(1)}',
        );
        expect(caja.width, greaterThan(caja.height), reason: texto);
      }
    });

    testWidgets('la fila DICE que se puede pulsar: chevrón', (tester) async {
      await pintar(tester, ancho: anchoDelTelefono);

      expect(
        find.byIcon(Icons.chevron_right),
        findsOneWidget,
        reason:
            'Sin chevrón, tocar y que abra y tocar y que no pase nada se '
            'parecen demasiado.',
      );
    });

    testWidgets('y al tocarla ABRE el cajón con su ficha', (tester) async {
      await pintar(tester, ancho: anchoDelTelefono);

      await tester.tap(find.text('Ferretería La Esquina'));
      await tester.pumpAndSettle();

      // La ✕ de la cabecera, que es la salida garantizada y no desaparece.
      expect(find.byTooltip('Cerrar'), findsOneWidget);
      // Y dentro, lo que la lista no cabía: zona, sucursal y coordenadas.
      expect(find.text('Zona de reparto'), findsOneWidget);
      expect(find.text('Zona 3'), findsOneWidget);
      expect(find.text('Sucursal'), findsOneWidget);
      expect(find.text('HAB'), findsOneWidget);
      expect(find.text('23.05, -82.29'), findsOneWidget);

      // La dirección, ahí sí, entera y dentro de la pantalla.
      final caja = tester.getRect(find.text(direccion));
      expect(caja.right, lessThanOrEqualTo(anchoDelTelefono));

      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.text('Zona de reparto'), findsNothing);
    });

    testWidgets('un cliente sin teléfono lo dice, y en la ficha también', (
      tester,
    ) async {
      await pintar(
        tester,
        ancho: anchoDelTelefono,
        clientes: [clienteDePrueba(telefono: null)],
      );

      expect(find.text('sin teléfono'), findsOneWidget);

      await tester.tap(find.text('Ferretería La Esquina'));
      await tester.pumpAndSettle();
      // Dos: el de la tarjeta, que sigue detrás del cajón, y el de la ficha.
      expect(find.text('sin teléfono'), findsNWidgets(2));
    });

    testWidgets('sin almacén con coordenadas la ficha no inventa una cifra', (
      tester,
    ) async {
      await pintar(
        tester,
        ancho: anchoDelTelefono,
        clientes: [clienteDePrueba(km: null)],
      );

      await tester.tap(find.text('Ferretería La Esquina'));
      await tester.pumpAndSettle();

      // Un hueco, nunca un cero: un `0.00 km` se lee como «está al lado».
      expect(find.text('0.0 km'), findsNothing);
      expect(
        find.text('Esta sucursal no tiene ningún almacén con coordenadas.'),
        findsOneWidget,
      );
    });
  });

  group('a 1440 px —el escritorio—', () {
    testWidgets('sigue siendo la tabla de cuatro columnas', (tester) async {
      await pintar(tester, ancho: anchoDeEscritorio);

      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Cliente'), findsOneWidget);
      expect(find.text('Dirección'), findsOneWidget);
      expect(find.text('Vendedor'), findsOneWidget);
      expect(find.text('Origen'), findsOneWidget);
    });

    testWidgets('la dirección larga no estira la tabla sin fin', (
      tester,
    ) async {
      await pintar(tester, ancho: anchoDeEscritorio);

      final caja = tester.getRect(find.text(direccionEnLaLista));
      expect(
        caja.width,
        lessThanOrEqualTo(TablaClientes.anchoDeLaDireccion + 1),
        reason:
            'La celda de la dirección mide ${caja.width.toStringAsFixed(1)} px: '
            'sin tope, la dirección más larga decide cuánto hay que arrastrar '
            'de lado para ver las otras tres columnas.',
      );
      expect(caja.right, lessThanOrEqualTo(anchoDeEscritorio));
    });

    testWidgets('la fila también abre, y sin columna de casillas', (
      tester,
    ) async {
      await pintar(tester, ancho: anchoDeEscritorio);

      // `DataTable` añade casillas por su cuenta en cuanto una fila es
      // pulsable, y aquí no hay nada que hacer con una selección de clientes.
      expect(find.byType(Checkbox), findsNothing);

      await tester.tap(find.text('Ferretería La Esquina'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Cerrar'), findsOneWidget);
      expect(find.text('Zona de reparto'), findsOneWidget);
    });
  });
}
