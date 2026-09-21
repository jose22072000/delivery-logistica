// La geometria del recorrido. Se calcula EN EL APARATO, asi que es lo que decide
// el orden en que sale el camion cuando no hay con quien consultarlo.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/rutas/datos/geo.dart';

void main() {
  // Un grado de longitud en el ecuador: 6371 × π/180 ≈ 111.19 km. Con el origen
  // en (0,0) los numeros se pueden comprobar a mano.
  const origen = Punto(0, 0);
  const unDecimoDeGrado = 11.1195;

  test('haversine da los km y no redondea', () {
    expect(
      haversineKm(origen, const Punto(0, 0.1)),
      closeTo(unDecimoDeGrado, 0.001),
    );
    expect(haversineKm(origen, origen), 0);
    // Simetrica: de ida y de vuelta es lo mismo.
    expect(
      haversineKm(const Punto(21.38, -77.91), const Punto(20.88, -76.26)),
      closeTo(
        haversineKm(const Punto(20.88, -76.26), const Punto(21.38, -77.91)),
        1e-9,
      ),
    );
  });

  test('los casos limite del orden de visita son explicitos', () {
    expect(vecinoMasCercano(origen, const []), isEmpty);
    expect(vecinoMasCercano(origen, const [Parada('a', 5, 5)]), ['a']);
  });

  test('el orden es vecino mas proximo, no el orden de entrada', () {
    final orden = vecinoMasCercano(origen, const [
      Parada('lejos', 0, 0.3),
      Parada('cerca', 0, 0.1),
      Parada('medio', 0, 0.2),
    ]);
    expect(orden, ['cerca', 'medio', 'lejos']);
  });

  test('EL DESEMPATE LO GANA LA PRIMERA DE LA LISTA', () {
    // Dos paradas exactamente a la misma distancia del origen. La comparacion es
    // `<` estricta, asi que gana la primera. Si esto cambiara, el orden de las
    // paradas dejaria de cuadrar con el del servidor sin que nada estuviera roto.
    final orden = vecinoMasCercano(origen, const [
      Parada('norte', 0.1, 0),
      Parada('este', 0, 0.1),
    ]);
    expect(orden.first, 'norte');
  });

  test('los tramos son consecutivos y NO cierran el circuito', () {
    final medidas = tramos(origen, const [
      Parada('a', 0, 0.1),
      Parada('b', 0, 0.2),
    ]);
    expect(medidas.length, 2);
    expect(medidas[0], closeTo(unDecimoDeGrado, 0.001));
    expect(medidas[1], closeTo(unDecimoDeGrado, 0.001));
  });

  test('los km del camion incluyen el regreso', () {
    // origen → 0.1 → 0.2 → origen = 0.1 + 0.1 + 0.2 grados = 4 décimas.
    final km = kmDelCircuito(origen, const [
      Parada('a', 0, 0.1),
      Parada('b', 0, 0.2),
    ]);
    expect(km, closeTo(unDecimoDeGrado * 4, 0.01));
    expect(kmDelCircuito(origen, const []), 0);
  });

  // -------------------------------------------------------------------------
  // EL ORDEN BUENO: vecino mas proximo + 2-opt + Or-opt
  // -------------------------------------------------------------------------
  //
  // Jose, 21/09/2026: «esa planificada esta mal, no hace ruta logica ni nada».
  // Lo que sigue es lo que lo arregla y lo que impide que se vuelva a torcer.

  group('el orden de visita', () {
    test('la primera parada sale DEL ALMACEN y no se pierde ninguna', () {
      const origen = Punto(23.125, -82.375);
      const paradas = [
        Parada('a', 23.14, -82.39),
        Parada('b', 23.09, -82.31),
        Parada('c', 23.16, -82.27),
        Parada('d', 23.05, -82.42),
      ];
      final orden = ordenDeVisita(origen, paradas);

      // Ninguna se cae y ninguna se repite: es una permutacion, no una seleccion.
      expect(
        orden.toSet(),
        paradas.map((p) => p.id).toSet(),
        reason: 'el orden de visita perdio o repitio paradas',
      );
      expect(orden.length, paradas.length);

      // El almacen NO es una parada: el primer tramo se mide DESDE el almacen.
      // Si 2-opt pudiera mover el origen, el camion empezaria en casa de un
      // cliente y los km del circuito serian otros sin que nada fallara.
      final porId = {for (final p in paradas) p.id: p};
      final ordenadas = [for (final id in orden) porId[id]!];
      expect(
        tramos(origen, ordenadas).first,
        haversineKm(origen, ordenadas.first.punto),
        reason: 'el recorrido tiene que arrancar en el almacen',
      );
    });

    test('los casos limite siguen siendo explicitos', () {
      const origen = Punto(23.125, -82.375);
      expect(ordenDeVisita(origen, const []), isEmpty);
      expect(ordenDeVisita(origen, const [Parada('a', 5, 5)]), ['a']);
    });

    test('mismo orden de entrada, mismo orden de salida (dos veces seguidas)', () {
      const origen = Punto(21.3808, -77.9169);
      const paradas = [
        Parada('holguin', 20.8872, -76.2631),
        Parada('ciego', 21.8404, -78.7625),
        Parada('bayamo', 20.3797, -76.6431),
        Parada('nuevitas', 21.5453, -77.2647),
        Parada('manzanillo', 20.3433, -77.1167),
      ];
      final primera = ordenDeVisita(origen, paradas);
      final segunda = ordenDeVisita(origen, paradas);
      expect(segunda, primera, reason: 'dos llamadas iguales dieron ordenes distintos');
      // Y la lista de quien llama no se toca: ordenar no es reordenarle los
      // pedidos al que arma la ruta.
      expect(paradas.map((p) => p.id), [
        'holguin',
        'ciego',
        'bayamo',
        'nuevitas',
        'manzanillo',
      ]);
    });

    test('la mejora BAJA los km y deshace el cruce', () {
      // Cuatro paradas puestas para que el greedy se deje una para el final y
      // tenga que cruzar el recorrido entero para ir a buscarla. Es el caso
      // `cruce-evidente` del fichero compartido.
      const origen = Punto(23.0, -82.4);
      const paradas = [
        Parada('cercana', 23.01, -82.38),
        Parada('noreste', 23.06, -82.36),
        Parada('este-lejano', 23.02, -82.30),
        Parada('norte', 23.07, -82.41),
      ];
      final greedy = _enOrden(paradas, vecinoMasCercano(origen, paradas));
      final bueno = _enOrden(paradas, ordenDeVisita(origen, paradas));

      final kmGreedy = kmDelCircuito(origen, greedy);
      final kmBueno = kmDelCircuito(origen, bueno);
      expect(
        kmBueno,
        lessThan(kmGreedy - 1e-9),
        reason:
            'el orden mejorado (${kmBueno.toStringAsFixed(3)} km) tiene que '
            'medir MENOS que el del vecino mas proximo '
            '(${kmGreedy.toStringAsFixed(3)} km)',
      );
      expect(
        _cruces(origen, greedy),
        greaterThan(0),
        reason: 'el caso ya no tiene cruce: deja de probar lo que dice probar',
      );
      expect(
        _cruces(origen, bueno),
        0,
        reason: 'el recorrido mejorado todavia se corta a si mismo',
      );
    });

    test('la distancia se puede cambiar por fuera (puerta abierta a las calles)', () {
      // No se prueba el enrutador por calles —que lo esta escribiendo otro— sino
      // que el orden de visita NO depende de la linea recta. Con una distancia
      // de mentira el orden tiene que salir distinto; si saliera igual, la
      // funcion que se pasa no se estaria usando.
      const origen = Punto(0, 0);
      const paradas = [
        Parada('norte-cerca', 0.05, 0),
        Parada('este-cerca', 0, 0.1),
        Parada('este-lejos', 0, 0.25),
      ];
      // Una calle de mentira: subir en latitud cuesta diez veces mas que ir de
      // lado. Con eso, la parada del norte deja de ser la primera.
      double comoSiFueranCalles(Punto a, Punto b) =>
          (a.lng - b.lng).abs() + 10 * (a.lat - b.lat).abs();
      expect(
        ordenDeVisita(origen, paradas, distancia: comoSiFueranCalles),
        isNot(ordenDeVisita(origen, paradas)),
        reason: 'la distancia que se pasa por fuera no se esta usando',
      );
    });

    test('con 60 paradas no cuelga la pantalla del logistico', () {
      for (final cuantas in [10, 30, 60]) {
        final paradas = _repartoDeMentira(cuantas);
        final reloj = Stopwatch()..start();
        final orden = ordenDeVisita(const Punto(23.125, -82.375), paradas);
        reloj.stop();
        expect(orden.length, cuantas);
        expect(
          reloj.elapsedMilliseconds,
          lessThan(2000),
          reason:
              'ordenar $cuantas paradas tardo ${reloj.elapsedMilliseconds} ms: '
              'eso es una pantalla congelada',
        );
        // ignore: avoid_print
        print('  $cuantas paradas: ${reloj.elapsedMicroseconds} us');
      }
    });
  });

  // -------------------------------------------------------------------------
  // LA PARIDAD CON EL SERVIDOR
  // -------------------------------------------------------------------------
  //
  // `docs/orden-de-paradas.casos.json` lo leen esta prueba y
  // `api/internal/api/orden_de_paradas_test.go`. Si alguien toca un lado y no el
  // otro, una de las dos se pone roja. Un comentario no falla; esto si
  // (CLAUDE.md §3-bis).

  group('los casos compartidos con el servidor', () {
    final fichero = File('../docs/orden-de-paradas.casos.json');
    final doc = jsonDecode(fichero.readAsStringSync()) as Map<String, dynamic>;
    final tolerancia = (doc['toleranciaKm'] as num).toDouble();

    test('el fichero esta donde dice y trae casos', () {
      expect(
        fichero.existsSync(),
        isTrue,
        reason: 'sin ${fichero.path} no hay nada que ate los dos lados',
      );
      expect((doc['casos'] as List), isNotEmpty);
      expect(
        (doc['mejoraMinimaKm'] as num).toDouble(),
        mejoraMinimaKm,
        reason:
            'el epsilon del fichero y el del codigo tienen que ser el mismo: '
            'con dos numeros distintos, Dart y Go dejan de decidir igual',
      );
    });

    for (final crudo in (doc['casos'] as List)) {
      final caso = crudo as Map<String, dynamic>;
      final nombre = caso['nombre'] as String;
      final origen = Punto(
        ((caso['origen'] as Map)['lat'] as num).toDouble(),
        ((caso['origen'] as Map)['lng'] as num).toDouble(),
      );
      final paradas = [
        for (final p in (caso['paradas'] as List))
          Parada(
            (p as Map)['id'] as String,
            (p['lat'] as num).toDouble(),
            (p['lng'] as num).toDouble(),
          ),
      ];
      final esperadoVecino = [
        for (final id in (caso['ordenVecinoMasProximo'] as List)) id as String,
      ];
      final esperado = [for (final id in (caso['ordenEsperado'] as List)) id as String];

      test('«$nombre» — ${caso['nota']}', () {
        expect(
          vecinoMasCercano(origen, paradas),
          esperadoVecino,
          reason:
              'el vecino mas proximo cambio en el aparato. Si el cambio es a '
              'proposito, hay que regenerar $nombre en '
              'docs/orden-de-paradas.casos.json Y cambiar el servidor: el orden '
              'de las paradas tiene que ser el mismo en los dos.',
        );
        expect(
          ordenDeVisita(origen, paradas),
          esperado,
          reason:
              'el orden de visita de «$nombre» ya no es el del fichero '
              'compartido. O se rompio la mejora, o se rompio el desempate, o '
              'alguien cambio el algoritmo en un solo lado.',
        );
        expect(
          kmDelCircuito(origen, _enOrden(paradas, esperado)),
          closeTo((caso['kmEsperado'] as num).toDouble(), tolerancia),
          reason: 'los km del circuito de «$nombre» no cuadran con el fichero',
        );
        expect(
          kmDelCircuito(origen, _enOrden(paradas, esperado)),
          lessThanOrEqualTo(
            kmDelCircuito(origen, _enOrden(paradas, esperadoVecino)) + 1e-9,
          ),
          reason:
              'en «$nombre» el orden «mejorado» mide MAS que el del vecino mas '
              'proximo: la mejora esta empeorando la ruta',
        );
      });
    }
  });
}

