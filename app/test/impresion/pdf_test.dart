/// Que las dos hojas salgan **sin red** y con los numeros que tienen que salir.
///
/// La prueba fuerte de este fichero es `sin red`: se tumba la pila de HTTP del
/// proceso entero y se genera el PDF igual. Si algun dia alguien cambia Roboto
/// por `PdfGoogleFonts`, esto revienta aqui y no en el patio de un almacen de
/// Camagüey con el camion cargado.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:reparto/impresion/armar_post_despacho.dart';
import 'package:reparto/impresion/estilo.dart';
import 'package:reparto/impresion/hoja.dart';
import 'package:reparto/impresion/post_despacho.dart';
import 'package:reparto/impresion/pre_despacho.dart';

/// Una pila de HTTP que no deja pasar nada. Cualquier intento de salir a la red
/// —bajar una fuente, pedir un icono— revienta con un mensaje que se entiende.
class _SinRed extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('la hoja intentó salir a la red');
}

final DateTime _impresoEn = DateTime(2026, 9, 14, 17, 20, 30);

HojaPreDespacho _pre({List<LineaPreDespacho>? lineas, String? dia}) =>
    HojaPreDespacho(
      sucursal: 'Camagüey',
      vehiculo: 'Camión #1',
      dia: dia,
      pedidos: 7,
      pesoKg: 412.5,
      lineas:
          lineas ??
          const <LineaPreDespacho>[
            LineaPreDespacho(
              producto: 'Arroz',
              formatos: 18,
              unidades: 360,
              pesoKg: 180,
            ),
            LineaPreDespacho(
              producto: 'Azúcar',
              formatos: 12,
              unidades: 240,
              pesoKg: 120,
            ),
            LineaPreDespacho(
              producto: 'Etiquetas',
              formatos: 2,
              unidades: 200,
              pesoKg: 0,
            ),
          ],
    );

HojaPostDespacho _post() => armarPostDespacho(
  const DatosDeRuta(
    ruta: 'R-014',
    sucursal: 'Camagüey',
    vehiculo: 'Camión #1',
    salida: '14/9/2026, 7:30:00',
    regreso: '14/9/2026, 15:05:00',
  ),
  const <PedidoDeRuta>[
    PedidoDeRuta(
      customerName: 'Bodega La Plaza',
      resultado: 'entregado',
      items: <ItemDePedido>[ItemDePedido(name: 'Arroz', packs: 10)],
    ),
    PedidoDeRuta(
      customerName: 'Cafetería El Puente',
      resultado: 'devuelto',
      resultadoNota: 'Cerrado, nadie recibió',
      items: <ItemDePedido>[ItemDePedido(name: 'Arroz', packs: 6)],
    ),
    PedidoDeRuta(
      customerName: 'Mercado Sur',
      items: <ItemDePedido>[ItemDePedido(name: 'Azúcar', packs: 9)],
    ),
  ],
);

/// El PDF comprime los flujos de dibujo, pero los diccionarios de objetos van en
/// claro: por ahi se puede comprobar el papel y la fuente sin rasterizar nada.
String _enClaro(List<int> bytes) => latin1.decode(bytes, allowInvalid: true);

