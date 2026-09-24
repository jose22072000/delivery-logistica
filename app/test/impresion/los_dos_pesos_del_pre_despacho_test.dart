/// LOS DOS PESOS DEL PRE-DESPACHO, EN EL PAPEL — 23/09/2026.
///
/// La hoja tenía DOS cuentas distintas en la misma columna `kg`: cada línea
/// imprimía el peso **por producto** (el del catálogo) y el renglón `Total`
/// imprimía el peso **de los pedidos**. Misma columna, misma unidad, y nada que
/// lo dijera. Medido en estos mismos datos: las líneas suman **300** y el total
/// imprimía **412,5**. En producción se vieron diez guiones encima de un total
/// de **29.835,4**, y quien cuadra el camión resta esas dos cifras a ojo.
///
/// Por qué estas pruebas leen el PDF y no las funciones: las funciones ya
/// estaban bien cada una por su lado —el fallo era **qué se imprimía dónde**—,
/// así que una prueba que sólo las llame no ve el fallo. Aquí se descomprime el
/// flujo de dibujo, se decodifican los glifos con el `ToUnicode` de cada fuente
/// y se reconstruyen los RENGLONES con su posición: es lo único que comprueba
/// que los dos pesos no comparten renglón y que cada cifra está donde su rótulo.
///
/// Hermana de `nada_se_sale_de_la_pagina_test.dart`, que lee el mismo flujo
/// para otra cosa.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/impresion/estilo.dart';
import 'package:reparto/impresion/hoja.dart';
import 'package:reparto/impresion/pre_despacho.dart';
import 'package:reparto/pantallas/pedidos/vista/vista_pre_despacho.dart'
    as pantalla;
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart'
    as datos;

final DateTime _impresoEn = DateTime(2026, 9, 14, 17, 20, 30);

// ---------------------------------------------------------------------------
// Leer lo que de verdad dice el papel
// ---------------------------------------------------------------------------

/// Un trozo de texto del PDF, con dónde se dibujó.
class Trozo {
  const Trozo({required this.texto, required this.x, required this.y});

  final String texto;
  final double x;
  final double y;
}

/// Un renglón del papel: todo lo que se dibujó a la misma altura, de izquierda
/// a derecha. Es la unidad que importa aquí, porque el fallo era **dos cuentas
/// en el mismo renglón**.
class Renglon {
  const Renglon({required this.y, required this.texto});

  final double y;
  final String texto;

  @override
  String toString() => 'y=${y.toStringAsFixed(1)}: $texto';
}

/// Lo que se saca de leer una hoja entera.
class Papel {
  const Papel({required this.renglones, required this.trozos});

  final List<Renglon> renglones;
  final List<Trozo> trozos;

  /// El renglón que contiene [aguja]. Falla con la hoja entera delante si no
  /// hay ninguno o si hay más de uno: las dos cosas son un fallo de verdad.
  ///
  /// [debajoDe] acota la búsqueda a lo que hay por debajo de esa altura, que es
  /// lo que hace falta para el peso de los pedidos: sale DOS veces en la hoja
  /// —en la cabecera y en el bloque del pie— y las dos con el mismo rótulo.
  Renglon renglonCon(String aguja, {double? debajoDe}) {
    final hallados = renglones
        .where(
          (r) =>
              r.texto.contains(aguja) && (debajoDe == null || r.y < debajoDe),
        )
        .toList();
    expect(
      hallados,
      hasLength(1),
      reason:
          'Se buscaba UN renglón con «$aguja» y hay ${hallados.length}. '
          'La hoja entera:\n$this',
    );
    return hallados.single;
  }

  bool get vacio => trozos.isEmpty;

  @override
  String toString() => renglones.map((r) => '  $r').join('\n');
}

/// Descomprime un objeto `stream` del PDF que empiece en [desde].
List<int>? _inflar(List<int> bytes, String claro, int desde) {
  final s = claro.indexOf('stream', desde);
  if (s < 0) return null;
  var ini = s + 'stream'.length;
  if (ini < claro.length && claro.codeUnitAt(ini) == 13) ini++;
  if (ini < claro.length && claro.codeUnitAt(ini) == 10) ini++;
  final fin = claro.indexOf('endstream', ini);
  if (fin < 0) return null;
  try {
    return ZLibCodec().decode(bytes.sublist(ini, fin));
  } catch (_) {
    return null;
  }
}