/// Las paradas en el orden que dice la lista de ids.
List<Parada> _enOrden(List<Parada> paradas, List<String> orden) {
  final porId = {for (final p in paradas) p.id: p};
  return [for (final id in orden) porId[id]!];
}

/// Cuantos pares de tramos del circuito se cortan. Un cruce es la señal de que
/// la ruta no es logica: siempre se puede deshacer y siempre sale mas corta.
/// A esta escala (una ciudad) medir en el plano lat/lng vale.
int _cruces(Punto origen, List<Parada> ordenadas) {
  final puntos = [origen, for (final p in ordenadas) p.punto, origen];
  var cuantos = 0;
  for (var i = 0; i + 1 < puntos.length; i++) {
    for (var j = i + 2; j + 1 < puntos.length; j++) {
      // Los tramos pegados comparten un extremo: tocarse no es cruzarse. El
      // primero y el ultimo comparten el almacen.
      if (i == 0 && j + 1 == puntos.length - 1) continue;
      if (_seCortan(puntos[i], puntos[i + 1], puntos[j], puntos[j + 1])) {
        cuantos++;
      }
    }
  }
  return cuantos;
}

bool _seCortan(Punto a, Punto b, Punto c, Punto d) {
  double lado(Punto p, Punto q, Punto r) =>
      (q.lng - p.lng) * (r.lat - p.lat) - (q.lat - p.lat) * (r.lng - p.lng);
  final d1 = lado(c, d, a);
  final d2 = lado(c, d, b);
  final d3 = lado(a, b, c);
  final d4 = lado(a, b, d);
  return (d1 > 0) != (d2 > 0) && (d3 > 0) != (d4 > 0);
}

/// Un reparto de mentira repartido por La Habana, siempre el mismo (la semilla
/// esta escrita a mano para que la medida del tiempo se pueda repetir).
List<Parada> _repartoDeMentira(int cuantas) {
  var semilla = 20260921;
  double siguiente() {
    semilla = (semilla * 1103515245 + 12345) & 0x7fffffff;
    return semilla / 0x7fffffff;
  }

  return [
    for (var i = 0; i < cuantas; i++)
      Parada(
        'p$i',
        23.0 + siguiente() * 0.2,
        -82.5 + siguiente() * 0.3,
      ),
  ];
}
