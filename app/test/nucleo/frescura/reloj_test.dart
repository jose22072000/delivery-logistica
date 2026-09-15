import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/frescura/reloj_de_datos.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  group('los tramos', () {
    final ahora = DateTime(2026, 9, 14, 12, 30);

    test('nunca descargado NO es lo mismo que viejo', () {
      final estado = EstadoFrescura.de(null, ahora: ahora);
      expect(estado, isA<SinDescargar>());
      expect(estado.texto, 'Sin descargar todavía');
      expect(estado.enAmbar, isTrue);
    });

    test('menos de una hora: la hora, en gris', () {
      final estado = EstadoFrescura.de(
        DateTime(2026, 9, 14, 7, 42),
        ahora: DateTime(2026, 9, 14, 8, 30),
      );
      expect(estado.texto, 'Datos de las 7:42');
      expect(estado.enAmbar, isFalse);
    });

    test('entre una hora y un dia: la distancia, en gris', () {
      final estado = EstadoFrescura.de(
        DateTime(2026, 9, 14, 7, 30),
        ahora: DateTime(2026, 9, 14, 12, 30),
      );
      expect(estado.texto, 'Datos de hace 5 h');
      expect(estado.enAmbar, isFalse);
    });

    test('justo en la hora ya cuenta como horas', () {
      final estado = EstadoFrescura.de(
        DateTime(2026, 9, 14, 11, 30),
        ahora: ahora,
      );
      expect(estado, isA<DatosDeHoras>());
      expect(estado.texto, 'Datos de hace 1 h');
    });

    test('mas de un dia: el dia de la semana, en AMBAR', () {
      // Aqui es donde se arma la ruta de anteayer creyendo que es la de hoy.
      final estado = EstadoFrescura.de(
        DateTime(2026, 9, 8, 9), // martes
        ahora: DateTime(2026, 9, 10, 12),
      );
      expect(estado.texto, 'Datos del martes — hace 2 días');
      expect(estado.enAmbar, isTrue);
    });

    test('un solo dia va en singular', () {
      final estado = EstadoFrescura.de(
        DateTime(2026, 9, 13, 9),
        ahora: DateTime(2026, 9, 14, 12),
      );
      expect(estado.texto, endsWith('hace 1 día'));
    });
  });

  group('el registro', () {
    late BaseLocal base;
    late RelojFalso reloj;
    late RegistroDeFrescura frescura;

    setUp(() {
      base = baseDePrueba();
      reloj = RelojFalso(DateTime(2026, 9, 14, 7, 42));
      frescura = RegistroDeFrescura(base, reloj: reloj.leer);
    });

    tearDown(() => base.close());

    test('`hasta` se guarda TAL CUAL, sin parsear', () async {
      const delServidor = '2026-09-14T11:02:31.481Z';
      await frescura.marcar(Colecciones.pedidos, hasta: delServidor);

      expect(await frescura.desde(Colecciones.pedidos), delServidor);
      final fila = await frescura.leer(Colecciones.pedidos);
      expect(fila!.hasta, delServidor);
      expect(fila.bajadaAt, DateTime(2026, 9, 14, 7, 42));
    });

    test('marcar dos veces actualiza, no duplica', () async {
      await frescura.marcar(Colecciones.pedidos, hasta: 'a', completa: true);
      reloj.ahora = DateTime(2026, 9, 14, 9);
      await frescura.marcar(Colecciones.pedidos, hasta: 'b');

      final filas = await base.select(base.frescura).get();
      expect(filas, hasLength(1));
      expect(filas.single.hasta, 'b');
      expect(filas.single.completa, isFalse);
    });

    test('sin fila no se descargo: eso NO es «no hay nada»', () async {
      // Una lista vacia sin esta respuesta es un fallo que se lee como un dato
      // (caso S7).
      expect(await frescura.seDescargo(Colecciones.rutas), isFalse);
      await frescura.marcar(Colecciones.rutas, hasta: 'x');
      expect(await frescura.seDescargo(Colecciones.rutas), isTrue);
    });

    test(
      'la mas vieja manda, y una que falte deja todo sin descargar',
      () async {
        const dos = [Colecciones.pedidos, Colecciones.rutas];

        await frescura.marcar(Colecciones.pedidos, hasta: 'a');
        expect(
          await frescura.laMasVieja(dos).first,
          isNull,
          reason: 'falta `routes`: la pantalla no esta al dia',
        );

        reloj.ahora = DateTime(2026, 9, 14, 11);
        await frescura.marcar(Colecciones.rutas, hasta: 'b');
        expect(
          await frescura.laMasVieja(dos).first,
          DateTime(2026, 9, 14, 7, 42),
          reason: 'manda la bajada mas vieja de las dos',
        );
      },
    );

    test('`laMasViejaAhora` contesta LO MISMO, sin dejar un stream abierto', () async {
      // La usa el vigia para decidir en seco si vale la pena un ciclo al volver
      // delante. Si contestara otra cosa que la version en vivo, la franja y el
      // vigia estarian mirando dos aparatos distintos.
      const dos = [Colecciones.pedidos, Colecciones.rutas];

      expect(await frescura.laMasViejaAhora(dos), isNull);

      await frescura.marcar(Colecciones.pedidos, hasta: 'a');
      expect(
        await frescura.laMasViejaAhora(dos),
        isNull,
        reason: 'falta `routes`: igual que la de siempre, sin descargar',
      );

      reloj.ahora = DateTime(2026, 9, 14, 11);
      await frescura.marcar(Colecciones.rutas, hasta: 'b');
      expect(
        await frescura.laMasViejaAhora(dos),
        await frescura.laMasVieja(dos).first,
      );
      expect(await frescura.laMasViejaAhora(dos), DateTime(2026, 9, 14, 7, 42));
    });
  });

  group('el widget', () {
    testWidgets('pinta el tramo y lo que queda sin subir', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RelojDeDatos(
              estado: EstadoFrescura.de(null, ahora: DateTime(2026, 9, 14, 12)),
              sinSubir: 3,
            ),
          ),
        ),
      );

      expect(find.text('Sin descargar todavía'), findsOneWidget);
      expect(find.text('3 sin subir'), findsOneWidget);
    });

    // El caso de «mientras actualiza, lo dice» NO se borro: se mudo a
    // `test/navegacion/armazon_test.dart`, que es donde ahora vive esa frase.
    // El reloj de datos ya no la dice —lo decia a la vez que la barra superior,
    // dos ruedas girando una encima de la otra— y alli se comprueba las dos
    // mitades: que la barra lo dice y que la franja NO.

    testWidgets('sin nada pendiente no hay boton', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RelojDeDatos(
              estado: DatosRecientes(DateTime(2026, 9, 14, 7, 42)),
            ),
          ),
        ),
      );

      expect(find.text('Datos de las 7:42'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
    });
  });
}