int? _objeto(String claro, int numero) {
  final m = RegExp('(^|[^0-9])$numero 0 obj').firstMatch(claro);
  return m?.end;
}

/// El `ToUnicode` de una fuente: glifo -> carácter.
///
/// Cada fuente lleva su propio subconjunto, así que el glifo `0x0001` es una
/// letra distinta en la normal y en la negrita. Por eso se guardan por nombre
/// (`/F6`, `/F11`) y no en un solo mapa, que era la forma fácil de leer basura.
Map<int, String> _cmap(List<int> bytes, String claro, int obj) {
  final fin = _objeto(claro, obj);
  if (fin == null) return const <int, String>{};
  final inflado = _inflar(bytes, claro, fin);
  if (inflado == null) return const <int, String>{};
  final texto = latin1.decode(inflado, allowInvalid: true);
  final mapa = <int, String>{};
  for (final m in RegExp(
    r'<([0-9a-fA-F]{4})>\s*<([0-9a-fA-F]{4,})>',
  ).allMatches(texto)) {
    final glifo = int.parse(m.group(1)!, radix: 16);
    final destino = m.group(2)!;
    final unidades = <int>[
      for (var i = 0; i + 4 <= destino.length; i += 4)
        int.parse(destino.substring(i, i + 4), radix: 16),
    ];
    mapa[glifo] = String.fromCharCodes(unidades);
  }
  return mapa;
}

/// Las fuentes de la página: `/F6` -> su mapa de glifos.
Map<String, Map<int, String>> _fuentes(List<int> bytes, String claro) {
  final fuentes = <String, Map<int, String>>{};
  for (final rec in RegExp(r'/Font<<([^>]*)>>').allMatches(claro)) {
    for (final f in RegExp(
      r'/(F\d+) (\d+) 0 R',
    ).allMatches(rec.group(1)!)) {
      final nombre = f.group(1)!;
      final obj = int.parse(f.group(2)!);
      final fin = _objeto(claro, obj);
      if (fin == null) continue;
      final dic = claro.substring(fin, (fin + 2000).clamp(0, claro.length));
      final tu = RegExp(r'/ToUnicode (\d+) 0 R').firstMatch(dic);
      if (tu == null) continue;
      fuentes[nombre] = _cmap(bytes, claro, int.parse(tu.group(1)!));
    }
  }
  return fuentes;
}

