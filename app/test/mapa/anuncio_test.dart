// QUÉ HAY COLGADO Y QUÉ TENGO YO.
//
// La comparación es pura y se prueba sin red ni disco. Lo que se comprueba no es
// que sepa comparar cadenas: es que **no diga «al día» cuando no lo sabe** y que
// **no mande a nadie a bajar 61 MB porque haya salido un nivel más grande**.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/mapa/anuncio_de_mapa.dart';

NivelDeMapa nivel(String clave, {String version = '260916', int bytes = 1000, String? sha}) =>
    NivelDeMapa(
      nivel: clave,
      version: version,
      bytes: bytes,
      sha256: sha ?? 'a' * 64,
      url: 'https://x/$clave.pmtiles',
    );

PaqueteGuardado guardado(String clave, {String version = '260916', String? sha}) =>
    PaqueteGuardado(
      nivel: clave,
      version: version,
      bytes: 1000,
      sha256: sha ?? 'a' * 64,
      guardadoAt: DateTime(2026, 9, 17),
    );

void main() {
  group('la comparación', () {
    test('sin nada guardado, se ofrece lo que hay', () {
      final e = compararElMapa(
        tengo: null,
        colgados: [nivel('basico'), nivel('completo')],
      );
      expect(e, isA<SinPaqueteDeMapa>());
      expect((e as SinPaqueteDeMapa).ofertas, hasLength(2));
    });

    test('lo mismo que tengo es estar al día', () {
      final e = compararElMapa(
        tengo: guardado('completo'),
        colgados: [nivel('completo')],
      );
      expect(e, isA<MapaAlDia>());
    });

    test('otra versión del MISMO nivel es uno nuevo', () {
      final e = compararElMapa(
        tengo: guardado('completo', version: '260801'),
        colgados: [nivel('completo', version: '260916')],
      );
      expect(e, isA<HayMapaNuevo>());
      // El motivo nombra las dos versiones: «hay uno nuevo» a secas no le dice a
      // nadie si le corre prisa.
      expect((e as HayMapaNuevo).motivo, contains('260801'));
      expect(e.motivo, contains('260916'));
    });

    test(
      'un nivel MÁS GRANDE no me deja desactualizado',
      () {
        // Quien eligió «Sólo carreteras» porque tiene 2,4 MB y la conexión de
        // allá no está desactualizado porque haya salido uno de 61 MB. Eso no es
        // una versión nueva: es otra decisión, y la toma él.
        final e = compararElMapa(
          tengo: guardado('basico'),
          colgados: [
            nivel('basico'),
            // Con OTRA versión: si el código mirase «el último» en vez de «el
            // mío», aquí diría que hay uno nuevo. Con la misma versión la
            // diferencia no se notaría y la prueba no comprobaría nada — se vio
            // rompiendo la guarda a propósito.
            nivel('detallado', version: '261001', bytes: 61089619),
          ],
        );
        expect(e, isA<MapaAlDia>());
        // Pero el otro nivel se sigue ofreciendo, por si lo quiere.
        expect((e as MapaAlDia).ofertas, hasLength(2));
      },
    );

    test('misma versión y otra huella también avisa', () {
      // Alguien volvió a colgar el fichero sin cambiar el número. Callarlo deja
      // el aparato con algo que el servidor cree que no tiene, para siempre.
      final e = compararElMapa(
        tengo: guardado('completo', sha: 'a' * 64),
        colgados: [nivel('completo', sha: 'b' * 64)],
      );
      expect(e, isA<HayMapaNuevo>());
      expect((e as HayMapaNuevo).motivo, contains('sin cambiar de versión'));
    });

    test('un nivel que ya no se cuelga no se alarma ni se borra', () {
      // El mapa de Cuba de hace un mes sigue siendo un mapa de Cuba.
      final e = compararElMapa(
        tengo: guardado('detallado'),
        colgados: [nivel('basico')],
      );
      expect(e, isA<MapaAlDia>());
    });
  });

  group('leer lo que anuncia el servidor', () {
    test('un nivel entero se lee', () {
      final n = NivelDeMapa.deJson({
        'nivel': 'completo',
        'version': '260916',
        'fecha': '2026-09-16T00:00:00Z',
        'bytes': 25763142,
        'sha256': 'ED9C3BF5DD964BC0FA319B1807BB5D7C620DB057DBF76E6A270463E407F1E9C9',
        'url': 'https://reparto.procovar.cloud/mapa/cuba-completo.pmtiles',
      });
      expect(n, isNotNull);
      expect(n!.bytes, 25763142);
      // En minúsculas: el `sha256` se compara como texto y un servidor que lo
      // mande en mayúsculas haría fallar TODAS las descargas, para siempre.
      expect(n.sha256, startsWith('ed9c'));
    });

    test('a un nivel al que le falta algo NO se le hace caso', () {
      final base = {
        'nivel': 'completo',
        'version': '260916',
        'bytes': 100,
        'sha256': 'a' * 64,
        'url': 'https://x/c.pmtiles',
      };
      for (final quita in base.keys) {
        final crudo = {...base}..remove(quita);
        expect(
          NivelDeMapa.deJson(crudo),
          isNull,
          reason:
              'sin «$quita» o se baja a ciegas o no hay forma de saber si llegó '
              'entero',
        );
      }
      // Y los valores que no valen aunque estén.
      expect(NivelDeMapa.deJson({...base, 'bytes': 0}), isNull);
      expect(NivelDeMapa.deJson({...base, 'sha256': 'corto'}), isNull);
      expect(
        NivelDeMapa.deJson({...base, 'url': 'reparto.procovar.cloud/c.pmtiles'}),
        isNull,
      );
    });

    test('un nivel desconocido se ofrece con su clave, no se esconde', () {
      // NADA SE DESCARTA EN SILENCIO. Si alguien cuelga un nivel nuevo, sale —
      // feo, pero sale — en vez de desaparecer sin que nadie sepa por qué.
      final n = nivel('provincial');
      expect(n.titulo, contains('provincial'));
    });

    test('los que no se pudieron leer se CUENTAN', () async {
      final dio = Dio()..httpClientAdapter = _ServidorQueAnuncia({
        'niveles': [
          {
            'nivel': 'basico',
            'version': '260916',
            'bytes': 2375346,
            'sha256': 'a' * 64,
            'url': 'https://x/b.pmtiles',
          },
          // A éste le falta el sha256.
          {
            'nivel': 'completo',
            'version': '260916',
            'bytes': 25763142,
            'url': 'https://x/c.pmtiles',
          },
        ],
      });

      final hay = await AnuncioDeMapa(dio, 'https://x/api').loQueHay();

      expect(hay.niveles, hasLength(1));
      expect(
        hay.ilegibles,
        1,
        reason:
            'si el servidor anuncia dos y aquí se entiende uno, la persona tiene '
            'que poder enterarse de que falta uno',
      );
    });

    test('«niveles: null» es «no hay nada colgado», no un error', () async {
      final dio = Dio()..httpClientAdapter = _ServidorQueAnuncia({'niveles': null});
      final hay = await AnuncioDeMapa(dio, 'https://x/api').loQueHay();
      expect(hay.niveles, isEmpty);
      expect(hay.ilegibles, 0);
    });

    test('una respuesta que no es el contrato se dice', () async {
      final dio = Dio()..httpClientAdapter = _ServidorQueAnuncia({'niveles': 'sí'});
      expect(
        () => AnuncioDeMapa(dio, 'https://x/api').loQueHay(),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('los tamaños se escriben como aquí', () {
    expect(enMegas(2375346), '2,4 MB');
    expect(enMegas(25763142), '25,8 MB');
    expect(enMegas(61089619), '61,1 MB');
    expect(enMegas(91082), '91 kB');
  });
}

class _ServidorQueAnuncia implements HttpClientAdapter {
  _ServidorQueAnuncia(this.cuerpo);

  final Object cuerpo;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? peticion, Future<void>? cancelar) async =>
      ResponseBody.fromString(
        _json(cuerpo),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

String _json(Object o) {
  // `jsonEncode` de verdad, para que la prueba no invente un JSON que el
  // servidor no mandaría nunca.
  return const JsonEncoder().convert(o);
}
