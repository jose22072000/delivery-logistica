/// NINGÚN TRAZADO SE SALE DE LA HOJA — 22/09/2026.
///
/// Esto no comprueba que un radio sea un número: comprueba lo que de verdad
/// pasó. `border-radius: 999px` en la web no dibuja un radio de 999 —CSS lo
/// recorta a la mitad de la caja— pero el paquete `pdf` no recorta nada y se
/// cree los 999: la etiqueta `SIN MARCAR`, de 57,6 x 11,8 pt, trazaba de -691 a
/// +749 pt, y ese único relleno crema `#FFF4D6` tapaba la A4 entera. Como se
/// pinta DESPUÉS de la cabecera, desaparecían el código de ruta, la sucursal y
/// el camión.
///
/// La forma de cazarlo es la misma con la que se diagnosticó: **descomprimir el
/// flujo de dibujo del PDF generado** y mirar que ningún punto de ningún trazado
/// se salga de la página. Así cae éste y cualquier hermano suyo —otro radio,
/// una sombra, un borde— que aparezca mañana, aunque nadie se acuerde de esta
/// historia.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:reparto/impresion/armar_post_despacho.dart';
import 'package:reparto/impresion/estilo.dart';
import 'package:reparto/impresion/hoja.dart';
import 'package:reparto/impresion/post_despacho.dart';
import 'package:reparto/impresion/pre_despacho.dart';

final DateTime _impresoEn = DateTime(2026, 9, 14, 17, 20, 30);

/// Un punto de un trazado que cae fuera del papel, con de dónde salió.
class PuntoFuera {
  const PuntoFuera({
    required this.operador,
    required this.x,
    required this.y,
    required this.motivo,
  });

  final String operador;
  final double x;
  final double y;
  final String motivo;

  @override
  String toString() =>
      '$motivo: el operador `$operador` traza en '
      '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}) pt';
}

/// Lo que se saca de mirar un flujo de dibujo entero.
class Revision {
  const Revision({required this.fuera, required this.puntos});

  /// Los puntos que se salen del papel.
  final List<PuntoFuera> fuera;

  /// Cuántos puntos de trazado se han mirado. Si esto es cero, la revisión no
  /// ha comprobado NADA: el flujo no se pudo leer y la prueba estaría verde sin
  /// serlo.
  final int puntos;
}

/// Descomprime los flujos de dibujo del PDF.
///
/// Se queda sólo con los que son texto de operadores: los `.ttf` embebidos
/// también van comprimidos y no son un dibujo.
List<String> flujosDeDibujo(List<int> bytes) {
  final claro = latin1.decode(bytes, allowInvalid: true);
  final out = <String>[];
  var i = 0;
  while (true) {
    final s = claro.indexOf('stream', i);
    if (s < 0) break;
    var ini = s + 'stream'.length;
    if (ini < claro.length && claro.codeUnitAt(ini) == 13) ini++;
    if (ini < claro.length && claro.codeUnitAt(ini) == 10) ini++;
    final fin = claro.indexOf('endstream', ini);
    if (fin < 0) break;
    i = fin + 1;

    List<int> inflado;
    try {
      inflado = ZLibCodec().decode(bytes.sublist(ini, fin));
    } catch (_) {
      continue;
    }
    final texto = latin1.decode(inflado, allowInvalid: true);
    final imprimibles = texto.codeUnits
        .where((c) => c == 10 || c == 13 || (c >= 32 && c < 127))
        .length;
    final esTexto = texto.isNotEmpty && imprimibles > texto.length * 0.98;
    if (esTexto && texto.contains(' cm ')) out.add(texto);
  }
  return out;
}