/// Lee el PDF y devuelve lo que dice, renglón a renglón.
///
/// Lleva la matriz de transformación (`q`, `Q`, `cm`) igual que el revisor de
/// `nada_se_sale_de_la_pagina_test.dart`, porque la posición de cada texto está
/// en la celda y no en el `Td`.
Papel leerElPapel(List<int> bytes) {
  final claro = latin1.decode(bytes, allowInvalid: true);
  final fuentes = _fuentes(bytes, claro);
  final trozos = <Trozo>[];

  var i = 0;
  while (true) {
    final s = claro.indexOf('stream', i);
    if (s < 0) break;
    final inflado = _inflar(bytes, claro, s);
    i = claro.indexOf('endstream', s + 6);
    if (i < 0) break;
    if (inflado == null) continue;
    final flujo = latin1.decode(inflado, allowInvalid: true);
    if (!flujo.contains(' Tf ')) continue;

    var ctm = <double>[1, 0, 0, 1, 0, 0];
    final pila = <List<double>>[];
    final ops = <double>[];
    var fuente = '';
    var tx = 0.0;
    var ty = 0.0;

    for (final t in flujo.split(RegExp(r'\s+'))) {
      if (t.isEmpty) continue;
      final n = double.tryParse(t);
      if (n != null) {
        ops.add(n);
        continue;
      }
      if (t.startsWith('/F')) {
        fuente = t.substring(1);
        ops.clear();
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
        case 'Td' || 'TD':
          if (ops.length >= 2) {
            tx = ops[ops.length - 2];
            ty = ops[ops.length - 1];
          }
        case 'Tm':
          if (ops.length >= 6) {
            tx = ops[ops.length - 2];
            ty = ops[ops.length - 1];
          }
        default:
          if (!t.endsWith('TJ') && !t.endsWith('Tj')) break;
          final mapa = fuentes[fuente] ?? const <int, String>{};
          final buf = StringBuffer();
          for (final h in RegExp(r'<([0-9a-fA-F]+)>').allMatches(t)) {
            final hex = h.group(1)!;
            for (var k = 0; k + 4 <= hex.length; k += 4) {
              final glifo = int.parse(hex.substring(k, k + 4), radix: 16);
              buf.write(mapa[glifo] ?? '\u0000');
            }
          }
          final texto = buf.toString();
          if (texto.isNotEmpty) {
            trozos.add(
              Trozo(
                texto: texto,
                x: ctm[0] * tx + ctm[2] * ty + ctm[4],
                y: ctm[1] * tx + ctm[3] * ty + ctm[5],
              ),
            );
          }
      }
      ops.clear();
    }
  }

  // Los que se dibujaron a la misma altura son un renglón. Se redondea porque
  // dos celdas de la misma fila no siempre caen en el mismo decimal.
  final porAltura = <int, List<Trozo>>{};
  for (final t in trozos) {
    porAltura.putIfAbsent((t.y * 2).round(), () => <Trozo>[]).add(t);
  }
  final renglones = porAltura.entries.map((e) {
      final enOrden = e.value.toList()..sort((a, b) => a.x.compareTo(b.x));
      return Renglon(
        y: e.key / 2,
        texto: enOrden.map((t) => t.texto).join(' '),
      );
    }).toList()
    ..sort((a, b) => b.y.compareTo(a.y));

  return Papel(renglones: renglones, trozos: trozos);
}

// ---------------------------------------------------------------------------
// Las hojas de los casos
// ---------------------------------------------------------------------------

/// Las dos líneas con peso: suman **300**, y los pedidos pesan **412,5**.
HojaPreDespacho _todoSabido() => const HojaPreDespacho(
  sucursal: 'Camagüey',
  vehiculo: 'Camión #1',
  pedidos: 7,
  pesoKg: 412.5,
  lineas: <LineaPreDespacho>[
    LineaPreDespacho(producto: 'Arroz', formatos: 18, unidades: 360, pesoKg: 180),
    LineaPreDespacho(producto: 'Azúcar', formatos: 12, unidades: 240, pesoKg: 120),
  ],
);

/// La misma hoja con UNA línea sin peso: la del 22/09/2026, la paca.
HojaPreDespacho _faltaUna() => const HojaPreDespacho(
  sucursal: 'Camagüey',
  vehiculo: 'Camión #1',
  pedidos: 7,
  pesoKg: 412.5,
  lineas: <LineaPreDespacho>[
    LineaPreDespacho(producto: 'Arroz', formatos: 18, unidades: 360, pesoKg: 180),
    LineaPreDespacho(producto: 'Azúcar', formatos: 12, unidades: 240, pesoKg: 120),
    LineaPreDespacho(
      producto: 'Servilleta paca 24p',
      formatos: 7,
      unidades: null,
      pesoKg: null,
    ),
  ],
);