int _paginas(String claro) =>
    RegExp(r'/Type\s*/Page[^s]').allMatches(claro).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('la hoja se arma SIN RED', () {
    test('el pre-despacho sale con la pila de HTTP tumbada', () async {
      final bytes = await HttpOverrides.runZoned(
        () => pdfPreDespacho(_pre(), impresoEn: _impresoEn),
        createHttpClient: (SecurityContext? c) =>
            throw StateError('la hoja intentó salir a la red'),
      );
      expect(bytes, isNotEmpty);
      expect(_enClaro(bytes.take(5).toList()), '%PDF-');
    });

    test('el post-despacho también', () async {
      final bytes = await HttpOverrides.runZoned(
        () => pdfPostDespacho(_post(), impresoEn: _impresoEn),
        createHttpClient: (SecurityContext? c) =>
            throw StateError('la hoja intentó salir a la red'),
      );
      expect(bytes, isNotEmpty);
      expect(_enClaro(bytes.take(5).toList()), '%PDF-');
    });

    test('y con la pila tumbada para TODO el proceso, no solo para la zona', () async {
      // `runZoned` solo tapa lo que ocurra dentro de la zona; esto tapa tambien
      // lo que se haya quedado colgando de otra.
      final antes = HttpOverrides.current;
      HttpOverrides.global = _SinRed();
      addTearDown(() => HttpOverrides.global = antes);

      // Y sin la cache de fuentes: la primera carga es la que bajaria la fuente.
      olvidarFuentes();

      final pre = await pdfPreDespacho(_pre(), impresoEn: _impresoEn);
      final post = await pdfPostDespacho(_post(), impresoEn: _impresoEn);
      expect(pre, isNotEmpty);
      expect(post, isNotEmpty);
    });
  });

  group('la fuente va EMBEBIDA en el fichero', () {
    late String claro;

    setUpAll(() async {
      claro = _enClaro(await pdfPreDespacho(_pre(), impresoEn: _impresoEn));
    });

    test('el PDF lleva dentro el fichero de la fuente', () {
      // `FontFile2` es como el PDF llama a un TrueType incrustado. Si la fuente
      // fuera de sistema o de red, aqui no habria ninguno.
      expect(claro, contains('/FontFile2'));
      expect(claro, contains('Roboto'));
    });

    test('las dos fuentes salen del propio paquete, no de la red', () async {
      // El origen es el `rootBundle`: ficheros que viajan dentro del APK.
      expect(
        (await rootBundle.load(rutaRegular)).lengthInBytes,
        greaterThan(1000),
      );
      expect(
        (await rootBundle.load(rutaNegrita)).lengthInBytes,
        greaterThan(1000),
      );
    });

    test('nadie dejó una URL de Google Fonts dentro del PDF', () {
      expect(claro, isNot(contains('fonts.gstatic')));
      expect(claro, isNot(contains('fonts.googleapis')));
    });
  });

  group('el papel es el que se imprime, no el de pantalla', () {
    test('A4 con 12 mm de margen', () async {
      // 12 mm en puntos: 12 * 72/25.4 = 34.0157…
      expect(hojaA4.marginLeft, closeTo(34.0157, 0.001));
      expect(hojaA4.marginTop, closeTo(34.0157, 0.001));
      expect(hojaA4.width, PdfPageFormat.a4.width);
      expect(hojaA4.height, PdfPageFormat.a4.height);

      final claro = _enClaro(
        await pdfPreDespacho(_pre(), impresoEn: _impresoEn),
      );
      expect(claro, contains('/MediaBox'));
    });

    test('la columna de marcar a mano tiene ancho de verdad', () {
      // 70 px y 78 px del HTML: 18.5 mm y 20.6 mm. Sin esto la columna se
      // cierra y no cabe el numero que hay que escribir dentro.
      expect(anchoSacado.width, closeTo(18.5 * PdfPageFormat.mm, 0.001));
      expect(anchoBajo.width, closeTo(20.6 * PdfPageFormat.mm, 0.001));
      expect(anchoSacado.width, greaterThan(50)); // > 17 mm, da para un numero
    });

    test('una hoja larga pasa de página sin romperse', () async {
      final muchas = <LineaPreDespacho>[
        for (var i = 0; i < 120; i++)
          LineaPreDespacho(
            producto: 'Producto número $i con nombre largo de almacén',
            formatos: i + 1,
            unidades: (i + 1) * 20,
            pesoKg: (i + 1) * 1.5,
          ),
      ];
      final claro = _enClaro(
        await pdfPreDespacho(_pre(lineas: muchas), impresoEn: _impresoEn),
      );
      expect(_paginas(claro), greaterThan(1));
    });
  });

  group('los totales que se imprimen son los que cuadran el camión', () {
    test('el pre-despacho suma empaques y unidades de todas las líneas', () {
      final t = TotalesPreDespacho.de(_pre());
      expect(t.formatos, 32); // 18 + 12 + 2
      expect(t.unidades, 800); // 360 + 240 + 200
    });

    test('el peso total es el de la hoja, NO la suma de las líneas', () {
      // La de Next imprime `d.pesoKg`, el del conjunto de pedidos. La suma por
      // producto da 300 y el del conjunto 412.5: se imprime el segundo, que es
      // el que cuadra con lo que pesa el camión.
      final h = _pre();
      final suma = h.lineas.fold<num>(0, (t, l) => t + l.pesoKg);
      expect(suma, 300);
      expect(TotalesPreDespacho.de(h).pesoKg, 412.5);
    });

    test('un producto sin peso imprime una raya, no un cero', () {
      expect(pesoDeFila(0), '—');
      expect(pesoDeFila(12), '12.0');
      // En el total el cero sí se escribe: es una cifra, no un hueco.
      expect(pesoTotal(0), '0.0');
      expect(pesoTotal(412.5), '412.5');
    });

    test('los números se escriben como en la de Next: 5, no 5.0', () {
      expect(numero(5), '5');
      expect(numero(5.0), '5');
      expect(numero(5.5), '5.5');
    });

    test('el post-despacho suma solo las filas que se imprimen', () {
      final h = _post();
      final t = TotalesPostDespacho.de(h);
      expect(h.lineasConResto.map((l) => l.producto), <String>[
        'Azúcar',
        'Arroz',
      ]);
      expect(t.salio, 25); // 16 de arroz + 9 de azúcar
      expect(t.entregado, 10);
      expect(t.queda, 15); // 6 devueltos + 9 sin marcar
      expect(t.salio, t.entregado + t.queda);
    });
  });

  group('la fecha de impresión es punto de paridad con la de Next', () {
    setUpAll(prepararFechas);

    test('sale como toLocaleString("es")', () {
      expect(
        fechaDeImpresion(DateTime(2026, 9, 14, 17, 20, 30)),
        '14/9/2026, 17:20:30',
      );
    });

    test('la hora no se rellena con cero y los minutos sí', () {
      // `toLocaleString('es')` da `14/9/2026, 9:05:03`.
      expect(
        fechaDeImpresion(DateTime(2026, 9, 14, 9, 5, 3)),
        '14/9/2026, 9:05:03',
      );
    });

    test('la medianoche es 0, no 24 ni 12', () {
      expect(
        fechaDeImpresion(DateTime(2026, 1, 2, 0, 0, 0)),
        '2/1/2026, 0:00:00',
      );
    });
  });

  group('los casos vacíos también salen en papel', () {
    test('una ruta entregada entera imprime «no queda nada»', () async {
      final h = armarPostDespacho(
        const DatosDeRuta(ruta: 'R-1', sucursal: 'Camagüey', vehiculo: ''),
        const <PedidoDeRuta>[
          PedidoDeRuta(
            customerName: 'Uno',
            resultado: 'entregado',
            items: <ItemDePedido>[ItemDePedido(name: 'Arroz', packs: 3)],
          ),
        ],
      );
      expect(h.lineasConResto, isEmpty);
      expect(h.pendientes, isEmpty);

      final bytes = await pdfPostDespacho(h, impresoEn: _impresoEn);
      expect(bytes, isNotEmpty);
    });

    test('un pre-despacho sin líneas no revienta', () async {
      final bytes = await pdfPreDespacho(
        _pre(lineas: const <LineaPreDespacho>[]),
        impresoEn: _impresoEn,
      );
      expect(bytes, isNotEmpty);
      expect(
        TotalesPreDespacho.de(_pre(lineas: const <LineaPreDespacho>[]))
            .formatos,
        0,
      );
    });

    test('con día filtrado y sin él, las dos salen', () async {
      final con = await pdfPreDespacho(
        _pre(dia: '2026-09-14'),
        impresoEn: _impresoEn,
      );
      final sin = await pdfPreDespacho(_pre(), impresoEn: _impresoEn);
      expect(con, isNotEmpty);
      expect(sin, isNotEmpty);
      // La línea del día ocupa: con día la hoja pesa más.
      expect(con.length, greaterThan(sin.length));
    });
  });

  group('lo que se escribe en el detalle de cada parada', () {
    test('productos separados por " · " y con su número', () {
      const p = ParadaPendiente(
        cliente: 'Cafetería El Puente',
        resultado: 'devuelto',
        nota: null,
        productos: <ProductoDeParada>[
          ProductoDeParada(producto: 'Arroz', formatos: 6),
          ProductoDeParada(producto: 'Azúcar', formatos: 2),
        ],
      );
      expect(productosDeParada(p), 'Arroz × 6 · Azúcar × 2');
    });

    test('una parada sin productos imprime una raya', () {
      const p = ParadaPendiente(
        cliente: 'Vacía',
        resultado: null,
        nota: null,
        productos: <ProductoDeParada>[],
      );
      expect(productosDeParada(p), '—');
    });
  });
}
