import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/paginacion.dart';

void main() {
  group('el rango que se ensena', () {
    test('la primera pagina empieza en 1', () {
      final r = Rango.de(pagina: 1, porPagina: 50, total: 123);
      expect(r.desde, 1);
      expect(r.hasta, 50);
    });

    test('la ultima pagina no pasa del total', () {
      final r = Rango.de(pagina: 3, porPagina: 50, total: 123);
      expect(r.desde, 101);
      expect(r.hasta, 123);
    });

    test('sin nada, 0–0: nunca «1–50 de 0»', () {
      final r = Rango.de(pagina: 1, porPagina: 50, total: 0);
      expect(r.desde, 0);
      expect(r.hasta, 0);
    });

    test('una pagina mas alla del total no da un rango al reves', () {
      // Pasa de verdad: se esta en la pagina 5 y llega una bajada que quita
      // pedidos. Sin esto se lee «Mostrando 201–123 de 123».
      final r = Rango.de(pagina: 5, porPagina: 50, total: 123);
      expect(r.desde, lessThanOrEqualTo(r.hasta));
    });
  });

  group('cuantas paginas', () {
    test('123 de 50 en 50 son 3', () {
      expect(totalDePaginas(total: 123, porPagina: 50), 3);
    });

    test('100 de 50 en 50 son 2, no 3', () {
      expect(totalDePaginas(total: 100, porPagina: 50), 2);
    });

    test('sin nada hay 1 pagina, no 0', () {
      expect(totalDePaginas(total: 0, porPagina: 50), 1);
    });
  });

  group('los numeros visibles: hasta 5', () {
    test('con menos de 5 salen todas', () {
      expect(paginasVisibles(actual: 1, totalPaginas: 3), [1, 2, 3]);
    });

    test('en el medio, la actual va centrada', () {
      expect(paginasVisibles(actual: 7, totalPaginas: 20), [5, 6, 7, 8, 9]);
    });

    test('al principio se pega al 1, sin huecos a la izquierda', () {
      expect(paginasVisibles(actual: 1, totalPaginas: 20), [1, 2, 3, 4, 5]);
    });

    test('al final se pega a la ultima', () {
      expect(paginasVisibles(actual: 20, totalPaginas: 20), [
        16,
        17,
        18,
        19,
        20,
      ]);
    });
  });

  testWidgets('con el total a 0 no se pinta nada', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Paginacion(pagina: 1, porPagina: 50, total: 0, alIrA: (_) {}),
        ),
      ),
    );
    expect(find.textContaining('Mostrando'), findsNothing);
  });

  testWidgets('con datos ensena el texto del pliego', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Paginacion(pagina: 2, porPagina: 50, total: 123, alIrA: (_) {}),
        ),
      ),
    );
    expect(find.text('Mostrando 51–100 de 123'), findsOneWidget);
  });
}