/// Recorre un flujo de dibujo llevando la matriz de transformación (`q`, `Q`,
/// `cm`) y comprueba cada punto de cada trazado contra el papel.
///
/// Se miran los puntos de control de las curvas igual que los de paso: el fallo
/// de la mancha crema estaba justo ahí, en los controles de la `c`.
Revision revisar(String flujo, PdfPageFormat papel, {double holgura = 0.5}) {
  var ctm = <double>[1, 0, 0, 1, 0, 0];
  final pila = <List<double>>[];
  final ops = <double>[];
  final fuera = <PuntoFuera>[];
  var puntos = 0;

  void mirar(String operador, double x, double y) {
    puntos++;
    final px = ctm[0] * x + ctm[2] * y + ctm[4];
    final py = ctm[1] * x + ctm[3] * y + ctm[5];
    String? motivo;
    if (px < -holgura) {
      motivo = 'se sale por la izquierda (x = ${px.toStringAsFixed(2)} < 0)';
    } else if (px > papel.width + holgura) {
      motivo =
          'se sale por la derecha (x = ${px.toStringAsFixed(2)} > '
          '${papel.width.toStringAsFixed(2)})';
    } else if (py < -holgura) {
      motivo = 'se sale por abajo (y = ${py.toStringAsFixed(2)} < 0)';
    } else if (py > papel.height + holgura) {
      motivo =
          'se sale por arriba (y = ${py.toStringAsFixed(2)} > '
          '${papel.height.toStringAsFixed(2)})';
    }
    if (motivo != null) {
      fuera.add(PuntoFuera(operador: operador, x: px, y: py, motivo: motivo));
    }
  }

  for (final t in flujo.split(RegExp(r'\s+'))) {
    if (t.isEmpty) continue;
    final n = double.tryParse(t);
    if (n != null) {
      ops.add(n);
      continue;
    }
    switch (t) {
      case 'q':
        pila.add(List<double>.from(ctm));
      case 'Q':
        if (pila.isNotEmpty) ctm = pila.removeLast();
      case 'cm':
        if (ops.length >= 6) {
          final m = ops.sublist(ops.length - 6);
          ctm = <double>[
            m[0] * ctm[0] + m[1] * ctm[2],
            m[0] * ctm[1] + m[1] * ctm[3],
            m[2] * ctm[0] + m[3] * ctm[2],
            m[2] * ctm[1] + m[3] * ctm[3],
            m[4] * ctm[0] + m[5] * ctm[2] + ctm[4],
            m[4] * ctm[1] + m[5] * ctm[3] + ctm[5],
          ];
        }
      case 'm' || 'l':
        if (ops.length >= 2) mirar(t, ops[ops.length - 2], ops[ops.length - 1]);
      case 'c':
        if (ops.length >= 6) {
          final o = ops.sublist(ops.length - 6);
          mirar(t, o[0], o[1]);
          mirar(t, o[2], o[3]);
          mirar(t, o[4], o[5]);
        }
      case 'v' || 'y':
        if (ops.length >= 4) {
          final o = ops.sublist(ops.length - 4);
          mirar(t, o[0], o[1]);
          mirar(t, o[2], o[3]);
        }
      case 're':
        if (ops.length >= 4) {
          final o = ops.sublist(ops.length - 4);
          mirar(t, o[0], o[1]);
          mirar(t, o[0] + o[2], o[1] + o[3]);
        }
    }
    ops.clear();
  }
  return Revision(fuera: fuera, puntos: puntos);
}

/// Mira el PDF entero y grita con las coordenadas de lo que se sale.
void nadaSeSaleDelPapel(List<int> bytes, {required String hoja}) {
  final flujos = flujosDeDibujo(bytes);
  expect(
    flujos,
    isNotEmpty,
    reason:
        'En «$hoja» no se pudo descomprimir NI UN flujo de dibujo: esta prueba '
        'no habría comprobado nada. Si el paquete `pdf` cambió cómo comprime, '
        'hay que arreglar el lector, no borrar la prueba.',
  );

  final fuera = <PuntoFuera>[];
  var puntos = 0;
  for (final flujo in flujos) {
    final r = revisar(flujo, hojaA4);
    fuera.addAll(r.fuera);
    puntos += r.puntos;
  }

  expect(
    puntos,
    greaterThan(50),
    reason:
        'En «$hoja» sólo se han mirado $puntos puntos de trazado: la hoja '
        'dibuja muchos más, así que el lector del flujo no está leyendo.',
  );

  expect(
    fuera,
    isEmpty,
    reason:
        'En «$hoja» hay ${fuera.length} punto(s) de trazado fuera de la A4 '
        '(${hojaA4.width.toStringAsFixed(2)} x '
        '${hojaA4.height.toStringAsFixed(2)} pt). Un relleno así tapa la hoja '
        'entera y se come la cabecera. Los peores:\n'
        '${fuera.take(6).map((p) => '  · $p').join('\n')}',
  );
}

HojaPostDespacho _rutaConParadasSinMarcar() => armarPostDespacho(
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
    // La que hacía la mancha: sin marcar, etiqueta ámbar con relleno.
    PedidoDeRuta(
      customerName: 'Mercado Sur',
      items: <ItemDePedido>[ItemDePedido(name: 'Azúcar', packs: 9)],
    ),
    PedidoDeRuta(
      customerName: 'Kiosco Malecón',
      resultado: 'cancelado',
      resultadoNota: 'El cliente canceló',
      items: <ItemDePedido>[ItemDePedido(name: 'Aceite', packs: 4)],
    ),
  ],
);

