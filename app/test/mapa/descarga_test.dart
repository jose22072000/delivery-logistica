// LA DESCARGA: entera, comprobada y reanudable.
//
// **Aquí no sale ni una petición de red.** El servidor es un doble que vive en
// este fichero y sirve bytes de una lista: es lo que permite ejercitar el
// reanudado, el `sha256` que no cuadra y el corte a mitad sin depender de
// ninguna conexión — ni de la de Cuba, ni de la de nadie.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/mapa/anuncio_de_mapa.dart';
import 'package:reparto/mapa/carpeta_del_mapa.dart';
import 'package:reparto/mapa/descarga_de_mapa.dart';

/// El paquete de mentira: 30.000 bytes con un patrón, para que un trozo puesto
/// en el sitio equivocado se note en el `sha256`.
final elFichero = Uint8List.fromList(
  List.generate(30000, (i) => (i * 31 + 7) % 251),
);
final laHuella = sha256.convert(elFichero).toString();

NivelDeMapa elNivel({int? bytes, String? huella}) => NivelDeMapa(
  nivel: 'completo',
  version: '260916',
  bytes: bytes ?? elFichero.length,
  sha256: huella ?? laHuella,
  url: 'https://reparto.procovar.cloud/mapa/cuba-completo.pmtiles',
);

/// UN SERVIDOR DE MENTIRA, con las tres formas de portarse que importan.
class ServidorDeMentira implements HttpClientAdapter {
  ServidorDeMentira({
    this.entiendeRange = true,
    this.cortaEn,
    this.codigo = 200,
    this.contentRangeMentiroso = false,
  });

  /// `false` imita a un servidor que ignora `Range` y manda el fichero entero
  /// con un `200`. Es lo que hace que un reanudado ingenuo deje un fichero del
  /// doble de tamaño.
  final bool entiendeRange;

  /// Cuántos bytes sirve antes de cortar, contados desde el principio del
  /// fichero. `null` los sirve todos.
  final int? cortaEn;

  final int codigo;

  /// `true` contesta `206` pero con un `Content-Range` que empieza en otro
  /// sitio. Es el caso que deja un agujero en medio del fichero.
  final bool contentRangeMentiroso;

  /// Cuántas veces se pidió. Sirve para comprobar que reanudar no vuelve a
  /// bajarlo todo.
  final peticiones = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions opciones,
    Stream<Uint8List>? cuerpo,
    Future<void>? cancelar,
  ) async {
    final rango = opciones.headers['Range'] as String?;
    peticiones.add(rango);

    if (codigo != 200) {
      return ResponseBody.fromString('no', codigo);
    }

    var desde = 0;
    if (rango != null && entiendeRange) {
      desde = int.parse(rango.replaceAll(RegExp(r'[^0-9]'), ''));
    }
    final hasta = cortaEn ?? elFichero.length;
    final trozo = Uint8List.sublistView(
      elFichero,
      desde,
      hasta > desde ? hasta : desde,
    );

    final cabeceras = <String, List<String>>{};
    if (rango != null && entiendeRange) {
      final empiezaEn = contentRangeMentiroso ? desde + 100 : desde;
      cabeceras['content-range'] = [
        'bytes $empiezaEn-${elFichero.length - 1}/${elFichero.length}',
      ];
    }
    return ResponseBody(
      Stream<Uint8List>.fromIterable([
        // En trozos, como llega de verdad.
        for (var i = 0; i < trozo.length; i += 4096)
          Uint8List.sublistView(
            trozo,
            i,
            i + 4096 > trozo.length ? trozo.length : i + 4096,
          ),
      ]),
      rango != null && entiendeRange ? 206 : 200,
      headers: cabeceras,
    );
  }

  @override
  void close({bool force = false}) {}
}

({Dio dio, CarpetaEnMemoria carpeta, DescargaDeMapa descarga}) montar(
  ServidorDeMentira servidor,
) {
  final dio = Dio()..httpClientAdapter = servidor;
  final carpeta = CarpetaEnMemoria();
  return (
    dio: dio,
    carpeta: carpeta,
    descarga: DescargaDeMapa(dio, carpeta, reloj: () => DateTime(2026, 9, 17)),
  );
}

