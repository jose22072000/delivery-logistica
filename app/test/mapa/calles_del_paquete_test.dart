// LAS PRUEBAS DEL ENRUTADOR SIN CONEXIÓN.
//
// Lo que tienen que atrapar es **un solo fallo**, el que Jose vio el 21/09/2026
// en el teléfono con el avión puesto: que la ruta se dibuje en líneas rectas de
// parada a parada. Todo lo demás de aquí son las tres costuras que hacen falta
// para que eso no pase.
//
// Van en tres alturas, y las tres hacen falta:
//
//  1. **Con el fichero de verdad** (60 MB, Cuba entera, z15). Es la única que
//     comprueba que esto funciona sobre las teselas que de verdad lleva el
//     aparato. Se salta con motivo si el fichero no está: una prueba que sólo
//     corre en una máquina no puede ponerse roja en la de otro.
//  2. **Con teselas de mentira**, sobre el armado del grafo. Es la que caza la
//     costura entre teselas sin depender de nada.
//  3. **Sin mapa ninguno**, sobre la regla de que un tramo malo no se lleva por
//     delante a los demás.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/mapa/calles_del_paquete.dart';
import 'package:reparto/mapa/pmtiles.dart';
import 'package:reparto/pantallas/rutas/datos/geo.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';

/// El paquete de verdad. Vive en el cuaderno de esta sesión, no en el repo: son
/// 60 MB y no se meten en git.
const _elFicheroDeVerdad =
    '/tmp/claude-1000/-mnt-datos-Work/7334aff6-02dc-47ca-ac43-1128133094d8/'
    'scratchpad/cuba-detallado.pmtiles';

class _RangosDeFichero implements LeerPorRangos {
  _RangosDeFichero(this._f);

  final RandomAccessFile _f;

  @override
  Future<Uint8List> leer(int desde, int largo) async {
    await _f.setPosition(desde);
    return _f.read(largo);
  }

  @override
  Future<void> cerrar() async => _f.close();
}

