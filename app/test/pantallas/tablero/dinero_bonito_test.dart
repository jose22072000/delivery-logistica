import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/navegacion/estado_navegacion.dart';
import 'package:reparto/pantallas/tablero/vista/kit.dart';

/// `dineroBonito` CONVIERTE DE VERDAD, comprobado pintándolo.
///
/// La prueba hermana (`importes_en_la_moneda_test.dart`) lee el código y caza las dos
/// mutaciones obvias: volver al «$» escrito a mano, y quitarle el `ref`. Pero deja un
/// hueco en medio —dejar la firma y los comentarios intactos y poner el cuerpo en
/// `Numeros.importe(usd)` a secas— y con ese hueco el tablero pintaría «0,04» sin moneda
/// con CUP puesto en la barra, en verde.
///
/// Ésta cierra el hueco por el único sitio que no se puede falsear: montando el widget y
/// leyendo lo que sale. Es un `Consumer` pelado, sin base de datos ni streams detrás, así
/// que no tiene con qué colgarse.
void main() {
  /// Pinta el importe con la tasa y la moneda que se le digan.
  Future<String> pintar(
    WidgetTester tester, {
    required TasaDeLaMirada tasa,
    required String moneda,
    required double usd,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tasaDeLaMiradaProvider.overrideWithValue(tasa),
          monedaEfectivaProvider.overrideWithValue(moneda),
        ],
        child: MaterialApp(
          home: Consumer(builder: (_, ref, _) => Text(dineroBonito(ref, usd))),
        ),
      ),
    );
    return (tester.widget<Text>(find.byType(Text))).data!;
  }

  final conTasa = TasaDeLaMirada.hay(
    cupPorUsd: 715,
    traidoAt: DateTime(2026, 9, 16),
  );

  testWidgets('con CUP convierte con la tasa de ESA sucursal', (tester) async {
    // 0,04 × 715 = 28,6 → 29. Es el domicilio de TCP WALTER, el único con cobro de La
    // Habana, y el número que se comprobó en el teléfono y en la web el 16/09/2026.
    expect(
      await pintar(tester, tasa: conTasa, moneda: 'CUP', usd: 0.04),
      '29 CUP',
    );
  });

  testWidgets('con USD no convierte nada', (tester) async {
    expect(
      await pintar(tester, tasa: conTasa, moneda: 'USD', usd: 0.04),
      '0,04 USD',
    );
  });

  testWidgets('la moneda SIEMPRE se dice', (tester) async {
    // Un importe sin moneda al lado es el fallo que se coló por el hueco de la prueba de
    // código: «0,04» a secas se lee como pesos o como dólares según quien mire, y esto es
    // lo que alguien va a cobrar.
    for (final moneda in ['USD', 'CUP']) {
      final salida = await pintar(
        tester,
        tasa: conTasa,
        moneda: moneda,
        usd: 12.5,
      );
      expect(
        salida.endsWith(moneda),
        isTrue,
        reason: 'con $moneda salió «$salida», sin decir en qué moneda es',
      );
    }
  });

  testWidgets('sin tasa de esta sucursal NO se inventa una conversión', (
    tester,
  ) async {
    // La regla de la casa: «la tasa es POR SUCURSAL y sin la de esa sucursal no se
    // convierte nada: no se cae a la de otra ni a un número por defecto». En la práctica
    // `monedaEfectivaProvider` ya se cae a USD, pero si algún día llegara aquí un CUP sin
    // tasa, lo que NO puede salir es un número convertido.
    expect(
      await pintar(
        tester,
        tasa: const TasaDeLaMirada.no('esta sucursal no tiene tasa'),
        moneda: 'CUP',
        usd: 0.04,
      ),
      '0,04 USD',
      reason: 'sin tasa se enseña el dólar, nunca un CUP inventado',
    );
  });
}
