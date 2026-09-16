import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/diseno/colores.dart';

String _hex(Color c) =>
    '#${((c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void main() {
  // LO QUE COMPRUEBA ESTE FICHERO
  //
  // La paleta ya no son numeros escritos: se calcula del oro del logo cada vez
  // que arranca la aplicacion. Eso es una ventaja —cambiar el oro cambia todo—
  // y un riesgo: nadie mira un color que no esta escrito. Estas pruebas son el
  // que lo mira.
  //
  // Si manana alguien cambia `Paleta.oro` por un amarillo claro y los botones se
  // quedan con letras ilegibles, revienta aqui y no en el patio de un almacen.

  test('el logo tiene DOS colores y son los que manda la paleta', () {
    // El `#054C74` de PROCOVAR aparece en `icono.svg` en un COMENTARIO, no en un
    // trazo. Se conto como color del logo una vez y metio un azul inventado en
    // la aplicacion; esta prueba es para que no vuelva a pasar.
    final svg = File('marca/icono.svg').readAsStringSync();
    final sinComentarios = svg.replaceAll(
      RegExp(r'<!--.*?-->', dotAll: true),
      '',
    );
    final usados = RegExp(r'#[0-9A-Fa-f]{6}')
        .allMatches(sinComentarios)
        .map((m) => m.group(0)!.toUpperCase())
        .toSet();
    expect(usados, {'#E0A52A', '#17130E'});
    expect(_hex(Paleta.oro), '#E0A52A');
    expect(_hex(Paleta.tinta), '#17130E');
  });

  test('las letras de un boton se leen encima del boton', () {
    // Esta es la que habria cazado el «azul con letras blancas» del dia 16.
    expect(
      contrasteEntre(Colores.sobreMarca, Colores.marca),
      greaterThanOrEqualTo(4.5),
      reason: 'el texto del boton principal no se lee sobre su propio fondo',
    );
  });

  test('cada senal se lee sobre su propio tinte', () {
    final pares = {
      'aviso': (Colores.ambar, Colores.ambarFondo),
      'hecho': (Colores.verde, Colores.verdeFondo),
      'en curso': (Colores.enCurso, Colores.enCursoFondo),
      'impide': (Colores.rojo, Colores.rojoFondo),
      'normal': (Colores.gris, Colores.grisFondo),
    };
    for (final MapEntry(key: nombre, value: (tono, fondo)) in pares.entries) {
      expect(
        contrasteEntre(tono, fondo),
        greaterThanOrEqualTo(4.5),
        reason: 'la insignia de «$nombre» no se lee',
      );
    }
  });

  test('el texto se lee sobre el papel y sobre las tarjetas', () {
    for (final fondo in [Colores.papel, Colores.blanco]) {
      for (final tono in [
        Colores.tinta,
        Colores.tintaSuave,
        Colores.primario,
        Colores.ambar,
        Colores.verde,
        Colores.enCurso,
        Colores.rojo,
      ]) {
        expect(
          contrasteEntre(tono, fondo),
          greaterThanOrEqualTo(4.5),
          reason: '${_hex(tono)} no se lee sobre ${_hex(fondo)}',
        );
      }
    }
  });

  test('las cuatro senales se distinguen entre si', () {
    // Dos insignias pequenas se confunden de un vistazo si comparten tono Y
    // peso. Separarse es una de las dos cosas:
    //
    //   · tonos a mas de 60 grados, o
    //   · tonos a mas de 30 grados Y una diferencia de luz de mas de 0.08.
    //
    // La segunda es la que sostiene «impide» contra «aviso»: un rojo y un ambar
    // son vecinos de verdad en la rueda y no hay forma de alejarlos sin que uno
    // deje de ser rojo o el otro deje de ser ambar. Lo que los separa es que el
    // que impide es mas oscuro, que es como se lee «alto» en todas partes.
    //
    // La marca y el aviso NO entran aqui a proposito: los dos son calidos y lo
    // que los separa es la forma —el aviso siempre es un tinte con texto oscuro,
    // la marca siempre un relleno macizo—. Esta escrito en `Paleta.aviso`.
    final senales = {
      'aviso': HSLColor.fromColor(Paleta.aviso),
      'hecho': HSLColor.fromColor(Paleta.hecho),
      'en curso': HSLColor.fromColor(Paleta.enCurso),
      'impide': HSLColor.fromColor(Paleta.impide),
    };
    for (final a in senales.entries) {
      for (final b in senales.entries) {
        if (a.key.compareTo(b.key) >= 0) continue;
        final bruta = (a.value.hue - b.value.hue).abs();
        final tono = bruta > 180 ? 360 - bruta : bruta;
        final luz = (a.value.lightness - b.value.lightness).abs();
        expect(
          tono > 60 || (tono > 30 && luz > 0.08),
          isTrue,
          reason:
              '«${a.key}» y «${b.key}» se parecen demasiado: '
              '${tono.toStringAsFixed(0)} grados de tono y '
              '${luz.toStringAsFixed(2)} de luz',
        );
      }
    }
  });

  test('las senales son de la familia del oro: su misma saturacion', () {
    // Esto es lo que hace que sea UNA paleta y no cuatro colores sueltos: todas
    // tienen la saturacion del oro, o sea la misma fuerza de color.
    //
    // La luz la comparten las dos que informan —el aviso y el hecho—. Las dos
    // que tienen un vecino peligroso bajan de luz a proposito para separarse de
    // el: «impide» del aviso, «en curso» del hecho. Esta en la prueba de arriba.
    final oro = HSLColor.fromColor(Paleta.oro);
    for (final c in [
      Paleta.aviso,
      Paleta.hecho,
      Paleta.enCurso,
      Paleta.impide,
    ]) {
      expect(
        (HSLColor.fromColor(c).saturation - oro.saturation).abs(),
        lessThan(0.02),
        reason: 'un color con otra saturacion se ve prestado al lado del oro',
      );
    }
    expect(
      HSLColor.fromColor(Paleta.aviso).lightness,
      closeTo(oro.lightness, 0.02),
    );
    expect(
      HSLColor.fromColor(Paleta.hecho).lightness,
      closeTo(oro.lightness, 0.02),
    );
    expect(
      HSLColor.fromColor(Paleta.impide).lightness,
      lessThan(oro.lightness),
    );
    expect(
      HSLColor.fromColor(Paleta.enCurso).lightness,
      lessThan(oro.lightness),
    );
  });

  test('no queda un solo azul en toda la paleta', () {
    // ## Esta prueba ya fallo una vez por ser demasiado estrecha
    //
    // Nacio mirando solo de 210 a 250 grados, que es donde vive el `#1F4FE0` de
    // la de Next y el `#1F5BD6` del complementario exacto del oro. Con esa
    // ventana, el `#1983AA` de «en curso» —tono 195— pasaba tan campante, y el
    // 16/09/2026 Jose lo vio en el telefono en la tarjeta de «Trayendo
    // datos...»: «sigo con los azules». Tenia razon: 195 grados es azul para
    // quien lo mira, se llame petroleo en la rueda o se llame como sea.
    //
    // Asi que la ventana pasa a ser LA MITAD FRIA ENTERA, de 170 a 290. El logo
    // no tiene una gota de azul —ni verdoso, ni petroleo, ni cian, ni indigo— y
    // ninguna senal derivada puede tenerla. El verde de «hecho» queda a 155 y el
    // cobre de «en curso» a 22, los dos fuera por un margen amplio.
    //
    // Se miran TODAS las senales, no un puñado escogido a mano: la de la vez
    // pasada estaba en la lista y aun asi paso.
    for (final MapEntry(key: nombre, value: c) in <String, Color>{
      'Paleta.oro': Paleta.oro,
      'Paleta.tinta': Paleta.tinta,
      'Paleta.hecho': Paleta.hecho,
      'Paleta.aviso': Paleta.aviso,
      'Paleta.impide': Paleta.impide,
      'Paleta.enCurso': Paleta.enCurso,
      'Colores.marca': Colores.marca,
      'Colores.primario': Colores.primario,
      'Colores.secundario': Colores.secundario,
      'Colores.acento': Colores.acento,
      'Colores.verde': Colores.verde,
      'Colores.ambar': Colores.ambar,
      'Colores.rojo': Colores.rojo,
      'Colores.enCurso': Colores.enCurso,
      'Colores.gris': Colores.gris,
    }.entries) {
      final hsl = HSLColor.fromColor(c);
      // La saturacion baja se perdona: un gris con un matiz frio no se lee como
      // azul. Lo que no se perdona es un color con fuerza en esa mitad.
      if (hsl.saturation <= 0.15) continue;
      expect(
        hsl.hue > 170 && hsl.hue < 290,
        isFalse,
        reason:
            '$nombre es ${_hex(c)}, tono ${hsl.hue.round()}: cae en la mitad '
            'fria y se ve azul. El logo no tiene ninguno',
      );
    }
  });

  test('ninguna pantalla escribe un color a mano', () {
    // La paleta solo sirve de algo si es el UNICO sitio donde hay colores. Un
    // `Color(0xFF1F4FE0)` suelto en una pantalla sobrevive a cambiar la paleta,
    // que es justamente el problema que se vino a arreglar.
    final permitidos = {
      'lib/diseno/colores.dart', // es la paleta
    };
    final culpables = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (permitidos.contains(f.path)) continue;
      final codigo = f
          .readAsStringSync()
          .replaceAll(RegExp(r'//.*'), '')
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
      for (final m in RegExp(
        r'Color\(0x[0-9A-Fa-f]{8}\)|Colors\.(?!transparent|black\b|white\b)[a-z]\w*',
      ).allMatches(codigo)) {
        culpables.add('${f.path}: ${m.group(0)}');
      }
    }
    expect(culpables, isEmpty, reason: culpables.join('\n'));
  });

  test('imprime la paleta entera', () {
    String fila(String n, Color c, [Color? sobre]) {
      final contra = sobre == null
          ? ''
          : '  contraste ${contrasteEntre(c, sobre).toStringAsFixed(1)}';
      return '${n.padRight(16)}${_hex(c)}$contra';
    }

    debugPrint(
      [
        '',
        '── LA PALETA ──────────────────────────────',
        fila('oro (logo)', Paleta.oro),
        fila('tinta (logo)', Paleta.tinta),
        fila('papel', Paleta.papel),
        '',
        '── MARCA ──────────────────────────────────',
        fila('relleno', Colores.marca),
        fila('sus letras', Colores.sobreMarca, Colores.marca),
        fila('texto', Colores.primario, Colores.papel),
        fila('tenue', Colores.primarioTenue),
        '',
        '── SENALES ────────────────────────────────',
        fila('aviso', Colores.ambar, Colores.ambarFondo),
        fila('aviso fondo', Colores.ambarFondo),
        fila('hecho', Colores.verde, Colores.verdeFondo),
        fila('hecho fondo', Colores.verdeFondo),
        fila('en curso', Colores.enCurso, Colores.enCursoFondo),
        fila('en curso fondo', Colores.enCursoFondo),
        fila('impide', Colores.rojo, Colores.rojoFondo),
        fila('impide fondo', Colores.rojoFondo),
        fila('normal', Colores.gris, Colores.grisFondo),
        '',
        '── SOPORTE ────────────────────────────────',
        fila('tinta suave', Colores.tintaSuave, Colores.papel),
        fila('linea', Colores.linea),
        fila('linea fuerte', Colores.lineaFuerte),
        '',
      ].join('\n'),
    );
  });
}