HojaPreDespacho _pre() => const HojaPreDespacho(
  sucursal: 'Camagüey',
  vehiculo: 'Camión #1',
  pedidos: 7,
  pesoKg: 412.5,
  lineas: <LineaPreDespacho>[
    LineaPreDespacho(producto: 'Arroz', formatos: 18, unidades: 360, pesoKg: 180),
    LineaPreDespacho(producto: 'Azúcar', formatos: 12, unidades: 240, pesoKg: 120),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ningún trazado del papel se sale de la página', () {
    test('el post-despacho de una ruta CON paradas sin marcar', () async {
      final h = _rutaConParadasSinMarcar();
      // Que el caso sea el que fallaba: si un día deja de haber etiqueta ámbar,
      // esta prueba dejaría de mirar lo que tiene que mirar.
      expect(h.sinMarcar, greaterThan(0));
      expect(h.pendientes.any((p) => p.resultado == null), isTrue);

      final bytes = await pdfPostDespacho(h, impresoEn: _impresoEn);
      nadaSeSaleDelPapel(bytes, hoja: 'post-despacho con paradas sin marcar');
    });

    test('y la cabecera sigue dibujándose ANTES que las etiquetas', () async {
      // El orden importa: el relleno de la etiqueta se pinta después, así que
      // si se desborda, tapa. Mientras la cabecera vaya primero en el flujo, un
      // relleno desbordado la borra — que es exactamente lo que se vio.
      final bytes = await pdfPostDespacho(
        _rutaConParadasSinMarcar(),
        impresoEn: _impresoEn,
      );
      final flujo = flujosDeDibujo(bytes).first;
      final cabecera = flujo.indexOf('cm'); // el primer bloque es la cabecera
      final crema = flujo.indexOf('1 0.95686 0.83922 rg'); // #FFF4D6
      expect(crema, greaterThan(0), reason: 'no se pintó el crema #FFF4D6');
      expect(cabecera, lessThan(crema));
    });

    test('el post-despacho de una ruta completada entera', () async {
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
      final bytes = await pdfPostDespacho(h, impresoEn: _impresoEn);
      nadaSeSaleDelPapel(bytes, hoja: 'post-despacho de una ruta completada');
    });

    test('el pre-despacho, que no lleva ni una píldora', () async {
      final bytes = await pdfPreDespacho(_pre(), impresoEn: _impresoEn);
      nadaSeSaleDelPapel(bytes, hoja: 'pre-despacho');
    });
  });

  group('el lector del flujo de dibujo caza de verdad lo que se sale', () {
    // Sin esto, la prueba de arriba podría estar verde por no leer nada.
    test('un radio de 999 en una caja de 11,8 pt sale señalado', () {
      // El trazado literal que salía con `borderRadius: 999 * px`: una caja
      // pequeña con curvas que se van a -691 y a +749.
      const flujo =
          'q 1 0 0 1 100 400 cm 0 749.25 m 0 -691.05 749.25 0 749.25 0 c '
          '57.64 0 l 0 -691.05 749.25 0 -691.05 749.25 c 0 749.25 l f Q';
      final r = revisar(flujo, hojaA4);
      expect(r.puntos, greaterThan(0));
      expect(r.fuera, isNotEmpty);
      expect(
        r.fuera.map((p) => p.motivo).join(' '),
        allOf(contains('se sale por abajo'), contains('-291.05')),
      );
    });

    test('y un trazado que cabe no se señala', () {
      const flujo = 'q 1 0 0 1 100 400 cm 0 0 m 50 0 l 50 12 l 0 12 l f Q';
      final r = revisar(flujo, hojaA4);
      expect(r.puntos, 4);
      expect(r.fuera, isEmpty);
    });

    test('la traslación de `cm` se aplica: lo de dentro puede salirse', () {
      // Mismo trazado, pero colocado al borde de la hoja: ahora sí se sale.
      const flujo = 'q 1 0 0 1 570 830 cm 0 0 m 50 0 l 50 12 l 0 12 l f Q';
      final r = revisar(flujo, hojaA4);
      expect(r.fuera, isNotEmpty);
      expect(r.fuera.first.motivo, contains('se sale por la derecha'));
    });
  });

  group('las curvas de la píldora miden lo que mide su caja', () {
    test('el radio no puede ser mayor que la mitad del alto de la caja', () async {
      // Leído del flujo de verdad, no del código: las curvas de las píldoras y
      // de las etiquetas empiezan en `0 <radio> m`. Con el fallo, ese número
      // era 749,25.
      final bytes = await pdfPostDespacho(
        _rutaConParadasSinMarcar(),
        impresoEn: _impresoEn,
      );
      final flujo = flujosDeDibujo(bytes).first;
      final radios = RegExp(r'(?:^| )0 (\d+(?:\.\d+)?) m 0 ')
          .allMatches(flujo)
          .map((m) => double.parse(m.group(1)!))
          .toList();
      expect(
        radios,
        isNotEmpty,
        reason: 'no se encontró ninguna curva de píldora en el flujo',
      );
      // La píldora más alta de esta hoja mide 15,05 pt; ninguna caja pasa de
      // 20 pt, así que ningún radio puede pasar de 10.
      for (final r in radios) {
        expect(
          r,
          lessThan(10),
          reason:
              'hay una curva con radio $r pt: eso no es la mitad de ninguna '
              'caja de esta hoja, es un `999` que nadie recortó',
        );
      }
    });
  });
}