/// LA HOJA DE PRODUCCIÓN: diez guiones encima de un total de 29.835,4.
HojaPreDespacho _lasDiezRayas() => HojaPreDespacho(
  sucursal: 'La Habana',
  vehiculo: 'Camión #4',
  pedidos: 264,
  pesoKg: 29835.4,
  lineas: <LineaPreDespacho>[
    for (var i = 0; i < 10; i++)
      LineaPreDespacho(
        producto: 'Producto sin emparejar $i',
        formatos: 100 + i,
        unidades: null,
        pesoKg: null,
      ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('el lector del papel lee de verdad', () {
    // Sin esto, todo lo de abajo podría estar verde por no leer nada: un
    // `contains` sobre una hoja vacía no se cumple, pero un `isNot(contains)`
    // sí, y esas son la mitad de estas pruebas.
    test('saca los literales que se sabe que están en la hoja', () async {
      final papel = leerElPapel(
        await pdfPreDespacho(_faltaUna(), impresoEn: _impresoEn),
      );
      expect(papel.vacio, isFalse, reason: 'no se leyó NI UN texto del PDF');
      expect(papel.trozos.length, greaterThan(30));
      final todo = papel.renglones.map((r) => r.texto).join('\n');
      expect(todo, contains('Pre-despacho'));
      expect(todo, contains('EMPAQUES'));
      expect(todo, contains('Servilleta paca 24p'));
      expect(todo, contains('Sacó del almacén'));
      expect(todo, contains('14/9/2026, 17:20:30'));
    });

    test('y pone en el MISMO renglón lo que se dibuja a la misma altura', () async {
      final papel = leerElPapel(
        await pdfPreDespacho(_todoSabido(), impresoEn: _impresoEn),
      );
      // La fila de Arroz lleva sus cuatro cifras juntas.
      final arroz = papel.renglonCon('Arroz');
      expect(arroz.texto, contains('18'));
      expect(arroz.texto, contains('360'));
      expect(arroz.texto, contains('180.0'));
    });
  });

  group('los dos pesos van en renglones distintos y rotulados', () {
    test('con las cifras de verdad: 300 por producto y 412.5 de pedidos', () async {
      final h = _todoSabido();
      expect(
        h.lineas.fold<num>(0, (t, l) => t + (l.pesoKg ?? 0)),
        300,
        reason: 'el caso ya no es el que se midió',
      );
      expect(h.pesoKg, 412.5);

      final papel = leerElPapel(await pdfPreDespacho(h, impresoEn: _impresoEn));
      // Los dos, buscados en el bloque del pie: el de los pedidos sale también
      // en la cabecera y con el mismo rótulo.
      final pie = papel.renglonCon(TextoPreDespacho.total).y;
      final productos = papel.renglonCon(
        TextoPreDespacho.pesoDeLosProductos,
        debajoDe: pie,
      );
      final pedidos = papel.renglonCon(
        TextoPreDespacho.pesoDeLosPedidos,
        debajoDe: pie,
      );

      expect(
        productos.y,
        isNot(pedidos.y),
        reason:
            'Los dos pesos han vuelto al MISMO renglón:\n'
            '  ${productos.texto}\n'
            'Son dos cuentas distintas (300 del catálogo, 412.5 de los '
            'pedidos) y juntas se restan a ojo.',
      );

      expect(
        productos.texto,
        contains('300.0 kg'),
        reason:
            'El renglón de los productos dice «${productos.texto}» y tenía '
            'que llevar los 300.0 kg que suman sus líneas.',
      );
      expect(
        productos.texto,
        isNot(contains('412.5')),
        reason:
            'El renglón rotulado «peso de los PRODUCTOS» está imprimiendo el '
            'peso de los PEDIDOS: «${productos.texto}». Es el fallo entero, '
            'sólo que ahora con rótulo, que es peor.',
      );
      expect(
        pedidos.texto,
        contains('412.5 kg'),
        reason: 'el renglón de los pedidos dice «${pedidos.texto}»',
      );
      expect(pedidos.texto, isNot(contains('300.0')));
    });

    test('y el Total de la columna kg es el total de ESA columna', () async {
      final papel = leerElPapel(
        await pdfPreDespacho(_todoSabido(), impresoEn: _impresoEn),
      );
      final total = papel.renglonCon(TextoPreDespacho.total);
      expect(
        total.texto,
        contains('300.0'),
        reason:
            'El pie de la tabla dice «${total.texto}». Debajo de una columna '
            'de pesos por producto sólo puede ir la suma de esa columna.',
      );
      expect(
        total.texto,
        isNot(contains('412.5')),
        reason:
            'Ha vuelto el peso de los PEDIDOS al pie de la columna `kg`: '
            '«${total.texto}». Eso es lo que se restaba a ojo.',
      );
    });

    test('la hoja dice por qué no son el mismo número', () async {
      final papel = leerElPapel(
        await pdfPreDespacho(_todoSabido(), impresoEn: _impresoEn),
      );
      final todo = papel.renglones.map((r) => r.texto).join(' ');
      expect(
        todo,
        contains(TextoPreDespacho.noSonElMismoNumero),
        reason:
            'Sin la frase, dos cifras en kg una encima de otra se restan. '
            'La hoja:\n$papel',
      );
    });

    test('el de los productos vale «—» cuando sus líneas lo valen', () async {
      final papel = leerElPapel(
        await pdfPreDespacho(_faltaUna(), impresoEn: _impresoEn),
      );

      final total = papel.renglonCon(TextoPreDespacho.total);
      expect(
        total.texto,
        contains('—'),
        reason:
            'Con una línea sin peso, el total de la columna no se puede dar: '
            '«${total.texto}»',
      );
      expect(
        RegExp(r'\d+\.\d').hasMatch(total.texto.split('37').last),
        isFalse,
        reason:
            'El pie de la columna `kg` lleva una cifra con una línea sin '
            'peso: «${total.texto}». Un total a medias se lee como completo.',
      );

      final productos = papel.renglonCon(
        TextoPreDespacho.pesoDeLosProductos,
        debajoDe: total.y,
      );
      expect(
        productos.texto,
        contains('1 de 3 productos sin peso'),
        reason:
            'Se dice CUÁNTOS faltan, que es lo que alguien puede ir a '
            'arreglar. Salió: «${productos.texto}»',
      );
      expect(productos.texto, isNot(contains('412.5')));

      // Y su pareja: el de los pedidos sí se sabe, y sale entero.
      expect(
        papel
            .renglonCon(TextoPreDespacho.pesoDeLosPedidos, debajoDe: total.y)
            .texto,
        contains('412.5 kg'),
      );
    });

    test('las DIEZ RAYAS de producción encima de 29835.4', () async {
      final papel = leerElPapel(
        await pdfPreDespacho(_lasDiezRayas(), impresoEn: _impresoEn),
      );

      final total = papel.renglonCon(TextoPreDespacho.total);
      expect(
        total.texto,
        isNot(contains('29835.4')),
        reason:
            'Éste es el caso literal de producción: diez guiones en la '
            'columna `kg` y «${total.texto}» debajo. Ese número no es la suma '
            'de esos guiones y no puede ir ahí.',
      );

      final productos = papel.renglonCon(
        TextoPreDespacho.pesoDeLosProductos,
        debajoDe: total.y,
      );
      expect(
        productos.texto,
        contains(TextoPreDespacho.sinPesoEnElCatalogo),
        reason:
            'Con los diez productos sin peso se dice eso, no una raya muda: '
            '«${productos.texto}»',
      );
      expect(
        papel
            .renglonCon(TextoPreDespacho.pesoDeLosPedidos, debajoDe: total.y)
            .texto,
        contains('29835.4 kg'),
      );

      // Y el de la cabecera, que es el MISMO número, va rotulado también: una
      // cifra en kg sin rótulo en esta hoja es media resta hecha.
      final enLaCabecera = papel.renglones
          .where((r) => r.texto.contains('29835.4'))
          .toList();
      expect(enLaCabecera, hasLength(2));
      for (final r in enLaCabecera) {
        expect(
          r.texto,
          contains(TextoPreDespacho.pesoDeLosPedidos),
          reason: 'hay un 29835.4 sin rótulo en «${r.texto}»',
        );
      }
    });
  });

  group('el papel y la pantalla dicen LO MISMO', () {
    // §3-bis del CLAUDE.md: dos sitios que contestan lo mismo se atan con una
    // prueba, no con un comentario. La pantalla lo arregló el 22/09/2026 y el
    // papel se quedó atrás; que no vuelva a pasar al revés.
    test('los rótulos son los mismos, letra por letra', () {
      expect(
        TextoPreDespacho.pesoDeLosProductos,
        pantalla.TotalesDelPreDespacho.pesoDeLosProductos,
      );
      expect(
        TextoPreDespacho.pesoDeLosPedidos,
        pantalla.TotalesDelPreDespacho.pesoDeLosPedidos,
      );
      expect(
        TextoPreDespacho.noSonElMismoNumero,
        pantalla.TotalesDelPreDespacho.porQueNoSuman,
      );
    });

    test('y la cifra del peso de los productos se escribe igual en los dos', () {
      // Mismo caso en los dos tipos de totales, que son distintos a propósito
      // (el papel no depende de la capa de pantallas).
      final casos = <List<double?>>[
        <double?>[180, 120],
        <double?>[180, null],
        <double?>[null, null],
      ];
      for (final pesos in casos) {
        final enPapel = TotalesPreDespacho.de(
          HojaPreDespacho(
            sucursal: 'Camagüey',
            vehiculo: '',
            pedidos: 7,
            pesoKg: 412.5,
            lineas: <LineaPreDespacho>[
              for (final p in pesos)
                LineaPreDespacho(
                  producto: 'P$p',
                  formatos: 1,
                  unidades: 1,
                  pesoKg: p,
                ),
            ],
          ),
        );
        final enPantalla = datos.TotalesPreDespacho(
          <datos.LineaPreDespacho>[
            for (final p in pesos)
              datos.LineaPreDespacho(
                producto: 'P$p',
                empaques: 1,
                unidades: 1,
                pesoKg: p,
              ),
          ],
          pedidos: 7,
          pesoDeLosPedidos: 412.5,
        );
        expect(
          pesoDeLosProductosEnPapel(enPapel),
          pantalla.pesoDelPreDespacho(enPantalla),
          reason:
              'Con los pesos $pesos el papel y la pantalla escriben cosas '
              'distintas. Quien mira las dos tiene que ver lo mismo.',
        );
      }
    });
  });

  group('el total de la columna es el total de lo que la columna imprime', () {
    test('un peso que la columna pinta «—» no entra en la suma', () {
      for (final kg in <num?>[null, 0]) {
        expect(pesoDeFila(kg), '—');
        expect(
          sePuedeSumarElPeso(kg),
          isFalse,
          reason:
              'La celda imprime «—» para $kg pero el total lo suma: el pie '
              'sería la suma de celdas que no dicen ningún número.',
        );
      }
      for (final kg in <num>[0.1, 12, 180]) {
        expect(pesoDeFila(kg), isNot('—'));
        expect(sePuedeSumarElPeso(kg), isTrue);
      }
    });

    test('el `?? 0` del asistente de rutas no cuela un total corto', () {
      // `rutas/vista/asistente_nueva_ruta.dart` construye la hoja con
      // `pesoKg: linea.pesoKg ?? 0`: por ese camino un peso que no se sabe
      // llega como cero. Si el cero sumara, el total saldría corto y con
      // pinta de completo — el cero creíble de siempre.
      final t = TotalesPreDespacho.de(
        const HojaPreDespacho(
          sucursal: 'Camagüey',
          vehiculo: '',
          pedidos: 3,
          pesoKg: 412.5,
          lineas: <LineaPreDespacho>[
            LineaPreDespacho(producto: 'Arroz', formatos: 18, unidades: 360, pesoKg: 180),
            LineaPreDespacho(producto: 'Etiquetas', formatos: 2, unidades: 200, pesoKg: 0),
          ],
        ),
      );
      expect(
        t.pesoDeLosProductos,
        isNull,
        reason:
            'Con una línea a cero el total dio ${t.pesoDeLosProductos}: eso '
            'es la suma de una columna que imprime «—» en esa fila.',
      );
      expect(pesoDeFila(t.pesoDeLosProductos), '—');
      expect(t.sinPeso, 1);
    });

    test('los dos pesos son dos campos distintos, y no el mismo', () {
      final t = TotalesPreDespacho.de(_todoSabido());
      expect(t.pesoDeLosProductos, 300);
      expect(t.pesoDeLosPedidos, 412.5);
      expect(
        t.pesoDeLosProductos,
        isNot(t.pesoDeLosPedidos),
        reason: 'si un día coinciden, este caso dejó de probar lo que prueba',
      );
    });
  });
}