double _largoKm(List<Punto> linea) {
  var total = 0.0;
  for (var i = 0; i + 1 < linea.length; i++) {
    total += haversineKm(linea[i], linea[i + 1]);
  }
  return total;
}

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('con el paquete de Cuba de verdad', () {
    late PaqueteDeTeselas paquete;
    var hayFichero = false;

    setUp(() async {
      final f = File(_elFicheroDeVerdad);
      hayFichero = f.existsSync();
      if (hayFichero) {
        paquete = await PaqueteDeTeselas.abrir(_RangosDeFichero(f.openSync()));
      }
    });

    tearDown(() async {
      if (hayFichero) await paquete.cerrar();
    });

    /// Se salta con motivo, no falla. El fichero es de esta sesión.
    bool sinFichero() {
      if (hayFichero) return false;
      markTestSkipped(
        'no está $_elFicheroDeVerdad (60 MB, Cuba entera, z15): esta prueba '
        'sólo corre donde se haya descargado el paquete. Se genera con '
        '`herramientas/mapa-cuba` o se baja de /api/mapa.',
      );
      return true;
    }

    test('dos paradas de La Habana NO salen en línea recta', () async {
      if (sinFichero()) return;
      // Dos puntos dentro de La Habana, a unos 3 km: Centro Habana y Vedado
      // alto. Por calles hay que rodear manzanas; en recta se cruzan enteras.
      const a = Punto(23.1136, -82.3666);
      const b = Punto(23.1290, -82.3900);

      final reloj = Stopwatch()..start();
      final linea = await CallesDelPaquete(paquete).entre(const [a, b]);
      final ms = reloj.elapsedMilliseconds;

      expect(
        linea,
        isNotNull,
        reason: 'el paquete tiene z15 sobre La Habana: si esto es null, el '
            'enrutador no está leyendo las teselas o no engancha las paradas',
      );
      // LO QUE SE COMPRUEBA ES QUE NO ES LA RECTA. Dos vértices es exactamente
      // la recta, que es el fallo del que sale todo esto.
      expect(
        linea!.length,
        greaterThan(20),
        reason: 'una ruta por calles de 3 km en La Habana tiene decenas de '
            'vértices; ${linea.length} es la recta o poco más, o sea el fallo '
            'del 21/09: «la ruta no es logica es son rectas»',
      );

      final porCalles = _largoKm(linea);
      final enRecta = haversineKm(a, b);
      expect(
        porCalles,
        greaterThan(enRecta * 1.05),
        reason: 'por calles SIEMPRE se anda más que en recta; '
            '${porCalles.toStringAsFixed(2)} km contra '
            '${enRecta.toStringAsFixed(2)} km es sospechosamente parecido a la '
            'recta',
      );
      expect(
        porCalles,
        lessThan(enRecta * 2),
        reason: 'un rodeo de más del doble no es una ruta, es el grafo roto: '
            'A* cruzó media ciudad porque las costuras no cerraban. '
            '${porCalles.toStringAsFixed(2)} km contra '
            '${enRecta.toStringAsFixed(2)} km en recta',
      );

      // El coste, que aquí es parte del contrato: esto corre en el hilo de la
      // interfaz. El tope está flojo a propósito —una máquina de integración es
      // más lenta que este portátil, donde da 35 ms en caliente— pero un
      // segundo ya es un mapa congelado y hay que enterarse.
      expect(
        ms,
        lessThan(1000),
        reason: 'un tramo de La Habana tardó $ms ms en el hilo de la interfaz',
      );
    });

    test('un tramo sin camino sale recto y los demás siguen por calles',
        () async {
      if (sinFichero()) return;
      const almacen = Punto(23.1136, -82.3666);
      const cliente = Punto(23.1290, -82.3900);
      // Mar abierto al norte de La Habana: no hay ni una tesela de carretera.
      const enElMar = Punto(23.5000, -82.3666);

      final linea =
          await CallesDelPaquete(paquete).entre(const [almacen, cliente, enElMar]);

      expect(linea, isNotNull);
      // El último tramo es la recta: el punto del mar entra tal cual y el
      // anterior es el cliente, sin nada en medio.
      expect(
        linea!.last.lat,
        closeTo(enElMar.lat, 1e-9),
        reason: 'la línea tiene que acabar en la parada, venga por donde venga',
      );
      final antesDelUltimo = linea[linea.length - 2];
      expect(
        haversineKm(antesDelUltimo, cliente),
        lessThan(0.001),
        reason: 'el tramo al mar tiene que ser UNA recta del cliente al punto: '
            'si hay vértices en medio, alguien inventó un camino',
      );
      // Y lo que importa: el primer tramo NO perdió sus calles por culpa del
      // segundo.
      expect(
        linea.length,
        greaterThan(20),
        reason: 'un tramo sin camino tiró el recorrido entero a rectas; son '
            '${linea.length} vértices para dos tramos, y el primero es una '
            'ruta de 3 km por La Habana',
      );
    });

    test('dos paradas en el mar devuelven null, no una excepción', () async {
      if (sinFichero()) return;
      final linea = await CallesDelPaquete(paquete)
          .entre(const [Punto(23.50, -82.36), Punto(23.60, -82.40)]);
      expect(
        linea,
        isNull,
        reason: 'sin calles y sin respaldo la respuesta es null, como '
            '`SinCallesQueSeguir`: el mapa dibuja la recta y LO DICE',
      );
    });

    test('sin calles por el paquete se le pregunta al respaldo', () async {
      if (sinFichero()) return;
      final red = _RespaldoDeMentira();
      final linea = await CallesDelPaquete(paquete, respaldo: red)
          .entre(const [Punto(23.50, -82.36), Punto(23.60, -82.40)]);
      expect(red.veces, 1, reason: 'el respaldo es lo que queda cuando el '
          'paquete no sabe de esa zona');
      expect(linea, red.linea);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('el grafo, con teselas de mentira', () {
    // Una calle recta de este a oeste que cruza el borde entre la tesela
    // (1000, 500) y la (1001, 500), a z14. Cada tesela la trae recortada con el
    // margen del generador —o sea, sobresaliendo por el borde— y con los
    // vértices en sitios ligeramente distintos, que es lo que hace de verdad
    // Douglas-Peucker cuando simplifica cada tesela por su cuenta.
    const z = 14;
    const tx = 1000;
    const ty = 500;
    const ext = 4096.0;

    List<CadenaDeVia> laCalleEnDosTeselas({double desfaseDeLaSegunda = 2}) {
      final cadenas = <CadenaDeVia>[];
      // La tesela de la izquierda: entra por el medio y se sale por la derecha.
      recortarALaTesela(
        const [Offset(1000, 2048), Offset(3000, 2048), Offset(4608, 2048)],
        ext,
        tx,
        ty,
        1.0,
        cadenas,
      );
      // La de la derecha: la MISMA calle, entrando desde la izquierda con el
      // sobrante del margen, y medio metro más abajo.
      recortarALaTesela(
        [
          Offset(-512, 2048 + desfaseDeLaSegunda),
          Offset(1000, 2048 + desfaseDeLaSegunda),
          Offset(3000, 2048 + desfaseDeLaSegunda),
        ],
        ext,
        tx + 1,
        ty,
        1.0,
        cadenas,
      );
      return cadenas;
    }

    test('el sobrante del margen se tira y la calle se corta en el borde', () {
      final cadenas = laCalleEnDosTeselas();
      expect(cadenas, hasLength(2));
      // El borde entre la tesela 1000 y la 1001, en la rejilla global, es
      // 1001 * 4096. Las dos cadenas tienen que acabar/empezar exactamente ahí:
      // es lo único que permite coserlas.
      const borde = 1001 * 4096.0;
      expect(
        cadenas[0].puntos[cadenas[0].puntos.length - 2],
        closeTo(borde, 1e-6),
        reason: 'la cadena de la izquierda tiene que acabar EN el borde; si '
            'acaba pasado, el sobrante del margen sigue dentro y la misma '
            'calle entra dos veces en el grafo',
      );
      expect(
        cadenas[1].puntos[0],
        closeTo(borde, 1e-6),
        reason: 'la cadena de la derecha tiene que empezar EN el borde',
      );
    });

    test('LA COSTURA: los dos trozos de la misma calle quedan unidos', () {
      final cadenas = laCalleEnDosTeselas();
      final porUnidad = metrosPorUnidad(23.1, z);
      final grafo = GrafoDeCalles.deCadenas(
        cadenas,
        toleranciaUnidades: 8.0 / porUnidad,
      );

      // El extremo oeste (dentro de la tesela izquierda) y el este (dentro de
      // la derecha).
      final oeste = grafo.nodoMasCerca((tx + 1000 / ext) * 4096,
          (ty + 2048 / ext) * 4096, 50);
      final este = grafo.nodoMasCerca((tx + 1 + 3000 / ext) * 4096,
          (ty + 2050 / ext) * 4096, 50);
      expect(oeste, isNotNull);
      expect(este, isNotNull);

      final camino = grafo.camino(oeste!, este!);
      expect(
        camino,
        isNotNull,
        reason: 'LA COSTURA ENTRE TESELAS ESTÁ ROTA. Los dos trozos de la misma '
            'calle, uno en cada tesela, quedaron en dos componentes sueltas: el '
            'grafo se parte en el borde de cada tesela y el enrutado cae a la '
            'recta — que es el fallo del 21/09 exactamente',
      );
      expect(camino!.length, greaterThanOrEqualTo(2));
    });

    test('dos calles paralelas separadas de verdad NO se cosen', () {
      // La misma prueba de antes pero con la segunda tesela 60 metros más
      // abajo: eso ya no es el error de la simplificación, son dos calles
      // distintas. Coserlas haría que el camión atravesara manzanas.
      final cadenas = laCalleEnDosTeselas(desfaseDeLaSegunda: 110);
      final porUnidad = metrosPorUnidad(23.1, z);
      final grafo = GrafoDeCalles.deCadenas(
        cadenas,
        toleranciaUnidades: 8.0 / porUnidad,
      );
      final oeste = grafo.nodoMasCerca(
          (tx + 1000 / ext) * 4096, (ty + 2048 / ext) * 4096, 50);
      final este = grafo.nodoMasCerca(
          (tx + 1 + 3000 / ext) * 4096, (ty + (2048 + 110) / ext) * 4096, 50);
      expect(grafo.camino(oeste!, este!), isNull,
          reason: 'la tolerancia de costura se coló 60 m: a esa distancia son '
              'dos calles y no dos mitades de una');
    });

    test('EL CRUCE sin vértice compartido también une', () {
      // Douglas-Peucker borra el vértice del cruce de las dos calles rectas: en
      // el fichero de verdad, cuatro teselas de La Habana traían 776 cruces
      // así. Sin partir las vías por el punto de corte, el grafo queda en
      // trozos aunque las calles se dibujen cruzándose.
      final cadenas = <CadenaDeVia>[];
      recortarALaTesela(
        const [Offset(500, 2048), Offset(3500, 2048)],
        ext,
        tx,
        ty,
        1.0,
        cadenas,
      );
      recortarALaTesela(
        const [Offset(2048, 500), Offset(2048, 3500)],
        ext,
        tx,
        ty,
        1.0,
        cadenas,
      );
      final porUnidad = metrosPorUnidad(23.1, z);
      final grafo = GrafoDeCalles.deCadenas(
        cadenas,
        toleranciaUnidades: 8.0 / porUnidad,
      );
      final enLaHorizontal = grafo.nodoMasCerca(
          (tx + 500 / ext) * 4096, (ty + 2048 / ext) * 4096, 50);
      final enLaVertical = grafo.nodoMasCerca(
          (tx + 2048 / ext) * 4096, (ty + 500 / ext) * 4096, 50);
      expect(
        grafo.camino(enLaHorizontal!, enLaVertical!),
        isNotNull,
        reason: 'las dos calles se cruzan y ninguna tiene un vértice ahí: si '
            'no se parten por el punto de corte, no hay forma de pasar de una '
            'a otra y el grafo queda en telaraña suelta',
      );
    });

    test('A* devuelve el camino corto, no uno cualquiera', () {
      // Un rectángulo: por arriba 3000 unidades, por abajo 3000 + un rodeo.
      final cadenas = <CadenaDeVia>[];
      // Lado corto (arriba).
      recortarALaTesela(
        const [Offset(500, 1000), Offset(3500, 1000)],
        ext, tx, ty, 1.0, cadenas,
      );
      // Rodeo (abajo), tres lados.
      recortarALaTesela(
        const [
          Offset(500, 1000),
          Offset(500, 3000),
          Offset(3500, 3000),
          Offset(3500, 1000),
        ],
        ext, tx, ty, 1.0, cadenas,
      );
      final porUnidad = metrosPorUnidad(23.1, z);
      final grafo = GrafoDeCalles.deCadenas(
        cadenas,
        toleranciaUnidades: 8.0 / porUnidad,
      );
      final izq = grafo.nodoMasCerca(
          (tx + 500 / ext) * 4096, (ty + 1000 / ext) * 4096, 50)!;
      final der = grafo.nodoMasCerca(
          (tx + 3500 / ext) * 4096, (ty + 1000 / ext) * 4096, 50)!;
      final camino = grafo.camino(izq, der)!;
      // Por arriba son dos nodos; por el rodeo, cuatro.
      expect(camino, hasLength(2),
          reason: 'A* se fue por el rodeo teniendo el lado corto delante: '
              'la heurística no es admisible o los pesos están mal');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('un tramo malo no se lleva por delante a los demás', () {
    const p0 = Punto(23.10, -82.40);
    const p1 = Punto(23.11, -82.39);
    const p2 = Punto(23.12, -82.38);
    const p3 = Punto(23.13, -82.37);

    /// Un tramo «por calles» de mentira: tres vértices, el del medio desviado.
    List<Punto> porCalles(Punto a, Punto b) => [
          a,
          Punto((a.lat + b.lat) / 2 + 0.001, (a.lng + b.lng) / 2),
          b,
        ];

    test('el tramo sin camino sale recto y SÓLO ése', () async {
      final hecho = await coserLosTramos(
        const [p0, p1, p2, p3],
        (a, b) async => a == p1 ? null : porCalles(a, b),
        quedaTiempo: () => true,
      );

      expect(hecho.algunoPorCalles, isTrue,
          reason: 'dos de los tres tramos salieron por calles: si esto es '
              'falso, el tramo sin camino se llevó por delante a los otros y '
              'el recorrido entero acabará en rectas');
      // p0→p1 por calles (3 puntos), p1→p2 recto (sólo p2), p2→p3 por calles.
      expect(
        hecho.linea.map((p) => '${p.lat},${p.lng}').toList(),
        [
          '${p0.lat},${p0.lng}',
          '${(p0.lat + p1.lat) / 2 + 0.001},${(p0.lng + p1.lng) / 2}',
          '${p1.lat},${p1.lng}',
          '${p2.lat},${p2.lng}',
          '${(p2.lat + p3.lat) / 2 + 0.001},${(p2.lng + p3.lng) / 2}',
          '${p3.lat},${p3.lng}',
        ],
        reason: 'el tramo p1→p2 no tenía camino: tiene que salir recto ÉL, y '
            'los otros dos seguir por calles. Si aquí salen seis puntos '
            'seguidos sin desvíos, un solo tramo malo tiró toda la ruta a '
            'rectas — el fallo del 21/09',
      );
    });

    test('ningún tramo por calles = no hay respuesta propia', () async {
      final hecho = await coserLosTramos(
        const [p0, p1, p2],
        (a, b) async => null,
        quedaTiempo: () => true,
      );
      expect(hecho.algunoPorCalles, isFalse,
          reason: 'es lo que hace que se le pregunte al respaldo en vez de '
              'devolver una recta disfrazada de recorrido');
    });

    test('agotado el presupuesto, lo que queda sale recto y sin pedir nada',
        () async {
      var pedidos = 0;
      final hecho = await coserLosTramos(
        const [p0, p1, p2, p3],
        (a, b) async {
          pedidos++;
          return porCalles(a, b);
        },
        quedaTiempo: () => pedidos < 1,
      );
      expect(pedidos, 1,
          reason: 'pasado el presupuesto no se calcula ni un tramo más: es lo '
              'que evita que una ruta de veinticinco paradas congele el mapa');
      expect(hecho.linea, hasLength(5),
          reason: 'el primer tramo por calles (3 puntos) y los otros dos '
              'rectos, que aportan un punto cada uno');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  test('menos de dos paradas no es un recorrido', () async {
    final hecho = await coserLosTramos(
      const [Punto(23.1, -82.4)],
      (a, b) async => null,
      quedaTiempo: () => true,
    );
    expect(hecho.linea, hasLength(1));
    expect(hecho.algunoPorCalles, isFalse);
  });

  test('metrosPorUnidad cuadra con el tamaño conocido de una tesela', () {
    // A z14 y en La Habana una tesela mide unos 2,25 km de lado.
    final lado = metrosPorUnidad(23.1, 14) * unidadesPorTesela;
    expect(lado, closeTo(2250, 60),
        reason: 'si esto se va, se van con ello la tolerancia de costura y el '
            'radio de enganche, que se calculan en metros');
    // Y una unidad es de medio metro, que es lo que justifica coser a 8 m.
    expect(metrosPorUnidad(23.1, 14), closeTo(0.55, 0.03));
  });
}

/// Un respaldo que contesta siempre lo mismo y cuenta cuántas veces le
/// preguntaron. **No sale ni una petición**: regla de la casa en este PC.
class _RespaldoDeMentira implements RecorridoPorCalles {
  int veces = 0;
  final linea = <Punto>[
    const Punto(23.50, -82.36),
    const Punto(23.55, -82.38),
    const Punto(23.60, -82.40),
  ];

  @override
  Future<List<Punto>?> entre(List<Punto> puntos) async {
    veces++;
    return linea;
  }
}
