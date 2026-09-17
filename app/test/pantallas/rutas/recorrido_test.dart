// DE LA BASE AL DIBUJO: `recorridoDe` es lo unico de todo este trozo que sabe
// que existe Drift, asi que es lo unico que se prueba contra una base de verdad.
//
// Y hay una cosa que SOLO se puede comprobar aqui: que el croquis y la lista de
// paradas cuentan la misma ruta en el mismo orden. Son dos pantallas que
// contestan a lo mismo, y dos respuestas sobre lo mismo se separan sin que salte
// nada (`CLAUDE.md` §3-bis) — salvo que haya una prueba que las ate.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/rutas/datos/recorrido.dart';
import 'package:reparto/pantallas/rutas/datos/repositorio_rutas.dart';

import '../../apoyo/base_de_prueba.dart';
import '../pedidos/sembrar.dart';
import 'rutas_a_mano.dart';

void main() {
  group('lo que sale de la base', () {
    late BaseLocal base;

    setUp(() => base = baseDePrueba());
    tearDown(() => base.close());

    test('las paradas llegan al croquis en el orden de la ruta', () async {
      await sembrarCatalogo(base);
      await base
          .into(base.routes)
          .insert(
            RoutesCompanion.insert(
              id: 'R1',
              routeCode: const Value('RT-001'),
              branchId: const Value('B1'),
              originLat: const Value(21.38),
              originLng: const Value(-77.91),
            ),
          );
      // Se siembran a proposito EN DESORDEN: si el croquis pintara en el orden
      // en que estan en la tabla —o alfabetico— esto lo caza.
      await sembrarPedido(
        base,
        id: 'o3',
        cliente: 'Ana',
        ultimaRutaId: 'R1',
        orden: 3,
        endLat: 21.3,
        endLng: -77.3,
      );
      await sembrarPedido(
        base,
        id: 'o1',
        cliente: 'Zoe',
        ultimaRutaId: 'R1',
        orden: 1,
        endLat: 21.1,
        endLng: -77.1,
      );
      await sembrarPedido(
        base,
        id: 'o2',
        cliente: 'Beto',
        ultimaRutaId: 'R1',
        orden: 2,
        endLat: 21.2,
        endLng: -77.2,
      );

      final ruta = await ConsultasRutas(base).rutaConTodo('R1').first;
      final recorrido = recorridoDe(ruta!);

      expect(
        [for (final p in recorrido.paradas) p.etiqueta],
        ['Zoe', 'Beto', 'Ana'],
      );
      // Y el orden del dibujo es el mismo que el de la lista de paradas del
      // detalle, que sale de esta misma consulta.
      expect(
        [for (final p in recorrido.paradas) p.id],
        [for (final p in ruta.paradas) p.id],
      );
      expect(recorrido.origen!.lat, 21.38);
      expect(recorrido.nombreDelOrigen, 'Camagüey');
    });

    test('una ruta sin coordenadas de origen no inventa ninguna', () async {
      await sembrarCatalogo(base);
      await base
          .into(base.routes)
          .insert(
            RoutesCompanion.insert(id: 'R2', branchId: const Value('B1')),
          );

      final ruta = await ConsultasRutas(base).rutaConTodo('R2').first;
      final recorrido = recorridoDe(ruta!);

      // Ni un `0,0` de relleno, que cae en el Golfo de Guinea y dibuja una ruta
      // de nueve mil kilometros.
      expect(recorrido.origen, isNull);
      expect(recorrido.hayAlgoQueDibujar, isFalse);
    });
  });

  group('la conversion', () {
    test('numera TODAS las paradas, tengan coordenadas o no', () {
      final recorrido = recorridoDe(
        rutaAMano(
          paradas: [
            paradaAMano(id: 'a', cliente: 'Ana', lat: 21.1, lng: -77.1),
            paradaAMano(id: 'b', cliente: 'Beto'),
            paradaAMano(id: 'c', cliente: 'Carla', lat: 21.3, lng: -77.3),
          ],
        ),
      );

      expect([for (final p in recorrido.paradas) p.numero], [1, 2, 3]);
      expect([for (final p in recorrido.dibujables) p.numero], [1, 3]);
      expect(recorrido.sinCoordenadas, 1);
    });

    test('una parada a medias —lat sin lng— no se dibuja', () {
      // Media coordenada es peor que ninguna: se pinta en el meridiano cero.
      final recorrido = recorridoDe(
        rutaAMano(
          paradas: [paradaAMano(id: 'a', cliente: 'Ana', lat: 21.1)],
        ),
      );

      expect(recorrido.dibujables, isEmpty);
      expect(recorrido.sinCoordenadas, 1);
    });

    test('se sabe cual esta entregada y cual va en el regreso', () {
      final recorrido = recorridoDe(
        rutaAMano(
          paradas: [
            paradaAMano(
              id: 'a',
              cliente: 'Ana',
              lat: 21.1,
              lng: -77.1,
              resultado: ResultadoParada.entregado,
            ),
            paradaAMano(
              id: 'b',
              cliente: 'Beto',
              lat: 21.2,
              lng: -77.2,
              tramo: Tramo.regreso,
            ),
            paradaAMano(
              id: 'c',
              cliente: 'Carla',
              lat: 21.3,
              lng: -77.3,
              resultado: ResultadoParada.devuelto,
            ),
          ],
        ),
      );

      expect(recorrido.paradas[0].entregada, isTrue);
      expect(recorrido.paradas[1].esRegreso, isTrue);
      // `devuelto` NO es `entregado`: se pinta como pendiente, que es lo que es.
      expect(recorrido.paradas[2].entregada, isFalse);
    });

    test('el importe nulo se queda nulo y no se convierte en cero', () {
      final recorrido = recorridoDe(
        rutaAMano(
          paradas: [
            paradaAMano(id: 'a', cliente: 'Ana', lat: 21.1, lng: -77.1),
            paradaAMano(
              id: 'b',
              cliente: 'Beto',
              lat: 21.2,
              lng: -77.2,
              precio: 0,
            ),
          ],
        ),
      );

      expect(recorrido.paradas[0].importe, isNull);
      // Un cero de verdad sigue siendo un cero: lo que no vale es fabricarlo.
      expect(recorrido.paradas[1].importe, 0);
    });
  });
}