void main() {
  test('una descarga entera deja el paquete y su apunte', () async {
    final m = montar(ServidorDeMentira());
    final avisos = <int>[];

    final r = await m.descarga.bajar(
      elNivel(),
      comoVa: ({required bajados, required total}) => avisos.add(bajados),
    );

    expect(r, isA<DescargaLista>());
    expect(await m.carpeta.bytes('cuba-completo.pmtiles'), elFichero.length);
    // El `.parcial` desaparece: si se quedara, la próxima vez se reanudaría
    // sobre un fichero ya completo.
    expect(m.carpeta.tiene('cuba-completo.pmtiles.parcial'), isFalse);

    final apunte = PaqueteGuardado.deJson(
      await m.carpeta.leerTexto('cuba-completo.json'),
    );
    expect(apunte, isNotNull);
    expect(apunte!.version, '260916');
    expect(apunte.sha256, laHuella);
    expect(apunte.bytes, elFichero.length);

    // Y se fue diciendo cómo iba: sin esto la pantalla sólo puede pintar una
    // rueda, que no distingue «va lenta» de «está parada».
    expect(avisos, isNotEmpty);
    expect(avisos.last, elFichero.length);
  });

  test('una descarga cortada se dice, y se conserva lo bajado', () async {
    final m = montar(ServidorDeMentira(cortaEn: 12000));

    final r = await m.descarga.bajar(elNivel());

    expect(r, isA<DescargaFallida>());
    final fallo = r as DescargaFallida;
    expect(fallo.sePuedeReanudar, isTrue);
    expect(fallo.bajados, 12000);
    // EL MOTIVO DICE EL NÚMERO. «No se pudo descargar» no le dice a nadie qué
    // hacer; «llegaron 12,0 MB de 30,0» sí.
    expect(fallo.motivo, contains('12 kB'));
    expect(fallo.motivo, contains('30 kB'));
    // Y el bueno NO se ha tocado: nunca se pisa hasta que la huella cuadra.
    expect(m.carpeta.tiene('cuba-completo.pmtiles'), isFalse);
    expect(await m.carpeta.bytes('cuba-completo.pmtiles.parcial'), 12000);
  });

  test('reanudar continúa donde se quedó y NO vuelve a bajarlo todo', () async {
    final primero = ServidorDeMentira(cortaEn: 12000);
    final m = montar(primero);
    await m.descarga.bajar(elNivel());
    expect(await m.carpeta.bytes('cuba-completo.pmtiles.parcial'), 12000);

    // Segunda vuelta con el mismo estado en la carpeta.
    final segundo = ServidorDeMentira();
    m.dio.httpClientAdapter = segundo;
    final r = await m.descarga.bajar(elNivel());

    expect(r, isA<DescargaLista>());
    expect(
      segundo.peticiones.single,
      'bytes=12000-',
      reason:
          'en la conexión de allá, volver a bajar los 12 kB que ya estaban es '
          'la diferencia entre terminar y no terminar',
    );
    expect(await m.carpeta.bytes('cuba-completo.pmtiles'), elFichero.length);
  });

  test(
    'un servidor que ignora Range NO deja un fichero del doble',
    () async {
      final m = montar(ServidorDeMentira(cortaEn: 12000));
      await m.descarga.bajar(elNivel());

      // El segundo servidor contesta 200 con el fichero entero aunque se le pida
      // un rango. Pegarlo detrás de lo que había dejaría 42.000 bytes.
      m.dio.httpClientAdapter = ServidorDeMentira(entiendeRange: false);
      final r = await m.descarga.bajar(elNivel());

      expect(r, isA<DescargaLista>());
      expect(await m.carpeta.bytes('cuba-completo.pmtiles'), elFichero.length);
    },
  );

  test('un Content-Range que empieza en otro sitio se caza', () async {
    final m = montar(ServidorDeMentira(cortaEn: 12000));
    await m.descarga.bajar(elNivel());

    // Contesta 206 pero desde otro sitio: pegarlo detrás deja un agujero de 100
    // bytes en medio, y el fichero saldría del tamaño justo y roto.
    m.dio.httpClientAdapter = ServidorDeMentira(contentRangeMentiroso: true);
    final r = await m.descarga.bajar(elNivel());

    expect(r, isA<DescargaFallida>());
    expect((r as DescargaFallida).motivo, contains('no continuó donde se le pidió'));
    // No se escribió ni un byte de ese trozo: el parcial se descartó entero.
    expect(m.carpeta.tiene('cuba-completo.pmtiles.parcial'), isFalse);

    // Y el siguiente intento, con un servidor que se porta, termina bien.
    m.dio.httpClientAdapter = ServidorDeMentira();
    expect(await m.descarga.bajar(elNivel()), isA<DescargaLista>());
    expect(await m.carpeta.bytes('cuba-completo.pmtiles'), elFichero.length);
  });

  test('si la huella no cuadra NO se da por bueno', () async {
    final m = montar(ServidorDeMentira());

    final r = await m.descarga.bajar(
      elNivel(huella: 'a' * 64),
    );

    expect(r, isA<DescargaFallida>());
    final fallo = r as DescargaFallida;
    expect(fallo.motivo, contains('huella'));
    // Se borra: reanudar encima de un fichero envenenado no lo arregla nunca.
    expect(fallo.sePuedeReanudar, isFalse);
    expect(m.carpeta.tiene('cuba-completo.pmtiles.parcial'), isFalse);
    expect(m.carpeta.tiene('cuba-completo.pmtiles'), isFalse);
    expect(m.carpeta.tiene('cuba-completo.json'), isFalse);
  });

  test('si los bytes no llegan al tope anunciado, NO se da por bueno', () async {
    // El servidor sirve 30.000 y el anuncio dice 40.000. Es el fallo de los
    // 2.000 clientes: se pide un tope y nadie mira si se alcanzó.
    final m = montar(ServidorDeMentira());

    final r = await m.descarga.bajar(elNivel(bytes: 40000));

    expect(r, isA<DescargaFallida>());
    expect((r as DescargaFallida).motivo, contains('se cortó'));
    expect(m.carpeta.tiene('cuba-completo.pmtiles'), isFalse);
  });

  test('un parcial más grande que el paquete se tira y se empieza', () async {
    final m = montar(ServidorDeMentira());
    // Como si hubiera quedado el parcial de otra versión, más gorda.
    m.carpeta.sembrar('cuba-completo.pmtiles.parcial', List.filled(50000, 1));

    final r = await m.descarga.bajar(elNivel());

    expect(r, isA<DescargaLista>());
    expect(await m.carpeta.bytes('cuba-completo.pmtiles'), elFichero.length);
  });

  test('el servidor que contesta 500 se dice con su código', () async {
    final m = montar(ServidorDeMentira(codigo: 500));

    final r = await m.descarga.bajar(elNivel());

    expect(r, isA<DescargaFallida>());
    expect((r as DescargaFallida).motivo, contains('500'));
    expect(
      r.motivo,
      contains('servidor'),
      reason:
          'un 500 no es un problema de señal, y mandar a mirar la cobertura a '
          'quien tiene cobertura es mandarlo a mirar donde no es',
    );
  });

  test('detener conserva lo bajado', () async {
    final m = montar(ServidorDeMentira());
    final token = CancelToken();
    // Se cancela en cuanto empiezan a llegar bytes.
    final r = await m.descarga.bajar(
      elNivel(),
      cancelar: token,
      comoVa: ({required bajados, required total}) {
        if (bajados > 4000 && !token.isCancelled) token.cancel();
      },
    );

    expect(r, isA<DescargaFallida>());
    expect((r as DescargaFallida).sePuedeReanudar, isTrue);
    expect(m.carpeta.tiene('cuba-completo.pmtiles'), isFalse);
  });

  test('el apunte que se escribe se vuelve a leer igual', () async {
    final m = montar(ServidorDeMentira());
    await m.descarga.bajar(elNivel());

    final texto = await m.carpeta.leerTexto('cuba-completo.json');
    // Que sea JSON de verdad, no una cadena que se le parece.
    final crudo = jsonDecode(texto!);
    expect(crudo, isA<Map<String, Object?>>());
    expect(PaqueteGuardado.deJson(texto)!.nivel, 'completo');
  });
}
